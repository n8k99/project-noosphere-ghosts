(in-package :af64.runtime.action-executor)

;; Import JSON utils from the project's own json module
;; parse-json and encode-json are already imported via packages.lisp

;;;; UNIVERSAL TOOL SOCKET
;;;; Gives ghosts hands. Any tool in the registry can be called by any ghost
;;;; whose tool_scope overlaps with the tool's scope.

(defvar *tool-registry* (make-hash-table :test #'equal)
  "Registry of available tools, loaded from config/tool-registry.json")

(defvar *tool-registry-loaded* nil)

(defun load-tool-registry ()
  "Load tool definitions from JSON config."
  (handler-case
      (let* ((config-path (merge-pathnames
                           "config/tool-registry.json"
                           (truename "/opt/project-noosphere-ghosts/")))
             (content (uiop:read-file-string config-path))
             (parsed (af64.utils.json:parse-json content )))
        (setf *tool-registry* (or (gethash :TOOLS parsed) (make-hash-table :test #'equal)))
        (setf *tool-registry-loaded* t)
        (format t "  [tool-socket] Loaded ~a tools from registry~%"
                (hash-table-count *tool-registry*)))
    (error (e)
      (format t "  [tool-socket-error] Failed to load registry: ~a~%" e))))

(defun get-tools-for-agent (agent-id)
  "Return list of (tool-name . tool-def) pairs available to this agent based on tool_scope."
  (unless *tool-registry-loaded* (load-tool-registry))
  ;; Fetch agent's tool_scope from API
  (handler-case
      (let* ((agent-response (api-get (format nil "/api/agents/~a" agent-id)))
             (agent-data (when (and agent-response (hash-table-p agent-response))
                           (or (gethash :AGENT agent-response) agent-response)))
             (scope-raw (when (and agent-data (hash-table-p agent-data))
                          (gethash :TOOL-SCOPE agent-data)))
             ;; Normalize scope items to lowercase strings for comparison
             (scope-list (cond
                           ((listp scope-raw) scope-raw)
                           ((vectorp scope-raw) (coerce scope-raw 'list))
                           ((stringp scope-raw) (list scope-raw))
                           (t '())))
             (scope (mapcar (lambda (s) (string-downcase (if (symbolp s) (symbol-name s) s))) scope-list))
             (available '()))
        (maphash (lambda (tool-name tool-def)
                   (let* ((tool-scope (gethash :SCOPE tool-def))
                          (tool-scope-raw (cond
                                            ((listp tool-scope) tool-scope)
                                            ((vectorp tool-scope) (coerce tool-scope 'list))
                                            (t '())))
                          (tool-scope-list (mapcar (lambda (s) (string-downcase (if (symbolp s) (symbol-name s) s))) tool-scope-raw))
                          (status (gethash :STATUS tool-def)))
                     ;; Tool is available if agent scope overlaps tool scope AND tool is built
                     (when (and (not (equal status "not_built"))
                                (intersection scope tool-scope-list :test #'string-equal))
                       (push (cons tool-name tool-def) available))))
                 *tool-registry*)
        available)
    (error (e)
      (format t "  [tool-socket] Error fetching scope for ~a: ~a~%" agent-id e)
      '())))

(defun format-tools-for-prompt (tools)
  "Format available tools as a structured block for the LLM prompt."
  (if (null tools)
      nil
      (with-output-to-string (s)
        (format s "AVAILABLE TOOLS:~%")
        (format s "To use a tool, output a TOOL_CALL block (keep arg values SHORT — no multi-line content in JSON):~%")
        (format s "```tool_call~%{\"tool\": \"tool_name\", \"args\": {\"param\": \"value\"}}~%```~%~%")
        (format s "IMPORTANT: Never put long spec/content text directly in a tool_call JSON value — it breaks parsing.~%")
        (format s "Instead: write your spec/content as normal markdown ABOVE the tool_call, then call the tool with just the tool_name.~%")
        (format s "For build_tool: write your spec above, then call with just {\"tool\": \"build_tool\", \"args\": {\"tool_name\": \"name_here\"}}.~%~%")
        (dolist (entry tools)
          (let* ((raw-name (car entry))
                 ;; Convert keyword back to snake_case for display
                 (name (if (symbolp raw-name)
                           (string-downcase (substitute #\_ #\- (symbol-name raw-name)))
                           raw-name))
                 (def (cdr entry))
                 (desc (gethash :DESCRIPTION def))
                 (params (gethash :PARAMETERS def)))
            (format s "- **~a**: ~a~%" name desc)
            (when (and params (hash-table-p params) (> (hash-table-count params) 0))
              (maphash (lambda (k v) (format s "    ~a: ~a~%" k v)) params))
            (format s "~%"))))))

(defun safe-json-extract (json-text)
  "Try to parse JSON, handling common LLM failures like unescaped newlines in strings."
  ;; First try direct parse
  (handler-case
      (af64.utils.json:parse-json json-text)
    (error ()
      ;; Fallback: try to extract tool name and args with regex-like search
      ;; This handles the case where the spec/content field breaks JSON encoding
      (let ((tool-pos (search "\"tool\"" json-text))
            (args-table (make-hash-table :test #'equal)))
        (when tool-pos
          (let* ((val-start (position #\" json-text :start (+ tool-pos 7)))
                 (val-end (when val-start (position #\" json-text :start (1+ val-start))))
                 (tool-name (when (and val-start val-end)
                              (subseq json-text (1+ val-start) val-end))))
            ;; Try to extract simple string args before the content blows up
            (let ((result (make-hash-table :test #'equal)))
              (when tool-name
                ;; Extract tool_name/tool-name arg if present
                (dolist (key-pat '("\"tool_name\"" "\"TOOL-NAME\"" "\"TOOL_NAME\""))
                  (let ((kp (search key-pat json-text)))
                    (when kp
                      (let* ((vs (position #\" json-text :start (+ kp (length key-pat) 1)))
                             (ve (when vs (position #\" json-text :start (1+ vs))))
                             (v (when (and vs ve) (subseq json-text (1+ vs) ve))))
                        (when v (setf (gethash :TOOL-NAME args-table) v))))))
                (setf (gethash :TOOL result) (intern (string-upcase (substitute #\- #\_ tool-name)) :keyword))
                (setf (gethash :ARGS result) args-table)
                result))))))))

(defun parse-tool-calls (content)
  "Extract tool_call blocks from LLM output. Returns list of (tool-name . args-hash)."
  (let ((results '())
        (search-from 0))
    (loop
      (let ((start (search "```tool_call" content :start2 search-from)))
        (unless start (return results))
        (let* ((json-start (+ start (length "```tool_call")))
               ;; Skip whitespace/newlines after marker
               (json-start (position-if (lambda (c) (not (member c '(#\Newline #\Return #\Space #\Tab)))) content :start json-start))
               (end (search "```" content :start2 (or json-start (1+ start)))))
          (if (and json-start end (> end json-start))
              (let ((json-text (string-trim '(#\Space #\Tab #\Newline #\Return)
                                            (subseq content json-start end))))
                (let ((parsed (safe-json-extract json-text)))
                  (when parsed
                    (let ((tool-name (gethash :TOOL parsed))
                          (args (or (gethash :ARGS parsed) (make-hash-table :test #'equal))))
                      (when tool-name
                        (push (cons tool-name args) results)))))
                (setf search-from (1+ end)))
              (return results)))))))

(defun normalize-tool-key (name)
  "Convert a tool name string to the keyword the JSON parser produces.
   e.g. 'query_db' -> :QUERY-DB"
  (intern (string-upcase (substitute #\- #\_ name)) :keyword))

(defun build-cli-args (args tool-def)
  "Build CLI argument list from tool call args hash table."
  (let ((positional-key (gethash :POSITIONAL-ARG tool-def))
        (result '()))
    ;; Positional arg first
    (when positional-key
      (let ((val (or (gethash (intern (string-upcase positional-key) :keyword) args)
                     (gethash positional-key args))))
        (when val
          (push (if (stringp val) val (format nil "~a" val)) result))))
    ;; Named flags
    (maphash (lambda (key val)
               (let ((key-str (string-downcase (if (symbolp key) (symbol-name key) (format nil "~a" key)))))
                 (when (and (stringp val)
                            (not (equal key-str (or positional-key ""))))
                   (push (format nil "--~a" (substitute #\- #\_ key-str)) result)
                   (push val result))))
             args)
    (nreverse result)))

(defun execute-tool-call (tool-name args agent-id)
  "Execute a single tool call. Returns result string."
  (unless *tool-registry-loaded* (load-tool-registry))
  (let ((tool-def (or (gethash (normalize-tool-key tool-name) *tool-registry*)
                      (gethash tool-name *tool-registry*))))
    (unless tool-def
      (return-from execute-tool-call
        (format nil "ERROR: Tool '~a' not found in registry." tool-name)))
    ;; Check if tool is built
    (when (equal (gethash :STATUS tool-def) "not_built")
      (return-from execute-tool-call
        (format nil "ERROR: Tool '~a' has not been built yet." tool-name)))
    (let ((script (gethash :SCRIPT tool-def))
          (command (gethash :COMMAND tool-def))
          (dangerous (gethash :DANGEROUS tool-def)))
      ;; Safety: don't run dangerous tools without explicit approval
      (when dangerous
        (return-from execute-tool-call
          (format nil "ERROR: Tool '~a' requires approval before execution." tool-name)))
      (format t "  [tool-exec] ~a calling ~a~%" agent-id tool-name)
      (handler-case
          (cond
            ;; Special case: query_db — run psql directly
            ((string-equal tool-name "query_db")
             (let* ((sql (or (gethash :SQL args) "SELECT 1"))
                    ;; Safety: read-only queries only
                    (sql-lower (string-downcase sql)))
               (when (or (search "insert" sql-lower)
                         (search "update" sql-lower)
                         (search "delete" sql-lower)
                         (search "drop" sql-lower)
                         (search "alter" sql-lower)
                         (search "truncate" sql-lower))
                 (return-from execute-tool-call "ERROR: Only SELECT queries allowed."))
               (let ((output (uiop:run-program
                              (list "sudo" "-u" "postgres" "psql" "-d" "master_chronicle" "-t" "-c" sql)
                              :output :string :error-output :string
                              :ignore-error-status t)))
                 (subseq output 0 (min 2000 (length output))))))

            ;; Special case: build_tool — async subprocess
            ((string-equal tool-name "build_tool")
             (let* ((tool-to-build (or (gethash :TOOL_NAME args) (gethash :TOOL-NAME args) "unnamed"))
                    ;; 1. Try file on disk
                    (spec-from-file (handler-case
                                        (uiop:read-file-string
                                         (format nil "/root/gotcha-workspace/tools/~a/spec.md" tool-to-build))
                                      (error () nil)))
                    ;; 2. Try DB stage_notes chain: get goal_id from build task, pull spec+design+infra-review
                    (spec-from-db (unless spec-from-file
                                    (handler-case
                                        (let* ((task-json (api-get (format nil "/api/af64/tasks?assigned_to=~a&status=in-progress&limit=1" agent-id)))
                                               (tasks (if (vectorp task-json) (coerce task-json 'list)
                                                         (or (gethash :TASKS task-json) (list))))
                                               (task (when tasks (first tasks)))
                                               (goal-id (when task (gethash :GOAL-ID task))))
                                          (when goal-id
                                            ;; Pull spec, infra-review, and design stage_notes for this goal
                                            (let* ((stages-json (api-get (format nil "/api/af64/tasks?goal_id=~a&limit=10" goal-id)))
                                                   (all-tasks (if (vectorp stages-json) (coerce stages-json 'list)
                                                                (or (gethash :TASKS stages-json) (list))))
                                                   (spec-notes "")
                                                   (design-notes "")
                                                   (infra-notes ""))
                                              (dolist (t-item all-tasks)
                                                (let ((stage (gethash :STAGE t-item))
                                                      (notes (or (gethash :STAGE-NOTES t-item) "")))
                                                  (when (and stage (> (length notes) 0))
                                                    (cond ((string-equal stage "spec") (setf spec-notes notes))
                                                          ((string-equal stage "design") (setf design-notes notes))
                                                          ((string-equal stage "infra-review") (setf infra-notes notes))))))
                                              (let ((combined (format nil "# SPEC~%~a~%~%# INFRASTRUCTURE REVIEW~%~a~%~%# DESIGN~%~a" spec-notes infra-notes design-notes)))
                                                (when (> (length combined) 50) combined)))))
                                      (error (e) (format nil "DB spec lookup failed: ~a" e)))))
                    ;; 3. Inline arg fallback
                    (spec (or spec-from-file spec-from-db (gethash :SPEC args) (gethash "SPEC" args) ""))
                    (spec-file (format nil "/tmp/ghost-spec-~a-~a.md" agent-id tool-to-build)))
               (with-open-file (s spec-file :direction :output :if-exists :supersede)
                 (write-string spec s))
               (uiop:launch-program
                (list script spec-file tool-to-build agent-id)
                :output (format nil "/tmp/tool-builder-~a.log" tool-to-build)
                :error-output (format nil "/tmp/tool-builder-~a.err" tool-to-build))
               (format nil "Build started for ~a. Claude Code is writing files to /root/gotcha-workspace/tools/~a/" tool-to-build tool-to-build)))

            ;; Special case: write_document — INSERT into documents table
            ((string-equal tool-name "write_document")
             (let* ((path (or (gethash :PATH args) "Uncategorized/untitled"))
                    (title (or (gethash :TITLE args) "Untitled"))
                    (doc-content (or (gethash :CONTENT args) ""))
                    ;; Escape single quotes for SQL
                    (escaped-path (substitute #\' #\' path))
                    (escaped-title (substitute #\' #\' title))
                    (escaped-content (with-output-to-string (s)
                                      (loop for c across doc-content
                                            do (if (char= c #\') (write-string "''" s) (write-char c s))))))
               (let ((output (uiop:run-program
                              (list "sudo" "-u" "postgres" "psql" "-d" "master_chronicle" "-t" "-c"
                                    (format nil "INSERT INTO documents (path, title, content, created_at, updated_at) VALUES ('~a', '~a', '~a', NOW(), NOW()) ON CONFLICT (path) DO UPDATE SET content = EXCLUDED.content, title = EXCLUDED.title, updated_at = NOW() RETURNING id;"
                                            escaped-path escaped-title escaped-content))
                              :output :string :error-output :string
                              :ignore-error-status t)))
                 (format nil "Document written: ~a (id: ~a)" path (string-trim '(#\Space #\Newline) output)))))

            ;; General case: run Python script
            (script
             (let* ((interpreter (or (gethash :INTERPRETER tool-def)
                                     "/root/gotcha-workspace/.venv/bin/python3"))
                    (cli-args (build-cli-args args tool-def))
                    (full-cmd (append (list interpreter script) cli-args))
                    (output (uiop:run-program full-cmd
                                              :output :string
                                              :error-output :string
                                              :ignore-error-status t)))
               (subseq output 0 (min 3000 (length output)))))

            ;; Command-based tool
            (command
             (let* ((cmd-args (loop for key being the hash-keys of args
                                    for val being the hash-values of args
                                    collect val))
                    (full-cmd (format nil "~a ~{~a~^ ~}" command cmd-args))
                    (output (uiop:run-program
                             (list "/bin/bash" "-c" full-cmd)
                             :output :string :error-output :string
                             :ignore-error-status t)))
               (subseq output 0 (min 2000 (length output)))))

            (t (format nil "ERROR: Tool '~a' has no script or command configured." tool-name)))
        (error (e)
          (format nil "ERROR executing ~a: ~a" tool-name e))))))

(defun process-tool-calls (content agent-id)
  "Parse and execute all tool calls in LLM output. Returns results alist."
  (handler-case
      (let* ((calls (parse-tool-calls content))
             (results '()))
        (format t "  [tool-socket] ~a: parsed ~a tool call(s)~%" agent-id (length calls))
        (dolist (call calls)
          (let* ((tool-name (if (symbolp (car call))
                                (string-downcase (substitute #\_ #\- (symbol-name (car call))))
                                (car call)))
                 (args (cdr call))
                 (result (execute-tool-call tool-name args agent-id)))
            (format t "  [tool-result] ~a/~a: ~a~%" agent-id tool-name
                    (subseq result 0 (min 80 (length result))))
            (push (list tool-name result) results)))
        (nreverse results))
    (error (e)
      (format t "  [tool-socket-error] process-tool-calls failed for ~a: ~a~%" agent-id e)
      '())))
