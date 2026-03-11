#!/usr/bin/env python3
"""AF64 Fitness Scoring — tracks agent performance via API.

Fitness determines model tier access:
- High fitness + high energy → Prime (best LLM)
- Positive fitness + energy → Working (mid-tier)
- Low/zero → Base (cheapest)

Scoring events:
  approved: +3  (human approved agent's work)
  engaged: +1   (human engaged with agent's output)
  ignored: -1   (agent's output was ignored)
  corrected: -2 (human corrected agent's mistake)
  task_completed: +5 (agent completed a task)
  task_revision: -3  (agent's work sent back for revision)
"""
import os
from api_client import api_get, api_post

HUMAN_AGENT = os.environ.get("AF64_HUMAN_AGENT", "nathan")

SCORE_MAP = {
    "approved": 3,
    "engaged": 1,
    "ignored": -1,
    "corrected": -2,
    "task_completed": 5,
    "task_revision_required": -3,
}


def record_fitness_event(agent_id, event_type, score=None, description=""):
    """Record a fitness event for an agent via API."""
    if score is None:
        score = SCORE_MAP.get(event_type, 0)
    
    api_post("/api/fitness", {
        "agent_id": agent_id,
        "event_type": event_type,
        "score": score,
        "description": description,
    })


def get_fitness_score(agent_id, days=30):
    """Get total fitness score for an agent over N days."""
    data = api_get(f"/api/fitness/{agent_id}?days={days}")
    return data.get("total", 0)


def classify_human_response(message_text):
    """Classify a human's response to determine fitness impact.
    
    Returns: event_type string or None if no clear signal.
    """
    text = message_text.lower().strip()
    
    positive = ["good", "great", "nice", "perfect", "exactly", "yes", "correct",
                "well done", "thanks", "thank you", "approved", "love it", "brilliant"]
    negative = ["no", "wrong", "incorrect", "fix", "redo", "not what", "try again",
                "that's not", "missed", "failed"]
    
    for word in positive:
        if word in text:
            return "approved"
    for word in negative:
        if word in text:
            return "corrected"
    
    return "engaged"  # Default: human responded = engagement


def report(agent_id=None):
    """Get a fitness report. If agent_id given, single agent. Otherwise top/bottom."""
    if agent_id:
        score = get_fitness_score(agent_id)
        return {"agent_id": agent_id, "score": score}
    
    # For org-wide reports, you'd query the API for all agents
    # This is a simplified version
    return {"note": "Use get_fitness_score(agent_id) for individual scores"}
