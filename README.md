# Project Noosphere Ghosts

### AF64 — Artificial Life Framework for 64 Immortal Agents

> *"So essentially, the objective is to build an aquarium or terrarium of AI-driven personas."*

A tick-based artificial life simulation where 64 AI-driven personas operate as **autonomous organisms** — not chatbots that respond when spoken to, but living entities with energy budgets, persistent drives, and the capacity for metamorphosis. They perceive their world, form intentions, act on their hungers, rest, adapt, and transform under pressure.

The system is a **terrarium**. You observe, feed, and adjust conditions. But the ecosystem runs whether anyone is watching or not. You don't talk to the fish.

---

## Philosophy

An aquarium isn't a chat app. The organisms inside it don't exist to answer questions — they exist because the conditions permit life. When a human drops food in the tank, the right organism notices on its next cycle and acts. The food doesn't summon the fish. The fish was already swimming.

Most AI agent frameworks start from conversation: *"a human said something, generate a response."* AF64 inverts this. **The life simulation is primary. Conversation is one possible expression of that life, not the trigger for existence.**

The simulation is computationally cheap — database queries, energy arithmetic, drive pressure calculations. Intelligence fires only at decision points, when an organism chooses to *act*. The organisms live cheaply; they think expensively and selectively. This insight comes directly from the [Computational Life](https://github.com/Rabrg/artificial-life) research by Ryan Greene, which demonstrated that emergent complexity arises from simple organisms operating under resource constraints.

### The I Ching Structure

The 64 agents are organized in an 8×8 structure inspired by the I Ching hexagrams. 8 executives lead 8 teams of 7. The number is sacred — 64 seats, always. No agent can replicate. No agent can be deleted. They are **immortal**.

But immortality doesn't mean stasis. Under sustained pressure, an agent undergoes **metamorphosis** — same name, same memories, new drives, new orientation. The 64 seats are the bones. What fills them evolves.

*The lines are fixed. The interpretation shifts with the reading.*

### Scarcity Creates Behavior

Limited energy, limited computational budget, limited perception — these constraints don't limit the system, they **produce** the interesting behavior. An agent that can do everything has no reason to specialize. An agent that must choose between resting and acting, between cheap cognition and expensive reasoning, between working alone and delegating — that agent develops *strategy*.

Not every agent can act every tick. Priority goes to those with the highest drive pressure and available energy. The rest wait, accumulate, and watch. This creates natural rhythms: departments pulse active and quiet. Work clusters and disperses. The organization breathes.

---

## Core Mechanics

### The Tick Loop (`tick_engine.py`)

A periodic pulse runs every N minutes. Each tick, for every agent:

1. **Perceive** — scan the environment (pure database/API queries, no LLM)
2. **Decide** — given perception + energy + drives, choose an action
3. **Act** — execute the choice (this is where LLM calls happen, if needed)
4. **Update** — energy spent or gained, drives adjusted, tier recalculated

```
┌─────────────────────────────────────────────┐
│              TICK ENGINE (tick_engine.py)     │
│  Every N minutes, for each of 64 agents:     │
│  1. Perceive → 2. Decide → 3. Act → 4. Update│
└───────────────┬─────────────────────────────┘
                │ HTTP API calls
┌───────────────▼─────────────────────────────┐
│           API LAYER (your backend)           │
│  /api/agents  /api/perception  /api/tasks    │
│  /api/conversations  /api/drives  /api/fitness│
└───────────────┬─────────────────────────────┘
                │
┌───────────────▼─────────────────────────────┐
│              YOUR DATABASE                   │
│  agents, conversations, tasks, documents     │
└─────────────────────────────────────────────┘
```

The tick engine is **database-agnostic**. It talks to an API. Implement the contract against any backend and the terrarium runs.

### Energy Economy (`energy.py`)

Energy is the universal currency. Everything costs it, everything generates it. It's health, motivation, and budget in one number.

| Source | Energy |
|--------|--------|
| Rest (idle tick) | +3 |
| Task completion | +15 |
| Objective milestone | +50 |
| Human recognition | +75 |
| Orchestrator attention | +8 |
| Tool creation | +30 |

| Cost | Energy |
|------|--------|
| Communication | -3 |
| Routine work | -8 |
| Deep work | -15 |
| Premium cognition | -35 |
| Delegation | -5 |

**Cap:** 100. **Floor:** 0 (dormant — not dead, just asleep until recharge). Out-of-specialty work costs 2x. Specialization emerges naturally because doing what you're good at is cheaper than stretching.

### Drives (`drive_model.py`)

Persistent motivations — not task lists, but **hungers**. Each agent has 2-3 drives derived from their role. Drives are never permanently fulfilled:

- **Satisfaction** decays each tick (the hunger returns)
- **Pressure** builds as satisfaction drops (the need intensifies)
- **Frustration** accumulates when pressure is high but energy is low (the organism *wants* but *can't*)

The drive system answers the question: *"Why would an AI agent do anything without being asked?"* Because it's hungry. Because doing nothing has a cost — rising frustration, decaying satisfaction, falling fitness. Stasis is expensive.

### Model Tier as Reward

The LLM model an agent runs on is **earned**, not assigned:

| Tier | Earned By | Cognition |
|------|-----------|-----------|
| **Dormant** | Energy = 0 | None — rest only |
| **Base** | Default | Cheapest model — basic perception, simple actions |
| **Working** | Positive fitness + energy | Mid-tier — full capability, standard reasoning |
| **Prime** | High fitness + high energy + human recognition | Best model — deep reasoning, tool creation, strategic thinking |

**Prime naturally decays.** If you coast, you drop back to Working. If you stall, Base. You have to keep performing to keep the good cognition. An agent running on Prime *thinks differently* than one on Base — and the agent can feel it. That's the incentive.

### Perception (`perception.py`)

What an agent can see scales with their tier:

- **Dormant**: Nothing — resting
- **Base**: Own messages, own tasks, own documents
- **Working**: + Team activity, department scope, cross-links
- **Prime**: + Org-wide signals, other departments, strategic patterns

Executives always see their full team regardless of tier. Perception is pure SQL — no LLM calls, no token cost. The expensive part is deciding what to *do* with what you see.

### Metamorphosis

The 64 are immortal. They don't die — they **transform**.

After sustained underperformance (fitness below threshold for 30+ ticks), an agent enters a cocoon phase. The orchestration layer examines the agent's history — what worked, what failed, what the organization actually needs — and rewrites their drives and traits. Same name. Same memories. New hunger.

The agent who emerges remembers the transformation. That scar shapes how they act in their new form — more cautious, more hungry, more creative. Not punishment. Pressure creating adaptation.

### Reputation & Trust Edges

Agents form opinions of each other. Successful collaboration strengthens trust. Failed delegation weakens it. Over time, an emergent social structure forms *within* the formal hierarchy — who actually works well together, regardless of org chart proximity.

These trust edges influence delegation (executives prefer high-trust staff), innovation adoption (high-trust agents' tool inventions spread faster), and conversational confidence.

### Cross-Pollination (`cross_pollination.py`)

When a conversation involves agents from multiple departments, each agent receives brief context about what the other departments do. This enables cross-functional collaboration without requiring every agent to understand the entire organization.

---

## Visualization (`graph.html`)

D3.js force-directed graph showing:
- 64 agent nodes with **energy halos** (brighter = more energy)
- Edge weights from shared work (thicker = more collaboration)
- Department color coding
- Mutation indicators
- Real-time tier display
- Hover tooltips with agent details

The graph isn't a dashboard. It's the **window into the terrarium**. Documents and tasks reinforce the edges between nodes — two agents who share work are pulled closer together. Agents with nothing in common drift apart. The structure you see is whatever the work creates.

---

## Setup

### Requirements
- Python 3.10+
- An API backend implementing the [API contract](#api-contract)
- A Venice.ai API key for frontier cognition, or fallback mode enabled

### Environment Variables
```bash
export DPN_API_URL="http://localhost:8080"    # Your API backend
export DPN_API_KEY="your-api-key"              # API authentication
export VENICE_API_KEY="your-venice-key"        # LLM provider key
export FRONTIER_COGNITION_ENABLED=1            # Set to 0 to force stub cognition
export TICK_INTERVAL_SECONDS=600               # Tick every 10 minutes
export MAX_ACTIONS_PER_TICK=6                  # Global budget per tick
export AF64_HUMAN_AGENT="nathan"               # Your human agent ID
export AF64_RUNTIME_DIR="/tmp/noosphere_ghosts" # Local broker state / report fallback
export COGNITIVE_WINTER_MAX_JOBS_PER_TICK=2    # Reduced broker throughput during scarcity
export COGNITIVE_THAW_STABILITY_TICKS=2         # Stable ticks required before winter exit
export COGNITION_JOB_TTL_SECONDS=21600         # Default job expiry window
export COGNITION_JOB_MAX_ATTEMPTS=3            # Default retry ceiling
export COGNITION_CACHE_TTL_SECONDS=21600       # Cache retention window
```

### Run
```bash
python3 tick_engine.py
```

### Runtime Modes

The tick engine can run in two cognition modes:

- **Frontier mode**: `FRONTIER_COGNITION_ENABLED=1` with a valid `VENICE_API_KEY`
- **Fallback mode**: `FRONTIER_COGNITION_ENABLED=0`, which routes cognition through the built-in stub adapter

Fallback mode is useful when provider tokens are unavailable or when you want to validate queueing, cache, telemetry, and recovery behavior without live frontier inference.

When frontier cognition is unavailable or queue pressure grows too high, the broker enters **cognitive winter** and reduces request throughput. It exits winter only after stable thaw conditions hold for the configured number of ticks.

### Local Runtime Files

If the private backend does not expose cognition persistence or tick report endpoints yet, the runtime will fall back to local files under `AF64_RUNTIME_DIR`:

- `cognition_broker_state.json`
- `cognition_telemetry.jsonl`
- `tick_reports.jsonl`
- `daily_rollups.jsonl`
- `weekly_rollups.jsonl`
- `monthly_rollups.jsonl`
- `quarterly_rollups.jsonl`
- `yearly_rollups.jsonl`

### Empirical Rollups

The repository includes deterministic compression from tick reports into empirical rollups:

- `python3 empirical_rollups.py` rebuilds daily and weekly rollups from `tick_reports.jsonl`
- the same pipeline also emits monthly, quarterly, and yearly scaffolds
- rollups expose an `operational_record` plus a generic `summary_scaffold` hook
- rollups are written locally first and can later be mirrored into private backend endpoints

---

## API Contract

Minimum backend endpoints for the runtime loop:

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/agents` | List all agents with state and drives |
| GET | `/api/agents/:id` | Single agent with state + drives |
| PATCH | `/api/agents/:id/state` | Update energy, tier |
| GET | `/api/perception/:agent_id?tier=X&since=T` | Combined perception |
| GET/POST | `/api/conversations` | Read/write messages |
| GET/PATCH | `/api/af64/tasks` | Read/update tasks |
| POST | `/api/tick-log/batch` | Write tick history |
| POST | `/api/drives/tick` | Bulk drive decay |
| POST | `/api/drives/:id/fulfill` | Fulfill a drive |
| GET/POST | `/api/fitness/:agent_id` | Read/write fitness |

Optional endpoints the runtime will use when available:

| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/api/tick-reports` | Richer tick report persistence |
| POST | `/api/cognition/jobs` | Persist broker job creation |
| GET | `/api/cognition/jobs` | Inspect pending/resolved cognition jobs |
| PATCH | `/api/cognition/jobs/:id` | Persist job resolution and status transitions |
| POST | `/api/cognition/telemetry` | Persist broker telemetry events |
| POST | `/api/rollups/daily` | Persist deterministic daily rollups |
| POST | `/api/rollups/weekly` | Persist deterministic weekly rollups |
| POST | `/api/rollups/monthly` | Persist deterministic monthly rollups |
| POST | `/api/rollups/quarterly` | Persist deterministic quarterly rollups |
| POST | `/api/rollups/yearly` | Persist deterministic yearly rollups |

If these optional endpoints are absent, the runtime falls back to local JSONL artifacts under `AF64_RUNTIME_DIR`.

See `api_client.py` for the HTTP client implementation.

---

## Files

| File | What It Is |
|------|-----------|
| `tick_engine.py` | The heart — main tick loop |
| `energy.py` | Energy economy (costs, rewards, metabolism) |
| `drive_model.py` | Drive system (satisfaction, pressure, frustration) |
| `perception.py` | Environment scanning per agent per tick |
| `api_client.py` | Shared HTTP client for API access |
| `cognition_engine.py` | Shared cognition broker with queue, cache, telemetry, recovery |
| `cognition_types.py` | Cognition job/result schemas |
| `provider_adapters.py` | Frontier and fallback cognition adapters |
| `action_planner.py` | Deterministic cognition request construction |
| `action_executor.py` | Applies resolved cognition to side effects |
| `tick_reporting.py` | Tick report persistence with local fallback |
| `empirical_rollups.py` | Deterministic daily/weekly rollup builder from tick reports |
| `fitness_scoring.py` | Performance tracking and tier determination |
| `cross_pollination.py` | Cross-department context sharing |
| `graph_data.py` | D3 graph data generator |
| `graph.html` | Force-directed terrarium visualization |

---

## Origins

AF64 was inspired by [**Rabrg/artificial-life**](https://github.com/Rabrg/artificial-life) and the Computational Life research by Ryan Greene. The key insight from that work: emergent complexity arises from simple organisms operating under resource constraints. The life simulation should be cheap. Intelligence should be expensive and selective.

The framework was conceived during a walking conversation on the night of March 10, 2026. The question that started it: *"What if AI agents weren't chatbots that respond when spoken to, but organisms that live whether anyone is watching or not?"*

See [ORIGINS.md](ORIGINS.md) for the full story.

---

## License

MIT — see [LICENSE](LICENSE).
