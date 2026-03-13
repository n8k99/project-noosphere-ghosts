(in-package :af64.runtime.energy)

(defparameter +energy-cap+ 100)
(defparameter +energy-floor+ 0)
(defparameter +energy-starting+ 50)

(defparameter +energy-costs+
  (let ((table (make-hash-table :test #'equal)))
    (setf (gethash :rest table) 0)
    (setf (gethash :communicate table) -3)
    (setf (gethash :respond-message table) -5)
    (setf (gethash :routine-work table) -8)
    (setf (gethash :deep-work table) -15)
    (setf (gethash :opus-work table) -35)
    (setf (gethash :delegate table) -5)
    (setf (gethash :idle table) 0)
    table))

(defparameter +energy-rewards+
  (let ((table (make-hash-table :test #'equal)))
    (setf (gethash :rest table) 3)
    (setf (gethash :task-complete table) 15)
    (setf (gethash :milestone table) 50)
    (setf (gethash :nathan-recognition table) 75)
    (setf (gethash :orchestrator-attention table) 8)
    (setf (gethash :peer-ack table) 4)
    (setf (gethash :tool-creation table) 30)
    table))

(defparameter +out-of-specialty-mult+ 2.0)

(defun agent-path (agent-id)
  (format nil "/api/agents/~a" agent-id))

(defun update-energy (agent-id delta)
  (let ((response (api-patch (format nil "/api/agents/~a/state" agent-id)
                             (json-object :energy-delta delta))))
    (or (gethash :energy response) +energy-starting+)))

(defun get-energy (agent-id)
  (handler-case
      (let* ((data (api-get (agent-path agent-id)))
             (agent (gethash :agent data)))
        (or (and agent (gethash :energy agent)) +energy-starting+))
    (error () +energy-starting+)))

(defun get-cost (action &optional (in-specialty t))
  (let* ((key (if (keywordp action) action (json-keyword (string action))))
         (base (or (gethash key +energy-costs+) -5)))
    (if (or in-specialty (>= base 0))
        base
        (round (* base +out-of-specialty-mult+)))))
