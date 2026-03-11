#!/usr/bin/env python3
"""Empirical rollup tests from tick reports."""

import unittest

from empirical_rollups import (
    build_daily_rollups,
    build_monthly_rollups,
    build_quarterly_rollups,
    build_weekly_rollups,
    build_yearly_rollups,
)


def sample_report(ts, winter=False, provider="stub", cached=False, top_actor="eliana(work_task)"):
    return {
        "generated_at": ts,
        "counts": {"active": 2, "idle": 5, "dormant": 1},
        "top_actor": top_actor,
        "ecology": {"winter_active": winter},
        "broker": {"metrics": {"deferred": 1, "expired": 0, "cache_expired": 0}},
        "cognition": {
            "requests": [{"agent_id": "eliana", "job_id": "j1", "kind": "work_task", "priority": 90}],
            "resolutions": [{
                "agent_id": "eliana",
                "job_id": "j1",
                "action_name": "work_task",
                "provider": provider,
                "cached": cached,
                "model_used": "deterministic-fallback",
            }],
        },
        "agent_summaries": [{
            "agent_id": "eliana",
            "resolved_action": "work_task",
        }],
        "entries": [
            {"energy_before": 50, "energy_after": 42},
            {"energy_before": 20, "energy_after": 23},
        ],
    }


class EmpiricalRollupTests(unittest.TestCase):
    def test_build_daily_rollups_groups_by_date(self):
        reports = [
            sample_report("2026-03-11T10:00:00+00:00"),
            sample_report("2026-03-11T12:00:00+00:00", winter=True, cached=True),
            sample_report("2026-03-12T09:00:00+00:00"),
        ]

        daily = build_daily_rollups(reports)

        self.assertEqual(len(daily), 2)
        self.assertEqual(daily[0]["date"], "2026-03-11")
        self.assertEqual(daily[0]["operational_record"]["agent_activity"]["cognition_requests"], 2)
        self.assertEqual(daily[0]["operational_record"]["winter_ticks"], 1)
        self.assertEqual(daily[0]["operational_record"]["agent_activity"]["cache_hits"], 1)

    def test_build_weekly_rollups_aggregates_daily_rollups(self):
        daily = [
            {
                "date": "2026-03-11",
                "operational_record": {
                    "agent_activity": {"active": 4, "cognition_requests": 2},
                    "provider_usage": {"stub": 2},
                    "winter_ticks": 1,
                    "active_agents": ["eliana"],
                    "pending_agents": ["eliana"],
                    "top_actors": [("eliana(work_task)", 2)],
                    "total_energy_delta": -5,
                },
                "summary_scaffold": {"status": "unfilled"},
            },
            {
                "date": "2026-03-12",
                "operational_record": {
                    "agent_activity": {"active": 3, "cognition_requests": 1},
                    "provider_usage": {"venice": 1},
                    "winter_ticks": 0,
                    "active_agents": ["nova"],
                    "pending_agents": [],
                    "top_actors": [("nova(respond_message)", 1)],
                    "total_energy_delta": 4,
                },
                "summary_scaffold": {"status": "unfilled"},
            },
        ]

        weekly = build_weekly_rollups(daily)

        self.assertEqual(len(weekly), 1)
        record = weekly[0]["operational_record"]
        self.assertEqual(record["agent_activity"]["active"], 7)
        self.assertEqual(record["agent_activity"]["cognition_requests"], 3)
        self.assertEqual(record["winter_days"], 1)
        self.assertIn("eliana", record["active_agents"])
        self.assertIn("nova", record["active_agents"])

    def test_build_higher_order_rollups(self):
        daily = [
            {
                "date": "2026-03-11",
                "operational_record": {
                    "agent_activity": {"active": 4, "cognition_requests": 2},
                    "provider_usage": {"stub": 2},
                    "winter_ticks": 1,
                    "active_agents": ["eliana"],
                    "pending_agents": ["eliana"],
                    "top_actors": [("eliana(work_task)", 2)],
                    "total_energy_delta": -5,
                },
                "summary_scaffold": {"status": "unfilled"},
            },
            {
                "date": "2026-03-25",
                "operational_record": {
                    "agent_activity": {"active": 5, "cognition_requests": 3},
                    "provider_usage": {"venice": 3},
                    "winter_ticks": 0,
                    "active_agents": ["nova"],
                    "pending_agents": [],
                    "top_actors": [("nova(respond_message)", 2)],
                    "total_energy_delta": 7,
                },
                "summary_scaffold": {"status": "unfilled"},
            },
            {
                "date": "2026-04-04",
                "operational_record": {
                    "agent_activity": {"active": 6, "cognition_requests": 4},
                    "provider_usage": {"venice": 4},
                    "winter_ticks": 0,
                    "active_agents": ["vincent"],
                    "pending_agents": [],
                    "top_actors": [("vincent(work_task)", 3)],
                    "total_energy_delta": 9,
                },
                "summary_scaffold": {"status": "unfilled"},
            },
        ]

        monthly = build_monthly_rollups(daily)
        quarterly = build_quarterly_rollups(monthly)
        yearly = build_yearly_rollups(quarterly)

        self.assertEqual(len(monthly), 2)
        self.assertEqual(len(quarterly), 2)
        self.assertEqual(len(yearly), 1)
        self.assertEqual(quarterly[0]["operational_record"]["agent_activity"]["active"], 9)
        self.assertEqual(quarterly[1]["operational_record"]["agent_activity"]["active"], 6)
        self.assertEqual(yearly[0]["summary_scaffold"]["status"], "unfilled")


if __name__ == "__main__":
    unittest.main()
