;;; ═══════════════════════════════════════════════════════════
;;; AF64 Field Mapping — EM Droplet
;;; Maps runtime concepts to frontmatter keys in EM Staff documents
;;; Source: documents.frontmatter (jsonb, stored as text)
;;; Path pattern: Areas/Eckenrode Muziekopname/EM Staff/{name}.md
;;; ═══════════════════════════════════════════════════════════

(in-package :af64.config)

(defparameter *em-field-mapping*
  '(;; ── IDENTITY ──────────────────────────────────────────
    ;; The ghost reads who it is from these fields
    (:agent-id        . "id")              ; numeric string, maps to agents.af64_id
    (:full-name       . "full_name")
    (:title           . "title")           ; PascalCase filename (e.g. "ElianaRiviera")
    (:role            . "earth_role")      ; "Chief Technical Officer"
    (:department      . "earth_department"); "Engineering"
    (:position-level  . "earth_position_level") ; "Executive", "Analyst", etc.
    (:team            . "team")            ; wikilink: "[[TechnicalDevelopmentOffice]]"
    (:reports-to      . "reports_to")      ; wikilink: "[[NathanEckenrode]]"
    (:ceo             . "ceo")             ; always "[[NathanEckenrode]]"

    ;; ── SOUL ─────────────────────────────────────────────
    ;; Core identity traits — what makes this ghost THIS ghost
    (:archetype       . "archetype")       ; wikilink: "[[TheEngineer]]" → resolves to archetype doc
    (:strengths       . "strengths")       ; array of strings (may be empty on older entries)
    (:weaknesses      . "weaknesses")      ; array of strings
    (:birth-date      . "birth_date")      ; ISO date string
    (:birthweek       . "birthweek")       ; wikilink: "[[Virgo I]]" → astrology doc
    (:icon            . "icon")            ; emoji or icon reference

    ;; ── MEMORY (ORIGIN) ──────────────────────────────────
    ;; Backstory fields — used to seed formative memories
    (:education       . "education")       ; free text
    (:prev-experience . "previous_experience") ; free text
    (:reason-joining  . "reason_for_joining")  ; free text
    (:location        . "location")        ; city name
    (:joined-date     . "joined_date")     ; wikilink date or string

    ;; ── TOOLS ────────────────────────────────────────────
    (:skills          . "skills")          ; array (may be empty — populated in content body)
    (:hobbies         . "hobbies")         ; array or null
    (:tool-scope      . "tool_scope")      ; array of tool permission strings (from agents table)

    ;; ── RUNTIME ──────────────────────────────────────────
    ;; These are written by the tick engine, read on startup
    (:type            . "type")            ; "AF64-Ghost" or "AF64-PrimaryUser"
    (:agent-tier      . "agent_tier")      ; "executive" or "staff"
    (:energy          . "energy")          ; float 0-100, default 50
    (:tier            . "tier")            ; evolution tier: "base", "aware", "autonomous"
    (:ticks-alive     . "ticks_alive")     ; int
    (:ticks-at-tier   . "ticks_at_current_tier") ; int
    (:last-tick       . "last_tick_at")    ; ISO timestamp or null
    (:dormant-since   . "dormant_since")   ; ISO timestamp or null
    (:status          . "status")          ; "active", "dormant", etc.

    ;; ── ORBIS ────────────────────────────────────────────
    ;; Pantheon Formation / mythic layer — unlocked by evolution
    (:divine-persona     . "divine_persona")       ; string
    (:orbis-spec         . "orbis_specialization") ; string
    (:assigned-infra     . "assigned_infrastructure") ; string
    (:active-period      . "active_period")        ; string
    (:historical-era     . "historical_era")       ; string
    (:observation-focus  . "observation_focus")     ; array
    (:divine-manifest    . "divine_manifestations"); array
    (:faction-rels       . "faction_relationships"); array
    (:sources            . "sources")              ; array
    (:significance       . "significance")         ; string
    (:cultural-impact    . "cultural_impact")      ; string
    (:confidence         . "confidence")           ; string

    ;; ── EVOLUTION ────────────────────────────────────────
    (:metamorphosis-count    . "metamorphosis_count")    ; int, default 0
    (:orbis-threshold        . "orbis_fitness_threshold"); int, default 50
    (:orbis-unlocked         . "orbis_unlocked")         ; bool, default false
    ))

;;; ── WIKILINK RESOLUTION ──────────────────────────────────
;;; Fields whose values are [[wikilinks]] that resolve to other documents.
;;; The runtime should follow these links to enrich the ghost's context.

(defparameter *wikilink-fields*
  '(:archetype :team :reports-to :ceo :birthweek))

;;; ── PRIMARY USER DETECTION ───────────────────────────────
;;; The ghost checks frontmatter.type to know if a document is
;;; the primary user or a peer ghost.

(defparameter *primary-user-type* "AF64-PrimaryUser")
(defparameter *ghost-type* "AF64-Ghost")

;;; ── ENERGY REWARD: NATHAN RECOGNITION ────────────────────
;;; When the primary user interacts with a ghost (reply, approval,
;;; direct message), the ghost receives this energy reward.
;;; This is the highest reward in the system — the sunlight mechanic.

(defparameter *nathan-recognition-energy* 75)

;;; ── DOCUMENT QUERY ───────────────────────────────────────
;;; SQL to load a ghost's full identity from the DB

(defparameter *ghost-load-query*
  "SELECT d.id, d.title, d.path, d.frontmatter::jsonb, d.content,
          a.id as agent_id, a.af64_id, a.tool_scope, a.agent_tier
   FROM documents d
   JOIN agents a ON a.document_id = d.id
   WHERE a.id = $1")

(defparameter *all-ghosts-query*
  "SELECT d.id, d.title, d.frontmatter::jsonb, a.id as agent_id, a.af64_id
   FROM documents d
   JOIN agents a ON a.document_id = d.id
   WHERE (d.frontmatter::jsonb)->>'type' = 'AF64-Ghost'
   ORDER BY a.af64_id")

(defparameter *resolve-wikilink-query*
  "SELECT id, title, path, content, frontmatter::jsonb
   FROM documents
   WHERE path LIKE '%/' || $1 || '.md'
   AND path NOT LIKE 'Archive/%'
   LIMIT 1")
