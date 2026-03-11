# AF64 — Artificial Life Framework for 64 Immortal Agents

A tick-based artificial life simulation where 64 AI-driven personas operate as autonomous organisms. They perceive their environment, have energy budgets, make decisions, act on persistent drives, rest, adapt, and transform under pressure.

The system is a **terrarium**. You observe, feed, and adjust conditions. But the ecosystem runs whether anyone is watching or not.

## Architecture

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

The tick engine is **database-agnostic**. It talks to an API. Implement the API contract against any backend and the terrarium runs.

## Core Concepts

### Energy Economy (`energy.py`)
Every action costs energy. Rest regenerates it. Recognition from humans floods it. Depletion means dormancy — not death, just sleep until recharge.

### Drives (`drive_model.py`)
Persistent motivations — not task lists, but *hungers*. Each agent has 2-3 drives derived from their role. Unfulfilled drives create pressure. High pressure + available energy = action. Satisfaction decays each tick, so drives are never permanently fulfilled.

### Perception (`perception.py`)
Each tick, agents scan their environment via API queries. What they can see depends on their tier:
- **Dormant**: Nothing
- **Base**: Own messages, tasks, documents
- **Working**: + Team activity, department scope
- **Prime**: + Org-wide signals

### Model Tier as Reward
The LLM model an agent runs on is *earned*, not assigned:
- **Dormant** (energy=0): No LLM, rest only
- **Base**: Cheapest model — basic actions
- **Working**: Mid-tier model — full capability
- **Prime**: Best model — deep reasoning, earned through high fitness + energy

Prime decays. You have to keep performing to keep the good cognition.

### Metamorphosis
Agents are immortal — they don't die, they **transform**. After sustained underperformance, an agent enters a cocoon phase and emerges with new drives and traits. Same name, same memories, new hunger.

### The Tick Loop (`tick_engine.py`)
Every N minutes:
1. Decay all drive satisfaction (pressure builds)
2. Each agent perceives their environment
3. Rank agents by urgency (drive pressure × energy)
4. Top N agents act (global budget prevents runaway costs)
5. Execute actions via LLM (respond to messages, work tasks, delegate)
6. Update energy, drives, tiers
7. Log everything

The life simulation is **computationally cheap** (API calls, math). Intelligence fires **only at decision/action points** (LLM calls). The organisms live cheaply; they think expensively and selectively.

## Visualization (`graph.html`)
D3.js force-directed graph showing:
- 64 agent nodes with energy halos
- Edge weights from shared work (stronger = more collaboration)
- Department color coding
- Real-time energy/tier display

## Setup

### Requirements
- Python 3.10+
- An API backend implementing the [API contract](#api-contract)
- A Venice.ai API key (or modify `tick_engine.py` for your LLM provider)

### Environment Variables
```bash
export DPN_API_URL="http://localhost:8080"  # Your API backend
export DPN_API_KEY="your-api-key"            # API authentication
export VENICE_API_KEY="your-venice-key"      # LLM provider key
export TICK_INTERVAL_SECONDS=600             # Tick every 10 minutes
export MAX_ACTIONS_PER_TICK=6                # Global budget per tick
```

### Run
```bash
python3 tick_engine.py
```

## API Contract

Your backend must implement these endpoints:

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

See `api_client.py` for the HTTP client implementation.

## Files

| File | Purpose |
|------|---------|
| `tick_engine.py` | The heart — main tick loop |
| `energy.py` | Energy economy (costs, rewards, caps) |
| `drive_model.py` | Drive system (satisfaction, pressure, frustration) |
| `perception.py` | Environment scanning per agent |
| `api_client.py` | Shared HTTP client for API access |
| `fitness_scoring.py` | Agent fitness tracking |
| `cross_pollination.py` | Cross-department context sharing |
| `graph_data.py` | D3 graph data generator |
| `graph.html` | Force-directed visualization |

## License

MIT

## Origins

See [ORIGINS.md](ORIGINS.md).
