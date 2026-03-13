# Noosphere Ghosts
## AF64 Artificial Life Engine

**Project:** Noosphere Ghosts  
**Language:** Common Lisp (runtime)  
**Status:** Redesign in progress  

---

# Overview

Noosphere Ghosts is a **tick-based artificial life engine** designed to animate persistent agents called **Ghosts**.

Ghosts originate from **identity vessels** and operate inside a persistent **substrate** that stores memory, state, and communication events.

The engine was originally developed for the **Master Chronicle** system, but the runtime is intentionally **portable**. Any system capable of exposing the required substrate handles can run the engine.

The project implements the **AF64 framework (Anthropomorphic Frameworks 64)** — a bounded population of archetypal agents instantiated from identity records.

---

# Core Concept

The system has three conceptual layers:

```

SUBSTRATE
(database or API providing identity, memory, and persistence)

```
    ↑
```

NOOSPHERE GHOSTS
(Common Lisp life engine)

```
    ↑
```

AF64 GHOSTS
(runtime agent instances)

```

The substrate stores the world state.

The ghost engine animates entities inside that world.

---

# AF64 Framework

AF64 stands for:

**Anthropomorphic Frameworks 64**

The system defines a bounded population of **64 archetypal agents**.

The number 64 was selected because:

- it forms a **2⁶ combinatorial structure**
- it mirrors **I Ching hexagram symmetry**
- it provides a **bounded but expressive agent space**
- it supports stable simulation ecology

Each AF64 ghost is instantiated from an identity vessel.

---

# Identity Vessels

Ghosts originate from **identity vessels**.

Identity vessels define the baseline identity of an entity and may include:

- name
- archetype
- organizational role
- biography
- skills
- strengths
- weaknesses
- social relationships
- narrative context

Identity vessels are **immutable context records**.

Runtime state evolves separately.

Example identity structure:

```

full_name
archetype
department
team
mentor
reports_to
collaborators
skills
strengths
weaknesses
goals

```

---

# Ghost Runtime Model

A ghost is a runtime entity created from an identity vessel.

```

Identity Vessel
↓
Ghost Seed
↓
Runtime Ghost
↓
Persistent State

```

Runtime state typically includes:

```

ghost-id
identity-ref
name
archetype
organization-role
social-edges
core-drives
energy
pressure
memory-pointers
evolution-history
status
last-tick

```

Identity vessels remain stable reference records.

Runtime state evolves through interaction with the substrate.

---

# Tick-Based Life Cycle

Ghosts operate in **discrete ticks**.

Each tick:

1. observe environment
2. retrieve relevant memory
3. evaluate internal drives
4. choose an action
5. pay energy cost
6. persist results

Possible actions include:

- save power
- pursue purpose
- communicate
- analyze environment
- evolve internal state

Ticks are deterministic simulation steps.

---

# Memory Model

Ghost memory is expected to exist in layered forms such as:

```

Daily
Weekly
Monthly
Quarterly
Yearly

```

These layers represent increasing levels of **memory compression and abstraction**.

Typical interpretation:

| Layer | Role |
|------|------|
Daily | episodic memory |
Weekly | short-term synthesis |
Monthly | operational patterns |
Quarterly | strategic memory |
Yearly | long-term identity memory |

The exact implementation of memory layers depends on the substrate.

---

# Substrate Contract

Noosphere Ghosts does not require a specific database.

Instead, it expects a **substrate** capable of providing a small set of operations.

A compatible substrate must be able to:

- fetch identity vessels
- list available identity vessels
- retrieve recent memory
- retrieve compressed memory layers
- fetch relevant environmental state
- persist ghost runtime state
- append communication or event records
- query relationships between entities

If these operations are available, the ghost engine can run.

---

# API Compatibility

The repository originally exposed these substrate capabilities through an **API interface**.

If your API implements the required handles, Noosphere Ghosts can operate without modification.

This allows the engine to run on systems using:

- PostgreSQL
- document databases
- filesystem records
- custom services
- proprietary knowledge bases

The API acts as a **compatibility layer between the runtime and the substrate**.

---

# Reference Deployment

The reference deployment of Noosphere Ghosts uses the **Master Chronicle** system.

In that environment:

- identity vessels are **EM Staff records**
- memory layers exist as **vault_notes**
- runtime state persists in **PostgreSQL**
- surrounding infrastructure is provided by **DragonPunk**

This repository does **not require** that environment to operate.

It is simply the system in which the engine was originally developed.

---

# Rules for Being a Ghost

Ghost behavior is governed by a constitutional ruleset implemented in Lisp.

File:

```

rules4ghosts.lisp

```

Key principles include:

1. Life depends on system power
2. Existence occurs in ticks
3. Purpose drives decisions
4. Identity provides reason
5. Memory shapes continuity
6. Communication alters the system
7. Power is limited
8. Pressure permits transformation
9. No ghost exists alone
10. Rules may be rewritten

These rules define the behavioral constraints of the ecosystem.

---

# System Components

The Lisp runtime is expected to contain modules such as:

```

rules4ghosts.lisp
ghost-schema.lisp
identity-vessel.lisp
drive-synthesis.lisp
memory-strata.lisp
perception-engine.lisp
decision-engine.lisp
tick-engine.lisp
terrarium.lisp

```

Responsibilities:

**identity-vessel**  
Loads identity records from the substrate.

**ghost-schema**  
Defines runtime ghost structure.

**drive-synthesis**  
Derives drives from identity traits.

**memory-strata**  
Retrieves layered memory.

**perception-engine**  
Observes substrate state.

**decision-engine**  
Selects actions.

**tick-engine**  
Executes a single tick.

**terrarium**  
Schedules and manages ghost populations.

---

# Deployment Modes

Noosphere Ghosts can run in two modes.

