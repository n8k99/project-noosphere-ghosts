(in-package :af64)

(defun run-tick (&optional (tick-number 0))
  (af64.runtime.tick-engine:run-tick tick-number))
