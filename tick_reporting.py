#!/usr/bin/env python3
"""Local-first tick reporting helpers."""

import json

from api_client import api_post
from empirical_rollups import rebuild_rollups
from runtime_paths import ensure_runtime_dir, get_tick_reports_path


def write_tick_report(report):
    sink = "api"
    try:
        api_post("/api/tick-reports", report)
    except Exception:
        sink = "local"
        ensure_runtime_dir()
        with open(get_tick_reports_path(), "a", encoding="utf-8") as f:
            f.write(json.dumps(report, sort_keys=True, default=str) + "\n")

    try:
        rebuild_rollups()
    except Exception:
        pass
    return sink
