#!/bin/bash
source /opt/project-noosphere-ghosts/config/af64.env
export AF64_RUNTIME_DIR=/tmp/noosphere_ghosts
mkdir -p $AF64_RUNTIME_DIR

cd /opt/project-noosphere-ghosts/lisp
exec /usr/local/bin/sbcl --noinform --non-interactive \
  --eval '(require :asdf)' \
  --eval '(load "packages.lisp")' \
  --eval '(dolist (f (list "util/json" "util/http" "runtime/rules" "runtime/runtime-paths" "runtime/self-mod" "runtime/api-client" "runtime/openclaw-gateway" "runtime/cognition-types" "runtime/provider-adapters" "runtime/cognition-broker" "runtime/perception" "runtime/drive" "runtime/energy" "runtime/user-profile" "runtime/action-planner" "runtime/action-executor" "runtime/tool-socket" "runtime/empirical-rollups" "runtime/tick-reporting" "runtime/tick-engine" "main")) (load (format nil "~a.lisp" f)))' \
  --eval '(load "runtime/tick-engine.lisp")' \
  --eval '(format t "~%☿ AF64 Noosphere loaded. Frontier: ~a~%" (uiop:getenv "FRONTIER_COGNITION_ENABLED"))' \
  --eval '(format t "  Provider: OpenClaw Gateway (Max subscription)~%")' \
  --eval '(format t "  API: ~a~%" af64.runtime.api:*api-base*)' \
  --eval '(format t "  Tick interval: ~as~%" af64.runtime.tick-engine:*tick-interval*)' \
  --eval '(format t "  Max actions/tick: ~a~%" af64.runtime.tick-engine:*max-actions-per-tick*)' \
  --eval '(format t "~%Starting tick loop...~%")' \
  --eval '(loop for tick from 1
               do (format t "~%--- TICK ~a ---~%" tick)
                  (finish-output)
                  (handler-case (af64:run-tick tick)
                    (error (e) (format t "  [tick-error] ~a~%" e)))
                  (force-output)
                  (sleep af64.runtime.tick-engine:*tick-interval*))'
