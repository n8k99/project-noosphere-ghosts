(in-package :af64.runtime.drive)

(defun drives-path (agent-id)
  (format nil "/api/agents/~a/drives" agent-id))

(defun tick-drives ()
  (api-post "/api/drives/tick" (json-object)))

(defun fulfill-drive (agent-id drive-name amount)
  (api-post (format nil "/api/drives/~a/fulfill" agent-id)
            (json-object :drive-name drive-name :amount amount)))

(defun highest-pressure-drive (agent-id)
  (handler-case
      (let ((drives (api-get (drives-path agent-id))))
        (when (and drives (vectorp drives) (> (length drives) 0))
          (let ((top (aref drives 0)))
            (json-object
             :drive-name (gethash :drive-name top)
             :pressure (or (gethash :pressure top) 50)
             :satisfaction (or (gethash :satisfaction top) 50)
             :frustration (or (gethash :frustration top) 0)))))
    (error () nil))
