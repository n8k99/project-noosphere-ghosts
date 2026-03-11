#!/usr/bin/env python3
"""AF64 Tick Engine — THE HEART of the living organization.

Each tick: perceive → decide → act → rest → evolve.
Conservative first ticks: mostly rest + a few message responses.
"""

import json
import os
import sys
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone

from api_client import api_get, api_post, api_patch
from energy import COSTS, REWARDS, update_energy, get_energy, get_cost
from drive_model import tick_drives, fulfill_drive, get_highest_pressure_drive
from perception import perceive, has_actionable_items

# ── Config ──────────────────────────────────────────────────────────────
TICK_INTERVAL = max(60, int(os.environ.get("TICK_INTERVAL_SECONDS", "600")))
MAX_ACTIONS = int(os.environ.get("MAX_ACTIONS_PER_TICK", "6"))

# Venice API
VENICE_API_KEY = ""
try:
    # Load Venice API key from environment
        VENICE_API_KEY = os.environ.get("VENICE_API_KEY", "")
except Exception:
    pass

# Model routing by tier
MODEL_MAP = {
    "prime": "claude-sonnet-4-6",
    "working": "claude-sonnet-4-5",
    "base": "llama-3.3-70b",
}

# Persona directory
PERSONA_DIR = os.path.expanduser("~/gotcha-workspace/context/personas/")
_persona_cache = {}


