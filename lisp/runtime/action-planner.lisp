(in-package :af64.runtime.action-planner)

(defparameter *persona-dir*
  (uiop:ensure-directory-pathname
   (uiop:getenv "AF64_PERSONA_DIR" "~/gotcha-workspace/context/personas/")))

(defparameter *persona-map-file* (uiop:getenv "AF64_PERSONA_MAP_FILE"))
(defparameter *custom-persona-map* (make-hash-table :test #'equal))
(defparameter *persona-map-loaded* nil)

(defparameter *persona-cache* (make-hash-table :test #'equal))
(defparameter *job-ttl-seconds* (parse-integer (or (uiop:getenv "COGNITION_JOB_TTL_SECONDS") "21600")))
(defparameter *job-max-attempts* (parse-integer (or (uiop:getenv "COGNITION_JOB_MAX_ATTEMPTS") "3")))

(defun persona-map ()
  '(("nova" . nil)
    ("eliana" . "eliana.md")
    ("sarah" . "sarah.md")
    ("kathryn" . "kathryn.md")
    ("sylvia" . "sylvia.md")
    ("vincent" . "vincent.md")
    ("jmax" . "maxwell.md")
    ("lrm" . "morgan.md")))

(defun persona-path (agent-id)
  (let ((entry (assoc agent-id (persona-map) :test #'string-equal)))
    (when entry
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

(defun load-persona (agent-id agent-info)
  (or (gethash agent-id *persona-cache*)
      (let ((custom (resolve-custom-persona agent-id)))
        (when custom
          (setf (gethash agent-id *persona-cache*) custom)))
      (let ((path (persona-path agent-id)))
        (when (and path (probe-file path))
          (setf (gethash agent-id *persona-cache*)
                (strip-front-matter (uiop:read-file-string path)))))
      (let ((fallback (format nil "You are ~a, ~a at Eckenrode Muziekopname."
                              (or (gethash :full-name agent-info) agent-id)
                              (or (gethash :role agent-info) "staff"))))
        (setf (gethash agent-id *persona-cache*) fallback))))

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
                         :system-prompt (format nil "~a~%~%You are responding to a message in the Noosphere. Be concise (1-2 paragraphs)." persona)
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

(defun build-task-job (agent-id agent-info perception tier tick-number drive persona)
  (let ((task (first-vector-item (gethash :tasks perception))))
    (when task
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
                         :system-prompt (format nil "~a~%~%You are working on a task. Provide a concise progress update."
                                                persona)
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
         :max-attempts *job-max-attempts*)))))

(defun default-job-builder (agent-id agent-info perception tier tick-number drive)
  (let* ((persona (load-persona agent-id agent-info))
         (note (primary-user-note))
         (augmented (if note
                        (format nil "~a~%~a" persona note)
                        persona)))
    (or (build-message-job agent-id agent-info perception tier tick-number drive augmented)
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
