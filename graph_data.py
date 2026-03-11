#!/usr/bin/env python3
"""AF64 Graph Data Generator — generates D3-compatible JSON for the life visualization.

Uses the dpn-api instead of direct DB access.
"""
import json
from api_client import api_get
from runtime_paths import get_broker_state_path


def load_broker_snapshot():
    try:
        with open(get_broker_state_path(), encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def generate_graph_data():
    """Build the full graph data structure for the D3 visualization."""
    agents = api_get("/api/agents")
    broker_snapshot = load_broker_snapshot()
    pending_by_agent = broker_snapshot.get("pending_by_agent", {})
    
    nodes = []
    edges = []
    mutations = []
    
    for a in agents:
        state = a.get("state", {})
        drives = a.get("drives", [])
        
        node = {
            "id": a["id"],
            "name": a.get("full_name", a["id"]),
            "role": a.get("role", ""),
            "department": a.get("department", ""),
            "tier": state.get("tier", "base") if state else "base",
            "energy": state.get("energy", 50) if state else 50,
            "fitness": 0,
            "messages": 0,
            "document_links": 0,
            "mutations": 0,
            "tasks_completed": 0,
            "connectivity": 0,
            "pending_cognition": a["id"] in pending_by_agent,
        }
        
        # Get fitness
        try:
            fitness_data = api_get(f"/api/fitness/{a['id']}?days=30")
            node["fitness"] = fitness_data.get("total", 0)
        except:
            pass
        
        nodes.append(node)
        
        # Reports-to edges
        if a.get("reports_to"):
            edges.append({
                "source": a["id"],
                "target": a["reports_to"],
                "type": "reports_to",
                "weight": 1,
            })
    
    total_energy = sum(n["energy"] for n in nodes)
    
    return {
        "nodes": nodes,
        "edges": edges,
        "mutations": mutations,
        "meta": {
            "total_agents": len(nodes),
            "total_edges": len(edges),
            "total_energy": round(total_energy, 1),
            "broker": {
                "pending_jobs": len(broker_snapshot.get("pending_jobs", [])),
                "cache_entries": len(broker_snapshot.get("cache", {})),
                "recent_telemetry_events": len(broker_snapshot.get("telemetry", [])),
            },
        }
    }


if __name__ == "__main__":
    data = generate_graph_data()
    print(json.dumps(data, indent=2))
