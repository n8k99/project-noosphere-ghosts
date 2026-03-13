(in-package :af64.runtime.perception)

(defun empty-perception ()
  (let ((table (make-hash-table :test #'equal)))
    (setf (gethash :messages table) #())
    (setf (gethash :tasks table) #())
    (setf (gethash :documents table) #())
    (setf (gethash :team-activity table) #())
    table))

(defun perception-path (agent-id)
  (format nil "/api/perception/~a" agent-id))

(defun perceive (agent-id tier last-tick-at)
  (let ((since (or last-tick-at "1970-01-01T00:00:00Z")))
    (handler-case
        (api-get (perception-path agent-id) (list :tier tier :since since))
      (error (e)
        (declare (ignore e))
        (format t "  [perception-error] ~a~%" agent-id)
        (empty-perception)))))

(defun vector-non-empty-p (value)
  (and value (vectorp value) (> (length value) 0)))

(defun has-actionable-items (perception)
  (or (vector-non-empty-p (gethash :messages perception))
      (vector-non-empty-p (gethash :tasks perception))))
