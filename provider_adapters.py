#!/usr/bin/env python3
"""Provider adapters for broker-managed cognition."""

import json
import os
import urllib.request

from cognition_types import CognitionJob, CognitionResult


MODEL_MAP = {
    "prime": "claude-sonnet-4-6",
    "working": "claude-sonnet-4-5",
    "base": "llama-3.3-70b",
}

VENICE_API_KEY = os.environ.get("VENICE_API_KEY", "")
FRONTIER_COGNITION_ENABLED = os.environ.get("FRONTIER_COGNITION_ENABLED", "1").lower() not in {"0", "false", "no"}


class ProviderAdapter:
    name = "base"

    def generate(self, job: CognitionJob) -> CognitionResult | None:
        raise NotImplementedError


class VeniceAdapter(ProviderAdapter):
    name = "venice"

    def generate(self, job: CognitionJob) -> CognitionResult | None:
        if not FRONTIER_COGNITION_ENABLED or not VENICE_API_KEY:
            return None

        system_prompt = job.input_context["system_prompt"]
        messages = job.input_context["messages"]
        model = MODEL_MAP.get(job.requested_model_tier, MODEL_MAP["base"])
        payload = {
            "model": model,
            "max_tokens": 512,
            "messages": [{"role": "system", "content": system_prompt}] + messages,
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
                content = data.get("choices", [{}])[0].get("message", {}).get("content", "")
                if not content:
                    return None
                return CognitionResult(
                    job_id=job.id,
                    agent_id=job.agent_id,
                    action_name=job.action_name,
                    content=content,
                    provider_name=self.name,
                    model_used=model,
                )
        except Exception:
            return None


class StubAdapter(ProviderAdapter):
    name = "stub"

    def generate(self, job: CognitionJob) -> CognitionResult | None:
        if job.kind == "respond_message":
            msg = job.input_context.get("source_message", {})
            content = f"Acknowledged. I saw your message about: {msg.get('message', '')[:140]}"
        elif job.kind == "work_task":
            task = job.input_context.get("task", {})
            content = f"Progress update: I am advancing task #{task.get('id')} and will continue with the next concrete step."
        else:
            content = "No cognition output available."

        return CognitionResult(
            job_id=job.id,
            agent_id=job.agent_id,
            action_name=job.action_name,
            content=content,
            provider_name=self.name,
            model_used="deterministic-fallback",
            metadata={"fallback": True},
        )


def build_default_provider_chain() -> list[ProviderAdapter]:
    providers: list[ProviderAdapter] = [VeniceAdapter(), StubAdapter()]
    return providers
