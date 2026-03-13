(in-package :af64.runtime.action-executor)

(defun execute-respond-message (result metadata)
  (let* ((source (gethash :source-message metadata (make-hash-table :test #'equal)))
         (payload (json-object
                   :from-agent (cognition-result-agent-id result)
                   :to-agent (json-array (gethash :from source))
                   :message (cognition-result-content result)
                   :channel (or (gethash :channel source) "noosphere")
                   :thread-id (gethash :thread-id source)
                   :metadata (json-object
                              :responding-to (format nil "~a" (gethash :id source))
                              :source "cognition_broker"
                              :job-id (cognition-result-job-id result)
                              :provider (cognition-result-provider-name result)
                              :cached (cognition-result-cached result)))))
    (let ((response (api-post "/api/conversations" payload)))
      (json-object
       :action :respond-message
       :job-id (cognition-result-job-id result)
       :msg-id (gethash :id source)
       :reply-id (gethash :id response)
       :provider (cognition-result-provider-name result)
       :cached (cognition-result-cached result)
       :response (subseq (cognition-result-content result)
                         0 (min 200 (length (cognition-result-content result))))))))

(defun execute-work-task (result metadata)
  (let ((task (gethash :task metadata)))
    (when task
      (api-patch (format nil "/api/af64/tasks/~a" (gethash :id task))
                 (json-object :status "in-progress")))
    (json-object
     :action :work-task
     :job-id (cognition-result-job-id result)
     :task-id (and task (gethash :id task))
     :provider (cognition-result-provider-name result)
     :cached (cognition-result-cached result)
     :response (subseq (cognition-result-content result)
                       0 (min 200 (length (cognition-result-content result))))))

(defun execute-cognition-result (result)
  (let* ((action (cognition-result-action-name result))
         (metadata (or (cognition-result-metadata result)
                       (make-hash-table :test #'equal))))
    (cond
      ((string= action "respond_message")
       (execute-respond-message result metadata))
      ((string= action "work_task")
       (execute-work-task result metadata))
      (t nil)))
