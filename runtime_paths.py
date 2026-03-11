#!/usr/bin/env python3
"""Shared runtime paths for local durability."""

import os


def get_runtime_dir():
    return os.environ.get("AF64_RUNTIME_DIR", "/tmp/noosphere_ghosts")


def get_broker_state_path():
    return os.path.join(get_runtime_dir(), "cognition_broker_state.json")


def get_broker_telemetry_path():
    return os.path.join(get_runtime_dir(), "cognition_telemetry.jsonl")


def get_tick_reports_path():
    return os.path.join(get_runtime_dir(), "tick_reports.jsonl")


def get_daily_rollups_path():
    return os.path.join(get_runtime_dir(), "daily_rollups.jsonl")


def get_weekly_rollups_path():
    return os.path.join(get_runtime_dir(), "weekly_rollups.jsonl")


def get_monthly_rollups_path():
    return os.path.join(get_runtime_dir(), "monthly_rollups.jsonl")


def get_quarterly_rollups_path():
    return os.path.join(get_runtime_dir(), "quarterly_rollups.jsonl")


def get_yearly_rollups_path():
    return os.path.join(get_runtime_dir(), "yearly_rollups.jsonl")


def get_notes_dir():
    return os.path.join(get_runtime_dir(), "notes")


def ensure_runtime_dir():
    os.makedirs(get_runtime_dir(), exist_ok=True)
