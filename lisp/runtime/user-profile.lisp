(in-package :af64.runtime.user-profile)

(defparameter *primary-user-handle* (uiop:getenv "AF64_PRIMARY_USER_HANDLE"))
(defparameter *primary-user-id* (uiop:getenv "AF64_PRIMARY_USER_ID"))
(defparameter *primary-user-name* (uiop:getenv "AF64_PRIMARY_USER_NAME"))
(defparameter *primary-user-cache* nil)

(defun primary-user-handle ()
  *primary-user-handle*)

(defun primary-user-id ()
  *primary-user-id*)

(defun fetch-primary-user-profile ()
  (when (and (primary-user-id) (null *primary-user-cache*))
    (handler-case
        (setf *primary-user-cache*
              (api-get (format nil "/api/agents/~a" (primary-user-id))))
      (error () (setf *primary-user-cache* :unavailable))))
  (when (eq *primary-user-cache* :unavailable)
    nil)
  *primary-user-cache*)

(defun primary-user-agent-record ()
  (let ((profile (fetch-primary-user-profile)))
    (cond
      ((hash-table-p profile)
       (or (gethash :agent profile) profile))
      (t nil)))

(defun primary-user-note ()
  (let ((agent (primary-user-agent-record)))
    (when (and agent *primary-user-handle*)
      (let ((name (or (gethash :full_name agent) *primary-user-name* "the primary user"))
            (role (gethash :role agent))
            (department (gethash :department agent)))
        (format nil "Handle ~a refers to ~a~@[ (~a)~]~@[ in ~a~]."
                *primary-user-handle*
                name
                role
                department)))))
