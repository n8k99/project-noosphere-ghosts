# CLAUDE.md — AI Assistant Guide for Noosphere Ghosts

## Project Overview

Noosphere Ghosts is a tick-based artificial life engine implementing the **AF64 framework** (Anthropomorphic Frameworks 64). It animates persistent agents called "Ghosts" that perceive, reason, act, and remember within a substrate-abstracted environment. The runtime is written entirely in **Common Lisp** (SBCL).

Key concepts: tick-based execution, shared cognition broker, energy economy, drive-pressure systems, empirical memory compression, and constitutional rules governing ghost behavior.

The vision: "organisms that live whether anyone is watching or not" — not chatbots that respond when spoken to.

## Branches

- **`main`** — Public-facing baseline with core architecture
- **`em-droplet`** — Production deployment branch with full runtime (tool-socket, OpenClaw gateway, EM Staff integration, pipeline stages, Python tooling). **This is the more complete and active branch.**

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
├── launch.sh                      # Startup script (em-droplet)
├── config/                        # Runtime configuration (em-droplet)
│   ├── af64.env                   # Environment variable defaults
│   ├── em-field-mapping.lisp      # EM Staff frontmatter → AF64 concept mapping
│   ├── provider-config.json       # LLM provider chain configuration
│   └── tool-registry.json         # 32+ tool definitions with scope permissions
├── lisp/                          # Common Lisp source code
│   ├── af64.asd                   # ASDF system definition
│   ├── packages.lisp              # Package definitions and exports
│   ├── main.lisp                  # Entry point (af64:run-tick)
│   ├── runtime/                   # Core execution engine
│   ├── util/                      # Low-level utilities (JSON, HTTP)
│   └── tools/                     # CLI tools (onboarding wizard)
├── tools/                         # Python/shell operational tools (em-droplet)
│   ├── nightly-memory-synthesis.py # Nightly Ollama-powered memory summaries
│   ├── tool-builder.sh            # Spawns Claude Code to build tools from specs
│   ├── sync-eliana-to-dailynotes.py
│   └── write_vault_memory.py
└── sql/                           # Database scripts (em-droplet)
    ├── fill_graph_holes.sql       # Missing team document creation
    └── formative_memories_executives.sql  # Formative false memories for executives
```

### Runtime Modules (`lisp/runtime/`)

| Module | Purpose |
|---|---|
| `tick-engine.lisp` | 5-phase tick cycle: perceive → rank → classify → request → resolve |
| `cognition-broker.lisp` | Shared cognition queue, cache, telemetry, cognitive winter |
| `cognition-types.lisp` | Job and Result data structures |
| `perception.lisp` | Fetches messages, tasks, documents from substrate |
| `drive.lisp` | Drive decay, pressure calculation, fulfillment |
| `energy.lisp` | Energy budgets, action costs/rewards, off-peak multiplier |
| `action-planner.lisp` | Constructs cognition jobs; loads persona from EM Staff DB |
| `action-executor.lisp` | Pipeline stage advancement with output validation |
| `provider-adapters.lisp` | LLM provider chain abstraction (Anthropic, Venice, etc.) |
| `openclaw-gateway.lisp` | OAuth-based LLM access through OpenClaw Max subscription |
| `tool-socket.lisp` | Universal tool execution — registry, parsing, dispatch |
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
- **External tools**: `curl` (HTTP), `python3` (tooling), `ollama` (local LLM for memory synthesis)
- **No external Lisp libraries** — JSON parsing and HTTP are implemented in-repo
- **Data formats**: JSON, JSONL (tick reports, telemetry, rollups), Markdown with YAML frontmatter (persona/identity files)
- **Database**: PostgreSQL (reference substrate via Master Chronicle API)
- **LLM gateway**: OpenClaw proxy (`127.0.0.1:18789`) routing to Anthropic

## Building and Running

### Quick start (manual)
```bash
cd lisp
sbcl --eval '(require :asdf)' \
     --eval '(asdf:load-system :af64)' \
     --eval '(af64:run-tick 1)' \
     --quit
```

### Production (em-droplet)
```bash
./launch.sh
```
This loads `config/af64.env`, creates the runtime directory, loads all modules in order, and starts an infinite tick loop with 30-second intervals.

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `DPN_API_URL` | `http://localhost:8080` | Substrate API base URL |
| `DPN_API_KEY` | `dpn-nova-2026` | Substrate API key |
| `AF64_RUNTIME_DIR` | `/tmp/noosphere_ghosts/` | Local runtime state directory |
| `AF64_PERSONA_DIR` | `~/gotcha-workspace/context/personas/` | Persona file directory |
| `AF64_PERSONA_MAP_FILE` | — | Custom persona map file (fallback) |
| `AF64_MEMORY_TABLE` | `vault_notes` | Memory storage table |
| `AF64_MEMORY_LAYER` | `daily` | Memory abstraction layer |
| `AF64_PRIMARY_USER_HANDLE` | `[[NathanEckenrode]]` | Primary user wikilink |
| `AF64_PRIMARY_USER_ID` | `nathan_eckenrode` | Primary user ID |
| `FRONTIER_COGNITION_ENABLED` | `1` | Enable frontier LLM calls |
| `MAX_ACTIONS_PER_TICK` | `5` | Max actions per tick |
| `TICK_INTERVAL_SECONDS` | `30` | Seconds between ticks |
| `OPENCLAW_GATEWAY_PASS` | — | OpenClaw proxy auth token |
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
- **Action costs**: Rest (0), Communicate (-3), Respond (-5), Routine (-8), Deep (-15), Opus (-35), Delegate (-5)
- **Action rewards**: Rest (+5), Task (+15), Milestone (+50), Nathan recognition (+75), Tool creation (+30), Orchestrator attention (+8), Peer ack (+4)
- **Off-peak multiplier**: 2x (outside 8AM–2PM ET weekdays)
- **Default models**: Sonnet (prime/working), Haiku (base), Opus (Nova only)
- **Broker cache TTL**: 6 hours (configurable)

