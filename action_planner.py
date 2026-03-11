#!/usr/bin/env python3
"""Deterministic planning for cognition requests."""

import hashlib
import json
import os

from cognition_types import CognitionJob, future_utc_iso


PERSONA_DIR = os.path.expanduser("~/gotcha-workspace/context/personas/")
_persona_cache: dict[str, str] = {}
JOB_TTL_SECONDS = int(os.environ.get("COGNITION_JOB_TTL_SECONDS", "21600"))
JOB_MAX_ATTEMPTS = int(os.environ.get("COGNITION_JOB_MAX_ATTEMPTS", "3"))


def load_persona(agent_id, agent_info):
    if agent_id in _persona_cache:
        return _persona_cache[agent_id]

    persona_files = {
        "nova": None,
        "eliana": "eliana.md",
        "sarah": "sarah.md",
        "kathryn": "kathryn.md",
        "sylvia": "sylvia.md",
        "vincent": "vincent.md",
        "jmax": "maxwell.md",
        "lrm": "morgan.md",
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

    fallback = f"You are {agent_info.get('full_name', agent_id)}, {agent_info.get('role', 'staff')} at Eckenrode Muziekopname."
    _persona_cache[agent_id] = fallback
    return fallback


def compute_priority(energy, tier, drive_pressure, action_name):
    tier_bonus = {"prime": 20, "working": 10, "base": 0, "dormant": -100}.get(tier, 0)
    action_bonus = {"respond_message": 8, "work_task": 5}.get(action_name, 0)
    return round(float(drive_pressure) + (float(energy) * 0.35) + tier_bonus + action_bonus, 2)


def make_cache_key(payload):
    normalized = json.dumps(payload, sort_keys=True, default=str)
    return hashlib.sha256(normalized.encode()).hexdigest()


def build_cognition_job(agent_id, agent_info, perception, tier, tick_number, drive):
    persona = load_persona(agent_id, agent_info)
    drive_pressure = drive["pressure"] if drive else 50

    if perception.get("messages"):
        msg = perception["messages"][0]
        payload = {
            "agent_id": agent_id,
            "kind": "respond_message",
            "message_id": msg.get("id"),
            "thread_id": msg.get("thread_id"),
            "from": msg.get("from"),
            "message": msg.get("message", ""),
            "tier": tier,
        }
        return CognitionJob(
            agent_id=agent_id,
            tick_number=tick_number,
            kind="respond_message",
            priority=compute_priority(agent_info["energy"], tier, drive_pressure, "respond_message"),
            requested_model_tier=tier,
            input_context={
                "system_prompt": (
                    f"{persona}\n\n"
                    "You are responding to a message in the Noosphere. "
                    "Be concise (1-2 paragraphs max). Have opinions. No filler.\n"
                    "Nathan is the CEO. Don't ask permission, just do your job."
                ),
                "messages": [{"role": "user", "content": f"[{msg['from']}]: {msg['message']}"}],
                "source_message": msg,
            },
            cache_key=make_cache_key(payload),
            action_name="respond_message",
            cost_estimate=5,
            expires_at=future_utc_iso(JOB_TTL_SECONDS),
            max_attempts=JOB_MAX_ATTEMPTS,
        )

    if perception.get("tasks"):
        task = perception["tasks"][0]
        payload = {
            "agent_id": agent_id,
            "kind": "work_task",
            "task_id": task.get("id"),
            "status": task.get("status"),
            "text": task.get("text", ""),
            "tier": tier,
        }
        return CognitionJob(
            agent_id=agent_id,
            tick_number=tick_number,
            kind="work_task",
            priority=compute_priority(agent_info["energy"], tier, drive_pressure, "work_task"),
            requested_model_tier=tier,
            input_context={
                "system_prompt": (
                    f"{persona}\n\n"
                    "You are working on a task. Provide a concise progress update or completion report.\n"
                    "Be specific about what you did. 1-2 paragraphs max."
                ),
                "messages": [{
                    "role": "user",
                    "content": (
                        f"Task #{task['id']}: {task['text']}\n"
                        f"Status: {task['status']}\n"
                        f"Assigned by: {task.get('assigned_by', 'unknown')}"
                    ),
                }],
                "task": task,
            },
            cache_key=make_cache_key(payload),
            action_name="work_task",
            cost_estimate=8,
            expires_at=future_utc_iso(JOB_TTL_SECONDS),
            max_attempts=JOB_MAX_ATTEMPTS,
        )

    return None
