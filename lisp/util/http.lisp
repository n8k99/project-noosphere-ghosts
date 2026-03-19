(in-package :af64.utils.http)

(defun %format-header (header)
  (etypecase header
    (cons (format nil "~a: ~a" (car header) (cdr header)))
    (string header)))

(defun http-request (method url &key headers body (timeout 30))
  (let* ((header-args (loop for header in headers
                            collect "-H"
                            collect (%format-header header)))
         ;; For bodies, use --data-binary @- and pipe via stdin
         ;; This avoids shell arg length limits and special char issues
         (body-args (when body (list "--data-binary" "@-")))
         (args (append (list "curl" "-sS" "-L" "-X" (string-upcase method)
                             "--max-time" (format nil "~d" timeout)
                             "-w" "\nHTTPSTATUS:%{http_code}\n")
                       header-args
                       body-args
                       (list url))))
    (multiple-value-bind (stdout stderr exit-code)
        (uiop:run-program args
                          :ignore-error-status t
                          :output :string
                          :error-output :string
                          :input (when body (make-string-input-stream body)))
      (let ((status (or exit-code 0))
            (out (or stdout "")))
        (multiple-value-bind (body-string http-status)
            (parse-curl-output out)
          (let ((final-status (if (= status 0) http-status status)))
            (values body-string final-status stderr)))))))

(defun parse-curl-output (text)
  (let* ((marker "HTTPSTATUS:")
         (pos (search marker text :from-end t)))
    (if pos
        (let* ((body (subseq text 0 pos))
               (status-start (+ pos (length marker)))
               (status-text (string-trim '(#\Space #\Tab #\Newline)
                                         (subseq text status-start)))
               (status (parse-integer status-text :junk-allowed t)))
          (values (string-trim '(#\Newline) body) status))
        (values text 0))))

(defun http-get (url &key headers)
  (http-request "GET" url :headers headers))

(defun http-post (url body &key headers)
  (http-request "POST" url :headers headers :body body))

(defun http-patch (url body &key headers)
  (http-request "PATCH" url :headers headers :body body))

(defun http-put (url body &key headers)
  (http-request "PUT" url :headers headers :body body))
