#!/usr/bin/env python3
"""Broker tests that do not require live frontier tokens."""

import os
import tempfile
import unittest
import uuid
from datetime import datetime, timedelta, timezone

os.environ["FRONTIER_COGNITION_ENABLED"] = "0"


def make_job(agent_id="eliana", priority=10.0, cache_key="k1", kind="respond_message"):
    from cognition_types import CognitionJob
    return CognitionJob(
        agent_id=agent_id,
        tick_number=1,
        kind=kind,
        priority=priority,
        requested_model_tier="base",
        input_context={
            "system_prompt": "Test prompt",
            "messages": [{"role": "user", "content": "Hello"}],
            "source_message": {"id": 1, "from": "nathan", "message": "Hello"},
        },
        cache_key=cache_key,
        action_name=kind,
        cost_estimate=5,
    )


class CognitionBrokerTests(unittest.TestCase):
    def setUp(self):
        os.environ["AF64_RUNTIME_DIR"] = tempfile.mkdtemp(prefix=f"noosphere-tests-{uuid.uuid4()}-")
        os.environ["FRONTIER_COGNITION_ENABLED"] = "0"
        os.environ["COGNITIVE_WINTER_MAX_JOBS_PER_TICK"] = "1"
        os.environ["COGNITIVE_THAW_STABILITY_TICKS"] = "2"

    def test_processes_highest_priority_first(self):
        from cognition_engine import CognitionBroker
        broker = CognitionBroker(max_jobs_per_tick=1)
        low = make_job(agent_id="a", priority=5.0, cache_key="low")
        high = make_job(agent_id="b", priority=25.0, cache_key="high")
        broker.submit_job(low)
        broker.submit_job(high)

        results = broker.process_tick()

        self.assertEqual(len(results), 1)
        self.assertEqual(results[0].agent_id, "b")
        self.assertEqual(len(broker.pending_jobs), 1)

    def test_cache_hit_returns_ready_result(self):
        from cognition_engine import CognitionBroker
        broker = CognitionBroker(max_jobs_per_tick=2)
        job1 = make_job(agent_id="a", priority=10.0, cache_key="same")
        broker.submit_job(job1)
        first = broker.process_tick()
        self.assertEqual(len(first), 1)

        job2 = make_job(agent_id="b", priority=11.0, cache_key="same")
        broker.submit_job(job2)
        second = broker.process_tick()

        self.assertEqual(len(second), 1)
        self.assertTrue(second[0].cached)

    def test_state_round_trip_restores_pending_jobs(self):
        from cognition_engine import CognitionBroker
        broker = CognitionBroker(max_jobs_per_tick=0)
        broker.submit_job(make_job(agent_id="restore", priority=8.0, cache_key="restore"))

        restored = CognitionBroker(max_jobs_per_tick=0)

        self.assertIsNotNone(restored.get_pending_job("restore"))

    def test_expired_job_is_dropped(self):
        from cognition_engine import CognitionBroker
        broker = CognitionBroker(max_jobs_per_tick=1)
        job = make_job(agent_id="expired", priority=9.0, cache_key="expired")
        job.expires_at = (datetime.now(timezone.utc) - timedelta(seconds=5)).isoformat()
        broker.submit_job(job)

        results = broker.process_tick()

        self.assertEqual(results, [])
        self.assertIsNone(broker.get_pending_job("expired"))

    def test_winter_budget_applies_when_frontier_disabled(self):
        from cognition_engine import CognitionBroker
        os.environ["COGNITIVE_WINTER_MAX_JOBS_PER_TICK"] = "1"
        broker = CognitionBroker(max_jobs_per_tick=3)
        broker.submit_job(make_job(agent_id="a", priority=5.0, cache_key="a"))
        broker.submit_job(make_job(agent_id="b", priority=8.0, cache_key="b"))

        summary = broker.get_ecology_state()
        results = broker.process_tick()

        self.assertTrue(summary["winter_active"])
        self.assertEqual(summary["request_budget"], 1)
        self.assertEqual(len(results), 1)

    def test_cache_entry_expires(self):
        from cognition_engine import CognitionBroker
        broker = CognitionBroker(max_jobs_per_tick=1)
        job = make_job(agent_id="cache", priority=10.0, cache_key="cache")
        broker.submit_job(job)
        broker.process_tick()
        broker.cache["cache"]["expires_at"] = (datetime.now(timezone.utc) - timedelta(seconds=1)).isoformat()

        broker.start_tick()
        broker.process_tick()

        self.assertNotIn("cache", broker.cache)

    def test_thaw_requires_stability(self):
        from cognition_engine import CognitionBroker
        os.environ["COGNITIVE_THAW_STABILITY_TICKS"] = "2"
        broker = CognitionBroker(max_jobs_per_tick=3)

        self.assertTrue(broker.get_ecology_state()["winter_active"])
        broker.process_tick()
        self.assertTrue(broker.get_ecology_state()["winter_active"])

        os.environ["FRONTIER_COGNITION_ENABLED"] = "1"
        broker.process_tick()
        self.assertTrue(broker.get_ecology_state()["winter_active"])
        broker.process_tick()
        self.assertFalse(broker.get_ecology_state()["winter_active"])


if __name__ == "__main__":
    unittest.main()
