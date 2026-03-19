(in-package :af64.runtime.openclaw-gateway)

;;; Single gateway module for all ghost cognition.
;;; Reads the OAuth token from OpenClaw's credential store and routes
;;; all LLM requests through the Max subscription.

(defparameter *openclaw-auth-profiles-path*
  (merge-pathnames ".openclaw/agents/main/agent/auth-profiles.json"
                   (user-homedir-pathname)))

(defparameter *openclaw-token* nil)
(defparameter *anthropic-endpoint* "https://api.anthropic.com/v1/messages")

(defparameter *tier-models*
  '((:base    . "claude-3-haiku-20240307")
    (:working . "claude-sonnet-4-20250514")
    (:prime   . "claude-sonnet-4-20250514")))

(defun load-openclaw-token ()
  "Read the Anthropic OAuth token from OpenClaw's auth-profiles.json.
   Always re-reads from disk to pick up token refreshes."
  (let ((path *openclaw-auth-profiles-path*))
    (when (probe-file path)
      (with-open-file (stream path)
        (let* ((text (make-string (file-length stream)))
               (n (read-sequence text stream)))
          (declare (ignore n))
          (let* ((data (parse-json text))
                 (profiles (gethash :profiles data))
                 ;; Prefer claude-tasks, fall back to default
                 (profile (or (gethash :anthropic\:claude-tasks profiles)
                              (gethash :anthropic\:default profiles))))
            (when profile
              (setf *openclaw-token* (gethash :token profile)))))))))

(defun ensure-token ()
  "Always reload token from disk (OAuth tokens rotate)."
  (load-openclaw-token)
  (or *openclaw-token*
      (error "No OpenClaw Anthropic token found in ~a" *openclaw-auth-profiles-path*)))

(defun model-for-tier (tier)
  "Return the model ID for a given tier keyword (:base, :working, :prime)."
  (or (cdr (assoc tier *tier-models*))
      (cdr (assoc :base *tier-models*))))

(defun gateway-complete (system-prompt messages &key (tier :base) (max-tokens 800))
  "Send a completion request through the OpenClaw Max subscription.
   SYSTEM-PROMPT: string for the system message.
   MESSAGES: list of hash-tables with :role and :content keys.
   TIER: :base, :working, or :prime (selects model).
   MAX-TOKENS: maximum response tokens.
   Returns the response text string, or NIL on failure."
  (let* ((token (ensure-token))
         (model (model-for-tier tier))
         (payload (json-object
                   :model model
                   :max_tokens max-tokens
                   :system system-prompt
                   :messages (apply #'json-array messages)))
         (headers (list (cons "Authorization" (format nil "Bearer ~a" token))
                        (cons "anthropic-version" "2023-06-01")
                        (cons "anthropic-beta" "claude-code-20250219,oauth-2025-04-20")
                        (cons "Content-Type" "application/json"))))
    (let ((encoded-payload (encode-json payload)))
      (format t "  [gateway-debug] model=~a payload-len=~a~%" model (length encoded-payload))
      ;; Dump first failed payload to /tmp for inspection
      (when (not (probe-file #P"/tmp/ghost-payload-dumped.json"))
        (with-open-file (out #P"/tmp/ghost-payload-dumped.json" :direction :output :if-exists :supersede)
          (write-string encoded-payload out))
        (format t "  [gateway-debug] payload dumped to /tmp/ghost-payload-dumped.json~%"))
    (multiple-value-bind (body status)
        (http-post *anthropic-endpoint* encoded-payload :headers headers)
      (cond
        ((= status 200)
         (let* ((data (parse-json body))
                (content-blocks (and data (gethash :content data)))
                (blocks (if (vectorp content-blocks)
                            (loop for b across content-blocks collect b)
                            content-blocks))
                (text-block (find-if (lambda (b)
                                       (and (hash-table-p b)
                                            (string= (or (gethash :type b) "") "text")))
                                     blocks)))
           (when text-block
             (gethash :text text-block))))
        (t
         (format t "  [gateway-error] HTTP ~a: ~a~%" status (subseq body 0 (min 200 (length body))))
         nil))))))
