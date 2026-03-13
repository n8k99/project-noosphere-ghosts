(in-package :af64.runtime.tick-reporting)

(defun write-tick-report (report)
  (let ((sink "api"))
    (handler-case
        (api-post "/api/tick-reports" report)
      (error ()
        (setf sink "local")
        (ensure-runtime-dir)
        (with-open-file (stream (tick-reports-path)
                                :direction :output
                                :if-exists :append
                                :if-does-not-exist :create)
          (write-string (encode-json report) stream)
          (write-char #\Newline stream)))))
    (ignore-errors (rebuild-rollups))
    sink))
