(in-package :af64.runtime.action-planner)

(defparameter *persona-dir*
  (uiop:ensure-directory-pathname
   (or (uiop:getenv "AF64_PERSONA_DIR") "~/gotcha-workspace/context/personas/")))

(defparameter *persona-map-file* (uiop:getenv "AF64_PERSONA_MAP_FILE"))
(defparameter *custom-persona-map* (make-hash-table :test #'equal))
(defparameter *persona-map-loaded* nil)

(defparameter *persona-cache* (make-hash-table :test #'equal))
(defparameter *job-ttl-seconds* (parse-integer (or (uiop:getenv "COGNITION_JOB_TTL_SECONDS") "21600")))
(defparameter *job-max-attempts* (parse-integer (or (uiop:getenv "COGNITION_JOB_MAX_ATTEMPTS") "3")))

(defun persona-map ()
  '(("nova" . "nova.md")
    ("eliana" . "eliana.md")
    ("sarah" . "sarah.md")
    ("kathryn" . "kathryn.md")
    ("sylvia" . "sylvia.md")
    ("vincent" . "vincent.md")
    ("jmax" . "maxwell.md")
    ("lrm" . "morgan.md")))

(defun persona-path (agent-id)
  (let ((entry (assoc agent-id (persona-map) :test #'string-equal)))
    (when (and entry (cdr entry))
      (merge-pathnames (cdr entry) *persona-dir*))))

(defun normalize-agent-key (agent-id)
  (string-downcase agent-id))

(defun coerce-to-string (value)
  (cond
    ((null value) "")
    ((stringp value) value)
    ((symbolp value) (symbol-name value))
    (t (princ-to-string value))))

(defun store-custom-persona (agent-id path)
  (let* ((defaults (and *persona-dir* (uiop:ensure-directory-pathname *persona-dir*)))
         (pathname (uiop:ensure-pathname (coerce-to-string path) :want-file t :ensure-defaults defaults))
         (resolved (if (probe-file pathname) (truename pathname) pathname)))
    (setf (gethash (normalize-agent-key (coerce-to-string agent-id)) *custom-persona-map*)
          (namestring resolved))))

(defun load-custom-persona-map ()
  (when (and *persona-map-file* (probe-file *persona-map-file*))
    (handler-case
        (let ((payload (parse-json (uiop:read-file-string *persona-map-file*))))
          (when (hash-table-p payload)
            (clrhash *custom-persona-map*)
            (maphash (lambda (agent path)
                       (when (and agent path)
                         (store-custom-persona (string agent) (string path))))
                     payload)))
      (error (e)
        (format t "~&[persona-map] failed to read ~a: ~a~%" *persona-map-file* e)))))

(defun ensure-persona-map-loaded ()
  (unless *persona-map-loaded*
    (load-custom-persona-map)
    (setf *persona-map-loaded* t)))

(defun strip-front-matter (text)
  (if (and text (>= (length text) 3) (string= (subseq text 0 3) "---"))
      (let ((end (search "\n---" text)))
        (if end
            (string-trim '(#\Newline #\Space) (subseq text (+ end 4)))
            text))
      text))

(defun read-persona-file (path)
  (handler-case
      (strip-front-matter (uiop:read-file-string path))
    (error () nil)))

(defun resolve-custom-persona (agent-id)
  (ensure-persona-map-loaded)
  (let ((path (gethash (normalize-agent-key agent-id) *custom-persona-map*)))
    (and path (read-persona-file path))))

(defun agent-id-to-em-staff-title (agent-id)
  "Convert agent_id (e.g. 'casey') to EM Staff doc title (e.g. 'CaseyHan')."
  ;; The agents table has document_id which links to the EM Staff doc
  ;; But we can also search by agent info
  nil)

(defun load-persona-from-em-staff (agent-id)
  "Load persona from EM Staff document in the DB (single source of truth).
   Uses the agents table document_id to find the right doc."
  (handler-case
      (let* ((response (api-get (format nil "/api/agents/~a" agent-id)))
             (agent-data (or (when (hash-table-p response) (gethash :agent response)) response))
             (doc-id (when (hash-table-p agent-data) (gethash :document-id agent-data))))
        (when doc-id
          (let* ((doc (api-get (format nil "/api/documents/~a" doc-id)))
                 (content (when (hash-table-p doc) (gethash :content doc))))
            (when content (strip-front-matter content)))))
    (error (e)
      (format t "  [em-staff-load] ~a: ~a~%" agent-id e)
      nil)))

(defun load-persona (agent-id agent-info)
  (let* ((full-name (or (gethash :full-name agent-info) agent-id))
         (role (or (gethash :role agent-info) "staff"))
         (identity-anchor (format nil "~%~%IDENTITY (non-negotiable): You are ~a. Your role is ~a at Eckenrode Muziekopname.~%STYLE: Be concise and direct. Do NOT sign off with your name, title, department, or any signature block. Do NOT write letters or use 'Dear [name]' / 'Thanks, [name]' format. Just deliver your work product."
                                  full-name role))
         (raw-persona
           (or ;; Try EM Staff document first (DB is source of truth)
               (load-persona-from-em-staff agent-id)
               ;; Fallback to custom persona map
               (handler-case
                   (resolve-custom-persona agent-id)
                 (error () nil))
               ;; Fallback to persona file
               (handler-case
                   (let ((path (persona-path agent-id)))
                     (when (and path (probe-file path))
                       (strip-front-matter (uiop:read-file-string path))))
                 (error () nil))
               ;; Last resort: generated
               (format nil "You are ~a, ~a at Eckenrode Muziekopname." full-name role))))
    (let ((result (concatenate 'string raw-persona identity-anchor)))
      (setf (gethash agent-id *persona-cache*) result))))

(defun compute-priority (energy tier drive-pressure action-name)
  (let* ((tier-name (if (and tier (not (keywordp tier))) (string-downcase tier) (or tier "base")))
         (tier-key (if (keywordp tier) tier (json-keyword tier-name)))
         (tier-bonus (or (gethash tier-key (json-object :prime 20 :working 10 :base 0 :dormant -100)) 0))
        (action-bonus (gethash action-name (json-object :respond-message 8 :work-task 5) 0)))
    (round (+ drive-pressure (* energy 0.35) tier-bonus action-bonus) 0.01)))

(defun make-cache-key (payload)
  (let* ((normalized (encode-json payload))
         (hash (sxhash normalized)))
    (format nil "~16,'0x" (logand hash #xffffffffffffffff))))

(defun first-vector-item (vec)
  (when (and vec (vectorp vec) (> (length vec) 0))
    (aref vec 0)))

(defun build-message-job (agent-id agent-info perception tier tick-number drive persona)
  (let ((msg (first-vector-item (gethash :messages perception))))
    (when msg
      (let* ((payload (json-object
                       :agent-id agent-id
                       :kind :respond-message
                       :message-id (gethash :id msg)
                       :thread-id (gethash :thread-id msg)
                       :from (gethash :from msg)
                       :message (gethash :message msg)
                       :tier tier))
             (priority (compute-priority (gethash :energy agent-info)
                                         tier
                                         (or (gethash :pressure drive) 50)
                                         :respond-message)))
        (make-cognition-job
         :agent-id agent-id
         :tick-number tick-number
         :kind "respond_message"
         :priority priority
         :requested-model-tier tier
         :input-context (json-object
                         :system-prompt (format nil "~a~%~%You are responding to a message in the Noosphere. Be concise (1-2 paragraphs). Speak directly. Do NOT write letters, sign-offs, or signature blocks. No 'Dear [name]', no 'Thanks, [YourName]', no title/department footer." persona)
                         :messages (json-array (json-object
                                               :role "user"
                                               :content (format nil "[~a]: ~a"
                                                                (gethash :from msg)
                                                                (gethash :message msg))))
                         :source-message msg)
         :cache-key (make-cache-key payload)
         :action-name "respond_message"
         :cost-estimate 5
         :expires-at (future-utc-iso *job-ttl-seconds*)
         :max-attempts *job-max-attempts*)))))

(defun load-hard-prompt (stage)
  "Load the hard prompt template for a pipeline stage from the DB."
  (let ((path-map '(("spec" . "Areas/Eckenrode Muziekopname/Engineering/Hard Prompts/tool-spec-format")
                     ("infra-review" . "Areas/Eckenrode Muziekopname/Engineering/Hard Prompts/infrastructure-review-guide")
                     ("design" . "Areas/Eckenrode Muziekopname/Engineering/Hard Prompts/architecture-review")
                     ("build" . "Areas/Eckenrode Muziekopname/Engineering/Hard Prompts/build-instructions")
                     ("security-review" . "Areas/Eckenrode Muziekopname/Engineering/Hard Prompts/security-review-guide")
                     ("test" . "Areas/Eckenrode Muziekopname/Engineering/Hard Prompts/qa-test-report")
                     ("deploy" . "Areas/Eckenrode Muziekopname/Engineering/Hard Prompts/deploy-checklist")
                     ("goal" . "")))) ;; Eliana delegates — no hard prompt needed
    (let ((path (cdr (assoc stage path-map :test #'string-equal))))
      (when (and path (> (length path) 0))
        (handler-case
            (let ((doc (api-get "/api/documents/search" (list :query path :limit 1))))
              (when (and doc (vectorp doc) (> (length doc) 0))
                (gethash :content (aref doc 0))))
          (error () nil))))))

(defun load-previous-stage-output (tool-name stage)
  "Load the output from the previous pipeline stage (e.g., SPEC.md for the design stage)."
  (let* ((prev-file-map '(("design" . "SPEC.md")
                           ("build" . "ARCHITECTURE.md")
                           ("test" . "TEST_RESULTS.md")
                           ("deploy" . "DEPLOY_LOG.md")))
         (prev-file (cdr (assoc stage prev-file-map :test #'string-equal))))
    (when prev-file
      (let ((path (format nil "~atools/~a/~a" (namestring (user-homedir-pathname))
                          tool-name prev-file)))
        (handler-case
            (when (probe-file path) (uiop:read-file-string path))
          (error () nil))))))

(defun build-pipeline-task-job (agent-id agent-info perception tier tick-number drive persona)
  "Build a job for a pipeline stage task. Injects hard prompt + previous stage context."
  (let ((task (first-vector-item (gethash :tasks perception))))
    (when task
      (let* ((stage (or (gethash :stage task) "open"))
             (tool-name (or (gethash :stage-notes task) 
                            ;; Extract tool name from task text: "[GOAL] Build tool: X" or "spec for X"
                            (let ((text (or (gethash :text task) "")))
                              (let ((pos (search "tool:" text :test #'char-equal)))
                                (when pos
                                  (string-trim '(#\Space) (subseq text (+ pos 5))))))
                            "unknown"))
             (hard-prompt (load-hard-prompt stage))
             (prev-output (load-previous-stage-output tool-name stage))
             (stage-requirements (cond
                                   ((string-equal stage "spec") "You MUST produce a detailed specification with ## headers, requirements, API endpoints, input/output schemas. Minimum 500 characters. Do NOT just say 'completed' — write the actual spec document.")
                                   ((string-equal stage "infra-review") "You MUST review actual infrastructure: database tables, API endpoints, deployment concerns, security boundaries. Minimum 400 characters. Reference specific tables, ports, services.")
                                   ((string-equal stage "design") "You MUST produce an architecture document with modules, functions, data flow, component diagrams. Minimum 500 characters. Name specific files, classes, schemas.")
                                   ((string-equal stage "build") "You MUST produce actual working code. Include 'def', 'fn', imports, full function bodies. Minimum 1000 characters of real code. No pseudocode. No summaries.")
                                   ((string-equal stage "security-review") "You MUST identify specific security concerns: auth, injection risks, secret handling, API key exposure, input sanitization. Minimum 400 characters.")
                                   ((string-equal stage "test") "You MUST write actual test cases with assertions, expected results, pass/fail for each. Minimum 400 characters.")
                                   ((string-equal stage "deploy") "You MUST document deployment steps: manifest updates, cron entries, PM2 config, file paths. Minimum 300 characters.")
                                   (t "Produce substantive output. Minimum 300 characters.")))
             (goal-text (handler-case
                           (let* ((goal-id (gethash :goal-id task)))
                             (if (and goal-id (numberp goal-id))
                                 (let ((goal-data (api-get (format nil "/api/af64/tasks/~a" goal-id))))
                                   (if (and goal-data (hash-table-p goal-data))
                                       (or (gethash :text goal-data) "")
                                       ""))
                                 ""))
                         (error () "")))
             (reality-anchor (format nil "REALITY ANCHOR: You are ~a, an employee at Eckenrode Muziekopname. You work on REAL software that runs on a production Linux server. Your tech stack: PostgreSQL (master_chronicle DB), Python 3, Rust (dpn-api), Next.js (dpn-kb), Ollama (local LLM), Kalshi API (prediction markets), RSS feeds. All tools go in ~~/gotcha-workspace/tools/. Do NOT reference Orbis, colonies, settlements, or any fictional worldbuilding. This is a real company building real software." agent-id))
             (agent-tools (handler-case
                              (let ((fn (find-symbol "GET-TOOLS-FOR-AGENT" :af64.runtime.action-executor)))
                                (if fn (funcall fn agent-id) '()))
                            (error () '())))
             (tools-prompt (handler-case
                               (let ((fn (find-symbol "FORMAT-TOOLS-FOR-PROMPT" :af64.runtime.action-executor)))
                                 (if fn (funcall fn agent-tools) nil))
                             (error () nil)))
             (dummy-tools-log (format t "  [planner-debug] ~a: ~a tools found, prompt ~a~%" agent-id (length agent-tools) (if tools-prompt "injected" "nil")))
             (system-prompt
               (format nil "~a~%~%~a~%~%~@[~a~%~%~]~@[INSTRUCTIONS FOR THIS STAGE:~%~a~%~%~]~@[PREVIOUS STAGE OUTPUT:~%~a~%~%~]~@[GOAL CONTEXT:~%~a~%~%~]You are working on pipeline stage: ~a~%Tool being built: ~a~%~%REQUIREMENTS: ~a~%~%You have tools available. You MUST use them by writing ```tool_call blocks. Example:
```tool_call
{\"tool\": \"market_scanner\", \"args\": {\"mode\": \"scan\"}}
```
Do NOT describe what you would do — actually call the tool. Do NOT write fake data — call a tool to get real data. Every pipeline stage MUST include at least one tool_call block with a real tool from your available tools list. Prose without tool calls will be REJECTED. Produce your full ~a output with actual tool calls and real results."
                       persona reality-anchor tools-prompt hard-prompt prev-output goal-text stage tool-name
                       stage-requirements stage))
             (rejection-feedback (let ((sn (gethash :stage-notes task)))
                                   (if (stringp sn) sn "")))
             (payload (json-object
                       :agent-id agent-id
                       :kind :work-task
                       :task-id (gethash :id task)
                       :stage stage
                       :tool-name tool-name
                       :tier tier
                       :tick tick-number
                       :feedback-hash (sxhash rejection-feedback)))
             (priority (compute-priority (gethash :energy agent-info)
                                         tier
                                         (or (gethash :pressure drive) 50)
                                         :work-task)))
        (make-cognition-job
         :agent-id agent-id
         :tick-number tick-number
         :kind "work_task"
         :priority priority
         :requested-model-tier (if (string-equal stage "build") "opus" tier) ;; Opus for build stage
         :input-context (json-object
                         :system-prompt system-prompt
                         :messages (json-array
                                    (json-object
                                     :role "user"
                                     :content (format nil "Task #~a: ~a~%Stage: ~a~%Tool: ~a~%~@[~%PREVIOUS ATTEMPT FEEDBACK:~%~a~%~%Fix the issues above and resubmit your full work product.~%~]~%Produce your complete ~a deliverable now."
                                                      (gethash :id task)
                                                      (gethash :text task)
                                                      stage tool-name
                                                      (when (search "REJECTED" rejection-feedback) rejection-feedback)
                                                      stage)))
                         :task task)
         :cache-key (make-cache-key payload)
         :action-name "work_task"
         :cost-estimate (if (string-equal stage "build") 15 5)
         :expires-at (future-utc-iso *job-ttl-seconds*)
         :max-attempts *job-max-attempts*)))))

(defun build-task-job (agent-id agent-info perception tier tick-number drive persona)
  "Route to pipeline task builder for engineering pipeline tasks, generic for others."
  (let ((task (first-vector-item (gethash :tasks perception))))
    (when task
      (let ((stage (or (gethash :stage task) "open")))
        (if (and (not (string-equal stage "open"))
                 (not (string-equal stage "done")))
            ;; Pipeline task — use pipeline-aware builder
            (build-pipeline-task-job agent-id agent-info perception tier tick-number drive persona)
            ;; Generic task
            (let* ((payload (json-object
                             :agent-id agent-id
                             :kind :work-task
                             :task-id (gethash :id task)
                             :status (gethash :status task)
                             :text (gethash :text task)
                             :tier tier))
                   (priority (compute-priority (gethash :energy agent-info)
                                               tier
                                               (or (gethash :pressure drive) 50)
                                               :work-task)))
              (make-cognition-job
               :agent-id agent-id
               :tick-number tick-number
               :kind "work_task"
               :priority priority
               :requested-model-tier tier
               :input-context (json-object
                               :system-prompt (format nil "~a~%~%You are working on a task. Provide a concise progress update.~%~%When you finish a task, output: COMPLETE: #<task_id>" persona)
                               :messages (json-array
                                          (json-object
                                           :role "user"
                                           :content (format nil "Task #~a: ~a~%Status: ~a"
                                                            (gethash :id task)
                                                            (gethash :text task)
                                                            (gethash :status task))))
                               :task task)
               :cache-key (make-cache-key payload)
               :action-name "work_task"
               :cost-estimate 8
               :expires-at (future-utc-iso *job-ttl-seconds*)
               :max-attempts *job-max-attempts*)))))))

(defun build-request-job (agent-id agent-info perception tier tick-number drive persona)
  "Build a job to process an agent_request directed at this agent."
  (let ((req (first-vector-item (gethash :requests perception))))
    (when req
      (let* ((status (or (gethash :status req) ""))
             (response-text (or (gethash :response req) ""))
             (from (or (gethash :from req) ""))
             (subject (or (gethash :subject req) ""))
             (req-type (or (gethash :type req) ""))
             (rel-context (format-relationships perception))
             ;; Build context based on request status
             (user-content
               (cond
                 ;; Resolved with response = Nathan gave feedback, ghost should acknowledge
                 ((and (string-equal status "resolved") (> (length response-text) 0))
                  (format nil "Request #~a from ~a has been RESOLVED by management.~%Subject: ~a~%Type: ~a~%Response: ~a~%~%Acknowledge this resolution. If the response includes instructions, note them for your next work cycle."
                          (gethash :id req) from subject req-type response-text))
                 ;; Deferred = put it aside, focus elsewhere
                 ((string-equal status "deferred")
                  (format nil "Request #~a from ~a has been DEFERRED.~%Subject: ~a~%Type: ~a~%~%This is on hold. Do not pursue it right now. Briefly acknowledge."
                          (gethash :id req) from subject req-type))
                 ;; Decision needed = escalated, ghost needs to weigh in
                 ((string-equal status "decision_needed")
                  (format nil "Request #~a from ~a needs a DECISION.~%Subject: ~a~%Type: ~a~%Context: ~a~%~%Analyze this and recommend a course of action to your manager."
                          (gethash :id req) from subject req-type (or (gethash :context req) "")))
                 ;; No handler / in progress = ghost should work on it
                 (t
                  (format nil "Request #~a from ~a (type: ~a)~%Subject: ~a~%Context: ~a~%~%This request is directed at you. Produce a concrete response or deliverable. Do NOT write a letter or address anyone as 'Dear [name]'. Just state your analysis and actions directly.~%~%Available actions:~%- If this belongs to someone else: REASSIGN: #~a to=<agent_id>~%- If you need a collaborator to build something: HANDOFF: @<agent_id> <instructions>~%- If you can handle it: just respond with your work."
                          (gethash :id req) from req-type subject (or (gethash :context req) "") (gethash :id req)))))
             (payload (json-object
                       :agent-id agent-id
                       :kind :handle-request
                       :request-id (gethash :id req)
                       :status status
                       :from from
                       :subject subject
                       :tier tier))
             (priority (compute-priority (gethash :energy agent-info)
                                         tier
                                         (or (gethash :pressure drive) 50)
                                         :respond-message)))  ;; Same priority as messages
        (make-cognition-job
         :agent-id agent-id
         :tick-number tick-number
         :kind "handle_request"
         :priority priority
         :requested-model-tier tier
         :input-context (json-object
                         :system-prompt (format nil "~a~a~%~%You are processing an organizational request in the Noosphere. Be concrete and professional." persona rel-context)
                         :messages (json-array (json-object :role "user" :content user-content))
                         :source-message (json-object :id (gethash :id req) :from from :channel "requests"))
         :cache-key (make-cache-key payload)
         :action-name "handle_request"
         :cost-estimate 5
         :expires-at (future-utc-iso *job-ttl-seconds*)
         :max-attempts *job-max-attempts*))))) 

(defun engineering-work-prompt (persona role responsibilities goals)
  (format nil "~a~%~%Your role: ~a (Engineering department)~%~%Your responsibilities:~%~a~%~%Your goals:~%~a~%~%CRITICAL CONTEXT: Most departments at EM have ZERO tools. They cannot do their jobs without tooling that Engineering builds. Here is the current deficit:~%- Art department (7 agents): needs graph curation tools (list_unlinked_docs, link_agent_to_doc, get_agent_links)~%- Marketing/Content (9 agents): needs editorial pipeline tools (draft_thought_police_post, list_reader_comments, assign_editorial)~%- Legal (8 agents): needs document review tools (list_pending_reviews, flag_compliance_issue, approve_document)~%- Strategy (5 agents): needs market intelligence tools (create_report, pull_kalshi_data, competitor_scan)~%- Music (4 agents): needs content tools (list_episodes, analyze_audio_features, tag_corpus)~%- Support (3 agents): needs admin tools (list_open_tickets, update_task_status, route_request)~%~%Your Engineering teammates:~%- casey (Casey Han) — Systems Engineer~%- danielle (Danielle Green) — Backend/QA Engineer~%- devin (Devin Park) — Full-Stack Developer~%- elise (Elise Park) — AI Systems Engineer~%- isaac (Isaac Miller) — Infrastructure Engineer~%- morgan (Morgan Fields) — DevOps Engineer~%- samir (Samir Khanna) — AI Architect~%- sanjay (Sanjay Patel) — Data Scientist/Security~%~%Your job this cycle: Pick ONE tool from the deficit above that you can spec out. Write a concrete tool specification with:~%1. Tool name (snake_case, e.g. list_episodes)~%2. Purpose — one sentence~%3. Input parameters (name, type, required/optional)~%4. Expected output (JSON structure)~%5. Database tables/columns it reads or writes~%6. Python function signature~%~%The spec must be IMPLEMENTATION-READY. A developer reading this should be able to write the code without asking questions.~%~%Then send it to the builder. At the end of your output, write exactly:~%HANDOFF: @builder Build <tool_name> per this spec.~%~%This will trigger an actual code generation pipeline that writes the tool into the GOTCHA workspace."
          persona role responsibilities goals))

(defun triage-work-prompt (persona role tasks)
  (let ((task-list (if (and tasks (> (length tasks) 0))
                       (with-output-to-string (s)
                         (loop for task across tasks
                               for i from 1
                               do (format s "~%~a. [#~a] ~a (status: ~a, assignee: ~a, dept: ~a)"
                                          i
                                          (gethash :id task)
                                          (gethash :text task)
                                          (gethash :status task)
                                          (or (gethash :assignee task) "NONE")
                                          (or (gethash :department task) "NONE"))))
                       "No unclassified tasks found.")))
    (format nil "~a~%~%Your role: ~a — Task Triage Specialist for the Office of the CEO~%~%TASK: Review unclassified/unassigned tasks and route them to the correct department.~%~%Available departments: Engineering, art, content_brand, audience_experience, legal, music, strategic_office, support, cross_functional, digital_partnership~%~%Tasks needing classification:~a~%~%For each task, output one line in this exact format:~%CLASSIFY: #<task_id> department=<dept> assignee=<agent_id_or_dept_head>~%~%Rules:~%- If the task mentions code/build/API/tools → Engineering (head: eliana)~%- If the task mentions content/editorial/blog/writing → content_brand (head: sylvia)~%- If the task mentions art/image/visual/design → art (head: vincent)~%- If the task mentions legal/compliance/contract → legal (head: jmax)~%- If the task mentions music/audio/episode/podcast → music (head: lrm)~%- If the task mentions strategy/market/data → strategic_office (head: kathryn)~%- If unsure, assign to the most relevant department head~%~%Classify ALL listed tasks. Be decisive."
            persona role task-list)))

(defun executive-delegation-prompt (persona role dept tasks)
  (let ((task-list (if (and tasks (> (length tasks) 0))
                       (with-output-to-string (s)
                         (loop for task across tasks
                               for i from 1
                               do (format s "~%~a. [#~a] ~a (status: ~a, assignee: ~a)"
                                          i
                                          (gethash :id task)
                                          (gethash :text task)
                                          (gethash :status task)
                                          (or (gethash :assignee task) "UNASSIGNED"))))
                       "")))
    (format nil "~a~%~%Your role: ~a — Head of ~a department~%~%You have tasks in your department queue. Tasks assigned to YOU should be delegated to your team members. You are a manager — you assign work, you don't do it yourself.~%~%Department tasks:~a~%~%Available actions:~%- DELEGATE: #<task_id> assignee=<staff_agent_id> — assign a task to a team member~%- COMPLETE: #<task_id> — mark a task as done (only if truly finished)~%~%Rules:~%- If a task is assigned to you → DELEGATE it to the best-fit team member~%- If a task is unassigned → DELEGATE it~%- If a task is already assigned to a team member → skip it (they own it)~%- If a task is done → COMPLETE it~%- Delegate ALL tasks that are assigned to you. You should have ZERO tasks on yourself after this."
            persona role dept task-list)))

(defun format-relationships (perception)
  "Build a relationships context string from perception data."
  (let* ((rels (gethash :relationships perception))
         (mentor (when (hash-table-p rels) (or (gethash :mentor rels) "")))
         (reports-to (when (hash-table-p rels) (or (gethash :reports-to rels) "")))
         (collabs (when (hash-table-p rels) (gethash :collaborators rels)))
         (activity (when (hash-table-p rels) (gethash :collaborator-activity rels)))
         (parts '()))
    (when (and mentor (> (length mentor) 0))
      (push (format nil "Your mentor: ~a (seek their guidance on unfamiliar areas)" mentor) parts))
    (when (and reports-to (> (length reports-to) 0))
      (push (format nil "You report to: ~a (align your work with their priorities)" reports-to) parts))
    (when (and collabs (> (length collabs) 0))
      (push (format nil "Your collaborators: ~{~a~^, ~} (coordinate with them, reference their work)"
                    (coerce collabs 'list)) parts))
    (when (and activity (> (length activity) 0))
      (push "Recent collaborator activity:" parts)
      (loop for a across activity
            do (when (hash-table-p a)
                 (push (format nil "  - ~a: ~a"
                               (gethash :agent a)
                               (subseq (or (gethash :message a) "") 0
                                       (min 100 (length (or (gethash :message a) ""))))) parts))))
    (if parts
        (format nil "~%~%RELATIONSHIPS:~%~{~a~%~}" (nreverse parts))
        "")))

(defun department-work-prompt (persona role dept responsibilities goals drive perception)
  (let ((drive-name (if (hash-table-p drive) (or (gethash :drive-name drive) "work") "work"))
        (pressure (if (hash-table-p drive) (or (gethash :pressure drive) 50) 50))
        (rel-context (format-relationships perception)))
    (format nil "~a~%~%Your role: ~a (~a department)~%~%Your responsibilities:~%~a~%~%Your goals:~%~a~%~%Your highest drive: ~a (pressure: ~a/100)~a~%~%You are starting a work cycle. Produce a CONCRETE deliverable — not reflections or musings. Based on your role, this should be one of:~%- A report or analysis with specific findings~%- A recommendation with actionable next steps~%- A draft document, editorial, or creative brief~%- A review of existing work with specific feedback~%- A proposal for collaboration with your collaborators~%~%When relevant, coordinate with your collaborators and mentor. Reference their recent work if you're aware of it. Address deliverables to your manager when appropriate.~%~%Write as yourself. Be specific, cite real things when possible. 2-3 paragraphs of substance."
            persona role dept responsibilities goals drive-name pressure rel-context)))

(defun build-proactive-job (agent-id agent-info perception tier tick-number drive persona)
  "Build a job for self-initiated work based on the agent's responsibilities and drives."
  (let ((is-triage (or (string-equal agent-id "lara") (string-equal agent-id "sarah"))))
  (when (or (gethash :proactive-eligible perception) is-triage)
    (let* ((resp (gethash :responsibilities perception))
           (responsibilities (if (hash-table-p resp) (or (gethash :responsibilities resp) "") ""))
           (goals (if (hash-table-p resp) (or (gethash :goals resp) "") ""))
           (role (if (hash-table-p resp) (or (gethash :role resp) "") ""))
           (dept (if (hash-table-p resp) (or (gethash :department resp) "") ""))
           (agent-dept (or (gethash :department agent-info) dept))
           (agent-tier (or (gethash :agent-tier agent-info) ""))
           (is-triage (or (string-equal agent-id "lara") (string-equal agent-id "sarah")))
           (is-exec (string-equal agent-tier "executive"))
           (tasks-in-perception (gethash :tasks perception))
           ;; Delegation triggers when tasks are unassigned OR assigned to this executive
           (has-delegatable-tasks (and tasks-in-perception
                                      (> (length tasks-in-perception) 0)
                                      (some (lambda (tk) 
                                              (let ((assignee (gethash :assignee tk)))
                                                (or (not assignee)
                                                    (string-equal assignee agent-id))))
                                            (coerce tasks-in-perception 'list))))
           (prompt (cond
                     ;; Triage agents classify unassigned tasks
                     ((and is-triage tasks-in-perception (> (length tasks-in-perception) 0))
                      (triage-work-prompt persona role tasks-in-perception))
                     ;; Executives with delegatable tasks (unassigned or assigned to them) → delegate
                     ((and is-exec has-delegatable-tasks)
                      (executive-delegation-prompt persona role agent-dept tasks-in-perception))
                     ;; Engineering builds tools
                     ((or (string-equal agent-dept "Engineering")
                          (string-equal agent-dept "engineering"))
                      (engineering-work-prompt persona role responsibilities goals))
                     ;; Everyone else → department work
                     (t (department-work-prompt persona role agent-dept responsibilities goals drive perception))))
           (payload (json-object :agent-id agent-id :kind :proactive-work :tick tick-number))
           (priority (compute-priority (gethash :energy agent-info)
                                       tier
                                       (or (gethash :pressure drive) 50)
                                       :work-task)))
      (make-cognition-job
       :agent-id agent-id
       :tick-number tick-number
       :kind "proactive_work"
       :priority priority
       :requested-model-tier tier
       :input-context (json-object
                       :system-prompt prompt
                       :messages (json-array (json-object
                                             :role "user"
                                             :content "Begin your work cycle. Produce a deliverable."))
                       :source-message (json-object :id 0 :from "system" :channel "noosphere"))
       :cache-key (make-cache-key payload)
       :action-name "proactive_work"
       :cost-estimate 5
       :expires-at (future-utc-iso *job-ttl-seconds*)
       :max-attempts *job-max-attempts*)))))

(defun default-job-builder (agent-id agent-info perception tier tick-number drive)
  "Build a cognition job. Priority: messages > requests > tasks. NO proactive work."
  (let* ((persona (load-persona agent-id agent-info))
         (note (handler-case (primary-user-note) (error () nil)))
         (augmented (if note
                        (format nil "~a~%~a" persona note)
                        persona)))
    (or (build-message-job agent-id agent-info perception tier tick-number drive augmented)
        (build-request-job agent-id agent-info perception tier tick-number drive augmented)
        (build-task-job agent-id agent-info perception tier tick-number drive augmented))))

(defun build-cognition-job (agent-id agent-info perception tier tick-number drive)
  (or (dispatch-ghost-behavior
       agent-id
       (json-object :agent-info agent-info
                    :perception perception
                    :tier tier
                    :tick-number tick-number
                    :drive drive)
       (lambda (ghost ctx)
         (declare (ignore ghost ctx))
         (default-job-builder agent-id agent-info perception tier tick-number drive)))
      (default-job-builder agent-id agent-info perception tier tick-number drive)))
