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
    (setf (gethash :rest table) 5)
    (setf (gethash :task-complete table) 15)
    (setf (gethash :milestone table) 50)
    (setf (gethash :nathan-recognition table) 75)
    (setf (gethash :orchestrator-attention table) 8)
    (setf (gethash :peer-ack table) 4)
    (setf (gethash :tool-creation table) 30)
    table))

(defparameter +out-of-specialty-mult+ 2.0)

;; Anthropic March 2026 promo: 2x usage outside 8AM-2PM ET weekdays (through March 28)
(defun off-peak-p ()
  "Returns T if current time is outside 8AM-2PM ET on weekdays (off-peak for Anthropic promo)."
  (multiple-value-bind (sec min hour date month year day) (get-decoded-time)
    (declare (ignore sec min date month year))
    ;; ET is UTC-4 (EDT in March). Convert: ET hour = UTC hour - 4
    ;; We get local time which is UTC on the server, so adjust
    (let ((et-hour (mod (- hour 4) 24))
          (weekday-p (< day 5)))  ;; 0=Mon..4=Fri are weekdays
      ;; Off-peak = NOT (8 <= et-hour < 14) on weekdays, OR any weekend hour
      (or (not weekday-p)
          (< et-hour 8)
          (>= et-hour 14)))))

(defun promo-multiplier ()
  "Returns 2 during off-peak (Anthropic March 2026 promo), 1 otherwise.
   Promo expires March 28, 2026."
  (multiple-value-bind (sec min hour date month year) (get-decoded-time)
    (declare (ignore sec min hour))
    (if (and (= year 2026) (= month 3) (<= date 28) (off-peak-p))
        2
        1)))

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
         (base (or (gethash key +energy-costs+) -5))
         (adjusted (if (or in-specialty (>= base 0))
                       base
                       (round (* base +out-of-specialty-mult+))))
         ;; Anthropic March 2026 promo: halve energy costs during off-peak
         (promo (promo-multiplier)))
    (if (and (> promo 1) (< adjusted 0))
        (round (/ adjusted promo))  ;; Half cost during off-peak
        adjusted)))
