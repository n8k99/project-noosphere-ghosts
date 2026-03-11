#!/usr/bin/env python3
"""AF64 Energy Economy — the metabolic system of the living organization."""

from api_client import api_get, api_patch

CAP = 100
FLOOR = 0
STARTING = 50

# Energy costs (negative = drain)
COSTS = {
    "rest": 0,
    "communicate": -3,
    "respond_message": -5,
    "routine_work": -8,
    "deep_work": -15,
    "opus_work": -35,
    "delegate": -5,
    "idle": 0,
}

# Out-of-specialty multiplier
OUT_OF_SPECIALTY_MULT = 2.0

# Energy rewards (positive = gain)
REWARDS = {
    "rest": 3,
    "task_complete": 15,
    "milestone": 50,
    "nathan_recognition": 75,
    "orchestrator_attention": 8,
    "peer_ack": 4,
    "tool_creation": 30,
}


def update_energy(conn_unused, agent_id, delta):
    """Update agent energy via API, clamped to [FLOOR, CAP]. Returns new energy."""
    result = api_patch(f"/api/agents/{agent_id}/state", {"energy_delta": delta})
    return result.get("energy", STARTING)


def get_energy(conn_unused, agent_id):
    """Read current energy for an agent via API."""
    try:
        data = api_get(f"/api/agents/{agent_id}")
        return data.get("agent", {}).get("energy", STARTING)
    except Exception:
        return STARTING


def get_cost(action, in_specialty=True):
    """Get energy cost for an action, with out-of-specialty multiplier."""
    cost = COSTS.get(action, -5)
    if not in_specialty and cost < 0:
        cost = int(cost * OUT_OF_SPECIALTY_MULT)
    return cost


if __name__ == "__main__":
    # Test via API
    e = get_energy(None, "nova")
    print(f"nova energy: {e}")
    new_e = update_energy(None, "nova", -10)
    print(f"nova after -10: {new_e}")
    new_e = update_energy(None, "nova", +10)
    print(f"nova after +10: {new_e}")
    print("energy.py OK (via API)")
