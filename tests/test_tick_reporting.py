#!/usr/bin/env python3
"""Integration-style tests for tick reporting fallback and rollup rebuild."""

import json
import os
import tempfile
import unittest
import uuid
from unittest import mock


class TickReportingTests(unittest.TestCase):
    def setUp(self):
        os.environ["AF64_RUNTIME_DIR"] = tempfile.mkdtemp(prefix=f"noosphere-reporting-{uuid.uuid4()}-")

    def test_write_tick_report_falls_back_locally_and_rebuilds_rollups(self):
        from runtime_paths import get_daily_rollups_path, get_tick_reports_path
        from tick_reporting import write_tick_report

        report = {
            "tick_number": 1,
            "generated_at": "2026-03-11T10:00:00+00:00",
            "counts": {"active": 1, "idle": 2, "dormant": 0},
            "top_actor": "eliana(work_task)",
            "ecology": {"winter_active": False},
            "broker": {"metrics": {"deferred": 0, "expired": 0, "cache_expired": 0}},
            "cognition": {
                "requests": [{"agent_id": "eliana", "job_id": "j1", "kind": "work_task", "priority": 50}],
                "resolutions": [{"agent_id": "eliana", "job_id": "j1", "action_name": "work_task", "provider": "stub", "cached": False}],
            },
            "agent_summaries": [{"agent_id": "eliana", "resolved_action": "work_task"}],
            "entries": [{"energy_before": 50, "energy_after": 42}],
        }

        with mock.patch("tick_reporting.api_post", side_effect=RuntimeError("offline")):
            sink = write_tick_report(report)

        self.assertEqual(sink, "local")
        self.assertTrue(os.path.exists(get_tick_reports_path()))
        self.assertTrue(os.path.exists(get_daily_rollups_path()))

        with open(get_tick_reports_path(), encoding="utf-8") as f:
            stored = [json.loads(line) for line in f if line.strip()]
        self.assertEqual(len(stored), 1)
        self.assertEqual(stored[0]["tick_number"], 1)

        with open(get_daily_rollups_path(), encoding="utf-8") as f:
            daily = [json.loads(line) for line in f if line.strip()]
        self.assertEqual(len(daily), 1)
        self.assertEqual(daily[0]["operational_record"]["agent_activity"]["cognition_requests"], 1)


if __name__ == "__main__":
    unittest.main()
