(in-package :af64.runtime.api)

(defparameter *api-base*
  (or (uiop:getenv "DPN_API_URL") "http://localhost:8080"))

(defparameter *api-key*
  (or (uiop:getenv "DPN_API_KEY") "dpn-nova-2026"))

(defun build-url (path &optional params)
  (let ((base (concatenate 'string *api-base* path)))
    (if params
        (concatenate 'string base "?" (encode-query params))
        base)))

(defun encode-query (params)
  (let ((pairs (normalize-params params)))
    (uiop:join-string
     (loop for (k . v) in pairs collect
           (format nil "~a=~a" (url-encode (keyword->json-key k)) (url-encode (format-value v))))
     :separator "&")))

(defun normalize-params (params)
  (cond
    ((hash-table-p params)
     (loop for key being the hash-keys of params
           collect (cons key (gethash key params))))
    ((and (listp params) (evenp (length params)))
     (loop for (k v) on params by #'cddr collect (cons k v)))
    ((listp params) params)
    (t '())))

(defun url-encode (text)
  (let ((str (if (stringp text) text (princ-to-string text)))
        (safe "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~"))
    (with-output-to-string (out)
      (loop for ch across str do
            (if (find ch safe)
                (write-char ch out)
                (format out "%%%02X" (char-code ch)))))))

(defun format-value (value)
  (cond
    ((stringp value) value)
    ((numberp value) (princ-to-string value))
    ((keywordp value) (keyword->json-key value))
    ((symbolp value) (symbol-name value))
    (t (princ-to-string value))))

(defun default-headers ()
  (list (cons "X-API-Key" *api-key*)
        (cons "Content-Type" "application/json")))

(defun parse-response (body status)
  (cond
    ((>= status 400)
     (error "API error ~a: ~a" status body))
    ((or (null body) (string= body ""))
     (make-hash-table :test #'equal))
    (t (parse-json body))))

(defun api-get (path &optional params)
  (multiple-value-bind (body status stderr)
      (http-get (build-url path params) :headers (list (cons "X-API-Key" *api-key*)))
    (declare (ignore stderr))
    (parse-response body status)))

(defun api-post (path payload)
  (multiple-value-bind (body status stderr)
      (http-post (build-url path)
                 (encode-json payload)
                 :headers (default-headers))
    (declare (ignore stderr))
    (parse-response body status)))

(defun api-patch (path payload)
  (multiple-value-bind (body status stderr)
      (http-patch (build-url path)
                  (encode-json payload)
                  :headers (default-headers))
    (declare (ignore stderr))
    (parse-response body status)))
