#!/usr/bin/env python3
"""AF64 Tick Engine — THE HEART of the living organization."""

import os
import time
from datetime import datetime, timezone

from action_executor import execute_cognition_result
from action_planner import build_cognition_job
from api_client import api_get, api_post, api_patch
from cognition_engine import CognitionBroker
from energy import COSTS, REWARDS, update_energy, get_energy, get_cost
from drive_model import tick_drives, fulfill_drive, get_highest_pressure_drive
from perception import perceive, has_actionable_items
from tick_reporting import write_tick_report

# ── Config ──────────────────────────────────────────────────────────────
TICK_INTERVAL = max(60, int(os.environ.get("TICK_INTERVAL_SECONDS", "600")))
MAX_ACTIONS = int(os.environ.get("MAX_ACTIONS_PER_TICK", "6"))
BROKER = CognitionBroker(max_jobs_per_tick=MAX_ACTIONS)


# ── Main tick loop ──────────────────────────────────────────────────────
def run_tick(tick_number):
    """Execute one tick of the engine."""
    now = datetime.now(timezone.utc)
    BROKER.start_tick()
    ecology_state = BROKER.get_ecology_state()

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

    # Phase 4: Top N request cognition
    active_count = 0
    idle_count = 0
    dormant_count = 0
    top_actor = None
    logs = []

    acting_set = set()
    request_budget = ecology_state["request_budget"]
    for aid, urgency, drive in rankings[:request_budget]:
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
            drive = get_highest_pressure_drive(None, aid)
            job = BROKER.get_pending_job(aid)
            if job is None:
                job = build_cognition_job(aid, a, p, a["tier"], tick_number, drive)
                if job is not None:
                    BROKER.submit_job(job)

            if job is not None:
                logs.append({
                    "tick_number": tick_number, "agent_id": aid, "action_taken": "request_cognition",
                    "action_detail": {"job_id": job.id, "kind": job.kind, "priority": job.priority},
                    "energy_before": energy_before, "energy_after": energy_before, "tier": a["tier"],
                    "model_used": None, "llm_called": False,
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
        else:
            idle_count += 1
            energy_after = update_energy(None, aid, REWARDS["rest"])
            action_name = "winter_idle" if ecology_state["winter_active"] and has_actionable_items(perceptions[aid]) else "idle"
            logs.append({
                "tick_number": tick_number, "agent_id": aid, "action_taken": action_name,
                "action_detail": {"winter_active": True} if action_name == "winter_idle" else {}, "energy_before": energy_before,
                "energy_after": energy_after, "tier": a["tier"],
                "model_used": None, "llm_called": False,
            })

    # Phase 5: Resolve broker work and apply side effects
    resolved_results = BROKER.process_tick()
    for result in resolved_results:
        try:
            action_detail = execute_cognition_result(result)
            if not action_detail:
                continue

            cost = get_cost(result.action_name)
            energy_before = get_energy(None, result.agent_id)
            energy_after = update_energy(None, result.agent_id, cost)
            drive = get_highest_pressure_drive(None, result.agent_id)
            if drive:
                fulfill_drive(None, result.agent_id, drive["drive_name"], 10 if result.action_name == "respond_message" else 15)

            active_count += 1
            if top_actor is None:
                top_actor = f"{result.agent_id}({result.action_name})"
            print(
                f"  [tick {tick_number}] agent={result.agent_id} action={result.action_name} "
                f"energy={energy_before:.0f}→{energy_after:.0f}",
                flush=True,
            )
            logs.append({
                "tick_number": tick_number,
                "agent_id": result.agent_id,
                "action_taken": result.action_name,
                "action_detail": action_detail,
                "energy_before": energy_before,
                "energy_after": energy_after,
                "tier": agents[result.agent_id]["tier"],
                "model_used": result.model_used,
                "llm_called": result.provider_name != "stub",
            })
        except Exception as e:
            print(f"  [cognition-exec-error] {result.agent_id}: {e}", flush=True)

    # Phase 6: Update tiers based on fitness
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

    # Phase 7: Write tick_log (batch)
    try:
        api_post("/api/tick-log/batch", {"entries": logs})
    except Exception as e:
        print(f"  [tick-log-error] {e}", flush=True)

    # Summary
    if not top_actor:
        top_actor = "none"
    broker_summary = BROKER.get_tick_summary()
    tick_report = {
        "tick_number": tick_number,
        "generated_at": now.isoformat(),
        "counts": {
            "active": active_count,
            "idle": idle_count,
            "dormant": dormant_count,
        },
        "budget": {
            "max_actions": MAX_ACTIONS,
            "request_budget": request_budget,
            "used_actions": active_count,
            "pending_jobs": broker_summary["pending_jobs"],
            "cache_entries": broker_summary["cache_entries"],
        },
        "top_actor": top_actor,
        "ecology": ecology_state,
        "broker": broker_summary,
        "entries": logs,
    }
    report_sink = write_tick_report(tick_report)
    print(
        f"[tick {tick_number}] active={active_count} idle={idle_count} dormant={dormant_count} "
        f"| top_actor={top_actor} | budget_used={active_count}/{MAX_ACTIONS} "
        f"| pending_jobs={broker_summary['pending_jobs']} cache={broker_summary['cache_entries']} "
        f"| report={report_sink}",
        flush=True,
    )


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
