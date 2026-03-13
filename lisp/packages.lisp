(defpackage :af64.utils.json
  (:use :cl)
  (:export :parse-json :encode-json :json-keyword :keyword->json-key
           :json-null :json-true :json-false :json-object :json-array))

(defpackage :af64.utils.http
  (:use :cl)
  (:import-from :af64.utils.json :encode-json :parse-json)
  (:import-from :uiop :run-program :process-info-output :process-info-error-output
                :process-info-exit-code)
  (:export :http-request :http-get :http-post :http-patch))

(defpackage :af64.rules
  (:use :cl)
  (:export :*rules-for-being-a-ghost* :ghost-rule :rewrite-ghost-rule
           :add-ghost-rule :lawful-actions))

(defpackage :af64.runtime.paths
  (:use :cl)
  (:import-from :uiop :ensure-directories-exist :ensure-directory-pathname :getenv)
  (:export :runtime-directory :ensure-runtime-dir :broker-state-path
           :broker-telemetry-path :tick-reports-path
           :daily-rollups-path :weekly-rollups-path :monthly-rollups-path
           :quarterly-rollups-path :yearly-rollups-path :notes-directory))

(defpackage :af64.runtime.self-mod
  (:use :cl)
  (:export :define-ghost-behavior :dispatch-ghost-behavior
           :list-ghost-behaviors :install-behavior-patch))

(defpackage :af64.runtime.api
  (:use :cl)
  (:import-from :af64.utils.http :http-get :http-post :http-patch)
  (:import-from :af64.utils.json :encode-json :parse-json :json-object :json-array
                :json-keyword :keyword->json-key)
  (:export :api-get :api-post :api-patch :*api-base* :*api-key*))

(defpackage :af64.runtime.cognition-types
  (:use :cl)
  (:import-from :af64.utils.json :json-object)
  (:import-from :af64.runtime.self-mod :define-ghost-behavior)
  (:export :cognition-job :make-cognition-job :cognition-result :make-cognition-result
           :job->plist :result->plist :utc-now-iso :future-utc-iso :parse-iso8601
           :job-from-json :result-from-json))

(defpackage :af64.runtime.user-profile
  (:use :cl)
  (:import-from :af64.runtime.api :api-get)
  (:export :primary-user-note :primary-user-handle :primary-user-id))

(defpackage :af64.runtime.cognition-broker
  (:use :cl)
  (:import-from :af64.runtime.cognition-types
                :cognition-job :cognition-result :make-cognition-job :make-cognition-result
                :job->plist :result->plist :utc-now-iso :parse-iso8601
                :job-from-json :result-from-json)
  (:import-from :af64.runtime.paths :ensure-runtime-dir :broker-state-path :broker-telemetry-path)
  (:import-from :af64.runtime.api :api-post :api-patch)
  (:import-from :af64.runtime.provider-adapters :build-default-provider-chain
                :provider-generate :provider-name)
  (:import-from :af64.utils.json :json-object :encode-json)
  (:export :make-cognition-broker :broker-start-tick :broker-submit-job
           :broker-get-pending-job :broker-process-tick :broker-pending-metrics
           :broker-telemetry :broker-ecology-state :broker-save-state :broker-load-state
           :broker-pending-count :broker-pending-agents :broker-tick-summary))

(defpackage :af64.runtime.perception
  (:use :cl)
  (:import-from :af64.runtime.api :api-get)
  (:export :perceive :has-actionable-items))

(defpackage :af64.runtime.drive
  (:use :cl)
  (:import-from :af64.runtime.api :api-get :api-post)
  (:import-from :af64.utils.json :json-object)
  (:export :tick-drives :fulfill-drive :highest-pressure-drive))

(defpackage :af64.runtime.energy
  (:use :cl)
  (:import-from :af64.runtime.api :api-get :api-patch)
  (:import-from :af64.utils.json :json-keyword :json-object)
  (:export :update-energy :get-energy :get-cost :+energy-costs+ :+energy-rewards+))

(defpackage :af64.runtime.action-planner
  (:use :cl)
  (:import-from :af64.runtime.cognition-types :make-cognition-job :future-utc-iso)
  (:import-from :af64.runtime.self-mod :dispatch-ghost-behavior :define-ghost-behavior)
  (:import-from :af64.runtime.user-profile :primary-user-note)
  (:import-from :af64.utils.json :json-object :json-array :json-keyword :encode-json :parse-json)
  (:export :build-cognition-job :load-persona :persona-path :*job-ttl-seconds*
           :*job-max-attempts* :compute-priority))

(defpackage :af64.runtime.action-executor
  (:use :cl)
  (:import-from :af64.runtime.api :api-post :api-patch)
  (:import-from :af64.utils.json :json-object :json-array)
  (:import-from :af64.runtime.cognition-types :cognition-result-action-name
                :cognition-result-agent-id :cognition-result-content
                :cognition-result-job-id :cognition-result-provider-name
                :cognition-result-cached :cognition-result-metadata)
  (:export :execute-cognition-result))

(defpackage :af64.runtime.tick-reporting
  (:use :cl)
  (:import-from :af64.utils.json :encode-json :json-object)
  (:import-from :af64.runtime.paths :ensure-runtime-dir :tick-reports-path)
  (:import-from :af64.runtime.api :api-post)
  (:import-from :af64.runtime.empirical-rollups :rebuild-rollups)
  (:export :write-tick-report))

(defpackage :af64.runtime.empirical-rollups
  (:use :cl)
  (:import-from :af64.utils.json :parse-json :encode-json :json-object)
  (:import-from :af64.runtime.paths :ensure-runtime-dir :tick-reports-path
                :daily-rollups-path :weekly-rollups-path :monthly-rollups-path
                :quarterly-rollups-path :yearly-rollups-path)
  (:import-from :af64.runtime.api :api-post)
  (:export :rebuild-rollups))

(defpackage :af64.runtime.tick-engine
  (:use :cl)
  (:import-from :af64.utils.json :json-object)
  (:import-from :af64.runtime.api :api-get)
  (:import-from :af64.runtime.action-planner :build-cognition-job)
  (:import-from :af64.runtime.action-executor :execute-cognition-result)
  (:import-from :af64.runtime.cognition-broker :make-cognition-broker :broker-start-tick
                :broker-submit-job :broker-get-pending-job :broker-process-tick
                :broker-ecology-state :broker-pending-count :broker-pending-agents
                :broker-tick-summary)
  (:import-from :af64.runtime.drive :tick-drives :highest-pressure-drive :fulfill-drive)
  (:import-from :af64.runtime.energy :update-energy :get-energy :get-cost :+energy-rewards+)
  (:import-from :af64.runtime.perception :perceive :has-actionable-items)
  (:import-from :af64.runtime.tick-reporting :write-tick-report)
  (:export :run-tick :*tick-interval* :*max-actions-per-tick* :*broker*))

(defpackage :af64
  (:use :cl)
  (:import-from :af64.runtime.tick-engine :run-tick)
  (:export :run-tick))
(defpackage :af64.runtime.provider-adapters
  (:use :cl)
  (:import-from :af64.utils.http :http-post)
  (:import-from :af64.utils.json :encode-json :parse-json :json-object :json-array :json-keyword)
  (:import-from :af64.runtime.cognition-types :make-cognition-result
                :cognition-job-requested-model-tier :cognition-job-id
                :cognition-job-agent-id :cognition-job-action-name
                :cognition-job-input-context :cognition-job-kind)
  (:export :build-default-provider-chain :provider-generate :provider-name))
