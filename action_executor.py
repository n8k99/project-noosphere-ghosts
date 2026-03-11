#!/usr/bin/env python3
"""Apply broker cognition results to API side effects."""

from api_client import api_patch, api_post


def execute_cognition_result(result):
    action_name = result.action_name
    metadata = result.metadata or {}

    if action_name == "respond_message":
        msg = metadata.get("source_message", {})
        payload = {
            "from_agent": result.agent_id,
            "to_agent": [msg.get("from")],
            "message": result.content,
            "channel": msg.get("channel", "noosphere"),
            "thread_id": msg.get("thread_id"),
            "metadata": {
                "responding_to": str(msg.get("id")),
                "source": "cognition_broker",
                "job_id": result.job_id,
                "provider": result.provider_name,
                "cached": result.cached,
            },
        }
        post_result = api_post("/api/conversations", payload)
        return {
            "action": "respond_message",
            "msg_id": msg.get("id"),
            "reply_id": post_result.get("id"),
            "response": result.content[:200],
        }

    if action_name == "work_task":
        task = metadata.get("task", {})
        api_patch(f"/api/af64/tasks/{task['id']}", {"status": "in-progress"})
        return {
            "action": "work_task",
            "task_id": task.get("id"),
            "response": result.content[:200],
        }

    return None
