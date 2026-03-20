(in-package :af64.runtime.action-executor)

(defun suppress-empty-response-p (content)
  "Return T if the response is empty or useless and should not be posted."
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) content)))
    (or (= (length trimmed) 0)
        (string-equal trimmed "[no response]")
        (string-equal trimmed "no response")
        (string-equal trimmed "[empty]")
        (string-equal trimmed "N/A")
        (and (< (length trimmed) 5) (not (find #\! trimmed))))))

(defun execute-respond-message (result metadata)
  (let* ((source (gethash :source-message metadata (make-hash-table :test #'equal)))
         (payload (json-object
                   :from-agent (cognition-result-agent-id result)
                   :to-agent (json-array (gethash :from source))
                   :message (cognition-result-content result)
                   :channel (or (gethash :channel source) "noosphere")
                   :thread-id (or (gethash :thread-id source) :null)
                   :metadata (json-object
                              :responding-to (format nil "~a" (gethash :id source))
                              :source "cognition_broker"
                              :job-id (cognition-result-job-id result)
                              :provider (cognition-result-provider-name result)
                              :cached (cognition-result-cached result)))))
    (if (suppress-empty-response-p (cognition-result-content result))
        (progn
          (format t "  [suppressed] ~a: empty/useless response~%" (cognition-result-agent-id result))
          (json-object :action :respond-message :suppressed t))
        (let ((response (api-post "/api/conversations" payload)))
          (json-object
           :action :respond-message
           :job-id (cognition-result-job-id result)
           :msg-id (gethash :id source)
           :reply-id (gethash :id response)
           :provider (cognition-result-provider-name result)
           :cached (cognition-result-cached result)
           :response (subseq (cognition-result-content result)
                             0 (min 200 (length (cognition-result-content result)))))))))

(defparameter *pipeline-advancement*
  '(;; Engineering pipeline
    ("spec" . ("infra-review" . "isaac"))
    ("infra-review" . ("design" . "casey"))
    ("design" . ("build" . "devin"))
    ("build" . ("security-review" . "sanjay"))
    ("security-review" . ("test" . "danielle"))
    ("test" . ("deploy" . "morgan"))
    ("deploy" . ("done" . "eliana"))
    ;; Investment pipeline
    ("thesis" . ("research" . "ethan_ng"))
    ("research" . ("analysis" . "tobias_kim"))
    ("analysis" . ("compliance" . "jonah_klein"))
    ("compliance" . ("documentation" . "lucas_bryant"))
    ("documentation" . ("approval" . "jmax"))
    ("approval" . ("done" . "kathryn"))
    ;; Editorial pipeline (Cognitive Submission)
    ("collection" . ("research" . "liam_rivera"))
    ("research" . ("curation" . "mara_ellison"))
    ("curation" . ("composition" . "nadia_sorenson"))
    ("composition" . ("editing" . "samantha_yu"))
    ("editing" . ("polish" . "julian_weber"))
    ("polish" . ("publish" . "sylvia"))
    ("publish" . ("done" . "sylvia"))
    ;; Modular Fortress pipeline (diamond - linear approximation)
    ;; discovery unblocks both pattern-analysis and architecture-research
    ("discovery" . ("pattern-analysis" . "ibrahim_hassan"))
    ("pattern-analysis" . ("security-audit" . "tina_gray"))
    ("architecture-research" . ("synthesis" . "tina_gray"))
    ("security-audit" . ("synthesis" . "tina_gray"))
    ("synthesis" . ("tool-audit" . "elise"))
    ("tool-audit" . ("module-standards" . "samir"))
    ("module-standards" . ("done" . "carmen_delgado"))
    ("security-standards" . ("done" . "carmen_delgado")))
  "stage → (next-stage . next-assignee)")

(defun validate-stage-output (stage content &optional (tools-executed 0))
  "Validate that stage output meets minimum requirements.
   tools-executed is the DETERMINISTIC count from process-tool-calls — not parseable from content.
   Returns (T . nil) if valid, (NIL . reason) if rejected."
  (let ((len (length content))
        (content-lower (string-downcase content)))
    ;; Universal: must be substantial output, not just 'COMPLETE: #id'
    (cond
      ((< len 200)
       (cons nil "Output too short. Minimum 200 characters of actual work product required."))
      ;; SPEC stage: must contain sections like ## or Requirements or API or Schema
      ((string-equal stage "spec")
       (if (or (search "##" content)
               (search "requirement" content-lower)
               (search "endpoint" content-lower)
               (search "interface" content-lower)
               (search "input" content-lower))
           (if (> len 500)
               (cons t nil)
               (cons nil "Spec must be at least 500 characters with structured sections."))
           (cons nil "Spec must include structured sections (## headers, requirements, interfaces, endpoints).")))
      ;; INFRA-REVIEW stage: must reference actual infrastructure concerns
      ((string-equal stage "infra-review")
       (if (or (search "postgres" content-lower)
               (search "api" content-lower)
               (search "endpoint" content-lower)
               (search "database" content-lower)
               (search "table" content-lower)
               (search "security" content-lower)
               (search "deploy" content-lower))
           (if (> len 400)
               (cons t nil)
               (cons nil "Infrastructure review must be at least 400 characters."))
           (cons nil "Infrastructure review must reference actual infrastructure (database, API, endpoints, tables, deployment).")))
      ;; DESIGN stage: must contain architecture/design elements
      ((string-equal stage "design")
       (if (or (search "##" content)
               (search "function" content-lower)
               (search "module" content-lower)
               (search "class" content-lower)
               (search "component" content-lower)
               (search "flow" content-lower)
               (search "schema" content-lower))
           (if (> len 500)
               (cons t nil)
               (cons nil "Design must be at least 500 characters with architectural detail."))
           (cons nil "Design must include architectural elements (modules, functions, components, schemas, data flow).")))
      ;; BUILD stage: must contain actual code
      ((string-equal stage "build")
       (if (or (search "def " content)
               (search "fn " content)
               (search "function " content)
               (search "import " content)
               (search "```" content))
           (if (> len 1000)
               (cons t nil)
               (cons nil "Build output must be at least 1000 characters — needs actual code."))
           (cons nil "Build stage must contain actual code (def, fn, function, import, or code blocks).")))
      ;; SECURITY-REVIEW stage: must reference security concerns
      ((string-equal stage "security-review")
       (if (or (search "vulnerab" content-lower)
               (search "auth" content-lower)
               (search "inject" content-lower)
               (search "sanitiz" content-lower)
               (search "encrypt" content-lower)
               (search "secret" content-lower)
               (search "api key" content-lower)
               (search "permission" content-lower))
           (if (> len 400)
               (cons t nil)
               (cons nil "Security review must be at least 400 characters."))
           (cons nil "Security review must address actual security concerns (auth, injection, secrets, permissions, encryption).")))
      ;; TEST stage: must contain test cases or results
      ((string-equal stage "test")
       (if (or (search "test" content-lower)
               (search "assert" content-lower)
               (search "pass" content-lower)
               (search "fail" content-lower)
               (search "expect" content-lower)
               (search "verify" content-lower))
           (if (> len 400)
               (cons t nil)
               (cons nil "Test report must be at least 400 characters."))
           (cons nil "Test stage must include test cases, assertions, pass/fail results.")))
      ;; DEPLOY stage: must reference deployment steps
      ((string-equal stage "deploy")
       (if (or (search "deploy" content-lower)
               (search "manifest" content-lower)
               (search "cron" content-lower)
               (search "pm2" content-lower)
               (search "install" content-lower)
               (search "pip" content-lower))
           (if (> len 300)
               (cons t nil)
               (cons nil "Deploy report must be at least 300 characters."))
           (cons nil "Deploy stage must reference actual deployment steps (manifest, install, cron, PM2).")))
      ;; Investment/editorial/analysis pipeline stages: MUST have actually executed tools
      ;; tools-executed is a deterministic count from the tool socket — ghosts cannot fake this
      ((member stage '("thesis" "research" "analysis" "compliance" "documentation" "approval"
                        "collection" "curation" "composition" "editing" "polish" "publish"
                        "discovery" "pattern-analysis" "architecture-research" "security-audit"
                        "synthesis" "tool-audit" "module-standards" "security-standards")
               :test #'string-equal)
       (cond
         ;; Deterministic check: tool socket must have executed at least 1 tool
         ((> tools-executed 0)
          (if (> len 400)
              (cons t nil)
              (cons nil (format nil "~a output too short. Must be 400+ chars with tool results." stage))))
         ;; Ghost wrote tool_call blocks but none executed (wrong tool name, parse error, etc.)
         ((search "```tool_call" content)
          (cons nil (format nil "~a stage: tool_call blocks found but 0 tools actually executed. Check your tool names match exactly. Available tools are listed in your prompt." stage)))
         ;; Pure prose — no attempt to use tools
         (t
          (cons nil (format nil "~a stage REJECTED: 0 tools executed. You MUST call tools using ```tool_call blocks. Do not write prose. Call real tools, get real data." stage)))))
      ;; Unknown stage — just check length
      (t (if (> len 300) (cons t nil)
             (cons nil "Output must be at least 300 characters of substantive work."))))))

(defun advance-pipeline (task-id current-stage agent-id content &key goal-id task-text)
  "Advance pipeline: mark current task done, unblock next stage task.
   Each stage is a separate task row. Advancement = done + unblock."
  (let ((next (cdr (assoc current-stage *pipeline-advancement* :test #'string-equal))))
    (when next
      (let ((next-stage (car next))
            (next-assignee (cdr next)))
        (handler-case
            (progn
              ;; Mark CURRENT task as done with the work output
              (api-patch (format nil "/api/af64/tasks/~a" task-id)
                         (json-object :status "done"
                                      :stage-notes (subseq content 0 (min 2000 (length content)))))
              ;; Unblock the NEXT stage task
              (when (and goal-id (not (string-equal next-stage "done")))
                (handler-case
                    ;; Query next assignee's tasks, find the blocked one for this goal
                    (let ((all-tasks (api-get (format nil "/api/af64/tasks?assigned_to=~a&status=blocked" next-assignee))))
                      (format t "  [unblock-debug] looking for goal-id=~a stage=~a in ~a tasks for ~a~%"
                              goal-id next-stage
                              (if all-tasks (if (vectorp all-tasks) (length all-tasks) (length all-tasks)) 0)
                              next-assignee)
                      (when all-tasks
                        ;; Handle both vector and list responses
                        (let ((task-list (if (vectorp all-tasks) (coerce all-tasks 'list) all-tasks)))
                          (dolist (candidate task-list)
                            (when (hash-table-p candidate)
                              (let ((cand-goal (gethash :GOAL-ID candidate))
                                    (cand-stage (gethash :STAGE candidate)))
                                (when (and (eql cand-goal goal-id)
                                           (string-equal (or cand-stage "") next-stage))
                                  (let ((next-id (gethash :ID candidate)))
                                    (api-patch (format nil "/api/af64/tasks/~a" next-id)
                                               (json-object :status "open"))
                                    (format t "  [unblocked] task #~a (~a) for @~a~%" next-id next-stage next-assignee)
                                    (return)))))))))
                  (error (e) (format t "  [unblock-error] ~a: ~a~%" task-id e))))
              ;; Post conversation about the advancement — include task + tool context
              (handler-case
                  (let* ((task-text (or task-text ""))
                         ;; Extract tool name from task-id (e.g. "comment-collector-build" → "comment-collector")
                         (tool-name (or (let ((tid (format nil "~a" task-id)))
                                          (let ((last-dash (position #\- tid :from-end t)))
                                            (when last-dash (subseq tid 0 last-dash))))
                                        (let ((pos (search "tool:" task-text :test #'char-equal)))
                                          (when pos (string-trim '(#\Space) (subseq task-text (+ pos 5)))))
                                        "unknown"))
                         ;; Truncate content to useful summary
                         (summary (subseq content 0 (min 300 (length content)))))
                    (api-post "/api/conversations"
                              (json-object :from-agent agent-id
                                           :to-agent (json-array next-assignee)
                                           :message (format nil "[Pipeline] ~a completed ~a for **~a** (task #~a). Advancing to ~a → @~a~%~%Summary: ~a"
                                                            agent-id current-stage tool-name task-id next-stage next-assignee summary)
                                           :channel "noosphere")))
                (error () nil))
              (format t "  [pipeline] ~a: ~a → ~a (@~a)~%" task-id current-stage next-stage next-assignee)
              ;; Fork handling: some stages unblock multiple downstream tasks
              ;; discovery → architecture-research (in addition to pattern-analysis)
              ;; synthesis → security-standards (in addition to tool-audit)
              (let ((fork-targets
                      (cond
                        ((string-equal current-stage "discovery")
                         '(("architecture-research" . "felix_wu")))
                        ((string-equal current-stage "synthesis")
                         '(("security-standards" . "sanjay")))
                        (t nil))))
                (dolist (fork fork-targets)
                  (let ((fork-stage (car fork))
                        (fork-assignee (cdr fork)))
                    (handler-case
                        (let ((all-tasks (api-get (format nil "/api/af64/tasks?assigned_to=~a&status=blocked" fork-assignee))))
                          (when all-tasks
                            (let ((task-list (if (vectorp all-tasks) (coerce all-tasks 'list) all-tasks)))
                              (dolist (candidate task-list)
                                (when (hash-table-p candidate)
                                  (let ((cand-goal (gethash :GOAL-ID candidate))
                                        (cand-stage (gethash :STAGE candidate)))
                                    (when (and (eql cand-goal goal-id)
                                               (string-equal (or cand-stage "") fork-stage))
                                      (let ((next-id (gethash :ID candidate)))
                                        (api-patch (format nil "/api/af64/tasks/~a" next-id)
                                                   (json-object :status "open"))
                                        (format t "  [fork-unblocked] task #~a (~a) for @~a~%" next-id fork-stage fork-assignee)
                                        (return)))))))))
                      (error (e) (format t "  [fork-error] ~a~%" e))))))
              ;; Reward completing agent with +15 energy for their stage
              (handler-case
                  (progn
                    (update-energy agent-id 15)
                    (format t "  [energy] ~a +15 energy (stage complete)~%" agent-id))
                (error () nil))
              ;; When pipeline is fully done, reward ALL pipeline participants +30
              (when (string-equal next-stage "done")
                (handler-case
                    (let ((rewarded (make-hash-table :test #'equal)))
                      (dolist (entry *pipeline-advancement*)
                        (let ((participant (cddr entry)))
                          (when (and participant (not (gethash participant rewarded)))
                            (setf (gethash participant rewarded) t)
                            (update-energy participant 30)
                            (format t "  [energy] ~a +30 energy (pipeline complete)~%" participant)))))
                  (error () nil)))
              ;; If done, also mark the parent goal task as done
              (when (and (string-equal next-stage "done") goal-id)
                (handler-case
                    (api-patch (format nil "/api/af64/tasks/~a" goal-id)
                               (json-object :status "done" :stage "done"))
                  (error () nil))))
          (error (e) (format t "  [pipeline-advance-error] ~a: ~a~%" task-id e)))))))

(defun handle-pipeline-blocked (task-id current-stage agent-id reason)
  "Handle BLOCKED output — revert to build stage with QA/security notes."
  (when (or (string-equal current-stage "test")
            (string-equal current-stage "security-review"))
    (handler-case
        (progn
          (api-patch (format nil "/api/af64/tasks/~a" task-id)
                     (json-object :stage "build" :assignee "devin" :status "open"
                                  :stage-notes (format nil "BLOCKED by QA (~a): ~a" agent-id reason)))
          (format t "  [pipeline-blocked] ~a: test → build (QA rejected)~%" task-id))
      (error (e) (format t "  [pipeline-blocked-error] ~a: ~a~%" task-id e)))))

(defun parse-blocked-lines (content)
  "Extract BLOCKED: #id reason lines."
  (let ((results '())
        (lines (uiop:split-string content :separator '(#\Newline))))
    (dolist (line lines)
      (let ((trimmed (string-trim '(#\Space #\Tab #\Return) line)))
        (when (and (> (length trimmed) 10) (search "BLOCKED:" trimmed))
          (let* ((after (subseq trimmed (+ (search "BLOCKED:" trimmed) 8)))
                 (id-match (and (search "#" after)
                                (let* ((start (1+ (search "#" after)))
                                       (end (or (position #\Space after :start start) (length after))))
                                  (parse-integer (subseq after start end) :junk-allowed t))))
                 (reason (if id-match
                             (let ((space-pos (position #\Space after :start (1+ (search "#" after)))))
                               (if space-pos (string-trim '(#\Space) (subseq after space-pos)) ""))
                             "")))
            (when id-match (push (list id-match reason) results))))))
    (nreverse results)))

(defun execute-work-task (result metadata)
  (let* ((task (gethash :task metadata))
         (content (cognition-result-content result))
         (agent-id (cognition-result-agent-id result))
         (stage (when task (or (gethash :stage task) "open")))
         (tools-executed 0))
    (when task
      (api-patch (format nil "/api/af64/tasks/~a" (gethash :id task))
                 (json-object :status "in-progress"
                              :stage-notes (subseq content 0 (min 2000 (length content)))))
      (format t "  [work-output] ~a (~a chars): ~a~%" agent-id (length content) (subseq content 0 (min 100 (length content)))))
    ;; UNIVERSAL TOOL SOCKET: parse and execute tool calls from ghost output
    (let ((tool-results (process-tool-calls content agent-id)))
      (setf tools-executed (length tool-results))
      (when tool-results
        (format t "  [tools] ~a executed ~a tool(s)~%" agent-id tools-executed)
        ;; Append tool results to stage_notes so they're visible
        (handler-case
            (let ((results-text (with-output-to-string (s)
                                  (dolist (r tool-results)
                                    (format s "~%--- TOOL: ~a ---~%~a~%" (first r) (second r))))))
              (setf content (concatenate 'string content results-text))
              (when (and task (gethash :id task))
                (api-patch (format nil "/api/af64/tasks/~a" (gethash :id task))
                           (json-object :stage-notes
                                        (subseq content 0 (min 4000 (length content)))))))
          (error () nil))))
    ;; Parse COMPLETE/DELEGATE/HANDOFF from work output
    (let ((mutations (apply-task-mutations agent-id content)))
      (when (> mutations 0)
        (format t "  [work-task-mutations] ~a applied ~a task updates~%" agent-id mutations)))
    ;; Auto-validate pipeline stage output — ghost doesn't need to say COMPLETE
    (when (and stage (not (string-equal stage "open")) (not (string-equal stage "done"))
               (gethash :id task))
      (let ((validation (validate-stage-output stage content tools-executed)))
        (if (car validation)
            (progn
              (format t "  [stage-passed] ~a passed ~a validation (~a chars)~%" agent-id stage (length content))
              (advance-pipeline (gethash :id task) stage agent-id content
                                :goal-id (gethash :goal-id task)
                                :task-text (gethash :text task)))
            (progn
              (format t "  [stage-rejected] ~a failed ~a validation: ~a~%" agent-id stage (cdr validation))
              ;; Count rejections — after 3 failures, mark blocked instead of retrying
              (let* ((prev-notes (or (gethash :stage-notes task) ""))
                     (rejection-count (let ((count 0) (pos 0))
                                        (loop
                                          (let ((found (search "REJECTED" prev-notes :start2 pos)))
                                            (unless found (return (1+ count)))
                                            (incf count)
                                            (setf pos (+ found 8)))))))
              ;; Write rejection back to stage_notes so ghost sees feedback next tick
              (handler-case
                  (cond
                    ((>= rejection-count 3)
                     (api-patch (format nil "/api/af64/tasks/~a" (gethash :id task))
                                (json-object :status "blocked"
                                             :stage-notes (format nil "BLOCKED after 3 rejections. Last failure: ~a~%Agent ~a cannot complete ~a stage. Needs intervention."
                                                                  (cdr validation) agent-id stage)))
                     (format t "  [stage-blocked] ~a blocked after 3 failed attempts at ~a~%" agent-id stage))
                    (t
                     (api-patch (format nil "/api/af64/tasks/~a" (gethash :id task))
                                (json-object :status "open"
                                             :stage-notes (format nil "REJECTED (attempt ~a/3): ~a~%~%Try again.~%~%Previous (~a chars):~%~a"
                                                                  rejection-count (cdr validation) (length content)
                                                                  (subseq content 0 (min 500 (length content))))))))
                (error () nil)))
              ;; Invalidate cache so ghost retries with fresh LLM call
              (handler-case
                  (let ((broker (when (boundp 'af64.runtime.tick-engine::*broker*)
                                  (symbol-value 'af64.runtime.tick-engine::*broker*))))
                    (when broker
                      (let ((cache (af64.runtime.cognition-broker::cognition-broker-cache broker)))
                        (maphash (lambda (k v)
                                   (declare (ignore v))
                                   (when (search agent-id k)
                                     (remhash k cache)))
                                 cache)
                        (format t "  [cache-cleared] ~a cache invalidated for retry~%" agent-id))))
                (error (e) (format t "  [cache-clear-error] ~a~%" e)))
              ;; Deduct energy for failed attempt
              (handler-case
                  (progn
                    (update-energy agent-id -5)
                    (format t "  [energy] ~a -5 energy (rejected stage output)~%" agent-id))
                (error () nil)))))))
    ;; Still parse COMPLETE lines for backward compat (non-pipeline tasks)
    (let ((completed (parse-complete-lines content)))
      (dolist (task-id completed)
        (when (and (not stage) (not (string-equal stage "open")))
          ;; Only for non-pipeline tasks
          nil)))
    ;; Handle BLOCKED (QA rejection)
    (let ((blocked (parse-blocked-lines content)))
      (dolist (b blocked)
        (handle-pipeline-blocked (first b) stage agent-id (second b))))
    (json-object
     :action :work-task
     :job-id (cognition-result-job-id result)
     :task-id (and task (gethash :id task))
     :stage stage
     :provider (cognition-result-provider-name result)
     :cached (cognition-result-cached result)
     :response (subseq content 0 (min 200 (length content)))))

(defun execute-cognition-result (result)
  (let* ((action (cognition-result-action-name result))
         (metadata (or (cognition-result-metadata result)
                       (make-hash-table :test #'equal))))
    (cond
      ((string= action "respond_message")
       (execute-respond-message result metadata))
      ((string= action "work_task")
       (execute-work-task result metadata))
      ((string= action "proactive_work")
       (execute-proactive-work result metadata))
      ((string= action "handle_request")
       (execute-handle-request result metadata))
      (t nil))
    ;; Write to agent_daily_memory after every action
    (write-agent-daily-memory result action)))

(defun parse-handoff (content)
  "Extract HANDOFF: @agent_id message from content. Returns (agent-id . message) or nil."
  (let ((pos (search "HANDOFF:" content)))
    (when pos
      (let* ((rest (string-trim '(#\Space #\Tab) (subseq content (+ pos 8))))
             (at-pos (position #\@ rest)))
        (when at-pos
          (let* ((after-at (subseq rest (1+ at-pos)))
                 (space-pos (position #\Space after-at)))
            (when space-pos
              (cons (subseq after-at 0 space-pos)
                    (string-trim '(#\Space #\Tab #\Newline) (subseq after-at space-pos))))))))))

(defun parse-classify-lines (content)
  "Extract CLASSIFY: #id department=dept assignee=agent lines. Returns list of (id dept assignee)."
  (let ((results '())
        (lines (uiop:split-string content :separator '(#\Newline))))
    (dolist (line lines)
      (let ((trimmed (string-trim '(#\Space #\Tab #\Return) line)))
        (when (and (> (length trimmed) 10) (search "CLASSIFY:" trimmed))
          (let* ((after (subseq trimmed (+ (search "CLASSIFY:" trimmed) 9)))
                 (id-match (and (search "#" after)
                                (let* ((start (1+ (search "#" after)))
                                       (end (position #\Space after :start start)))
                                  (when end (parse-integer (subseq after start end) :junk-allowed t)))))
                 (dept-match (when (search "department=" after)
                               (let* ((start (+ (search "department=" after) 11))
                                      (end (or (position #\Space after :start start) (length after))))
                                 (subseq after start end))))
                 (assignee-match (when (search "assignee=" after)
                                   (let* ((start (+ (search "assignee=" after) 9))
                                          (end (or (position #\Space after :start start) (length after))))
                                     (subseq after start end)))))
            (when (and id-match dept-match)
              (push (list id-match dept-match assignee-match) results))))))
    (nreverse results)))

(defun parse-delegate-lines (content)
  "Extract DELEGATE: #id assignee=agent lines. Returns list of (id assignee)."
  (let ((results '())
        (lines (uiop:split-string content :separator '(#\Newline))))
    (dolist (line lines)
      (let ((trimmed (string-trim '(#\Space #\Tab #\Return) line)))
        (when (and (> (length trimmed) 10) (search "DELEGATE:" trimmed))
          (let* ((after (subseq trimmed (+ (search "DELEGATE:" trimmed) 9)))
                 (id-match (and (search "#" after)
                                (let* ((start (1+ (search "#" after)))
                                       (end (position #\Space after :start start)))
                                  (when end (parse-integer (subseq after start end) :junk-allowed t)))))
                 (assignee-match (when (search "assignee=" after)
                                   (let* ((start (+ (search "assignee=" after) 9))
                                          (end (or (position #\Space after :start start) (length after))))
                                     (subseq after start end)))))
            (when (and id-match assignee-match)
              (push (list id-match assignee-match) results))))))
    (nreverse results)))

(defun parse-complete-lines (content)
  "Extract COMPLETE: #id lines. Returns list of task ids."
  (let ((results '())
        (lines (uiop:split-string content :separator '(#\Newline))))
    (dolist (line lines)
      (let ((trimmed (string-trim '(#\Space #\Tab #\Return) line)))
        (when (and (> (length trimmed) 10) (search "COMPLETE:" trimmed))
          (let* ((after (subseq trimmed (+ (search "COMPLETE:" trimmed) 9)))
                 (id-match (and (search "#" after)
                                (let* ((start (1+ (search "#" after)))
                                       (end (or (position #\Space after :start start) (length after))))
                                  (parse-integer (subseq after start end) :junk-allowed t)))))
            (when id-match
              (push id-match results))))))
    (nreverse results)))

(defun apply-task-mutations (agent-id content)
  "Parse CLASSIFY, DELEGATE, and COMPLETE lines from content and apply via API."
  (let ((classified (parse-classify-lines content))
        (delegated (parse-delegate-lines content))
        (completed (parse-complete-lines content))
        (count 0))
    (dolist (c classified)
      (handler-case
          (progn
            (api-patch (format nil "/api/af64/tasks/~a" (first c))
                       (json-object :department (second c)
                                    :assignee (or (third c) :null)))
            (incf count))
        (error (e) (format t "  [classify-error] task #~a: ~a~%" (first c) e))))
    (dolist (d delegated)
      (handler-case
          (progn
            (api-patch (format nil "/api/af64/tasks/~a" (first d))
                       (json-object :assignee (second d)))
            (incf count))
        (error (e) (format t "  [delegate-error] task #~a: ~a~%" (first d) e))))
    (dolist (task-id completed)
      (handler-case
          (progn
            (api-patch (format nil "/api/af64/tasks/~a" task-id)
                       (json-object :status "done"))
            (format t "  [complete] ~a marked task #~a done~%" agent-id task-id)
            (incf count))
        (error (e) (format t "  [complete-error] task #~a: ~a~%" task-id e))))
    count))

(defun execute-proactive-work (result metadata)
  "Post proactive work output as a conversation entry. Parse HANDOFF/CLASSIFY/DELEGATE."
  (let* ((agent-id (cognition-result-agent-id result))
         (content (cognition-result-content result))
         (handoff (parse-handoff content))
         (source (gethash :source-message metadata (make-hash-table :test #'equal)))
         ;; Post the main work output
         (payload (json-object
                   :from-agent agent-id
                   :to-agent (json-array "noosphere")
                   :message content
                   :channel "noosphere"
                   :thread-id :null
                   :metadata (json-object
                              :source "proactive_work"
                              :job-id (cognition-result-job-id result)
                              :provider (cognition-result-provider-name result)
                              :cached (cognition-result-cached result)))))
    (let ((response (api-post "/api/conversations" payload)))
      ;; Apply task classifications and delegations
      (let ((mutations (apply-task-mutations agent-id content)))
        (when (> mutations 0)
          (format t "  [task-mutations] ~a applied ~a task updates~%" agent-id mutations)))
      ;; If there's a handoff, route it
      (when handoff
        (let ((target-id (car handoff))
              (handoff-msg (cdr handoff)))
          (if (string-equal target-id "builder")
              ;; Special target: spawn actual tool builder
              (handler-case
                  (spawn-tool-build agent-id content (gethash :id response))
                (error (e)
                  (format t "  [builder-error] ~a: ~a~%" agent-id e)))
              ;; Normal handoff to another ghost
              (handler-case
                  (api-post "/api/conversations"
                            (json-object
                             :from-agent agent-id
                             :to-agent (json-array target-id)
                             :message (format nil "[Handoff from ~a]: ~a~%~%Reference: conversation #~a"
                                              agent-id handoff-msg (gethash :id response))
                             :channel "noosphere"
                             :thread-id :null
                             :metadata (json-object
                                        :source "handoff"
                                        :from-conversation (gethash :id response)
                                        :job-id (cognition-result-job-id result))))
                (error (e)
                  (format t "  [handoff-error] ~a → ~a: ~a~%" agent-id target-id e))))))
      (json-object
       :action :proactive-work
       :job-id (cognition-result-job-id result)
       :reply-id (gethash :id response)
       :handoff (when handoff (car handoff))
       :provider (cognition-result-provider-name result)
       :cached (cognition-result-cached result)
       :response (subseq content 0 (min 200 (length content)))))))

(defun parse-reassign (content)
  "Extract REASSIGN: #id to=agent_id lines. Returns list of (id target-agent)."
  (let ((results '())
        (lines (uiop:split-string content :separator '(#\Newline))))
    (dolist (line lines)
      (let ((trimmed (string-trim '(#\Space #\Tab #\Return) line)))
        (when (and (> (length trimmed) 10) (search "REASSIGN:" trimmed))
          (let* ((after (subseq trimmed (+ (search "REASSIGN:" trimmed) 9)))
                 (id-match (and (search "#" after)
                                (let* ((start (1+ (search "#" after)))
                                       (end (position #\Space after :start start)))
                                  (when end (parse-integer (subseq after start end) :junk-allowed t)))))
                 (to-match (when (search "to=" after)
                             (let* ((start (+ (search "to=" after) 3))
                                    (end (or (position #\Space after :start start) (length after))))
                               (subseq after start end)))))
            (when (and id-match to-match)
              (push (list id-match to-match) results))))))
    (nreverse results)))

(defun apply-reassignments (agent-id content)
  "Parse REASSIGN lines and update agent_requests via API."
  (let ((reassigns (parse-reassign content))
        (count 0))
    (dolist (r reassigns)
      (handler-case
          (progn
            ;; Update to_agent on the request and reset status to no_handler
            (api-put (format nil "/api/agents/requests/~a" (first r))
                     (json-object :status "no_handler"
                                  :to-agent (second r)
                                  :response (format nil "[~a] Reassigned to ~a" agent-id (second r))))
            ;; Post a conversation entry so the new agent sees it
            (api-post "/api/conversations"
                      (json-object
                       :from-agent agent-id
                       :to-agent (json-array (second r))
                       :message (format nil "[Reassigned from ~a]: Request #~a has been reassigned to you."
                                        agent-id (first r))
                       :channel "noosphere"
                       :thread-id :null
                       :metadata (json-object :source "reassignment" :request-id (first r))))
            (incf count))
        (error (e) (format t "  [reassign-error] ~a on #~a: ~a~%" agent-id (first r) e))))
    count))

(defun extract-tool-name (content)
  "Try to extract a tool name from the spec. Case-insensitive search for tool name patterns."
  (let ((lower (string-downcase content))
        (patterns '("tool name:" "tool_name:" "tool:" "build tool:")))
    (dolist (pat patterns)
      (let ((pos (search pat lower)))
        (when pos
          (let* ((after (string-trim '(#\Space #\Tab) (subseq content (+ pos (length pat)))))
                 (end (or (position #\Newline after) (min 60 (length after))))
                 (name (string-trim '(#\Space #\Tab #\Return #\* #\`) (subseq after 0 end))))
            (when (> (length name) 0)
              ;; Sanitize: lowercase, replace spaces/hyphens with underscores, remove special chars
              (return (substitute #\_ #\-
                       (substitute #\_ #\Space
                                   (string-downcase
                                    (remove-if-not (lambda (c) (or (alphanumericp c) (char= c #\_) (char= c #\-) (char= c #\Space)))
                                                   name))))))))))
    ;; Fallback: use timestamp
    (format nil "ghost_tool_~a" (get-universal-time))))

(defun spawn-tool-build (agent-id spec-content conversation-id)
  "Spawn a Claude Code process to actually build a tool from a ghost's spec."
  (let* ((tool-name (extract-tool-name spec-content))
         (spec-file (format nil "/tmp/ghost-spec-~a-~a.md" agent-id tool-name))
         (builder-script "/opt/project-noosphere-ghosts/tools/tool-builder.sh"))
    ;; Write spec to temp file
    (with-open-file (s spec-file :direction :output :if-exists :supersede)
      (write-string spec-content s))
    ;; Log the build kick-off
    (format t "  [tool-builder] ~a spawning build: ~a~%" agent-id tool-name)
    ;; Post a status message
    (api-post "/api/conversations"
              (json-object
               :from-agent agent-id
               :to-agent (json-array agent-id "noosphere")
               :message (format nil "🔨 Build started: ~a~%Spec from: ~a (conversation #~a)~%Building with Claude Code..."
                                tool-name agent-id conversation-id)
               :channel "noosphere"
               :thread-id :null
               :metadata (json-object :source "tool_builder" :tool-name tool-name :spec-from agent-id)))
    ;; Spawn async build process
    (uiop:launch-program
     (list builder-script spec-file tool-name agent-id)
     :output (format nil "/tmp/tool-builder-~a.log" tool-name)
     :error-output (format nil "/tmp/tool-builder-~a.err" tool-name))
    (format t "  [tool-builder] ~a build spawned for: ~a~%" agent-id tool-name)))

(defun execute-handle-request (result metadata)
  "Process an agent_request: post response as conversation, update request status, handle handoffs."
  (let* ((agent-id (cognition-result-agent-id result))
         (content (cognition-result-content result))
         (handoff (parse-handoff content))
         (source (gethash :source-message metadata (make-hash-table :test #'equal)))
         (request-id (gethash :id source))
         (from-agent (or (gethash :from source) "system"))
         ;; Post the response as a conversation entry
         (payload (json-object
                   :from-agent agent-id
                   :to-agent (json-array from-agent)
                   :message content
                   :channel "noosphere"
                   :thread-id :null
                   :metadata (json-object
                              :source "handle_request"
                              :request-id request-id
                              :job-id (cognition-result-job-id result)
                              :provider (cognition-result-provider-name result)
                              :cached (cognition-result-cached result)))))
    (let ((response (api-post "/api/conversations" payload)))
      ;; Update the request — mark as resolved with the ghost's response
      (when request-id
        (handler-case
            (api-put (format nil "/api/agents/requests/~a" request-id)
                     (json-object :status "resolved"
                                  :response (format nil "[~a] ~a" agent-id
                                                    (subseq content 0 (min 500 (length content))))))
          (error (e)
            (format t "  [request-update-error] ~a on #~a: ~a~%" agent-id request-id e))))
      ;; Apply task mutations (CLASSIFY/DELEGATE)
      (let ((mutations (apply-task-mutations agent-id content)))
        (when (> mutations 0)
          (format t "  [task-mutations] ~a applied ~a task updates~%" agent-id mutations)))
      ;; Apply reassignments
      (let ((reassigns (apply-reassignments agent-id content)))
        (when (> reassigns 0)
          (format t "  [reassignments] ~a reassigned ~a requests~%" agent-id reassigns)))
      ;; Handle handoffs
      (when handoff
        (let ((target-id (car handoff))
              (handoff-msg (cdr handoff)))
          (handler-case
              (api-post "/api/conversations"
                        (json-object
                         :from-agent agent-id
                         :to-agent (json-array target-id)
                         :message (format nil "[Handoff from ~a]: ~a~%~%Re: request #~a"
                                          agent-id handoff-msg request-id)
                         :channel "noosphere"
                         :thread-id :null
                         :metadata (json-object
                                    :source "handoff"
                                    :request-id request-id
                                    :job-id (cognition-result-job-id result))))
            (error (e)
              (format t "  [handoff-error] ~a → ~a: ~a~%" agent-id target-id e)))))
      (json-object
       :action :handle-request
       :job-id (cognition-result-job-id result)
       :request-id request-id
       :reply-id (gethash :id response)
       :handoff (when handoff (car handoff))
       :provider (cognition-result-provider-name result)
       :cached (cognition-result-cached result)
       :response (subseq content 0 (min 200 (length content)))))))

(defun write-agent-daily-memory (result action)
  "Write a summary of the agent's action to agent_daily_memory via API,
   AND to vault_notes daily note in the agent's _memories column."
  (handler-case
    (let* ((agent-id (cognition-result-agent-id result))
           (content (cognition-result-content result))
           (summary (subseq content 0 (min 500 (length content))))
           ;; Map action type to memory column
           (column (cond
                     ((string= action "respond_message") "actions_taken")
                     ((string= action "proactive_work") "actions_taken")
                     ((string= action "work_task") "actions_taken")
                     ((string= action "handle_request") "actions_taken")
                     (t "actions_taken")))
           ;; Check for decisions, handoffs, blockers in content
           (has-decision (or (search "DECISION:" content) (search "decided" content)))
           (has-handoff (search "HANDOFF:" content))
           (has-blocker (or (search "BLOCKED:" content) (search "blocked" content)))
           (payload (make-hash-table :test #'equal)))
      ;; Build payload — append to existing column content
      (setf (gethash "agent_id" payload) agent-id)
      (setf (gethash column payload) (format nil "~a: ~a" action summary))
      (when has-decision
        (setf (gethash "decisions_made" payload) summary))
      (when has-handoff
        (setf (gethash "handoffs" payload) summary))
      (when has-blocker
        (setf (gethash "blockers" payload) summary))
      (api-put "/api/agents/memory" payload)
      ;; ALSO write to vault_notes daily note in agent's _memories column
      (write-vault-note-memory agent-id action summary))
    (error (e)
      (format t "  [memory-write-error] ~a~%" e))))

(defun write-vault-note-memory (agent-id action summary)
  "Append ghost memory to today's vault_notes daily note in {agent_id}_memories column.
   Uses Python helper for safe parameterized SQL."
  (handler-case
    (let* ((clean-summary (subseq summary 0 (min 200 (length summary))))
           (cmd (format nil "/root/gotcha-workspace/.venv/bin/python3 /opt/project-noosphere-ghosts/tools/write_vault_memory.py ~a ~a ~a"
                        agent-id action clean-summary))
           (output (uiop:run-program cmd :output :string :error-output :string :ignore-error-status t)))
      (when (search "OK:" output)
        (format t "  [vault-memory] ~a → daily note (~a)~%" agent-id action)))
    (error (e)
      (format t "  [vault-memory-error] ~a: ~a~%" agent-id e))))
