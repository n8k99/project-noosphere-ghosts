# CLAUDE.md — AI Assistant Guide for Noosphere Ghosts

## Project Overview

Noosphere Ghosts is a tick-based artificial life engine implementing the **AF64 framework** (Anthropomorphic Frameworks 64). It animates persistent agents called "Ghosts" that perceive, reason, act, and remember within a substrate-abstracted environment. The runtime is written entirely in **Common Lisp** (SBCL).

Key concepts: tick-based execution, shared cognition broker, energy economy, drive-pressure systems, empirical memory compression, and constitutional rules governing ghost behavior.

## Repository Structure

```
project-noosphere-ghosts/
├── CLAUDE.md                      # This file
├── README.md                      # Project overview and setup
├── PROJECT_NOOSPHERE_GHOSTS.md    # Architecture, phases, milestones
├── ORIGINS.md                     # Inspiration and acknowledgments
├── DROPLET_HANDOFF.md             # Deployment and migration notes
├── LICENSE                        # MIT
├── rules4ghosts.lisp              # 11 constitutional rules for ghost behavior
├── graph.html                     # D3.js visualization
├── .gitignore                     # Excludes __pycache__, *.pyc
└── lisp/                          # All source code
    ├── af64.asd                   # ASDF system definition
    ├── packages.lisp              # Package definitions and exports
    ├── main.lisp                  # Entry point (af64:run-tick)
    ├── runtime/                   # Core execution engine (19 modules)
    ├── util/                      # Low-level utilities (JSON, HTTP)
    └── tools/                     # CLI tools (onboarding wizard)
```

### Runtime Modules (`lisp/runtime/`)

| Module | Purpose |
|---|---|
| `tick-engine.lisp` | Main tick loop — orchestrates perceive → plan → execute cycle |
| `cognition-broker.lisp` | Shared cognition queue, cache, telemetry, cognitive winter |
| `cognition-types.lisp` | Job and Result data structures |
| `perception.lisp` | Fetches messages, tasks, documents from substrate |
| `drive.lisp` | Drive decay, pressure calculation, fulfillment |
| `energy.lisp` | Energy budgets, action costs/rewards |
| `action-planner.lisp` | Constructs cognition jobs from agent context |
| `action-executor.lisp` | Applies cognition results as side effects |
| `provider-adapters.lisp` | LLM provider chain abstraction (OpenAI, Venice, etc.) |
| `empirical-rollups.lisp` | Deterministic daily/weekly/monthly/quarterly summaries |
| `tick-reporting.lisp` | Tick report output with broker telemetry |
| `self-mod.lisp` | Mutable behavior registry for runtime rule updates |
| `rules.lisp` | Constitutional ruleset enforcement |
| `api-client.lisp` | HTTP interface to substrate API |
| `user-profile.lisp` | Primary user context |
| `runtime-paths.lisp` | File paths for local state |

### Utility Modules (`lisp/util/`)

| Module | Purpose |
|---|---|
| `json.lisp` | Custom JSON parser/encoder (no external dependencies) |
| `http.lisp` | curl-based HTTP client |

## Technology Stack

- **Language**: Common Lisp (SBCL recommended)
- **Build system**: ASDF (bundled with SBCL)
- **External tools**: `curl` (HTTP), optionally `python3` (persona preprocessing)
- **No external Lisp libraries** — JSON parsing and HTTP are implemented in-repo
- **Data formats**: JSON, JSONL (tick reports, telemetry, rollups), Markdown (persona files)

## Building and Running

```bash
cd lisp
sbcl --eval '(require :asdf)' \
     --eval '(asdf:load-system :af64)' \
     --eval '(af64:run-tick 1)' \
     --quit
```

