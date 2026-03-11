#!/usr/bin/env python3
"""Shared cognition broker for AF64."""

from collections import deque
from datetime import datetime, timezone
import json
import os

from api_client import api_patch, api_post
from cognition_types import CognitionJob, CognitionResult, utc_now_iso
from provider_adapters import build_default_provider_chain
from runtime_paths import ensure_runtime_dir, get_broker_state_path, get_broker_telemetry_path


class CognitionBroker:
    def __init__(self, max_jobs_per_tick=6):
        self.max_jobs_per_tick = max_jobs_per_tick
        self.winter_max_jobs_per_tick = int(
            os.environ.get("COGNITIVE_WINTER_MAX_JOBS_PER_TICK", str(max(1, max_jobs_per_tick // 2 or 1)))
        )
        self.winter_pending_threshold = int(
            os.environ.get("COGNITIVE_WINTER_PENDING_THRESHOLD", str(max_jobs_per_tick * 3))
        )
        self.thaw_pending_threshold = int(
            os.environ.get("COGNITIVE_THAW_PENDING_THRESHOLD", str(max(1, self.winter_pending_threshold // 2)))
        )
        self.thaw_stability_ticks = int(os.environ.get("COGNITIVE_THAW_STABILITY_TICKS", "2"))
        self.cache_ttl_seconds = int(os.environ.get("COGNITION_CACHE_TTL_SECONDS", "21600"))
        self.providers = build_default_provider_chain()
        self.pending_jobs: deque[CognitionJob] = deque()
        self.pending_by_agent: dict[str, CognitionJob] = {}
        self.ready_results: list[CognitionResult] = []
        self.cache: dict[str, dict] = {}
        self.telemetry: list[dict] = []
        self.last_tick_metrics = self._empty_metrics()
        self._winter_active = False
        self._thaw_ready_ticks = 0
        self.load_state()

    def _empty_metrics(self):
        return {
            "queued": 0,
            "resolved": 0,
            "deferred": 0,
            "cache_hits": 0,
            "cache_expired": 0,
            "expired": 0,
            "retry_attempts": 0,
            "processed_budget": 0,
        }

    def start_tick(self):
        self.last_tick_metrics = self._empty_metrics()

    def _record(self, event_type, **fields):
        event = {"event_type": event_type, "at": utc_now_iso(), **fields}
        self.telemetry.append(event)
        self._append_local_telemetry(event)
        try:
            api_post("/api/cognition/telemetry", event)
        except Exception:
            pass
        self.save_state()

    def _frontier_enabled(self):
        return os.environ.get("FRONTIER_COGNITION_ENABLED", "1").lower() not in {"0", "false", "no"}

    def _force_winter(self):
        return os.environ.get("FORCE_COGNITIVE_WINTER", "0").lower() in {"1", "true", "yes"}

    def _parse_iso(self, value):
        if not value:
            return None
        return datetime.fromisoformat(value.replace("Z", "+00:00"))

    def _job_expired(self, job: CognitionJob):
        expires_at = self._parse_iso(job.expires_at)
        if expires_at is None:
            return False
        return expires_at <= datetime.now(timezone.utc)

    def _cache_entry_valid(self, entry):
        expires_at = self._parse_iso(entry.get("expires_at"))
        if expires_at is None:
            return True
        return expires_at > datetime.now(timezone.utc)

    def _expire_cache(self):
        retained = {}
        for key, entry in self.cache.items():
            if self._cache_entry_valid(entry):
                retained[key] = entry
                continue
            self.last_tick_metrics["cache_expired"] += 1
            self._record("cache_expired", cache_key=key)
        self.cache = retained

    def get_ecology_state(self):
        frontier_enabled = self._frontier_enabled()
        pending_count = len(self.pending_jobs)
        force_winter = self._force_winter()
        scarcity_trigger = pending_count >= self.winter_pending_threshold
        should_enter_winter = force_winter or not frontier_enabled or scarcity_trigger

        if should_enter_winter:
            winter_active = True
        elif self._winter_active:
            winter_active = self._thaw_ready_ticks < self.thaw_stability_ticks
        else:
            winter_active = False

        request_budget = self.winter_max_jobs_per_tick if winter_active else self.max_jobs_per_tick
        winter_reason = None
        if force_winter:
            winter_reason = "forced"
        elif not frontier_enabled:
            winter_reason = "frontier_disabled"
        elif scarcity_trigger:
            winter_reason = "queue_pressure"
        elif winter_active:
            winter_reason = "thaw_stabilizing"
        return {
            "frontier_enabled": frontier_enabled,
            "winter_active": winter_active,
            "winter_reason": winter_reason,
            "request_budget": request_budget,
            "pending_threshold": self.winter_pending_threshold,
            "thaw_pending_threshold": self.thaw_pending_threshold,
            "thaw_ready_ticks": self._thaw_ready_ticks,
        }

    def _refresh_ecology_state(self):
        frontier_enabled = self._frontier_enabled()
        pending_count = len(self.pending_jobs)
        stable_conditions = frontier_enabled and pending_count <= self.thaw_pending_threshold and not self._force_winter()
        if stable_conditions:
            self._thaw_ready_ticks += 1
        else:
            self._thaw_ready_ticks = 0

        ecology = self.get_ecology_state()
        if ecology["winter_active"] != self._winter_active:
            self._winter_active = ecology["winter_active"]
            self._record("winter_enter" if self._winter_active else "winter_exit", ecology=ecology)
        return ecology

    def _expire_jobs(self):
        retained = deque()
        while self.pending_jobs:
            job = self.pending_jobs.popleft()
            if self._job_expired(job):
                self.pending_by_agent.pop(job.agent_id, None)
                self.last_tick_metrics["expired"] += 1
                self._record("expired", agent_id=job.agent_id, job_id=job.id)
                continue
            retained.append(job)
        self.pending_jobs = retained

    def _append_local_telemetry(self, event):
        ensure_runtime_dir()
        with open(get_broker_telemetry_path(), "a", encoding="utf-8") as f:
            f.write(json.dumps(event, sort_keys=True, default=str) + "\n")

    def save_state(self):
        ensure_runtime_dir()
        payload = {
            "pending_jobs": [job.to_dict() for job in self.pending_jobs],
            "pending_by_agent": {agent_id: job.to_dict() for agent_id, job in self.pending_by_agent.items()},
            "ready_results": [result.to_dict() for result in self.ready_results],
            "cache": self.cache,
            "telemetry": self.telemetry[-200:],
            "last_tick_metrics": self.last_tick_metrics,
            "winter_active": self._winter_active,
            "thaw_ready_ticks": self._thaw_ready_ticks,
        }
        with open(get_broker_state_path(), "w", encoding="utf-8") as f:
            json.dump(payload, f, sort_keys=True, default=str)

    def load_state(self):
        try:
            with open(get_broker_state_path(), encoding="utf-8") as f:
                payload = json.load(f)
        except Exception:
            return

        self.pending_jobs = deque(CognitionJob(**job) for job in payload.get("pending_jobs", []))
        self.pending_by_agent = {
            agent_id: CognitionJob(**job)
            for agent_id, job in payload.get("pending_by_agent", {}).items()
        }
        self.ready_results = [CognitionResult(**result) for result in payload.get("ready_results", [])]
        raw_cache = payload.get("cache", {})
        self.cache = {}
        for key, entry in raw_cache.items():
            if isinstance(entry, dict) and "result" in entry:
                self.cache[key] = entry
            else:
                self.cache[key] = {
                    "result": entry,
                    "cached_at": utc_now_iso(),
                    "expires_at": None,
                }
        self.telemetry = payload.get("telemetry", [])
        self.last_tick_metrics = payload.get("last_tick_metrics", self._empty_metrics())
        self._winter_active = payload.get("winter_active", False)
        self._thaw_ready_ticks = payload.get("thaw_ready_ticks", 0)

    def submit_job(self, job: CognitionJob) -> CognitionJob:
        existing = self.pending_by_agent.get(job.agent_id)
        if existing and existing.status == "pending" and existing.cache_key == job.cache_key:
            self._record("duplicate_pending", agent_id=job.agent_id, job_id=existing.id)
            return existing

        cache_entry = self.cache.get(job.cache_key)
        if cache_entry and self._cache_entry_valid(cache_entry):
            cached_result = CognitionResult(**cache_entry["result"])
            ready_result = CognitionResult(
                job_id=job.id,
                agent_id=job.agent_id,
                action_name=job.action_name,
                content=cached_result.content,
                provider_name=cached_result.provider_name,
                model_used=cached_result.model_used,
                cached=True,
                metadata=dict(cached_result.metadata),
            )
            job.status = "resolved"
            job.provider_name = ready_result.provider_name
            job.result = ready_result.to_dict()
            job.resolved_at = utc_now_iso()
            self.pending_by_agent[job.agent_id] = job
            self.ready_results.append(ready_result)
            self.last_tick_metrics["cache_hits"] += 1
            self._record("cache_hit", agent_id=job.agent_id, job_id=job.id, cache_key=job.cache_key)
            return job
        if cache_entry and not self._cache_entry_valid(cache_entry):
            self.cache.pop(job.cache_key, None)
            self.last_tick_metrics["cache_expired"] += 1
            self._record("cache_expired", cache_key=job.cache_key)

        self.pending_jobs.append(job)
        self.pending_by_agent[job.agent_id] = job
        self.last_tick_metrics["queued"] += 1
        self._record("queued", agent_id=job.agent_id, job_id=job.id, priority=job.priority)
        try:
            api_post("/api/cognition/jobs", job.to_dict())
        except Exception:
            pass
        self.save_state()
        return job

    def process_tick(self) -> list[CognitionResult]:
        self._expire_cache()
        ecology = self._refresh_ecology_state()
        self._expire_jobs()
        results: list[CognitionResult] = list(self.ready_results)
        for result in results:
            self.pending_by_agent.pop(result.agent_id, None)
        self.ready_results = []
        if not self.pending_jobs:
            return results

        sorted_jobs = sorted(self.pending_jobs, key=lambda job: (-job.priority, job.created_at))
        self.pending_jobs = deque(sorted_jobs)

        processed = 0
        budget = ecology["request_budget"]
        retained = deque()
        while self.pending_jobs:
            job = self.pending_jobs.popleft()
            if processed >= budget:
                job.wait_ticks += 1
                retained.append(job)
                continue

            result = self._run_job(job)
            if result is None:
                if job.status == "abandoned":
                    continue
                job.wait_ticks += 1
                retained.append(job)
                self.last_tick_metrics["deferred"] += 1
                self._record("deferred", agent_id=job.agent_id, job_id=job.id)
                continue

            results.append(result)
            processed += 1
            self.last_tick_metrics["resolved"] += 1
            self.pending_by_agent.pop(job.agent_id, None)

        self.last_tick_metrics["processed_budget"] = processed
        self.pending_jobs = retained
        self.save_state()
        return results

    def _run_job(self, job: CognitionJob) -> CognitionResult | None:
        job.retry_count += 1
        job.last_attempt_at = utc_now_iso()
        self.last_tick_metrics["retry_attempts"] += 1
        if job.retry_count > job.max_attempts:
            job.status = "abandoned"
            self.pending_by_agent.pop(job.agent_id, None)
            self._record("abandoned", agent_id=job.agent_id, job_id=job.id, retries=job.retry_count)
            return None
        for provider in self.providers:
            result = provider.generate(job)
            if result is None:
                continue
            result.metadata.update(job.input_context)
            job.status = "resolved"
            job.provider_name = provider.name
            job.result = result.to_dict()
            job.resolved_at = utc_now_iso()
            self.cache[job.cache_key] = {
                "result": result.to_dict(),
                "cached_at": utc_now_iso(),
                "expires_at": self._parse_iso(job.expires_at).isoformat() if job.expires_at else None,
            }
            self._record("resolved", agent_id=job.agent_id, job_id=job.id, provider=provider.name)
            try:
                api_patch(f"/api/cognition/jobs/{job.id}", job.to_dict())
            except Exception:
                pass
            self.save_state()
            return result

        job.status = "pending"
        self.save_state()
        return None

    def get_pending_job(self, agent_id):
        return self.pending_by_agent.get(agent_id)

    def get_tick_summary(self):
        pending = len(self.pending_jobs)
        cache_size = len(self.cache)
        recent = self.telemetry[-25:]
        return {
            "pending_jobs": pending,
            "cache_entries": cache_size,
            "metrics": dict(self.last_tick_metrics),
            "ecology": self.get_ecology_state(),
            "recent_events": recent,
        }
