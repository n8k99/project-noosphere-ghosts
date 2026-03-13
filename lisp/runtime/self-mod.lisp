(in-package :af64.runtime.self-mod)

(defparameter *ghost-behaviors* (make-hash-table :test #'equal)
  "Mutable registry of ghost behaviors keyed by agent or archetype identifiers.")

(defmacro define-ghost-behavior (name (ghost context) &body body)
  "Define or replace a behavior handler." 
  `(setf (gethash ,name *ghost-behaviors*)
         (lambda (,ghost ,context)
           ,@body)))

(defun dispatch-ghost-behavior (name ghost context &optional default)
  (let ((fn (gethash name *ghost-behaviors*)))
    (cond
      (fn (funcall fn ghost context))
      (default (funcall default ghost context))
      (t nil))))

(defun list-ghost-behaviors ()
  (loop for k being the hash-keys of *ghost-behaviors* collect k))

(defun install-behavior-patch (form-text &key (package :af64.runtime.self-mod))
  "Evaluate FORM-TEXT (a string) inside PACKAGE, allowing runtime code updates."
  (let ((*package* (find-package package)))
    (multiple-value-bind (form _) (read-from-string form-text)
      (eval form))))
