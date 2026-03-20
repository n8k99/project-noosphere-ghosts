(in-package :af64.runtime.paths)

(defun runtime-directory ()
  (let* ((env (uiop:getenv "AF64_RUNTIME_DIR"))
         (dir (or env "/tmp/noosphere_ghosts/")))
    (uiop:ensure-directory-pathname dir)))

(defun ensure-runtime-dir ()
  (uiop:ensure-all-directories-exist (list (runtime-directory))))

(defun %make-runtime-path (filename)
  (namestring (merge-pathnames filename (runtime-directory))))

(defun broker-state-path ()
  (%make-runtime-path "cognition_broker_state.json"))

(defun broker-telemetry-path ()
  (%make-runtime-path "cognition_telemetry.jsonl"))

(defun tick-reports-path ()
  (%make-runtime-path "tick_reports.jsonl"))

(defun daily-rollups-path ()
  (%make-runtime-path "daily_rollups.jsonl"))

(defun weekly-rollups-path ()
  (%make-runtime-path "weekly_rollups.jsonl"))

(defun monthly-rollups-path ()
  (%make-runtime-path "monthly_rollups.jsonl"))

(defun quarterly-rollups-path ()
  (%make-runtime-path "quarterly_rollups.jsonl"))

(defun yearly-rollups-path ()
  (%make-runtime-path "yearly_rollups.jsonl"))

(defun notes-directory ()
  (%make-runtime-path "notes/"))
