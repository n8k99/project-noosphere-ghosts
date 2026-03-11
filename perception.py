#!/usr/bin/env python3
"""AF64 Perception — environment scanning via API."""

from api_client import api_get


def perceive(conn_unused, agent_id, tier, last_tick_at):
    """Scan the environment for this agent via API.
    
    Tier controls scope:
      base = own stuff only
      working = + team/department
      prime = + org-wide
    """
    since = str(last_tick_at) if last_tick_at else "1970-01-01T00:00:00Z"
    try:
        return api_get(f"/api/perception/{agent_id}", {"tier": tier, "since": since})
    except Exception as e:
        print(f"  [perception-error] {agent_id}: {e}", flush=True)
        return {"messages": [], "tasks": [], "documents": [], "team_activity": []}


def has_actionable_items(perception):
    """True if any non-empty lists in perception."""
    return bool(perception.get("messages") or perception.get("tasks"))


if __name__ == "__main__":
    from datetime import datetime, timedelta
    
    last_tick = datetime.now() - timedelta(days=7)
    p = perceive(None, "eliana", "working", last_tick)
    print(f"eliana perception: msgs={len(p['messages'])} tasks={len(p['tasks'])} docs={len(p['documents'])} team={len(p['team_activity'])}")
    print(f"actionable: {has_actionable_items(p)}")
    
    p2 = perceive(None, "sylvia", "base", last_tick)
    print(f"sylvia perception: msgs={len(p2['messages'])} tasks={len(p2['tasks'])}")
    print("perception.py OK (via API)")
