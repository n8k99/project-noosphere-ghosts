(in-package :af64.runtime.tick-engine)

(defparameter *tick-interval* (max 60 (parse-integer (or (uiop:getenv "TICK_INTERVAL_SECONDS") "600"))))
(defparameter *max-actions-per-tick* (parse-integer (or (uiop:getenv "MAX_ACTIONS_PER_TICK") "6")))
(defparameter *broker* (make-cognition-broker :max-jobs-per-tick *max-actions-per-tick*))

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

(defun determine-tier (fitness energy)
  (cond
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
   :model-used model-used
   :llm-called (not (string= provider-name "stub"))))

(defun run-tick (tick-number)
  (broker-start-tick *broker*)
  (let* ((now (utc-now-iso))
         (agents (fetch-active-agents))
         (ecology (broker-ecology-state *broker*))
         (request-budget (gethash :request-budget ecology))
         (perceptions (make-hash-table :test #'equal))
         (agent-map (make-hash-table :test #'equal))
         (drives (make-hash-table :test #'equal)))
    (handler-case (tick-drives)
      (error (e) (format t "  [drive-tick-error] ~a~%" e)))
    (dolist (agent agents)
      (let* ((aid (gethash :id agent))
             (tier (gethash :tier agent))
             (last-tick (or (gethash :last-tick-at agent) now)))
        (setf (gethash aid perceptions) (perceive aid tier last-tick))
        (setf (gethash aid agent-map) agent)))
    (let ((rankings '()))
      (dolist (agent agents)
        (let* ((aid (gethash :id agent))
               (energy (gethash :energy agent 50))
               (drive (or (gethash aid drives) (setf (gethash aid drives) (highest-pressure-drive aid))))
               (pressure (if drive (gethash :pressure drive) 50))
               (urgency (* pressure (/ energy 100.0))))
          (push (list aid urgency) rankings)))
      (setf rankings (sort rankings #'> :key #'second))
      (let ((acting-set (let ((subset (subseq rankings 0 (min request-budget (length rankings))))
                              (table (make-hash-table :test #'equal)))
                          (dolist (entry subset)
                            (let* ((aid (first entry))
                                   (perception (gethash aid perceptions)))
                              (when (has-actionable-items perception)
                                (setf (gethash aid table) t))))
                          table)
            (active-count 0)
            (idle-count 0)
            (dormant-count 0)
            (top-actor nil)
            (logs '())
            (cognition-requests '())
            (cognition-resolutions '())
            (agent-summaries (make-hash-table :test #'equal)))
        (dolist (agent agents)
          (let* ((aid (gethash :id agent))
                 (tier (gethash :tier agent))
                 (energy-before (gethash :energy agent 50))
                 (perception (gethash aid perceptions)))
            (cond
              ((<= energy-before 0)
               (incf dormant-count)
               (setf (gethash aid agent-summaries)
                     (json-object :agent-id aid :status "dormant" :tier tier
                                  :energy-before energy-before :energy-after energy-before))
               (push (build-log-entry tick-number aid "dormant" (json-object)
                                      tier energy-before energy-before nil nil)
                     logs))
              ((gethash aid acting-set)
               (let* ((drive (gethash aid drives))
                      (job (or (broker-get-pending-job *broker* aid)
                               (build-cognition-job aid agent perception tier tick-number drive))))
                 (if job
                     (progn
                       (broker-submit-job *broker* job)
                       (push (build-request-entry job) cognition-requests)
                       (setf (gethash aid agent-summaries)
                             (json-object :agent-id aid :status "requested_cognition"
                                          :tier tier :energy-before energy-before
                                          :requested-job-id (cognition-job-id job)
                                          :requested-kind (cognition-job-kind job)
                                          :request-priority (cognition-job-priority job)))
                       (push (build-log-entry tick-number aid "request_cognition"
                                              (json-object :job-id (cognition-job-id job)
                                                           :kind (cognition-job-kind job)
                                                           :priority (cognition-job-priority job))
                                              tier energy-before energy-before nil nil)
                             logs))
                     (let ((energy-after (update-energy-with-reward aid :rest)))
                       (incf idle-count)
                       (setf (gethash aid agent-summaries)
                             (json-object :agent-id aid :status "idle"
                                          :tier tier :energy-before energy-before
                                          :energy-after energy-after))
                       (push (build-log-entry tick-number aid "idle" (json-object)
                                              tier energy-before energy-after nil nil)
                             logs)))))
              (t
               (let ((energy-after (update-energy-with-reward aid :rest))
                     (action-name (if (and (gethash :winter-active ecology)
                                           (has-actionable-items perception))
                                     "winter_idle" "idle")))
                 (incf idle-count)
                 (setf (gethash aid agent-summaries)
                       (json-object :agent-id aid :status action-name :tier tier
                                    :energy-before energy-before :energy-after energy-after))
                 (push (build-log-entry tick-number aid action-name
                                        (if (string= action-name "winter_idle")
                                            (json-object :winter-active t)
                                            (json-object))
                                        tier energy-before energy-after nil nil)
                       logs))))))
        (dolist (result (broker-process-tick *broker*))
          (handler-case
              (let* ((action-detail (execute-cognition-result result)))
                (when action-detail
                  (let* ((agent-id (cognition-result-agent-id result))
                         (action (cognition-result-action-name result))
                         (cost (get-cost action))
                         (energy-before (get-energy agent-id))
                         (energy-after (update-energy agent-id cost))
                         (drive (or (gethash agent-id drives)
                                    (setf (gethash agent-id drives) (highest-pressure-drive agent-id)))))
                    (when drive
                      (fulfill-drive agent-id (gethash :drive-name drive)
                                     (if (string= action "respond_message") 10 15)))
                    (incf active-count)
                    (unless top-actor (setf top-actor (format nil "~a(~a)" agent-id action)))
                    (push (build-resolution-entry result) cognition-resolutions)
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
                                           energy-before energy-after (cognition-result-model-used result)
                                           (cognition-result-provider-name result))
                          logs))))
            (error (e) (format t "  [cognition-exec-error] ~a: ~a~%"
                               (cognition-result-agent-id result) e))))
        (dolist (agent agents)
          (let* ((aid (gethash :id agent))
                 (fitness (fetch-fitness aid))
                 (current-energy (get-energy aid))
                 (new-tier (determine-tier fitness current-energy))
                 (state-update (json-object
                                :tier new-tier
                                :last-tick-at now
                                :ticks-alive (+ 1 (or (gethash :ticks-alive agent) 0))
                                :ticks-at-current-tier (if (string= new-tier (gethash :tier agent))
                                                           (+ 1 (or (gethash :ticks-at-current-tier agent) 0))
                                                           0))))
            (handler-case
                (api-patch (format nil "/api/agents/~a/state" aid) state-update)
              (error (e) (format t "  [state-update-error] ~a: ~a~%" aid e)))))
        (let* ((log-vector (coerce (reverse logs) 'vector))
               (request-vector (coerce (reverse cognition-requests) 'vector))
               (resolution-vector (coerce (reverse cognition-resolutions) 'vector)))
          (handler-case
              (api-post "/api/tick-log/batch" (json-object :entries log-vector))
            (error (e) (format t "  [tick-log-error] ~a~%" e)))
          (let* ((summary (broker-tick-summary *broker*))
                 (report (json-object
                          :tick-number tick-number
                          :generated-at now
                          :counts (json-object :active active-count :idle idle-count :dormant dormant-count)
                          :budget (json-object :max-actions *max-actions-per-tick*
                                               :request-budget request-budget
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
                          :agent-summaries (coerce (loop for v being the hash-values of agent-summaries collect v) 'vector)
                          :entries log-vector))
                 (sink (write-tick-report report)))
            (format t "[tick ~a] active=~a idle=~a dormant=~a | top_actor=~a | budget_used=~a/~a | pending_jobs=~a cache=~a | report=~a~%"
                    tick-number active-count idle-count dormant-count (or top-actor "none")
                    active-count *max-actions-per-tick* (gethash :pending-jobs summary)
                    (gethash :cache-entries summary) sink)))))))
