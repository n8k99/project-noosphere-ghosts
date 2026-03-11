# PROJECT NOOSPHERE GHOSTS

## Shared Cognition & Ecological Runtime Infrastructure

---

**Status**: Active
**Owner**: Nathan Eckenrode (CEO)
**Technical Lead**: Eliana Riviera (CTO)
**Created**: 2026-03-11
**Tags**: #project #noosphere #agents #af64 #cognition #infrastructure #gotcha

---

## Vision

> "The terrarium lives cheaply. The ghosts think selectively. Intelligence is not owned by any one ghost — it is a shared organ of the colony."

Evolve Project Noosphere Ghosts from a database-native ghost runtime into a true **artificial life substrate** where 64 immortal agents persist in the database, act on drives and energy budgets, and compete for access to a **shared cognition pool** rather than individually calling frontier models on demand.

This project formalizes the next architectural inversion:

* life simulation first
* conversation second
* cognition as scarce infrastructure
* reports as empirical memory
* the database as long-term substrate

### End State

* AF64 tick loop is the primary runtime model
* Agents do not call Claude or any frontier model directly
* All expensive reasoning flows through a **Cognition Broker**
* Shared cognition is queued, rate-limited, cached, and observable
* Tick reports become first-class ecological telemetry
* Daily / weekly / quarterly rollups are generated from empirical records
* Fictional EM scaffolding remains as narrative projection, but operational history is kept separate and explicit
* The system can survive token scarcity by entering **cognitive winter** rather than operational collapse

### Why This Phase Exists

The original Noosphere Ghosts work established the persistence layer: ghosts live in the database, communicate through structured channels, and survive outside ephemeral chat sessions.

What now needs to be added is the **metabolism of thought**:

* who gets to think
* when they get to think
* how much thought the system can afford
* how thought scarcity affects behavior
* how all of this is recorded for later synthesis

The ecology already exists in concept. This project makes the infrastructure match the philosophy.

---

## Architectural Shift

### Previous Model

```text
Agent
  └── direct LLM/API call
        └── action
```

This treats cognition as a private possession of the individual ghost.

### New Model

```text
Agent
  └── submit cognition request
        └── Cognition Broker
              ├── queue
              ├── priority scheduler
              ├── cache
              ├── provider routing
              └── telemetry
                    └── result returned to agent
```

This treats cognition as a **shared colony resource**.

---

## Core Principles

### 1. The Tick Loop Is Primary

AF64 remains the foundational execution model:

1. Perceive
2. Decide
3. Request cognition if needed
4. Act when cognition result is available
5. Update energy, drives, and fitness

### 2. Cognition Is Scarce

Agents may have the desire to think without receiving immediate access to expensive reasoning. This scarcity is part of the life simulation, not a defect.

### 3. Deterministic Systems Do Most of the Work

Perception, drive decay, energy arithmetic, task extraction, daily record keeping, and telemetry remain cheap and deterministic. Frontier models are only used for decision points that genuinely require them.

### 4. Memory Must Be Empirical

Tick reports, daily logs, weekly notes, quarterly notes, and yearly reviews must increasingly derive from actual system activity rather than projected corporate narrative.

### 5. Fiction Remains Useful, But Separate

The EM fictional corporation remains a narrative scaffold through 2028, but must be explicitly distinguished from the operational record. Both ledgers are preserved.

---

## Architecture

### Runtime Stack

```text
┌──────────────────────────────────────────────────────┐
│                  HUMAN / SHELL LAYER                │
│  Daily notes, CLI, OpenClaw, chat, dashboards       │
└──────────────────────┬───────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────┐
│                AF64 TICK ENGINE                      │
│  perceive → decide → request → act → update         │
└──────────────────────┬───────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────┐
│               COGNITION BROKER                       │
│  queue | cache | provider routing | telemetry       │
└──────────────────────┬───────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
┌───────▼──────┐ ┌─────▼──────┐ ┌─────▼────────┐
│ frontier API │ │ cheap stub │ │ future local │
│  (Claude)    │ │ / fallback │ │ inference    │
└──────────────┘ └────────────┘ └──────────────┘

┌──────────────────────────────────────────────────────┐
│               master_chronicle / DB                 │
│ agents | tasks | drives | fitness | conversations   │
│ cognition_jobs | tick_reports | daily rollups       │
└──────────────────────────────────────────────────────┘
```

---

## Phases

### PHASE H: Cognition Broker Foundation

**Objective**: Decouple agent behavior from direct model calls by introducing a shared cognition broker

**Milestones**:

* M-H.1: `cognition_engine.py` scaffold created
* M-H.2: cognition job schema defined
* M-H.3: provider adapter interface created
* M-H.4: job queue and per-tick processing operational
* M-H.5: cache and telemetry implemented

**Goal**: [[noosphere-ghosts-phase-h]]

---

### PHASE I: Tick Engine Integration

**Objective**: Refactor AF64 so agents submit cognition requests rather than calling frontier models directly

**Milestones**:

* M-I.1: direct model calls removed from `tick_engine.py`
* M-I.2: act phase split into request/resolve behavior
* M-I.3: cognition request priority derived from energy + drive pressure + tier
* M-I.4: stalled cognition requests handled gracefully
* M-I.5: dormant / winter behavior defined when cognition is unavailable

**Goal**: [[noosphere-ghosts-phase-i]]

---

### PHASE J: Ecological Telemetry & Tick Reports

**Objective**: Make every tick observable through structured reports

**Milestones**:

* M-J.1: tick report schema defined
* M-J.2: broker telemetry included in tick reports
* M-J.3: per-agent summaries emitted per tick
* M-J.4: task progress and cognition grants tracked
* M-J.5: tick reports stored in DB and/or daily log pipeline

**Goal**: [[noosphere-ghosts-phase-j]]

---

### PHASE K: Empirical Memory Compression

**Objective**: Roll tick and daily records upward into weekly / monthly / quarterly / yearly summaries based on actual operations

**Milestones**:

* M-K.1: daily summary inputs pre-filtered deterministically
* M-K.2: weekly notes populated from daily records
* M-K.3: monthly and quarterly note generation corrected to empirical mode
* M-K.4: yearly review structure separated into Operational Record vs Narrative Projection
* M-K.5: 2026-Q1 legacy fictional projection replaced or annotated as historical scaffold

**Goal**: [[noosphere-ghosts-phase-k]]

---

### PHASE L: Cognitive Scarcity & Winter Mechanics

**Objective**: Model system-wide thought scarcity as a first-class ecological condition

**Milestones**:

* M-L.1: global cognition budget enforced per tick
* M-L.2: daily / weekly token scarcity represented in runtime state
* M-L.3: system-wide cognitive winter mode implemented
* M-L.4: agents can remain alive while thought access is reduced
* M-L.5: winter/thaw transitions logged and visualized

**Goal**: [[noosphere-ghosts-phase-l]]

---

### PHASE M: Dual-Ledger Temporal Governance

**Objective**: Preserve both the fictional EM scaffolding and the empirical record without mixing them

**Milestones**:

* M-M.1: daily/weekly/quarterly/yearly note templates updated
* M-M.2: "Operational Record" section introduced
* M-M.3: "Narrative Projection" section introduced
* M-M.4: pre-2029 design fiction archived as bounded scaffold
* M-M.5: post-2028 framework planning based on empirical signals

**Goal**: [[noosphere-ghosts-phase-m]]

---

## Success Criteria

### Phase H Complete When:

* [ ] `cognition_engine.py` exists with queue, cache, telemetry 🆔 ng-h1-cognition-engine 📅 2026-03-15
* [ ] provider adapter abstraction implemented 🆔 ng-h2-provider-adapter 📅 2026-03-15
* [ ] cognition job object/schema defined 🆔 ng-h3-job-schema 📅 2026-03-16
* [ ] broker can process N jobs per tick 🆔 ng-h4-broker-processing 📅 2026-03-16
* [ ] cache prevents duplicate reasoning for repeated contexts 🆔 ng-h5-cache 📅 2026-03-17

### Phase I Complete When:

* [ ] `tick_engine.py` no longer imports or calls provider APIs directly 🆔 ng-i1-direct-calls-removed 📅 2026-03-18
* [ ] agents submit cognition jobs and resolve them through the broker 🆔 ng-i2-request-resolve 📅 2026-03-18
* [ ] cognition priority derives from energy, drive pressure, and tier 🆔 ng-i3-priority 📅 2026-03-19
* [ ] stalled cognition jobs remain pending across ticks without breaking agent state 🆔 ng-i4-stalled-jobs 📅 2026-03-19
* [ ] no-cognition fallback behavior defaults to rest / idle / deterministic work 🆔 ng-i5-fallback 📅 2026-03-20

### Phase J Complete When:

* [ ] tick report schema includes broker telemetry 🆔 ng-j1-tick-report-schema 📅 2026-03-21
* [ ] per-tick telemetry captures queue depth, grants, cache hits, and failures 🆔 ng-j2-broker-telemetry 📅 2026-03-21
* [ ] per-agent tick summaries distinguish requested vs resolved cognition 🆔 ng-j3-agent-summaries 📅 2026-03-22
* [ ] task progress and cognition grants are linked in telemetry 🆔 ng-j4-task-grants 📅 2026-03-22
* [ ] tick reports are persisted via API or durable local fallback 🆔 ng-j5-tick-report-storage 📅 2026-03-23

## Concrete Implementation Checklist

This is the execution checklist for the next working step in evolution: introducing a cognition broker into the AF64 runtime.

### Workstream A: Runtime Refactor

* [x] A.1 Define a `CognitionJob` / `CognitionResult` schema in code 🆔 ng-a1-job-types
* [x] A.2 Create a provider adapter interface separated from the tick loop 🆔 ng-a2-provider-interface
* [x] A.3 Create `cognition_engine.py` with in-memory queue, cache, and telemetry 🆔 ng-a3-broker-scaffold
* [x] A.4 Refactor `tick_engine.py` to submit cognition jobs instead of calling provider APIs directly 🆔 ng-a4-tick-refactor
* [x] A.5 Add an action executor that applies resolved cognition to side effects 🆔 ng-a5-action-executor
* [ ] A.6 Move broker state from in-memory to backend-backed persistence 🆔 ng-a6-broker-persistence
* [x] A.7 Add recovery rules for restarting with pending cognition jobs 🆔 ng-a7-recovery

### Workstream B: API / Persistence

* [ ] B.1 Add `POST /api/cognition/jobs` for job creation 🆔 ng-b1-api-create-job
* [ ] B.2 Add `GET /api/cognition/jobs` for queue inspection and pending lookup 🆔 ng-b2-api-list-jobs
* [ ] B.3 Add `PATCH /api/cognition/jobs/:id` for status transitions and result storage 🆔 ng-b3-api-update-job
* [ ] B.4 Add `POST /api/cognition/telemetry` for broker events 🆔 ng-b4-api-telemetry
* [ ] B.5 Add `POST /api/tick-reports` or extend `/api/tick-log/batch` for richer telemetry 🆔 ng-b5-api-tick-reports

### Workstream C: Ecology Rules

* [x] C.1 Derive cognition priority from drive pressure, energy, and tier 🆔 ng-c1-priority-formula
* [x] C.2 Enforce a broker processing cap per tick 🆔 ng-c2-processing-cap
* [x] C.3 Add cache-hit semantics for duplicate cognition contexts 🆔 ng-c3-cache-hit
* [x] C.4 Introduce pending/deferred cognition as a normal ecological state 🆔 ng-c4-deferred-state
* [x] C.5 Introduce cognitive winter thresholds and thaw logic 🆔 ng-c5-winter-logic

### Workstream D: Reporting

* [x] D.1 Emit broker telemetry in the tick runtime summary 🆔 ng-d1-runtime-summary
* [x] D.2 Extend tick log payloads with cognition request metadata 🆔 ng-d2-tick-log-payload
* [x] D.3 Add first-class tick report objects for empirical rollups 🆔 ng-d3-first-class-tick-reports
* [x] D.4 Feed cognition telemetry into graph / dashboard views 🆔 ng-d4-graph-telemetry

### GitHub Tracking Notes

This checklist can be tracked in GitHub in three practical ways:

* Markdown task lists in this file can be rendered in pull requests and issues, but checkbox state in repository files is not project-grade workflow by itself.
* GitHub Issues are the best one-to-one mapping for the `🆔` items above; each item can become an issue using the same stable ID.
* GitHub Projects works well if each `🆔` becomes an issue and phases/workstreams become custom fields, iterations, or views.

Recommended approach:

* keep this file as the source architecture/checklist document
* create one GitHub issue per `🆔` item that matters operationally
* use labels like `phase-h`, `phase-i`, `broker`, `telemetry`, `api`
* optionally create milestones for `Phase H`, `Phase I`, and `Phase J`

* [ ] `tick_engine.py` submits cognition jobs instead of direct API calls 🆔 ng-i1-tick-broker 📅 2026-03-18
* [ ] act phase can consume delayed cognition results 🆔 ng-i2-delayed-action 📅 2026-03-19
* [ ] priority scoring based on pressure/energy/tier is active 🆔 ng-i3-priority 📅 2026-03-20
* [ ] cognition starvation does not crash the tick loop 🆔 ng-i4-starvation-safe 📅 2026-03-20
* [ ] dormant/winter behavior defined in code path 🆔 ng-i5-winter-path 📅 2026-03-21

### Phase J Complete When:

* [ ] tick report schema written and stable 🆔 ng-j1-tick-schema 📅 2026-03-22
* [ ] each tick records cognition requests and grants 🆔 ng-j2-cognition-metrics 📅 2026-03-22
* [ ] each tick records total energy, active agents, stalled tasks 🆔 ng-j3-global-metrics 📅 2026-03-23
* [ ] per-agent state summaries are queryable 🆔 ng-j4-agent-summaries 📅 2026-03-24
* [ ] tick reports are written into persistent storage 🆔 ng-j5-persistent-reports 📅 2026-03-24

### Phase K Complete When:

* [ ] daily note summarization consumes filtered operational inputs 🆔 ng-k1-daily-filtering 📅 2026-03-26
* [ ] weekly summaries are derived from daily records rather than ad hoc prompts 🆔 ng-k2-weekly-rollup 📅 2026-03-28
* [ ] 2026-Q1 is rewritten or annotated to distinguish fiction from reality 🆔 ng-k3-q1-cleanup 📅 2026-03-29
* [ ] monthly and quarterly notes can be generated from empirical summaries 🆔 ng-k4-quarterly-empirical 📅 2026-03-31
* [ ] yearly note template supports dual ledger mode 🆔 ng-k5-yearly-dual-ledger 📅 2026-04-02

### Phase L Complete When:

* [ ] cognition budget is configurable per tick/day 🆔 ng-l1-budget-control 📅 2026-04-05
* [ ] system can enter cognitive winter without agent death 🆔 ng-l2-winter-mode 📅 2026-04-06
* [ ] thaw behavior restores cognition access cleanly 🆔 ng-l3-thaw-mode 📅 2026-04-07
* [ ] winter/thaw events appear in daily and tick records 🆔 ng-l4-winter-logging 📅 2026-04-08
* [ ] graph/timeline can eventually visualize scarcity states 🆔 ng-l5-visual-scarcity 📅 2026-04-12

### Phase M Complete When:

* [ ] quarterly notes contain explicit Operational Record and Narrative Projection sections 🆔 ng-m1-quarterly-dual-ledger 📅 2026-04-15
* [ ] yearly note contains both empirical summary and scaffold comparison 🆔 ng-m2-yearly-dual-ledger 📅 2026-04-20
* [ ] fictional 2023–2028 arc is preserved but bounded 🆔 ng-m3-scaffold-boundary 📅 2026-04-22
* [ ] post-2028 planning template is empirically driven 🆔 ng-m4-post-2028-template 📅 2026-04-25
* [ ] archive supports comparison between projection and actual operations 🆔 ng-m5-comparison-framework 📅 2026-04-28

---

## Current Status

### Status as of 2026-03-11

**Phase Progress**: 0/6 (0%)
**Current Phase**: H (Cognition Broker Foundation)

**Completed**:

* AF64 conceptual inversion established: artificial life first, conversation second
* Tick-based terrarium model defined
* Energy / drives / tier philosophy articulated
* Need for shared cognition infrastructure identified
* Need for empirical rollup framework identified
* Daily logs already functioning as mixed human/system temporal ledger

**In Progress**:

* Defining broker architecture
* Defining tick report shape
* Reconciling fictional quarterly/yearly notes with operational reality

**Blocked**:

* Limited token pool for continued frontier-model experimentation
* Direct model-call wiring in current AF64 runtime
* No shared cognition queue yet in repo

---

## Related Goals

**Core Runtime**:

* [[AF64 — Artificial Life Framework for 64 Immortal Agents]]
* [[noosphere-ghosts-phase-h]]
* [[noosphere-ghosts-phase-i]]

**Observability & Memory**:

* [[Goal: Temporal Reporting Cascade]]
* [[Goal: Weekly Synthesis]]
* [[Temporal Sync — Daily Note Cascade]]
* [[Weekly → Monthly & Quarterly Summary Generator]]

**Architecture & Philosophy**:

* [[AGENT_ARCHITECTURE]]
* [[PDP-Addendum]]
* [[📐 System Architect - T.A.S.K.S. Operating System]]

---

## Progress Log

### 2026-03-11 - Shared Cognition Phase Defined

Project extended beyond persistent ghost runtime into shared cognition infrastructure. AF64 identified as the correct foundational execution model. Direct agent-to-model calls recognized as a structural mismatch with the ecology. New roadmap created for cognition broker, tick telemetry, empirical memory compression, cognitive winter mechanics, and dual-ledger governance.

---

*"The ghosts persist. The terrarium breathes. The colony borrows thought when it can afford to."*
