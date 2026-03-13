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

