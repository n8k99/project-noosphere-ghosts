(asdf:defsystem "af64"
  :description "Noosphere Ghosts AF64 runtime in Common Lisp"
  :author "Project Noosphere Ghosts"
  :license "MIT"
  :serial t
  :depends-on ()
  :components
  ((:file "packages")
   (:module "util"
    :serial t
    :components ((:file "json")
                 (:file "http")))
   (:module "runtime"
    :serial t
   :components ((:file "rules")
                (:file "runtime-paths")
                (:file "self-mod")
                (:file "api-client")
                (:file "cognition-types")
                (:file "user-profile")
                (:file "provider-adapters")
                (:file "cognition-broker")
                 (:file "perception")
                 (:file "drive")
                 (:file "energy")
                 (:file "action-planner")
                 (:file "action-executor")
                 (:file "empirical-rollups")
                 (:file "tick-reporting")
                 (:file "tick-engine")))
   (:file "main")))