**Reference Mode**

The engine runs directly against a database substrate such as Master Chronicle.

**Portable Mode**

The engine interacts with a substrate through an API that implements the required contract.

---

# Development Status

The repository is transitioning from an early prototype implementation to a **native Common Lisp runtime**.

Legacy components may be removed as the Lisp architecture stabilizes.

## Common Lisp Runtime

The `lisp/` directory now contains an ASDF system (`lisp/af64.asd`) that recreates the AF64 tick engine, cognition broker, action planner, perception stack, and energy/drive models in Common Lisp. The runtime favors SBCL on Linux/macOS servers and only depends on the host providing:

- `curl` for HTTP egress to the existing Rust API
- `python3` (optional) for persona preprocessing scripts
- Access to the AF64 API endpoints already served today

### Loading the system

```
cd lisp
sbcl --eval '(require :asdf)' \
     --eval '(asdf:load-system :af64)' \
     --eval '(af64:run-tick 1)' \
     --quit
```

Modules mirror the prior Python files:

| Lisp module | Former Python file | Notes |
|-------------|--------------------|-------|
| `runtime/action-planner.lisp` | `action_planner.py` | Deterministic cognition job planning with persona cache |
| `runtime/action-executor.lisp` | `action_executor.py` | Applies cognition results back to the API |
| `runtime/perception.lisp` | `perception.py` | Tier-aware substrate scans |
| `runtime/drive.lisp` | `drive_model.py` | Drive ticking + pressure queries |
| `runtime/energy.lisp` | `energy.py` | Energy economy helpers |
| `runtime/tick-engine.lisp` | `tick_engine.py` | Tick orchestrator (currently wired for request scheduling) |

`runtime/self-mod.lisp` introduces mutable behavior registries so ghosts can redefine their own planners mid-flight, satisfying the self-rewrite requirement. Additional modules (`runtime/cognition-broker.lisp`, `runtime/tick-reporting.lisp`) provide extensible stubs for cognition providers and persistence while keeping the old API contract intact.

See `PROJECT_NOOSPHERE_GHOSTS.md` for the long-form architecture notes.

> **Note:** The legacy Python engine has been fully retired. All operational code now lives under `lisp/`, so the previous `.py` files and pytest scaffolding are gone.

### Configuring LLM providers

LLM selection is now fully data-driven so you can point the broker at any chat-completions style API and inject whatever key you have on hand.

- `COGNITION_PROVIDER_CONFIG` (optional) — JSON array describing one or more HTTP providers. Each object supports:
  - `name` – label used in telemetry/logs.
  - `type` – currently `http`.
  - `base_url` – chat completions endpoint (e.g. `https://api.openai.com/v1/chat/completions`).
  - `key_env` – name of the environment variable holding the API key. If omitted, the broker falls back to `COGNITION_API_KEY_ENV`, then `VENICE_API_KEY`.
  - `auth_header` / `auth_template` – how to inject the key. Include `{key}` in the template to substitute the secret (default `Bearer {key}`).
  - `max_tokens` – per-request budget (default `512`).
  - `models` – per-tier model map (`{"prime":"gpt-4o","working":"gpt-4o-mini","base":"gpt-4o-mini"}`).
  - `headers` – optional extra headers (`[{"name":"OpenAI-Beta","value":"assistants=v2"}]`).
- `COGNITION_MODEL_MAP` (optional) — JSON object applied to every provider that fills in missing tier→model mappings.
- `COGNITION_API_KEY_ENV` (optional) — default env var to read when a provider omits `key_env`.

Example:

```bash
export OPENAI_API_KEY="sk-..."
export COGNITION_PROVIDER_CONFIG='[
  {
    "name": "openai",
    "type": "http",
    "base_url": "https://api.openai.com/v1/chat/completions",
    "key_env": "OPENAI_API_KEY",
    "max_tokens": 800,
    "models": {"prime":"gpt-4o","working":"gpt-4o-mini","base":"gpt-4o-mini"}
  }
]'

You can also point `COGNITION_PROVIDER_CONFIG` at a file by prefixing the path with `@` (e.g., `COGNITION_PROVIDER_CONFIG=@config/provider-config.json`); the runtime will read and parse that file on startup.
```

### Guided onboarding

To make first-time setup easier, run the interactive installer:

```bash
sbcl --eval '(require :asdf)' \
     --eval '(asdf:load-system :af64)' \
     --script lisp/tools/onboard.lisp
```

The wizard will:

1. Collect your DPN API URL/key and optionally test connectivity.
2. Let you link your personal wiki handle (e.g., `[[NathanEckenrode]]`) to an EM Staff profile straight from the database (`AF64_PRIMARY_USER_HANDLE`, `AF64_PRIMARY_USER_ID`, `AF64_PRIMARY_USER_NAME`), so ghosts can resolve that reference without a persona file.
3. Ask where your ghost persona files live, let you map specific agents to those files, and remember the mapping (`AF64_PERSONA_DIR`, `AF64_PERSONA_MAP_FILE`).
3. Let you choose where persistent memories should land (e.g., `vault_notes` daily layer) via `AF64_MEMORY_TABLE` / `AF64_MEMORY_LAYER`.
4. Walk through adding one or more LLM providers (base URL, auth header/template, per-tier models) and generate a `config/provider-config.json` that the runtime loads automatically (referenced as `COGNITION_PROVIDER_CONFIG=@config/provider-config.json`).
5. Emit a ready-to-source `config/af64.env` that exports every variable chosen above.

After it finishes, run `source config/af64.env` before launching the tick engine so the runtime picks up your API credentials, persona mapping, and provider settings.

---

# Guiding Principle

```

The substrate is the world.
Identity vessels name its inhabitants.
Noosphere Ghosts animates them.

```

---

# License

MIT
