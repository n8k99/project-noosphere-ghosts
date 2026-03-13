(require :asdf)
(asdf:load-system :af64)

(defpackage :af64.tools.onboard
  (:use :cl)
  (:import-from :uiop :ensure-directory-pathname :getcwd :ensure-pathname :read-file-string :url-encode)
  (:import-from :af64.utils.json :json-object :encode-json :parse-json)
  (:import-from :af64.utils.http :http-get)
  (:export :main))

(in-package :af64.tools.onboard)

(defparameter *config-dir*
  (ensure-directory-pathname (merge-pathnames "config/" (uiop:getcwd))))

(uiop:ensure-directories-exist *config-dir*)

(defun shell-escape (value)
  (let ((text (or value "")))
    (with-output-to-string (out)
      (write-char #\' out)
      (loop for ch across text do
            (if (char= ch #\')
                (write-string "'\\''" out)
                (write-char ch out)))
      (write-char #\' out))))

(defun prompt (message &key default allow-empty)
  (format t "~a~@[ [~a]~]: " message default)
  (force-output)
  (let ((input (read-line)))
    (cond
      ((and (zerop (length input)) default) default)
      ((or allow-empty (> (length input) 0)) input)
      (t (prompt message :default default :allow-empty allow-empty)))))

(defun yes-p (message &key (default t))
  (let* ((suffix (if default "Y/n" "y/N"))
         (answer (string-downcase (prompt (format nil "~a (~a)" message suffix) :allow-empty t))))
    (cond
      ((string= answer "") default)
      ((member answer '("y" "yes")) t)
      ((member answer '("n" "no")) nil)
      (t (yes-p message :default default)))))

(defun normalize-url (url)
  (let ((trimmed (string-right-trim "/" url)))
    (if (> (length trimmed) 0) trimmed url)))

(defun ensure-directory (path)
  (let ((pathname (ensure-directory-pathname path)))
    (unless (probe-file pathname)
      (when (yes-p (format nil "Directory ~a does not exist. Create it?" pathname))
        (uiop:ensure-directories-exist pathname)))
    pathname))

(defun detect-persona-files (dir)
  (let* ((pattern (merge-pathnames "*.*" dir))
         (files (directory pattern)))
    (remove-if-not (lambda (p)
                     (member (string-downcase (or (pathname-type p) "")) '("md" "txt" "org")))
                   files)))

(defun json-vector->list (value)
  (cond
    ((null value) '())
    ((vectorp value) (loop for item across value collect item))
    ((listp value) value)
    (t (list value))))

(defun string-prefix-p (prefix string)
  (and (<= (length prefix) (length string))
       (string= prefix string :end1 (length prefix) :end2 (length prefix))))

(defun string-suffix-p (suffix string)
  (let ((len (length suffix))
        (total (length string)))
    (and (<= len total)
         (string= suffix string :start2 (- total len)))))

(defun strip-wiki-handle (text)
  (let ((trim (string-trim '(#\Space #\[ #\]) text)))
    trim))

(defun normalize-wiki-handle (text)
  (let ((trim (string-trim '(#\Space) text)))
    (cond
      ((and (string-prefix-p "[[" trim) (string-suffix-p "]]" trim)) trim)
      ((> (length trim) 0) (format nil "[[~a]]" trim))
      (t ""))))

(defun fetch-agent-candidates (api-url api-key query)
  (let* ((base (normalize-url api-url))
         (endpoint (if (and query (> (length query) 0))
                       (format nil "~a/api/agents?search=~a" base (url-encode query))
                       (format nil "~a/api/agents" base))))
    (handler-case
        (multiple-value-bind (body status _)
            (http-get endpoint :headers (list (cons "X-API-Key" api-key)))
          (declare (ignore _))
          (when (< status 300)
            (json-vector->list (parse-json body))))
      (error (e)
        (format t "~&[onboard] Failed to fetch agents: ~a~%" e)
        nil))))

(defun describe-agent (agent)
  (let ((name (or (gethash :full_name agent) (gethash :id agent)))
        (role (gethash :role agent))
        (dept (gethash :department agent)))
    (format nil "~a~@[ — ~a~]~@[ / ~a~]"
            name role dept)))

(defun select-primary-user (api-url api-key)
  (when (yes-p "Would you like to link your personal wiki handle to a DB profile?" :default t)
    (loop
      (let* ((raw-handle (prompt "Enter your wiki handle (e.g., [[NathanEckenrode]])" :allow-empty nil))
             (handle (normalize-wiki-handle raw-handle))
             (query (strip-wiki-handle raw-handle))
             (candidates (fetch-agent-candidates api-url api-key query)))
        (if (null candidates)
            (when (not (yes-p "No matches found. Try again?" :default t))
              (return (values nil nil nil)))
            (progn
              (format t "~%Matching profiles:~%")
              (loop for agent in candidates
                    for idx from 1 do
                    (format t "  [~d] ~a (ID: ~a)~%"
                            idx (describe-agent agent) (gethash :id agent)))
              (let ((choice (prompt "Select a number (blank to search again)" :allow-empty t)))
                (if (zerop (length choice))
                    (format t "No selection made; enter a new search.~%")
                    (handler-case
                        (let ((index (parse-integer choice)))
                          (if (or (< index 1) (> index (length candidates)))
                              (format t "Invalid selection.~%")
                              (let ((selected (nth (1- index) candidates)))
                                (return (values handle
                                                (gethash :id selected)
                                                (or (gethash :full_name selected)
                                                    (gethash :id selected)))))))
                      (error () (format t "Invalid selection.~%"))))))))))

(defun select-persona-mapping (persona-dir)
  (let ((files (detect-persona-files persona-dir))
        (mapping (make-hash-table :test #'equal)))
    (unless files
      (format t "No persona files found in ~a. You can edit the map later.~%" persona-dir)
      (return-from select-persona-mapping mapping))
    (format t "Found the following persona files:~%")
    (loop for file in files
          for idx from 1 do
          (format t "  [~d] ~a~%" idx (namestring file)))
    (when (yes-p "Would you like to map specific ghost IDs to these files?" :default nil)
      (loop for agent = (prompt "Enter ghost ID to map (blank to finish)" :allow-empty t)
            while (> (length agent) 0) do
            (let ((choice (prompt "Enter file number for this ghost" :allow-empty nil)))
              (handler-case
                  (let ((index (parse-integer choice)))
                    (if (or (< index 1) (> index (length files)))
                        (format t "Invalid selection.~%")
                        (let ((file (nth (1- index) files)))
                          (setf (gethash agent mapping) (namestring file))
                          (format t "  ↳ mapped ~a → ~a~%" agent (namestring file)))))
                (error () (format t "Invalid selection.~%"))))))
    mapping))

(defun write-json-file (path content)
  (with-open-file (stream path :direction :output :if-exists :supersede :if-does-not-exist :create)
    (write-string (encode-json content) stream)
    (write-char #\Newline stream))
  (namestring path))

(defun collect-provider-configs ()
  (let ((providers '())
        (env-exports '()))
    (when (yes-p "Configure an LLM provider now?" :default t)
      (loop
        (let* ((name (prompt "Provider name" :default "openai"))
               (base-url (prompt "Chat completion base URL" :default "https://api.openai.com/v1/chat/completions"))
               (key-env (prompt "Environment variable for API key" :default "OPENAI_API_KEY"))
               (auth-header (prompt "Auth header name" :default "Authorization"))
               (auth-template (prompt "Auth template (use {key} placeholder)" :default "Bearer {key}"))
               (max-tokens (prompt "Max tokens per call" :default "800"))
               (prime-model (prompt "Prime tier model" :default "gpt-4o"))
               (working-model (prompt "Working tier model" :default "gpt-4o-mini"))
               (base-model (prompt "Base tier model" :default "gpt-4o-mini"))
               (api-key (prompt (format nil "Enter value for ~a (leave blank to skip)" key-env) :allow-empty t)))
          (push (json-object
                 :name name
                 :type "http"
                 :base_url base-url
                 :key_env key-env
                 :auth_header auth-header
                 :auth_template auth-template
                 :max_tokens (parse-integer max-tokens)
                 :models (json-object :prime prime-model :working working-model :base base-model))
                providers)
          (when (> (length api-key) 0)
            (push (cons key-env api-key) env-exports))
          (unless (yes-p "Add another provider?" :default nil)
            (return))))
    (values (nreverse providers) env-exports)))

(defun test-api-connection (base-url api-key)
  (when (yes-p "Test API connectivity now?" :default t)
    (handler-case
        (multiple-value-bind (body status _)
            (http-get (format nil "~a/api/health" (normalize-url base-url))
                      :headers (list (cons "X-API-Key" api-key)))
          (declare (ignore body _))
          (if (< status 300)
              (format t "API connection looks good (~a).~%" status)
              (format t "API responded with status ~a.~%" status)))
      (error (e) (format t "API test failed: ~a~%" e)))))

(defun current-timestamp ()
  (multiple-value-bind (second minute hour day month year)
      (decode-universal-time (get-universal-time) 0)
    (format nil "~4,'0D-~2,'0D-~2,'0D ~2,'0D:~2,'0D:~2,'0D UTC"
            year month day hour minute second)))

(defun write-env-file (path pairs)
  (with-open-file (stream path :direction :output :if-exists :supersede :if-does-not-exist :create)
    (format stream "# AF64 environment (generated ~a)~%~%" (current-timestamp))
    (dolist (pair pairs)
      (format stream "export ~a=%s~%" (car pair) (shell-escape (cdr pair)))))
  (namestring path))

(defun collect-memory-settings ()
  (values (prompt "Memory table for persistence" :default "vault_notes")
          (string-downcase (prompt "Default memory layer" :default "daily"))))

(defun hash-table->json-object (table)
  (let ((json (json-object)))
    (maphash (lambda (k v)
               (setf (gethash k json) v)) table)
    json))

(defun perform-onboarding ()
  (format t "~%=== Noosphere Ghosts Onboarding ===~%")
  (let* ((existing-url (or (uiop:getenv "DPN_API_URL") "http://localhost:8080"))
         (existing-key (uiop:getenv "DPN_API_KEY"))
         (api-url (normalize-url (prompt "DPN API URL" :default existing-url)))
         (api-key (prompt "DPN API Key" :default existing-key :allow-empty nil)))
    (test-api-connection api-url api-key)
    (multiple-value-bind (user-handle user-id user-name)
        (select-primary-user api-url api-key)
      (let* ((persona-dir (ensure-directory (prompt "Directory containing ghost personas" :default (or (uiop:getenv "AF64_PERSONA_DIR") "~/gotcha-workspace/context/personas/"))))
             (persona-map (select-persona-mapping persona-dir))
             (memory-table nil)
             (memory-layer nil))
        (multiple-value-setq (memory-table memory-layer) (collect-memory-settings))
        (multiple-value-bind (providers provider-env) (collect-provider-configs)
          (let* ((env-path (merge-pathnames "af64.env" *config-dir*))
                 (persona-map-path (and (> (hash-table-count persona-map) 0)
                                        (write-json-file (merge-pathnames "persona-map.json" *config-dir*)
                                                         (hash-table->json-object persona-map))))
                 (provider-file (and providers
                                     (write-json-file (merge-pathnames "provider-config.json" *config-dir*)
                                                      (coerce providers 'vector))))
                 (env-vars (append (list (cons "DPN_API_URL" api-url)
                                         (cons "DPN_API_KEY" api-key)
                                         (cons "AF64_PERSONA_DIR" (namestring persona-dir))
                                         (cons "AF64_MEMORY_TABLE" memory-table)
                                         (cons "AF64_MEMORY_LAYER" memory-layer))
                                   (when user-handle
                                     (list (cons "AF64_PRIMARY_USER_HANDLE" user-handle)))
                                   (when user-id
                                     (list (cons "AF64_PRIMARY_USER_ID" user-id)))
                                   (when user-name
                                     (list (cons "AF64_PRIMARY_USER_NAME" user-name)))
                                   (when persona-map-path
                                     (list (cons "AF64_PERSONA_MAP_FILE" persona-map-path)))
                                   (when provider-file
                                     (list (cons "COGNITION_PROVIDER_CONFIG"
                                                 (concatenate 'string "@" provider-file))))
                                   provider-env))
            (write-env-file env-path env-vars)
            (format t "~%✔ Wrote ~a~%" env-path)
            (when persona-map-path
              (format t "✔ Persona map stored at ~a~%" persona-map-path))
            (when provider-file
              (format t "✔ Provider config stored at ~a~%" provider-file))
            (when user-handle
              (format t "✔ Linked ~a to agent ID ~a~%" user-handle user-id))
            (format t "~%Next steps:~%  1. Run 'source ~a' before launching the tick engine.~%" env-path)
            (when provider-file
              (format t "  2. Ensure the provider API key env vars referenced above are exported.~%"))))))))

(defun main ()
  (perform-onboarding))

(main)
