#!/usr/bin/env python3
"""Dual-ledger note generation tests."""

import json
import os
import tempfile
import unittest
import uuid


class DualLedgerNoteTests(unittest.TestCase):
    def setUp(self):
        os.environ["AF64_RUNTIME_DIR"] = tempfile.mkdtemp(prefix=f"noosphere-notes-{uuid.uuid4()}-")

    def _write_jsonl(self, path, rows):
        with open(path, "w", encoding="utf-8") as f:
            for row in rows:
                f.write(json.dumps(row) + "\n")

    def test_generate_notes_creates_markdown_files(self):
        from dual_ledger_notes import generate_notes
        from runtime_paths import (
            ensure_runtime_dir,
            get_daily_rollups_path,
            get_notes_dir,
            get_quarterly_rollups_path,
            get_weekly_rollups_path,
            get_yearly_rollups_path,
        )

        ensure_runtime_dir()
        self._write_jsonl(get_daily_rollups_path(), [{
            "date": "2026-03-11",
            "operational_record": {"agent_activity": {"active": 2}, "provider_usage": {}, "top_actors": [], "total_energy_delta": 0},
            "narrative_projection": {"status": "unfilled", "note": "Daily narrative pending."},
        }])
        self._write_jsonl(get_weekly_rollups_path(), [{
            "week": "2026-W11",
            "operational_record": {"agent_activity": {"active": 10}, "provider_usage": {}, "top_actors": [], "total_energy_delta": 0},
            "narrative_projection": {"status": "unfilled", "note": "Weekly narrative pending."},
        }])
        self._write_jsonl(get_quarterly_rollups_path(), [{
            "quarter": "2026-Q1",
            "operational_record": {"agent_activity": {"active": 50}, "provider_usage": {}, "top_actors": [], "total_energy_delta": 0},
            "narrative_projection": {"status": "unfilled", "note": "Quarterly narrative pending."},
        }])
        self._write_jsonl(get_yearly_rollups_path(), [{
            "year": "2026",
            "operational_record": {"agent_activity": {"active": 120}, "provider_usage": {}, "top_actors": [], "total_energy_delta": 0},
            "narrative_projection": {"status": "unfilled", "note": "Yearly narrative pending."},
            "dual_ledger": {"operational_record_ready": True, "narrative_projection_ready": False},
        }])

        generate_notes()

        notes_dir = get_notes_dir()
        self.assertTrue(os.path.exists(os.path.join(notes_dir, "daily", "2026-03-11.md")))
        self.assertTrue(os.path.exists(os.path.join(notes_dir, "weekly", "2026-W11.md")))
        self.assertTrue(os.path.exists(os.path.join(notes_dir, "quarterly", "2026-Q1.md")))
        self.assertTrue(os.path.exists(os.path.join(notes_dir, "yearly", "2026.md")))


if __name__ == "__main__":
    unittest.main()