The ASDF system definition (`af64.asd`) loads components serially. No Quicklisp or external dependencies needed.

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `DPN_API_URL` | `http://localhost:8080` | Substrate API base URL |
| `DPN_API_KEY` | `dpn-nova-2026` | Substrate API key |
| `AF64_RUNTIME_DIR` | `/tmp/noosphere_ghosts/` | Local runtime state directory |
| `AF64_PERSONA_DIR` | `~/gotcha-workspace/context/personas/` | Persona file directory |
| `COGNITION_PROVIDER_CONFIG` | — | JSON array or `@filepath` for provider chain |
| `COGNITION_MODEL_MAP` | — | JSON object for model overrides |
| `COGNITIVE_WINTER_MAX_JOBS_PER_TICK` | — | Winter threshold: max jobs per tick |
| `COGNITIVE_WINTER_PENDING_THRESHOLD` | — | Winter threshold: pending queue depth |

## Code Conventions

### Naming
- **Packages**: `af64.runtime.*`, `af64.utils.*`, `af64.tools.*`
- **Functions**: kebab-case, descriptive verb-noun pairs (e.g., `fetch-active-agents`, `broker-submit-job`)
- **Variables**: kebab-case with `*earmuffs*` for specials/globals

### Patterns
- Hash tables (with `#'equal` test) as the primary data structure for agent state
- `handler-case` for graceful error degradation
- No external dependencies — all utilities implemented in-repo
- HTTP via `curl` subprocess, not a Lisp HTTP library
- JSON interop via custom parser in `util/json.lisp`

### Key Constants
- **Energy**: cap 100, floor 0, starting 50
- **Action costs**: Rest (0), Communicate (-3), Respond (-5), Routine (-8), Deep (-15), Opus (-35)
- **Action rewards**: Rest (+3), Task (+15), Milestone (+50), Nathan recognition (+75)
- **Default models**: Sonnet 4.6 (prime), Sonnet 4.5 (working), Llama 70B (base)
- **Broker cache TTL**: 6 hours (configurable)

## Architecture Notes

### Tick Cycle
Each tick follows: **perceive → evaluate drives → plan action → submit cognition job → execute result → persist state → report**

### Cognition Broker
The broker treats LLM reasoning as a scarce shared resource. It queues jobs, caches results, tracks telemetry, and implements "cognitive winter" (system-wide throttling when resources are exhausted).

### Substrate Abstraction
The engine is backend-agnostic. The API client (`api-client.lisp`) abstracts over PostgreSQL, document stores, or filesystem backends. The reference deployment uses the Master Chronicle system with PostgreSQL.

### Constitutional Rules
`rules4ghosts.lisp` defines 11 rules governing ghost behavior (e.g., identity preservation, energy conservation, communication norms). These are enforced at runtime via `rules.lisp`.

## Testing

No automated test framework is currently set up. Validation is done through:
- Empirical rollup verification from tick reports
- Broker state persistence and recovery checks
- API contract validation via live runtime
- Local fallback mode for testing without LLM provider tokens

## Project Phases

The project follows a phased roadmap (documented in `PROJECT_NOOSPHERE_GHOSTS.md`):

- **Phase H** (current): Cognition Broker Foundation
- **Phase I**: Tick Engine Integration
- **Phase J**: Ecological Telemetry & Tick Reports
- **Phase K**: Empirical Memory Compression
- **Phase L**: Cognitive Scarcity & Winter Mechanics
- **Phase M**: Dual-Ledger Temporal Governance

## Guidelines for AI Assistants

1. **Read before modifying** — Always read the relevant source file before making changes. The codebase has careful interdependencies.
2. **Respect the zero-dependency constraint** — Do not introduce external Lisp libraries. Implement utilities in `lisp/util/`.
3. **Follow existing naming conventions** — kebab-case, verb-noun function names, package-prefixed exports.
4. **Preserve the tick cycle contract** — Changes to any runtime module must maintain the perceive→plan→execute→report ordering.
5. **Consult `PROJECT_NOOSPHERE_GHOSTS.md`** for architectural decisions and phase boundaries before proposing structural changes.
6. **Constitutional rules are foundational** — Do not modify `rules4ghosts.lisp` without explicit instruction.
7. **Environment variables control runtime behavior** — Prefer configuration via env vars over hardcoded values.
8. **ASDF system definition** — When adding new source files, register them in `af64.asd` and define their package in `packages.lisp`.
