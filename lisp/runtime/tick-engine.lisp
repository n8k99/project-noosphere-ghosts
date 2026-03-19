(in-package :af64.runtime.tick-engine)

(defparameter *tick-interval* (max 60 (parse-integer (or (uiop:getenv "TICK_INTERVAL_SECONDS") "600"))))
(defparameter *max-actions-per-tick* (parse-integer (or (uiop:getenv "MAX_ACTIONS_PER_TICK") "6")))
(defvar *broker* nil)  ;; initialized at end of file after all functions defined

;;; --- Utilities ---

(defun vector->list (maybe-vector)
  (cond
    ((null maybe-vector) '())
    ((vectorp maybe-vector) (loop for i across maybe-vector collect i))
    ((listp maybe-vector) maybe-vector)
    (t (list maybe-vector))))

(defun fetch-active-agents ()
  (remove-if-not (lambda (agent)
                   (string= (gethash :status agent) "active"))
                 (vector->list (api-get "/api/agents"))))

(defun update-energy-with-reward (agent-id reward-key)
  (let ((delta (gethash reward-key +energy-rewards+ 0)))
    (update-energy agent-id delta)))

(defun build-request-entry (job)
  (json-object
   :agent-id (cognition-job-agent-id job)
   :job-id (cognition-job-id job)
   :kind (cognition-job-kind job)
   :priority (cognition-job-priority job)
   :status (cognition-job-status job)
   :wait-ticks (cognition-job-wait-ticks job)))

(defun build-resolution-entry (result)
  (json-object
   :agent-id (cognition-result-agent-id result)
   :job-id (cognition-result-job-id result)
   :action-name (cognition-result-action-name result)
   :provider (cognition-result-provider-name result)
   :cached (cognition-result-cached result)
   :model-used (cognition-result-model-used result)))

(defun fetch-fitness (agent-id)
  (handler-case
      (gethash :fitness (api-get (format nil "/api/fitness/~a" agent-id) (json-object :days 30)) 0)
    (error () 0)))

(defun determine-tier (fitness energy &optional agent-id)
  (cond
    ;; Nova always gets opus tier, never goes dormant
    ((and agent-id (string-equal agent-id "nova")) "opus")
    ;; Elise gets sonnet minimum (working tier floor)
    ((and agent-id (string-equal agent-id "elise") (> energy 0)) 
     (if (and (> fitness 50) (> energy 70)) "prime" "working"))
    ((<= energy 0) "dormant")
    ((and (> fitness 50) (> energy 70)) "prime")
    ((and (> fitness 0) (> energy 20)) "working")
    (t "base")))

(defun build-log-entry (tick-number agent-id action-name detail tier energy-before energy-after model-used provider-name)
  (json-object
   :tick-number tick-number
   :agent-id agent-id
   :action-taken action-name
   :action-detail detail
   :energy-before energy-before
   :energy-after energy-after
   :tier tier
   :model-used (or model-used "none")
   :llm-called (and provider-name (not (string= provider-name "stub")))))

;;; --- Phase 1: Perceive all agents ---

(defun phase-perceive (agents now)
  "Return (perceptions . agent-map) hash tables."
  (let ((perceptions (make-hash-table :test #'equal))
        (agent-map (make-hash-table :test #'equal)))
    (dolist (agent agents)
      (let* ((aid (gethash :id agent))
             (tier (gethash :tier agent))
             (last-tick (or (gethash :last-tick-at agent) "2026-01-01T00:00:00Z")))
        (handler-case
            (setf (gethash aid perceptions) (perceive aid tier last-tick))
          (error (e)
            (format t "  [perceive-err] ~a: ~a~%" aid e)
            (setf (gethash aid perceptions) (af64.runtime.perception:empty-perception))))
        (setf (gethash aid agent-map) agent)))
    (values perceptions agent-map)))

;;; --- Phase 2: Rank agents by urgency ---

(defun phase-rank (agents perceptions ecology)
  "Return (rankings acting-set drives) — rankings sorted desc, acting-set hash, drives hash."
  (let ((drives (make-hash-table :test #'equal))
        (rankings '())
        (request-budget (gethash :request-budget ecology)))
    (dolist (agent agents)
      (let* ((aid (gethash :id agent))
             (raw-energy (gethash :energy agent 50))
             (energy (if (numberp raw-energy) raw-energy 50))
             (drive (handler-case (highest-pressure-drive aid) (error () nil)))
             (raw-pressure (if drive (gethash :pressure drive) 50))
             (pressure (if (numberp raw-pressure) raw-pressure 50))
             (perception (gethash aid perceptions))
             ;; Boost urgency for agents with pending messages (+50) or tasks (+25)
             (msgs (when perception (gethash :messages perception)))
             (reqs (when perception (gethash :requests perception)))
             (tasks (when perception (gethash :tasks perception)))
             (msg-boost (if (and msgs (> (length msgs) 0)) 50 0))
             (req-boost (if (and reqs (> (length reqs) 0)) 40 0))
             (task-boost (if (and tasks (> (length tasks) 0)) 25 0))
             (urgency (+ (* pressure (/ energy 100.0)) msg-boost req-boost task-boost)))
        (when drive (setf (gethash aid drives) drive))
        (push (list aid urgency) rankings)))
    (setf rankings (sort rankings #'> :key #'second))
    ;; Filter to only agents with actionable items FIRST, then take top N
    (let* ((actionable (remove-if-not
                        (lambda (entry)
                          (let ((perception (gethash (first entry) perceptions)))
                            (has-actionable-items perception)))
                        rankings))
           (subset (subseq actionable 0 (min request-budget (length actionable))))
           (acting-set (make-hash-table :test #'equal)))
      (dolist (entry subset)
        (setf (gethash (first entry) acting-set) t))
      ;; Nova ALWAYS acts when she has messages — she's the orchestrator
      (let ((nova-perception (gethash "nova" perceptions)))
        (format t "  [nova-debug] perception=~a msgs=~a actionable=~a~%"
                (if nova-perception "yes" "nil")
                (when nova-perception (length (gethash :messages nova-perception)))
                (when nova-perception (has-actionable-items nova-perception)))
        (when (and nova-perception (has-actionable-items nova-perception))
          (setf (gethash "nova" acting-set) t)))
      (values rankings acting-set drives))))

;;; --- Phase 3: Process each agent (classify + submit jobs) ---

(defun process-dormant-agent (tick-number aid tier energy-before agent-summaries)
  "Handle a dormant agent. Dormant agents still rest and recover energy."
  (let ((energy-after (update-energy-with-reward aid :rest)))
    (setf (gethash aid agent-summaries)
          (json-object :agent-id aid :status "dormant" :tier tier
                       :energy-before energy-before :energy-after energy-after))
    (build-log-entry tick-number aid "dormant" (json-object :resting t)
                     tier energy-before energy-after nil nil)))

(defun process-acting-agent (tick-number aid agent tier energy-before perception drives agent-summaries)
  "Handle an agent in the acting set. Returns (log-entry . maybe-request)."
  (let* ((drive (gethash aid drives))
         (job (handler-case
                  (or (broker-get-pending-job *broker* aid)
                      (build-cognition-job aid agent perception tier tick-number drive))
                (error (e)
                  (format t "  [job-build-err] ~a: ~a~%" aid e)
                  nil))))
    (if job
        (progn
          (broker-submit-job *broker* job)
          (setf (gethash aid agent-summaries)
                (json-object :agent-id aid :status "requested_cognition"
                             :tier tier :energy-before energy-before
                             :requested-job-id (cognition-job-id job)
                             :requested-kind (cognition-job-kind job)
                             :request-priority (cognition-job-priority job)))
          (values (build-log-entry tick-number aid "request_cognition"
                                   (json-object :job-id (cognition-job-id job)
                                                :kind (cognition-job-kind job)
                                                :priority (cognition-job-priority job))
                                   tier energy-before energy-before nil nil)
                  (build-request-entry job)))
        (let ((energy-after (update-energy-with-reward aid :rest)))
          (setf (gethash aid agent-summaries)
                (json-object :agent-id aid :status "idle"
                             :tier tier :energy-before energy-before
                             :energy-after energy-after))
          (values (build-log-entry tick-number aid "idle" (json-object)
                                   tier energy-before energy-after nil nil)
                  nil)))))

(defun process-idle-agent (tick-number aid tier energy-before ecology perception agent-summaries)
  "Handle an idle/winter-idle agent. Returns a log entry."
  (let* ((energy-after (update-energy-with-reward aid :rest))
         (action-name (if (and (gethash :winter-active ecology)
                               (has-actionable-items perception))
                          "winter_idle" "idle")))
    (setf (gethash aid agent-summaries)
          (json-object :agent-id aid :status action-name :tier tier
                       :energy-before energy-before :energy-after energy-after))
    (build-log-entry tick-number aid action-name
                     (if (string= action-name "winter_idle")
                         (json-object :winter-active t)
                         (json-object))
                     tier energy-before energy-after nil nil)))

(defun phase-classify-agents (tick-number agents ecology perceptions acting-set drives)
  "Classify all agents. Returns (values logs requests active idle dormant summaries)."
  (let ((logs '())
        (requests '())
        (active-count 0)
        (idle-count 0)
        (dormant-count 0)
        (agent-summaries (make-hash-table :test #'equal)))
    (dolist (agent agents)
      (let* ((aid (gethash :id agent))
             (tier (gethash :tier agent))
             (energy-before (gethash :energy agent 50))
             (perception (gethash aid perceptions)))
        ;; Boss override: Nathan speaks, you respond
        (when (and (<= energy-before 0) perception)
          (let ((msgs (gethash :messages perception)))
            (when (and msgs (> (length msgs) 0)
                       (some (lambda (m) (string-equal "nathan" (or (gethash :FROM m nil) (gethash :FROM-AGENT m "")))) msgs))
              (format t "  [boss-override] ~a summoned by Nathan — waking from dormant~%" aid)
              (setf energy-before 50)
              (update-energy aid 50)
              (setf (gethash aid acting-set) t))))
        (cond
          ((<= energy-before 0)
           (incf dormant-count)
           (push (process-dormant-agent tick-number aid tier energy-before agent-summaries) logs))
          ((gethash aid acting-set)
           (multiple-value-bind (log-entry request)
               (process-acting-agent tick-number aid agent tier energy-before
                                     perception drives agent-summaries)
             (push log-entry logs)
             (when request (push request requests))))
          (t
           (incf idle-count)
           (push (process-idle-agent tick-number aid tier energy-before
                                     ecology perception agent-summaries) logs)))))
    (values logs requests active-count idle-count dormant-count agent-summaries)))

;;; --- Phase 4: Process broker results ---

(defun phase-process-cognition (tick-number drives agent-map agent-summaries)
  "Process completed cognition jobs. Returns (values logs resolutions active-count top-actor)."
  (let ((logs '())
        (resolutions '())
        (active-count 0)
        (top-actor nil))
    (dolist (result (broker-process-tick *broker*))
      (handler-case
          (let ((action-detail (execute-cognition-result result)))
            (when action-detail
              (let* ((agent-id (cognition-result-agent-id result))
                     (action (cognition-result-action-name result))
                     (cost (if (string-equal agent-id "nova") 0 (get-cost action)))
                     (energy-before (get-energy agent-id))
                     (energy-after (update-energy agent-id cost))
                     (drive (or (gethash agent-id drives)
                                (handler-case (highest-pressure-drive agent-id) (error () nil)))))
                (when drive
                  (handler-case
                      (fulfill-drive agent-id (gethash :drive-name drive)
                                     (if (string= action "respond_message") 10 15))
                    (error () nil)))
                (incf active-count)
                (unless top-actor
                  (setf top-actor (format nil "~a(~a)" agent-id action)))
                (push (build-resolution-entry result) resolutions)
                (let ((summary (or (gethash agent-id agent-summaries)
                                   (setf (gethash agent-id agent-summaries)
                                         (json-object :agent-id agent-id)))))
                  (setf (gethash :resolved-job-id summary) (cognition-result-job-id result))
                  (setf (gethash :resolved-action summary) action)
                  (setf (gethash :provider summary) (cognition-result-provider-name result))
                  (setf (gethash :cached summary) (cognition-result-cached result))
                  (setf (gethash :energy-after summary) energy-after))
                (push (build-log-entry tick-number agent-id action action-detail
                                       (gethash :tier (gethash agent-id agent-map))
                                       energy-before energy-after
                                       (cognition-result-model-used result)
                                       (cognition-result-provider-name result))
                      logs))))
        (error (e)
          (format t "  [cognition-exec-error] ~a: ~a~%"
                  (cognition-result-agent-id result) e))))
    (values logs resolutions active-count top-actor)))

;;; --- Phase 5: Update agent state ---

(defun phase-update-state (agents now)
  "PATCH each agent's tier and tick counters."
  (dolist (agent agents)
    (let* ((aid (gethash :id agent))
           (fitness (fetch-fitness aid))
           (current-energy (get-energy aid))
           (new-tier (determine-tier fitness current-energy aid))
           (state-update (json-object
                          :tier new-tier
                          :last-tick-at now
                          :ticks-alive (+ 1 (or (gethash :ticks-alive agent) 0))
                          :ticks-at-current-tier (if (string= new-tier (gethash :tier agent))
                                                     (+ 1 (or (gethash :ticks-at-current-tier agent) 0))
                                                     0))))
      (handler-case
          (api-patch (format nil "/api/agents/~a/state" aid) state-update)
        (error (e)
          (format t "  [state-update-error] ~a: ~a~%" aid e))))))

;;; --- Phase 6: Report ---

(defun phase-report (tick-number now ecology logs requests resolutions
                     active-count idle-count dormant-count top-actor agent-summaries)
  "Build and write the tick report."
  (let* ((log-vector (coerce (reverse logs) 'vector))
         (request-vector (coerce (reverse requests) 'vector))
         (resolution-vector (coerce (reverse resolutions) 'vector)))
    (handler-case
        (api-post "/api/tick-log/batch" (json-object :entries log-vector))
      (error (e) (format t "  [tick-log-error] ~a~%" e)))
    (let* ((summary (broker-tick-summary *broker*))
           (report (json-object
                    :tick-number tick-number
                    :generated-at now
                    :counts (json-object :active active-count :idle idle-count :dormant dormant-count)
                    :budget (json-object :max-actions *max-actions-per-tick*
                                         :request-budget (gethash :request-budget ecology)
                                         :used-actions active-count
                                         :pending-jobs (gethash :pending-jobs summary)
                                         :cache-entries (gethash :cache-entries summary))
                    :top-actor (or top-actor "none")
                    :ecology ecology
                    :broker summary
                    :cognition (json-object
                                :requests request-vector
                                :resolutions resolution-vector
                                :pending-agents (coerce (broker-pending-agents *broker*) 'vector))
                    :agent-summaries (coerce (loop for v being the hash-values of agent-summaries
                                                   collect v) 'vector)
                    :entries log-vector))
           (sink (write-tick-report report)))
      (format t "[tick ~a] active=~a idle=~a dormant=~a | top=~a | budget=~a/~a | pending=~a cache=~a | sink=~a~%"
              tick-number active-count idle-count dormant-count (or top-actor "none")
              active-count *max-actions-per-tick* (gethash :pending-jobs summary)
              (gethash :cache-entries summary) sink))))

;;; --- Main tick orchestrator ---

(defun run-tick (tick-number)
  (broker-start-tick *broker*)
  (let ((now (utc-now-iso))
        (agents nil)
        (ecology nil)
        (perceptions nil)
        (agent-map nil)
        (drives nil)
        (acting-set nil)
        (logs nil)
        (requests nil)
        (resolutions nil)
        (active-count 0)
        (idle-count 0)
        (dormant-count 0)
        (top-actor nil)
        (agent-summaries nil))
    ;; Fetch
    (setf agents (fetch-active-agents))
    (setf ecology (broker-ecology-state *broker*))
    (handler-case (tick-drives) (error (e) (format t "  [drive-tick-error] ~a~%" e)))
    ;; Phase 1
    (multiple-value-setq (perceptions agent-map) (phase-perceive agents now))
    ;; Phase 2
    (multiple-value-bind (r a d) (phase-rank agents perceptions ecology)
      (declare (ignore r))
      (setf acting-set a)
      (setf drives d))
    ;; Phase 3
    (multiple-value-bind (l r2 ac ic dc as)
        (phase-classify-agents tick-number agents ecology perceptions acting-set drives)
      (setf logs l)
      (setf requests r2)
      (setf active-count ac)
      (setf idle-count ic)
      (setf dormant-count dc)
      (setf agent-summaries as))
    ;; Phase 4
    (multiple-value-bind (cl res ca ta)
        (phase-process-cognition tick-number drives agent-map agent-summaries)
      (setf logs (append cl logs))
      (setf resolutions res)
      (incf active-count ca)
      (setf top-actor ta))
    ;; Phase 5
    (phase-update-state agents now)
    ;; Phase 6
    (phase-report tick-number now ecology logs requests resolutions
                  active-count idle-count dormant-count top-actor
                  agent-summaries)))

;;; Initialize broker (must be after all function definitions)
(setf *broker* (make-cognition-broker :max-jobs-per-tick *max-actions-per-tick*))