## Architecture Notes

### 5-Phase Tick Cycle (em-droplet)

1. **PERCEIVE** — Fetch all agents' perceptions (messages, requests, tasks, team activity)
2. **RANK** — Score agents by urgency: `pressure + message_boost + request_boost + task_boost`; select acting set
3. **CLASSIFY** — Determine each agent's state: dormant, acting, idle, or winter-idle
4. **REQUEST** — Submit cognition jobs to broker for agents needing thinking
5. **RESOLVE** — Process completed cognition results and execute side effects

### Energy Tier System
- **Dormant**: energy ≤ 0
- **Base**: 0 < energy ≤ 20, fitness ≤ 50 → uses Haiku
- **Working**: 20 < energy ≤ 70, fitness > 0 → uses Sonnet
- **Prime**: energy > 70 AND fitness > 50 → uses Sonnet
- **Special cases**: Nova → always Opus (never dormant); Elise → Sonnet minimum

### Cognition Broker
The broker treats LLM reasoning as a scarce shared resource. It queues jobs, caches results (keyed by SHA256 of normalized payload), tracks telemetry, and implements "cognitive winter" — system-wide throttling when resources are exhausted.

### Tool Socket
Universal tool execution system. Loads `config/tool-registry.json`, filters by agent `tool_scope` permissions, parses `tool_call` blocks from LLM output, and executes Python scripts, shell commands, or special handlers (`query_db`, `write_document`, `build_tool`).

### Pipeline Stages
The action executor validates output quality at each pipeline stage:

| Pipeline | Stages |
|---|---|
| **Engineering** | spec → infra-review → design → build → security-review → test → deploy → done |
| **Investment** | thesis → research → analysis → compliance → documentation → approval → done |
| **Editorial** | collection → research → curation → composition → editing → polish → publish → done |
| **Modular Fortress** | discovery → pattern-analysis + architecture-research → synthesis → tool-audit → module-standards → done |

Each stage has minimum length and content requirements for validation (e.g., `build` requires 1000+ chars with actual code).

### EM Staff Integration
Ghost identity comes from EM Staff documents in the database:
- **Path**: `Areas/Eckenrode Muziekopname/EM Staff/{AgentName}.md`
- **Frontmatter** contains: identity, archetype, skills, role, energy, tier, evolution state
- **Wikilinks** resolve teams, mentors, archetypes from the document graph
- **Mapping** defined in `config/em-field-mapping.lisp` covering: Identity, Soul, Memory, Tools, Runtime, Orbis (mythic layer), Evolution

### Substrate Abstraction
The engine is backend-agnostic. The API client abstracts over PostgreSQL, document stores, or filesystem backends. The reference deployment uses the Master Chronicle system with PostgreSQL.

### Constitutional Rules
`rules4ghosts.lisp` defines 11 rules governing ghost behavior (identity preservation, energy conservation, communication norms). Enforced at runtime via `rules.lisp`.

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

1. **Work on `em-droplet`** — This is the active development branch with the complete runtime. `main` is the public-facing baseline.
2. **Read before modifying** — Always read the relevant source file before making changes. The codebase has careful interdependencies.
3. **Respect the zero-dependency constraint** — Do not introduce external Lisp libraries. Implement utilities in `lisp/util/`.
4. **Follow existing naming conventions** — kebab-case, verb-noun function names, package-prefixed exports.
5. **Preserve the tick cycle contract** — Changes to any runtime module must maintain the 5-phase ordering: perceive → rank → classify → request → resolve.
6. **Consult `PROJECT_NOOSPHERE_GHOSTS.md`** for architectural decisions and phase boundaries before proposing structural changes.
7. **Constitutional rules are foundational** — Do not modify `rules4ghosts.lisp` without explicit instruction.
8. **Environment variables control runtime behavior** — Prefer configuration via env vars over hardcoded values. See `config/af64.env` for defaults.
9. **ASDF system definition** — When adding new source files, register them in `af64.asd` and define their package in `packages.lisp`.
10. **Tool registry** — New tools go in `config/tool-registry.json` with appropriate `scope` permissions. Tools execute via the tool-socket, not direct subprocess calls.
11. **EM Staff is the source of truth** — Ghost identity and state live in the database as EM Staff documents. Do not hardcode agent attributes.
12. **Pipeline validation matters** — Stage advancement in action-executor requires content quality checks. Do not bypass validation.
