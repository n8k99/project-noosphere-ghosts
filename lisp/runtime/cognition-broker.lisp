(in-package :af64.runtime.cognition-broker)

(defun env-int (name default)
  (let ((value (uiop:getenv name)))
    (if value
        (handler-case (parse-integer value)
          (error () default))
        default)))

(defun env-bool (name default)
  (let ((value (uiop:getenv name)))
    (if value
        (not (member (string-downcase value) '("0" "false" "no") :test #'string=))
        default)))

(defun make-metrics-table ()
  (let ((table (make-hash-table :test #'equal)))
    (dolist (key '(:queued :resolved :deferred :cache-hits :cache-expired :expired
                     :retry-attempts :processed-budget))
      (setf (gethash key table) 0))
    table))

(defstruct (cognition-broker (:constructor %make-cognition-broker))
  (max-jobs-per-tick 6)
  (winter-max-jobs-per-tick 3)
  (winter-pending-threshold 18)
  (thaw-pending-threshold 9)
  (thaw-stability-ticks 2)
  (cache-ttl-seconds 21600)
  (providers (build-default-provider-chain))
  (pending-jobs '())
  (pending-by-agent (make-hash-table :test #'equal))
  (ready-results '())
  (cache (make-hash-table :test #'equal))
  (telemetry '())
  (last-tick-metrics (make-metrics-table))
  (winter-active nil)
  (thaw-ready-ticks 0)
  (state-path (broker-state-path))
  (telemetry-path (broker-telemetry-path)))

(defun make-cognition-broker (&key (max-jobs-per-tick nil))
  (let* ((configured-max (or max-jobs-per-tick (env-int "MAX_ACTIONS_PER_TICK" 6)))
         (broker (%make-cognition-broker
                  :max-jobs-per-tick configured-max
                  :winter-max-jobs-per-tick (max 1 (env-int "COGNITIVE_WINTER_MAX_JOBS_PER_TICK"
                                                            (max 1 (floor configured-max 2))))
                  :winter-pending-threshold (env-int "COGNITIVE_WINTER_PENDING_THRESHOLD"
                                                     (* 3 configured-max))
                  :thaw-pending-threshold (env-int "COGNITIVE_THAW_PENDING_THRESHOLD"
                                                   (max 1 (floor (* 3 configured-max) 2)))
                  :thaw-stability-ticks (env-int "COGNITIVE_THAW_STABILITY_TICKS" 2)
                  :cache-ttl-seconds (env-int "COGNITION_CACHE_TTL_SECONDS" 21600))))
    (broker-load-state broker)
    broker))

(defun reset-metrics (broker)
  (setf (cognition-broker-last-tick-metrics broker) (make-metrics-table)))

(defun broker-start-tick (broker)
  (reset-metrics broker))

(defun record-telemetry (broker event)
  (setf (cognition-broker-telemetry broker)
        (cons event (subseq (cognition-broker-telemetry broker) 0
                            (min 199 (length (cognition-broker-telemetry broker))))))
  (ensure-runtime-dir)
  (with-open-file (stream (cognition-broker-telemetry-path broker)
                          :direction :output :if-exists :append :if-does-not-exist :create)
    (write-string (encode-json event) stream)
    (write-char #\Newline stream))
  (ignore-errors (api-post "/api/cognition/telemetry" event)))

(defun record-event (broker event-type &rest kvs)
  (let ((event (json-object :event-type event-type :at (utc-now-iso))))
    (loop for (k v) on kvs by #'cddr do (setf (gethash k event) v))
    (record-telemetry broker event)
    (broker-save-state broker)))

(defun cache-entry-valid-p (entry)
  (let ((expires (gethash :expires-at entry)))
    (if (null expires)
        t
        (let ((ts (parse-iso8601 expires)))
          (and ts (> ts (get-universal-time)))))))

(defun cache-expire (broker)
  (let ((removal '()))
    (maphash (lambda (key entry)
               (unless (cache-entry-valid-p entry)
                 (push key removal)))
             (cognition-broker-cache broker))
    (dolist (key removal)
      (remhash key (cognition-broker-cache broker))
      (incf (gethash :cache-expired (cognition-broker-last-tick-metrics broker)))
      (record-event broker "cache_expired" :cache-key key))))

(defun job-expired-p (job)
  (let ((expires (cognition-job-expires-at job)))
    (when expires
      (let ((ts (parse-iso8601 expires)))
        (and ts (<= ts (get-universal-time)))))))

(defun expire-jobs (broker)
  (let ((retained '()))
    (dolist (job (cognition-broker-pending-jobs broker))
      (if (job-expired-p job)
          (progn
            (remhash (cognition-job-agent-id job) (cognition-broker-pending-by-agent broker))
            (incf (gethash :expired (cognition-broker-last-tick-metrics broker)))
            (record-event broker "expired"
                          :agent-id (cognition-job-agent-id job)
                          :job-id (cognition-job-id job)))
          (push job retained)))
    (setf (cognition-broker-pending-jobs broker) (nreverse retained))))

(defun frontier-enabled-p ()
  (let ((value (or (uiop:getenv "FRONTIER_COGNITION_ENABLED") "1")))
    (not (member (string-downcase value) '("0" "false" "no") :test #'string=))))

(defun force-winter-p ()
  (env-bool "FORCE_COGNITIVE_WINTER" nil))

(defun broker-ecology-state (broker)
  (let* ((pending (broker-pending-count broker))
         (frontier (frontier-enabled-p))
         (scarcity (>= pending (cognition-broker-winter-pending-threshold broker)))
         (enter-winter (or (force-winter-p) (not frontier) scarcity))
         (winter-active (if enter-winter
                            t
                            (and (cognition-broker-winter-active broker)
                                 (< (cognition-broker-thaw-ready-ticks broker)
                                    (cognition-broker-thaw-stability-ticks broker)))))
         (reason (cond
                   ((force-winter-p) "forced")
                   ((not frontier) "frontier_disabled")
                   (scarcity "queue_pressure")
                   (winter-active "thaw_stabilizing")
                   (t nil)))
         (budget (if winter-active
                     (cognition-broker-winter-max-jobs-per-tick broker)
                     (cognition-broker-max-jobs-per-tick broker))))
    (json-object
     :frontier-enabled frontier
     :winter-active winter-active
     :winter-reason reason
     :request-budget budget
     :pending-threshold (cognition-broker-winter-pending-threshold broker)
     :thaw-pending-threshold (cognition-broker-thaw-pending-threshold broker)
     :thaw-ready-ticks (cognition-broker-thaw-ready-ticks broker)))

(defun refresh-ecology-state (broker)
  (let ((frontier (frontier-enabled-p))
        (pending (broker-pending-count broker)))
    (if (and frontier
             (<= pending (cognition-broker-thaw-pending-threshold broker))
             (not (force-winter-p)))
        (incf (cognition-broker-thaw-ready-ticks broker))
        (setf (cognition-broker-thaw-ready-ticks broker) 0))
    (let ((ecology (broker-ecology-state broker)))
      (when (not (eq (gethash :winter-active ecology) (cognition-broker-winter-active broker)))
        (setf (cognition-broker-winter-active broker) (gethash :winter-active ecology))
        (record-event broker (if (gethash :winter-active ecology) "winter_enter" "winter_exit")
                      :ecology ecology))
      ecology)))

(defun enqueue-job (broker job)
  (setf (cognition-broker-pending-jobs broker)
        (nconc (cognition-broker-pending-jobs broker) (list job))))

(defun submit-job-to-api (job)
  (ignore-errors (api-post "/api/cognition/jobs" (job->plist job))))

(defun broker-submit-job (broker job)
  (let* ((agent-id (cognition-job-agent-id job))
         (existing (gethash agent-id (cognition-broker-pending-by-agent broker))))
    (when (and existing
               (string= (cognition-job-status existing) "pending")
               (string= (cognition-job-cache-key existing) (cognition-job-cache-key job)))
      (record-event broker "duplicate_pending" :agent-id agent-id :job-id (cognition-job-id existing))
      (return-from broker-submit-job existing))
    (let ((cache-entry (gethash (cognition-job-cache-key job) (cognition-broker-cache broker))))
      (cond
        ((and cache-entry (cache-entry-valid-p cache-entry))
         (let* ((cached-result (result-from-json (gethash :result cache-entry)))
                (ready (make-cognition-result
                        :job-id (cognition-job-id job)
                        :agent-id (cognition-job-agent-id job)
                        :action-name (cognition-job-action-name job)
                        :content (cognition-result-content cached-result)
                        :provider-name (cognition-result-provider-name cached-result)
                        :model-used (cognition-result-model-used cached-result)
                        :cached t
                        :metadata (copy-hash-table (cognition-result-metadata cached-result)))))
           (setf (cognition-job-status job) "resolved"
                 (cognition-job-provider-name job) (cognition-result-provider-name ready)
                 (cognition-job-result job) (result->plist ready)
                 (cognition-job-resolved-at job) (utc-now-iso))
           (setf (gethash agent-id (cognition-broker-pending-by-agent broker)) job)
           (push ready (cognition-broker-ready-results broker))
           (incf (gethash :cache-hits (cognition-broker-last-tick-metrics broker)))
           (record-event broker "cache_hit" :agent-id agent-id :job-id (cognition-job-id job)
                         :cache-key (cognition-job-cache-key job))
           (broker-save-state broker)
           (return-from broker-submit-job job)))
        ((and cache-entry (not (cache-entry-valid-p cache-entry)))
         (remhash (cognition-job-cache-key job) (cognition-broker-cache broker))
         (incf (gethash :cache-expired (cognition-broker-last-tick-metrics broker)))
         (record-event broker "cache_expired" :cache-key (cognition-job-cache-key job)))))
    (enqueue-job broker job)
    (setf (gethash agent-id (cognition-broker-pending-by-agent broker)) job)
    (incf (gethash :queued (cognition-broker-last-tick-metrics broker)))
    (record-event broker "queued" :agent-id agent-id :job-id (cognition-job-id job)
                  :priority (cognition-job-priority job))
    (submit-job-to-api job)
    (broker-save-state broker)
    job))

(defun add-cache-entry (broker job result)
  (setf (gethash (cognition-job-cache-key job) (cognition-broker-cache broker))
        (json-object
         :result (result->plist result)
         :cached-at (utc-now-iso)
         :expires-at (cognition-job-expires-at job))))

(defun run-job (broker job)
  (incf (cognition-job-retry-count job))
  (incf (gethash :retry-attempts (cognition-broker-last-tick-metrics broker)))
  (setf (cognition-job-last-attempt-at job) (utc-now-iso))
  (when (> (cognition-job-retry-count job) (cognition-job-max-attempts job))
    (setf (cognition-job-status job) "abandoned")
    (remhash (cognition-job-agent-id job) (cognition-broker-pending-by-agent broker))
    (record-event broker "abandoned" :agent-id (cognition-job-agent-id job)
                  :job-id (cognition-job-id job) :retries (cognition-job-retry-count job))
    (return-from run-job nil))
  (dolist (provider (cognition-broker-providers broker))
    (let ((result (provider-generate provider job)))
      (when result
        (setf (cognition-job-status job) "resolved"
              (cognition-job-provider-name job) (provider-name provider)
              (cognition-job-result job) (result->plist result)
              (cognition-job-resolved-at job) (utc-now-iso))
        (add-cache-entry broker job result)
        (record-event broker "resolved" :agent-id (cognition-job-agent-id job)
                      :job-id (cognition-job-id job) :provider (provider-name provider))
        (ignore-errors (api-patch (format nil "/api/cognition/jobs/~a" (cognition-job-id job))
                                  (job->plist job)))
        (broker-save-state broker)
        (return-from run-job result))))
  (setf (cognition-job-status job) "pending")
  (broker-save-state broker)
  nil)

(defun broker-process-tick (broker)
  (cache-expire broker)
  (let ((ecology (refresh-ecology-state broker)))
    (expire-jobs broker)
    (let ((results (reverse (cognition-broker-ready-results broker))))
      (setf (cognition-broker-ready-results broker) '())
      (dolist (result results)
        (remhash (cognition-result-agent-id result) (cognition-broker-pending-by-agent broker)))
      (when (null (cognition-broker-pending-jobs broker))
        (return-from broker-process-tick results))
      (let* ((sorted (stable-sort (copy-list (cognition-broker-pending-jobs broker))
                                  (lambda (a b)
                                    (if (= (cognition-job-priority a) (cognition-job-priority b))
                                        (string< (cognition-job-created-at a) (cognition-job-created-at b))
                                        (> (cognition-job-priority a) (cognition-job-priority b))))))
             (budget (gethash :request-budget ecology))
             (processed 0)
             (retained '()))
        (dolist (job sorted)
          (if (>= processed budget)
              (progn
                (incf (cognition-job-wait-ticks job))
                (push job retained))
              (let ((result (run-job broker job)))
                (if result
                    (progn
                      (push result results)
                      (incf processed)
                      (incf (gethash :resolved (cognition-broker-last-tick-metrics broker)))
                      (remhash (cognition-job-agent-id job) (cognition-broker-pending-by-agent broker)))
                    (if (string= (cognition-job-status job) "abandoned")
                        nil
                        (progn
                          (incf (cognition-job-wait-ticks job))
                          (push job retained)
                          (incf (gethash :deferred (cognition-broker-last-tick-metrics broker)))
                          (record-event broker "deferred"
                                        :agent-id (cognition-job-agent-id job)
                                        :job-id (cognition-job-id job))))))))
        (setf (gethash :processed-budget (cognition-broker-last-tick-metrics broker)) processed)
        (setf (cognition-broker-pending-jobs broker) (nreverse retained))
        (broker-save-state broker)
        (nreverse results))))))

(defun broker-save-state (broker)
  (ensure-runtime-dir)
  (with-open-file (stream (cognition-broker-state-path broker)
                          :direction :output :if-exists :supersede :if-does-not-exist :create)
    (write-string
     (encode-json
      (json-object
       :pending-jobs (coerce (mapcar #'job->plist (cognition-broker-pending-jobs broker)) 'vector)
       :pending-by-agent (let ((table (make-hash-table :test #'equal)))
                           (maphash (lambda (agent job)
                                      (setf (gethash agent table) (job->plist job)))
                                    (cognition-broker-pending-by-agent broker))
                           table)
       :ready-results (coerce (mapcar #'result->plist (cognition-broker-ready-results broker)) 'vector)
       :cache (let ((table (make-hash-table :test #'equal)))
                (maphash (lambda (key value) (setf (gethash key table) value))
                         (cognition-broker-cache broker))
                table)
       :telemetry (coerce (subseq (cognition-broker-telemetry broker) 0
                                  (min 200 (length (cognition-broker-telemetry broker)))) 'vector)
       :last-tick-metrics (let ((table (make-hash-table :test #'equal)))
                            (maphash (lambda (k v) (setf (gethash k table) v))
                                     (cognition-broker-last-tick-metrics broker))
                            table)
       :winter-active (cognition-broker-winter-active broker)
       :thaw-ready-ticks (cognition-broker-thaw-ready-ticks broker)))
     stream)))

(defun broker-load-state (broker)
  (let ((path (cognition-broker-state-path broker)))
    (when (probe-file path)
      (with-open-file (stream path)
        (let* ((text (make-string (file-length stream)))
               (n (read-sequence text stream)))
          (declare (ignore n))
          (let ((payload (parse-json text)))
            (when payload
              (setf (cognition-broker-pending-jobs broker)
                    (loop for job across (or (gethash :pending-jobs payload) #())
                          collect (job-from-json job)))
              (let ((table (make-hash-table :test #'equal)))
                (maphash (lambda (agent job-hash)
                           (setf (gethash agent table) (job-from-json job-hash)))
                         (or (gethash :pending-by-agent payload) (make-hash-table :test #'equal)))
                (setf (cognition-broker-pending-by-agent broker) table))
              (setf (cognition-broker-ready-results broker)
                    (loop for res across (or (gethash :ready-results payload) #())
                          collect (result-from-json res)))
              (setf (cognition-broker-cache broker)
                    (or (gethash :cache payload) (make-hash-table :test #'equal)))
              (setf (cognition-broker-telemetry broker)
                    (loop for evt across (or (gethash :telemetry payload) #()) collect evt))
              (let ((metrics (make-metrics-table))
                    (saved (gethash :last-tick-metrics payload)))
                (when saved
                  (maphash (lambda (k v) (setf (gethash k metrics) v)) saved))
                (setf (cognition-broker-last-tick-metrics broker) metrics))
              (setf (cognition-broker-winter-active broker) (gethash :winter-active payload))
              (setf (cognition-broker-thaw-ready-ticks broker) (or (gethash :thaw-ready-ticks payload) 0))))))))

(defun broker-telemetry (broker)
  (cognition-broker-telemetry broker))

(defun broker-pending-metrics (broker)
  (cognition-broker-last-tick-metrics broker))

(defun broker-pending-count (broker)
  (length (cognition-broker-pending-jobs broker)))

(defun broker-pending-agents (broker)
  (loop for k being the hash-keys of (cognition-broker-pending-by-agent broker) collect k))

(defun broker-tick-summary (broker)
  (let ((recent (subseq (cognition-broker-telemetry broker) 0
                        (min 25 (length (cognition-broker-telemetry broker)))))
        (metrics (let ((table (make-hash-table :test #'equal)))
                   (maphash (lambda (k v) (setf (gethash k table) v))
                            (cognition-broker-last-tick-metrics broker))
                   table)))
    (json-object
     :pending-jobs (broker-pending-count broker)
     :cache-entries (hash-table-count (cognition-broker-cache broker))
     :metrics metrics
     :ecology (broker-ecology-state broker)
     :recent-events (coerce recent 'vector))))
