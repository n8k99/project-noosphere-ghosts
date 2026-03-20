(in-package :af64.runtime.task-scheduler)

;;; --- Task Scheduling ---
;;; Tasks can have three scheduling fields (set via API PATCH):
;;;   :scheduled-at  — ISO8601 datetime; task is not actionable until this time
;;;   :deadline      — ISO8601 datetime; urgency increases as deadline approaches
;;;   :recurrence    — JSON string describing repeat pattern, e.g.:
;;;                    {"interval":"daily"}
;;;                    {"interval":"weekly","day":"monday"}
;;;                    {"interval":"monthly","day_of_month":1}
;;;                    {"interval":"hours","every":12}

(defun task-ready-p (task now-universal)
  "Return T if the task is ready to be worked on (scheduled_at is nil or in the past)."
  (let ((scheduled-at (or (gethash :scheduled-at task)
                          (gethash :SCHEDULED-AT task))))
    (or (null scheduled-at)
        (string= scheduled-at "")
        (let ((scheduled-time (parse-iso8601 scheduled-at)))
          (or (null scheduled-time)
              (<= scheduled-time now-universal))))))

(defun deadline-urgency-boost (task now-universal)
  "Calculate an urgency boost (0-50) based on how close the deadline is.
   Returns 0 if no deadline. Max 50 when deadline is past or within 1 hour.
   Scales linearly over 48 hours."
  (let ((deadline (or (gethash :deadline task)
                      (gethash :DEADLINE task))))
    (if (or (null deadline) (string= deadline ""))
        0
        (let ((deadline-time (parse-iso8601 deadline)))
          (if (null deadline-time)
              0
              (let* ((remaining (- deadline-time now-universal))
                     (hours-48 (* 48 3600)))
                (cond
                  ;; Past deadline — max urgency
                  ((<= remaining 0) 50)
                  ;; Within 1 hour — near-max
                  ((<= remaining 3600) 45)
                  ;; Within 48 hours — scale linearly
                  ((<= remaining hours-48)
                   (round (* 40 (/ (- hours-48 remaining) (float hours-48)))))
                  ;; More than 48 hours out — no boost
                  (t 0))))))))

(defun filter-scheduled-tasks (tasks now-universal)
  "Filter a vector of tasks, keeping only those whose scheduled_at has passed.
   Returns a new vector."
  (if (or (null tasks) (= (length tasks) 0))
      tasks
      (let ((ready '()))
        (loop for task across tasks
              when (task-ready-p task now-universal)
                do (push task ready))
        (coerce (nreverse ready) 'vector))))

;;; --- Recurrence ---

(defun parse-recurrence (task)
  "Extract and parse the recurrence field from a task. Returns a hash-table or nil."
  (let ((rec (or (gethash :recurrence task)
                 (gethash :RECURRENCE task))))
    (when (and rec (stringp rec) (> (length rec) 0))
      (handler-case (parse-json rec)
        (error () nil)))))

(defun compute-next-scheduled-at (current-time recurrence)
  "Given a universal time and a recurrence hash-table, compute the next scheduled time.
   Returns an ISO8601 string."
  (let* ((interval (or (gethash :interval recurrence)
                       (gethash :INTERVAL recurrence)
                       "daily"))
         (next-time
           (cond
             ((string-equal interval "hourly")
              (+ current-time 3600))
             ((string-equal interval "hours")
              (let ((every (or (gethash :every recurrence)
                               (gethash :EVERY recurrence) 1)))
                (+ current-time (* (if (numberp every) every 1) 3600))))
             ((string-equal interval "daily")
              (+ current-time (* 24 3600)))
             ((string-equal interval "weekly")
              ;; Advance 7 days; if a specific day is set, adjust
              (let ((target-day (gethash :day recurrence)))
                (if target-day
                    (advance-to-weekday current-time target-day)
                    (+ current-time (* 7 24 3600)))))
             ((string-equal interval "monthly")
              (advance-to-next-month current-time
                                     (gethash :day-of-month recurrence)))
             (t (+ current-time (* 24 3600))))))
    (format-iso8601 next-time)))

(defun weekday-number (name)
  "Convert weekday name to Lisp's day-of-week (0=Monday, 6=Sunday)."
  (let ((lower (string-downcase name)))
    (cond
      ((search "mon" lower) 0)
      ((search "tue" lower) 1)
      ((search "wed" lower) 2)
      ((search "thu" lower) 3)
      ((search "fri" lower) 4)
      ((search "sat" lower) 5)
      ((search "sun" lower) 6)
      (t 0))))

(defun advance-to-weekday (current-time target-day-name)
  "Advance current-time to the next occurrence of the named weekday."
  (let ((target (weekday-number target-day-name)))
    (multiple-value-bind (sec min hour day month year dow)
        (decode-universal-time current-time 0)
      (declare (ignore sec min hour))
      (let* ((days-ahead (mod (- target dow) 7))
             (days-ahead (if (= days-ahead 0) 7 days-ahead)))
        (encode-universal-time 0 0 9 (+ day days-ahead) month year 0)))))

(defun advance-to-next-month (current-time day-of-month)
  "Advance to the specified day of next month. Clamps to last day if needed."
  (multiple-value-bind (sec min hour day month year)
      (decode-universal-time current-time 0)
    (declare (ignore sec min hour day))
    (let* ((target-day (or (when (numberp day-of-month) day-of-month) 1))
           (next-month (if (= month 12) 1 (1+ month)))
           (next-year (if (= month 12) (1+ year) year))
           ;; Clamp to valid day
           (max-day (days-in-month next-month next-year))
           (clamped-day (min target-day max-day)))
      (encode-universal-time 0 0 9 clamped-day next-month next-year 0))))

(defun days-in-month (month year)
  (case month
    ((1 3 5 7 8 10 12) 31)
    ((4 6 9 11) 30)
    (2 (if (or (and (zerop (mod year 4)) (not (zerop (mod year 100))))
               (zerop (mod year 400)))
           29 28))
    (t 30)))

(defun handle-task-recurrence (task-id task)
  "After a task completes, check for recurrence and schedule the next occurrence.
   Resets the task to 'scheduled' status with the next scheduled_at."
  (let ((recurrence (parse-recurrence task)))
    (when recurrence
      (let* ((now (get-universal-time))
             (next-at (compute-next-scheduled-at now recurrence)))
        (handler-case
            (progn
              (api-patch (format nil "/api/af64/tasks/~a" task-id)
                         (json-object :status "open"
                                      :scheduled-at next-at
                                      :stage "open"
                                      :stage-notes (format nil "Recurring task rescheduled. Next: ~a" next-at)))
              (format t "  [recurrence] task #~a rescheduled to ~a~%" task-id next-at)
              t)
          (error (e)
            (format t "  [recurrence-error] task #~a: ~a~%" task-id e)
            nil))))))
