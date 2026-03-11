#!/usr/bin/env python3
"""Shared types for cognition broker requests and results."""

from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Any
import uuid


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def future_utc_iso(seconds: int) -> str:
    return (datetime.now(timezone.utc) + timedelta(seconds=seconds)).isoformat()


@dataclass
class CognitionJob:
    agent_id: str
    tick_number: int
    kind: str
    priority: float
    requested_model_tier: str
    input_context: dict[str, Any]
    cache_key: str
    action_name: str
    cost_estimate: int = 0
    status: str = "pending"
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    provider_name: str | None = None
    result: dict[str, Any] | None = None
    error: str | None = None
    created_at: str = field(default_factory=utc_now_iso)
    resolved_at: str | None = None
    last_attempt_at: str | None = None
    expires_at: str | None = None
    retry_count: int = 0
    max_attempts: int = 3
    wait_ticks: int = 0

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "agent_id": self.agent_id,
            "tick_number": self.tick_number,
            "kind": self.kind,
            "priority": self.priority,
            "requested_model_tier": self.requested_model_tier,
            "input_context": self.input_context,
            "cache_key": self.cache_key,
            "action_name": self.action_name,
            "cost_estimate": self.cost_estimate,
            "status": self.status,
            "provider_name": self.provider_name,
            "result": self.result,
            "error": self.error,
            "created_at": self.created_at,
            "resolved_at": self.resolved_at,
            "last_attempt_at": self.last_attempt_at,
            "expires_at": self.expires_at,
            "retry_count": self.retry_count,
            "max_attempts": self.max_attempts,
            "wait_ticks": self.wait_ticks,
        }


@dataclass
class CognitionResult:
    job_id: str
    agent_id: str
    action_name: str
    content: str
    provider_name: str
    model_used: str | None
    cached: bool = False
    metadata: dict[str, Any] = field(default_factory=dict)
    created_at: str = field(default_factory=utc_now_iso)

    def to_dict(self) -> dict[str, Any]:
        return {
            "job_id": self.job_id,
            "agent_id": self.agent_id,
            "action_name": self.action_name,
            "content": self.content,
            "provider_name": self.provider_name,
            "model_used": self.model_used,
            "cached": self.cached,
            "metadata": self.metadata,
            "created_at": self.created_at,
        }