# ── Venice API (copied from noosphere_listener, independent) ────────────
def call_venice(system_prompt, messages, model="llama-3.3-70b"):
    """Call Venice.ai API. Returns response text or None."""
    if not VENICE_API_KEY:
        return None

    venice_messages = [{"role": "system", "content": system_prompt}] + messages
    payload = {
        "model": model,
        "max_tokens": 512,
        "messages": venice_messages,
    }

    req = urllib.request.Request(
        "https://api.venice.ai/api/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {VENICE_API_KEY}",
            "User-Agent": "Noosphere/1.0",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            if not raw:
                return None
            data = json.loads(raw)
            return data.get("choices", [{}])[0].get("message", {}).get("content", "")
    except Exception as e:
        print(f"  [venice-error] {e}", flush=True)
        return None


# ── Persona loading ─────────────────────────────────────────────────────
def load_persona(agent_id, agent_info):
    """Load persona text for an agent. Cached."""
    if agent_id in _persona_cache:
        return _persona_cache[agent_id]

    # Try file
    persona_files = {
        "nova": None, "eliana": "eliana.md", "sarah": "sarah.md",
        "kathryn": "kathryn.md", "sylvia": "sylvia.md", "vincent": "vincent.md",
        "jmax": "maxwell.md", "lrm": "morgan.md",
    }
    fname = persona_files.get(agent_id)
    if fname:
        path = os.path.join(PERSONA_DIR, fname)
        try:
            with open(path) as f:
                content = f.read()
            if content.startswith("---"):
                parts = content.split("---", 2)
                if len(parts) >= 3:
                    content = parts[2].strip()
            _persona_cache[agent_id] = content
            return content
        except Exception:
            pass

    # Try DB personnel file via API
    try:
        full_name = agent_info.get("full_name", agent_id)
        name_nospace = full_name.replace(" ", "").replace(".", "")
        docs = api_get("/api/af64/documents", {
            "path_prefix": f"Areas/Eckenrode Muziekopname/EM Staff/{name_nospace}",
            "limit": 1,
        })
        if docs and len(docs) > 0:
            # We only get summary from the API, not content. Use fallback.
            pass
    except Exception:
        pass

    # Fallback
    fallback = f"You are {agent_info.get('full_name', agent_id)}, {agent_info.get('role', 'staff')} at Eckenrode Muziekopname."
    _persona_cache[agent_id] = fallback
    return fallback


# ── Action execution ────────────────────────────────────────────────────
def execute_respond_message(agent_id, agent_info, perception, tier):
    """Respond to the most recent unread message via Venice."""
    msg = perception["messages"][0]
    model = MODEL_MAP.get(tier, "llama-3.3-70b")

    persona = load_persona(agent_id, agent_info)
    system_prompt = f"""{persona}

You are responding to a message in the Noosphere. Be concise (1-2 paragraphs max). Have opinions. No filler.
Nathan is the CEO. Don't ask permission, just do your job."""

    user_content = f"[{msg['from']}]: {msg['message']}"
    messages = [{"role": "user", "content": user_content}]

    response = call_venice(system_prompt, messages, model=model)
    if not response:
        return None, model, False

    # Post reply via API
    thread_id = msg.get("thread_id")
    channel = msg.get("channel", "noosphere")
    metadata = {"responding_to": str(msg["id"]), "source": "tick_engine"}

    result = api_post("/api/conversations", {
        "from_agent": agent_id,
        "to_agent": [msg["from"]],
        "message": response,
        "channel": channel,
        "thread_id": thread_id,
        "metadata": metadata,
    })

    new_id = result.get("id")
    return {"action": "respond_message", "msg_id": msg["id"], "reply_id": new_id, "response": response[:200]}, model, True


def execute_work_task(agent_id, agent_info, perception, tier):
    """Work on the highest priority open task via Venice."""
    task = perception["tasks"][0]
    model = MODEL_MAP.get(tier, "llama-3.3-70b")

    persona = load_persona(agent_id, agent_info)
    system_prompt = f"""{persona}

You are working on a task. Provide a concise progress update or completion report.
Be specific about what you did. 1-2 paragraphs max."""

    user_content = f"Task #{task['id']}: {task['text']}\nStatus: {task['status']}\nAssigned by: {task.get('assigned_by', 'unknown')}"
    messages = [{"role": "user", "content": user_content}]

    response = call_venice(system_prompt, messages, model=model)
    if not response:
        return None, model, False

    # Update task via API
    api_patch(f"/api/af64/tasks/{task['id']}", {"status": "in-progress"})

    return {"action": "work_task", "task_id": task["id"], "response": response[:200]}, model, True


# ── Main tick loop ──────────────────────────────────────────────────────
def run_tick(tick_number):
    """Execute one tick of the engine."""
    now = datetime.now(timezone.utc)

    # Load all agents with state via API
    agent_list = api_get("/api/agents")
    agents = {}
    for a in agent_list:
        if a.get("status") != "active":
            continue
        agents[a["id"]] = {
            "agent_id": a["id"],
            "energy": a.get("energy", 50),
            "tier": a.get("tier", "base"),
            "last_tick_at": a.get("last_tick_at"),
            "dormant_since": a.get("dormant_since"),
            "full_name": a.get("full_name", a["id"]),
            "role": a.get("role", ""),
            "department": a.get("department", ""),
            "agent_tier": a.get("agent_tier", "staff"),
            "reports_to": a.get("reports_to"),
        }

    # Phase 1: Tick drives (bulk API call)
    try:
        tick_drives(None, None)
    except Exception as e:
        print(f"  [drive-tick-error] {e}", flush=True)

    # Phase 2: Perceive for all agents
    perceptions = {}
    for aid, a in agents.items():
        last_tick = a["last_tick_at"] or str(now)
        perceptions[aid] = perceive(None, aid, a["tier"], last_tick)

    # Phase 3: Rank by urgency = drive_pressure * (energy/100)
    rankings = []
    for aid, a in agents.items():
        if a["energy"] <= 0:
            continue  # dormant
        drive = get_highest_pressure_drive(None, aid)
        pressure = drive["pressure"] if drive else 50
        urgency = pressure * (a["energy"] / 100.0)
        rankings.append((aid, urgency, drive))
    rankings.sort(key=lambda x: -x[1])

    # Phase 4: Top N act
    active_count = 0
    idle_count = 0
    dormant_count = 0
    top_actor = None
    logs = []

    acting_set = set()
    for aid, urgency, drive in rankings[:MAX_ACTIONS]:
        if has_actionable_items(perceptions[aid]):
            acting_set.add(aid)

    for aid, a in agents.items():
        energy_before = a["energy"]

        if a["energy"] <= 0:
            dormant_count += 1
            logs.append({
                "tick_number": tick_number, "agent_id": aid, "action_taken": "dormant",
                "action_detail": {}, "energy_before": energy_before, "energy_after": energy_before,
                "tier": a["tier"], "model_used": None, "llm_called": False,
            })
            continue

        if aid in acting_set:
            p = perceptions[aid]
            action_detail = None
            model_used = None
            llm_called = False
            action_name = "rest"

            if p["messages"]:
                action_name = "respond_message"
                result, model_used, llm_called = execute_respond_message(aid, a, p, a["tier"])
                if result:
                    action_detail = result
                    drive = get_highest_pressure_drive(None, aid)
                    if drive:
                        fulfill_drive(None, aid, drive["drive_name"], 10)
                else:
                    action_name = "rest"

            elif p["tasks"]:
                action_name = "work_task"
                result, model_used, llm_called = execute_work_task(aid, a, p, a["tier"])
                if result:
                    action_detail = result
                    drive = get_highest_pressure_drive(None, aid)
                    if drive:
                        fulfill_drive(None, aid, drive["drive_name"], 15)
                else:
                    action_name = "rest"

            cost = get_cost(action_name)
            energy_after = update_energy(None, aid, cost)

            if action_name != "rest":
                active_count += 1
                if top_actor is None:
                    top_actor = f"{aid}({action_name})"
                print(f"  [tick {tick_number}] agent={aid} action={action_name} energy={energy_before:.0f}→{energy_after:.0f} tier={a['tier']}", flush=True)
            else:
                idle_count += 1
                energy_after = update_energy(None, aid, REWARDS["rest"])

            logs.append({
                "tick_number": tick_number, "agent_id": aid, "action_taken": action_name,
                "action_detail": action_detail or {}, "energy_before": energy_before,
                "energy_after": energy_after, "tier": a["tier"],
                "model_used": model_used, "llm_called": llm_called,
            })
        else:
            idle_count += 1
            energy_after = update_energy(None, aid, REWARDS["rest"])
            logs.append({
                "tick_number": tick_number, "agent_id": aid, "action_taken": "idle",
                "action_detail": {}, "energy_before": energy_before,
                "energy_after": energy_after, "tier": a["tier"],
                "model_used": None, "llm_called": False,
            })

    # Phase 5: Update tiers based on fitness
    for aid, a in agents.items():
        try:
            fitness_data = api_get(f"/api/fitness/{aid}", {"days": 30})
            fitness = fitness_data.get("fitness", 0)
        except Exception:
            fitness = 0

        current_energy = get_energy(None, aid)

        if current_energy <= 0:
            new_tier = "dormant"
        elif fitness > 50 and current_energy > 70:
            new_tier = "prime"
        elif fitness > 0 and current_energy > 20:
            new_tier = "working"
        else:
            new_tier = "base"

        # Update state via API
        state_update = {
            "tier": new_tier,
            "last_tick_at": "now",
            "ticks_alive": (a.get("ticks_alive", 0) or 0) + 1,
        }
        if new_tier == a["tier"]:
            state_update["ticks_at_current_tier"] = (a.get("ticks_at_current_tier", 0) or 0) + 1
        else:
            state_update["ticks_at_current_tier"] = 0

        try:
            api_patch(f"/api/agents/{aid}/state", state_update)
        except Exception as e:
            print(f"  [state-update-error] {aid}: {e}", flush=True)

    # Phase 6: Write tick_log (batch)
    try:
        api_post("/api/tick-log/batch", {"entries": logs})
    except Exception as e:
        print(f"  [tick-log-error] {e}", flush=True)

    # Summary
    if not top_actor:
        top_actor = "none"
    print(f"[tick {tick_number}] active={active_count} idle={idle_count} dormant={dormant_count} | top_actor={top_actor} | budget_used={active_count}/{MAX_ACTIONS}", flush=True)


def main():
    print(f"🫀 AF64 Tick Engine starting — interval={TICK_INTERVAL}s, max_actions={MAX_ACTIONS}/tick (API mode)", flush=True)

    # Get last tick number via tick-log
    try:
        # Use a simple query approach - get max tick from recent logs
        agents = api_get("/api/agents")
        # We don't have a direct "max tick" endpoint, so start from where we were
        # The tick_log batch endpoint handles the rest
    except Exception:
        pass

    # Read last tick from a state file
    tick_file = "/tmp/af64_last_tick.txt"
    tick_number = 0
    try:
        with open(tick_file) as f:
            tick_number = int(f.read().strip())
    except Exception:
        pass

    print(f"Resuming from tick {tick_number}", flush=True)

    while True:
        tick_number += 1
        try:
            run_tick(tick_number)
            # Persist tick number
            with open(tick_file, "w") as f:
                f.write(str(tick_number))
        except Exception as e:
            print(f"[error] Tick {tick_number} failed: {e}", flush=True)
            import traceback
            traceback.print_exc()

        time.sleep(TICK_INTERVAL)


if __name__ == "__main__":
    main()
