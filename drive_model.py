#!/usr/bin/env python3
"""AF64 Drive Model — what agents WANT. Drives create pressure, pressure creates action."""

from api_client import api_get, api_post, api_patch

# Drive templates by role/department keywords
DRIVE_TEMPLATES = {
    "executive": [
        ("leadership", "Guide and develop team members"),
        ("strategic_vision", "Shape organizational direction"),
    ],
    "engineering": [("build", "Create and improve systems"), ("quality", "Ensure code reliability")],
    "legal": [("compliance", "Protect the organization legally"), ("ethics", "Uphold ethical standards")],
    "art": [("create", "Produce compelling visual work"), ("innovate", "Push creative boundaries")],
    "music": [("compose", "Create and analyze musical works"), ("preserve", "Document musical heritage")],
    "content": [("storytell", "Craft engaging narratives"), ("publish", "Get content to audiences")],
    "brand": [("storytell", "Craft engaging narratives"), ("publish", "Get content to audiences")],
    "strategic": [("analyze", "Derive insights from data"), ("optimize", "Improve organizational performance")],
    "audience": [("engage", "Connect with the audience"), ("measure", "Track engagement metrics")],
    "support": [("facilitate", "Enable smooth operations"), ("connect", "Bridge gaps between teams")],
    "operations": [("organize", "Keep things running smoothly"), ("efficiency", "Streamline processes")],
    "partnership": [("collaborate", "Build external relationships"), ("growth", "Expand reach and impact")],
    "impact": [("mission", "Advance social mission"), ("measure", "Quantify impact")],
    "analyst": [("analyze", "Derive insights from data")],
    "engineer": [("build", "Create and improve systems")],
    "designer": [("create", "Design compelling experiences")],
    "specialist": [("expertise", "Apply deep domain knowledge")],
    "manager": [("coordinate", "Orchestrate team efforts")],
    "coordinator": [("organize", "Keep projects on track")],
    "editor": [("refine", "Polish content to perfection")],
    "producer": [("deliver", "Ship high-quality output")],
    "researcher": [("discover", "Uncover new knowledge")],
    "advisor": [("counsel", "Provide expert guidance")],
    "default": [("contribute", "Add value to the organization"), ("grow", "Develop skills and knowledge")],
}


def tick_drives(conn_unused, agent_id, energy=None):
    """Tick ALL drives via API (single bulk call). Called once per tick cycle."""
    # The API handles all agents at once
    api_post("/api/drives/tick", {})


def fulfill_drive(conn_unused, agent_id, drive_name, amount):
    """Satisfy a drive via API."""
    api_post(f"/api/drives/{agent_id}/fulfill", {"drive_name": drive_name, "amount": amount})


def get_highest_pressure_drive(conn_unused, agent_id):
    """Return the drive pushing hardest for this agent via API."""
    try:
        drives = api_get(f"/api/agents/{agent_id}/drives")
        if drives and len(drives) > 0:
            d = drives[0]  # Already sorted by pressure DESC
            return {
                "drive_name": d["drive_name"],
                "pressure": d.get("pressure", 50),
                "satisfaction": d.get("satisfaction", 50),
                "frustration": d.get("frustration", 0),
            }
    except Exception:
        pass
    return None


if __name__ == "__main__":
    # Test via API
    result = api_post("/api/drives/tick", {})
    print(f"tick_drives: {result}")

    d = get_highest_pressure_drive(None, "eliana")
    print(f"eliana top drive: {d}")

    if d:
        fulfill_drive(None, "eliana", d["drive_name"], 20)
        d2 = get_highest_pressure_drive(None, "eliana")
        print(f"eliana after fulfill: {d2}")
    
    print("drive_model.py OK (via API)")
