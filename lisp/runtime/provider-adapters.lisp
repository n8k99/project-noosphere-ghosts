(in-package :af64.runtime.provider-adapters)

(defparameter *default-tier-models*
  '((:prime . "claude-sonnet-4-20250514")
    (:working . "claude-sonnet-4-20250514")
    (:base . "claude-3-haiku-20240307")))

(defun read-json-from-source (value)
  (cond
    ((null value) nil)
    ((zerop (length value)) nil)
    ((char= (char value 0) #\@)
     (let ((path (subseq value 1)))
       (handler-case (parse-json (uiop:read-file-string path))
         (error () (format t "~&[provider-config] failed to read ~a~%" path) nil))))
    (t (handler-case (parse-json value)
         (error (e) (format t "~&[provider-config] failed to parse JSON: ~a~%" e) nil)))))

(defun %vector->list (value)
  (cond
    ((null value) '())
    ((vectorp value) (loop for item across value collect item))
    ((listp value) value)
    (t (list value))))

(defun %keywordize (value default)
  (cond
    ((keywordp value) value)
    ((stringp value) (json-keyword (string-downcase value)))
    (t default)))

(defun make-model-map (&rest sources)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (tier '(:prime :working :base))
      (setf (gethash tier table)
            (or (loop for source in sources
                      for candidate = (and source (gethash tier source))
                      when candidate return candidate)
                (cdr (assoc tier *default-tier-models*)))))
    table))

(defun parse-model-overrides-from-env ()
  (read-json-from-source (uiop:getenv "COGNITION_MODEL_MAP")))

(defparameter *global-model-overrides* (parse-model-overrides-from-env))

(defclass provider-adapter ()
  ((name :initarg :name :initform "provider" :reader provider-name)))

(defgeneric provider-generate (adapter job))

(defclass http-provider (provider-adapter)
  ((base-url :initarg :base-url :reader provider-base-url)
   (key-env :initarg :key-env :reader provider-key-env)
   (auth-header :initarg :auth-header :initform "Authorization" :reader provider-auth-header)
   (auth-template :initarg :auth-template :initform "Bearer {key}" :reader provider-auth-template)
   (model-map :initarg :model-map :reader provider-model-map)
   (max-tokens :initarg :max-tokens :initform 512 :reader provider-max-tokens)
   (extra-headers :initarg :extra-headers :initform '() :reader provider-extra-headers)))

(defclass anthropic-provider (provider-adapter)
  ((base-url :initarg :base-url :initform "https://api.anthropic.com/v1/messages" :reader provider-base-url)
   (key-env :initarg :key-env :initform "ANTHROPIC_API_KEY" :reader provider-key-env)
   (model-map :initarg :model-map :reader provider-model-map)
   (max-tokens :initarg :max-tokens :initform 800 :reader provider-max-tokens)))

(defclass stub-adapter (provider-adapter) ())

(defun cfg-value (cfg &rest keys)
  (loop for key in keys
        for value = (and cfg (gethash key cfg))
        when value return value))

(defun normalize-headers (value)
  (loop for entry in (%vector->list value)
        for name = (or (cfg-value entry :name :header) "")
        for val = (or (cfg-value entry :value) "")
        when (> (length name) 0)
          collect (cons name val)))

(defun load-provider-configs ()
  (let ((parsed (read-json-from-source (uiop:getenv "COGNITION_PROVIDER_CONFIG"))))
    (when parsed
      (%vector->list parsed))))

(defun default-provider-config ()
  (list (json-object
         :name "anthropic"
         :type "anthropic"
         :base_url "https://api.anthropic.com/v1/messages"
         :key_env "ANTHROPIC_API_KEY"
         :max_tokens 800)))

(defun ensure-model-map (provider-overrides)
  (make-model-map provider-overrides *global-model-overrides*))

(defun build-http-provider (cfg)
  (let* ((name (or (cfg-value cfg :name) "http"))
         (base-url (or (cfg-value cfg :base-url :base_url) "https://api.openai.com/v1/chat/completions"))
         (key-env (or (cfg-value cfg :key-env :key_env) (uiop:getenv "COGNITION_API_KEY_ENV") "ANTHROPIC_API_KEY"))
         (auth-header (or (cfg-value cfg :auth-header :auth_header) "Authorization"))
         (auth-template (or (cfg-value cfg :auth-template :auth_template) "Bearer {key}"))
         (max-tokens (or (cfg-value cfg :max-tokens :max_tokens) 512))
         (model-overrides (cfg-value cfg :models :model_map))
         (headers (normalize-headers (cfg-value cfg :headers)))
         (model-map (ensure-model-map model-overrides)))
    (make-instance 'http-provider
                   :name name
                   :base-url base-url
                   :key-env key-env
                   :auth-header auth-header
                   :auth-template auth-template
                   :model-map model-map
                   :max-tokens max-tokens
                   :extra-headers headers)))

(defun build-anthropic-provider (cfg)
  (let* ((name (or (cfg-value cfg :name) "anthropic"))
         (base-url (or (cfg-value cfg :base-url :base_url) "https://api.anthropic.com/v1/messages"))
         (key-env (or (cfg-value cfg :key-env :key_env) "ANTHROPIC_API_KEY"))
         (max-tokens (or (cfg-value cfg :max-tokens :max_tokens) 800))
         (model-overrides (cfg-value cfg :models :model_map))
         (model-map (ensure-model-map model-overrides)))
    (make-instance 'anthropic-provider
                   :name name
                   :base-url base-url
                   :key-env key-env
                   :model-map model-map
                   :max-tokens max-tokens)))

(defun build-provider-adapters ()
  (let ((configs (or (load-provider-configs) (default-provider-config)))
        (instances '()))
    (dolist (cfg configs)
      (let ((type (string-downcase (or (cfg-value cfg :type) "http"))))
        (cond
          ((string= type "anthropic")
           (push (build-anthropic-provider cfg) instances))
          ((string= type "http")
           (push (build-http-provider cfg) instances)))))
    (push (make-instance 'stub-adapter :name "stub") instances)
    (nreverse instances)))

(defun provider-api-key (env-name)
  (and env-name (uiop:getenv env-name)))

(defun format-auth-value (template api-key)
  (let ((token "{key}"))
    (cond
      ((and template (search token template))
       (with-output-to-string (out)
         (loop with start = 0
               for pos = (search token template :start2 start)
               while pos do
                 (write-string (subseq template start pos) out)
                 (write-string api-key out)
                 (setf start (+ pos (length token)))
               finally (write-string (subseq template start) out))))
      (template template)
      (t api-key))))

(defun tier-model (provider job)
  (let* ((tier (or (cognition-job-requested-model-tier job) "base"))
         (tier-key (%keywordize tier :base))
         (map (provider-model-map provider)))
    (or (gethash tier-key map) (gethash :base map))))

(defmethod provider-generate ((adapter http-provider) job)
  (let ((api-key (provider-api-key (provider-key-env adapter))))
    (when (and api-key (> (length api-key) 0))
      (let* ((context (cognition-job-input-context job))
             (system-prompt (gethash :system-prompt context ""))
             (system-message (json-object :role "system" :content system-prompt))
             (user-messages (%vector->list (gethash :messages context)))
             (full-messages (apply #'json-array (cons system-message user-messages)))
             (payload (json-object
                       :model (tier-model adapter job)
                       :max_tokens (provider-max-tokens adapter)
                       :messages full-messages))
             (headers (append (provider-extra-headers adapter)
                              (list (cons (provider-auth-header adapter)
                                          (format-auth-value (provider-auth-template adapter) api-key))
                                    (cons "Content-Type" "application/json")))))
        (multiple-value-bind (body status _)
            (http-post (provider-base-url adapter) (encode-json payload) :headers headers)
          (declare (ignore _))
          (when (= status 200)
            (let* ((data (parse-json body))
                   (choices (and data (gethash :choices data)))
                   (first-choice (and choices (> (length choices) 0) (aref choices 0)))
                   (message (and first-choice (gethash :message first-choice)))
                   (content (and message (gethash :content message))))
              (when content
                (make-cognition-result
                 :job-id (cognition-job-id job)
                 :agent-id (cognition-job-agent-id job)
                 :action-name (cognition-job-action-name job)
                 :content content
                 :provider-name (provider-name adapter)
                 :model-used (tier-model adapter job)
                 :metadata (cognition-job-input-context job))))))))))

(defmethod provider-generate ((adapter anthropic-provider) job)
  "Route all cognition through the OpenClaw gateway module."
  (let* ((context (cognition-job-input-context job))
         (system-prompt (or (gethash :system-prompt context) ""))
         (user-messages (%vector->list (gethash :messages context)))
         (non-system-messages
           (remove-if (lambda (m)
                        (and (hash-table-p m)
                             (string= (or (gethash :role m) "") "system")))
                      user-messages))
         (final-messages (if (null non-system-messages)
                             (list (json-object :role "user" :content "Continue."))
                             non-system-messages))
         (tier (cognition-job-requested-model-tier job))
         (model (model-for-tier (cond
                                  ((string= tier "prime") :prime)
                                  ((string= tier "working") :working)
                                  (t :base))))
         (content (gateway-complete system-prompt final-messages
                                    :tier (cond
                                            ((string= tier "prime") :prime)
                                            ((string= tier "working") :working)
                                            (t :base))
                                    :max-tokens (provider-max-tokens adapter))))
    (when content
      (make-cognition-result
       :job-id (cognition-job-id job)
       :agent-id (cognition-job-agent-id job)
       :action-name (cognition-job-action-name job)
       :content content
       :provider-name "openclaw-gateway"
       :model-used model
       :metadata (cognition-job-input-context job)))))

(defmethod provider-generate ((adapter stub-adapter) job)
  (let* ((context (cognition-job-input-context job))
         (content
           (cond
             ((string= (cognition-job-kind job) "respond_message")
              (let* ((msg (or (gethash :source-message context) (make-hash-table :test #'equal)))
                     (text (or (gethash :message msg) "")))
                (format nil "Acknowledged. I saw your message about: ~a"
                        (if (> (length text) 140)
                            (subseq text 0 140)
                            text))))
             ((string= (cognition-job-kind job) "work_task")
              (let* ((task (or (gethash :task context) (make-hash-table :test #'equal)))
                     (task-id (gethash :id task)))
                (format nil "Progress update: advancing task #~a and lining up the next concrete step."
                        (or task-id "unknown"))))
             (t "No cognition output available."))))
    (make-cognition-result
     :job-id (cognition-job-id job)
     :agent-id (cognition-job-agent-id job)
     :action-name (cognition-job-action-name job)
     :content content
     :provider-name (provider-name adapter)
     :model-used "deterministic-fallback"
     :metadata (cognition-job-input-context job))))

(defun build-default-provider-chain ()
  (build-provider-adapters))
