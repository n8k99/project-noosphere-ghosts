#!/usr/bin/env python3
"""Deterministic rollups from empirical tick reports."""

from collections import Counter
from datetime import datetime
import json

from api_client import api_post
from runtime_paths import (
    ensure_runtime_dir,
    get_daily_rollups_path,
    get_monthly_rollups_path,
    get_quarterly_rollups_path,
    get_tick_reports_path,
    get_weekly_rollups_path,
    get_yearly_rollups_path,
)


def _read_jsonl(path):
    rows = []
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                rows.append(json.loads(line))
    except FileNotFoundError:
        return []
    return rows


def _write_jsonl(path, rows):
    ensure_runtime_dir()
    with open(path, "w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, sort_keys=True, default=str) + "\n")


def load_tick_reports():
    return _read_jsonl(get_tick_reports_path())


def _date_key(timestamp):
    return datetime.fromisoformat(timestamp.replace("Z", "+00:00")).date().isoformat()


def _week_key(date_string):
    dt = datetime.fromisoformat(date_string)
    iso = dt.isocalendar()
    return f"{iso.year}-W{iso.week:02d}"


def _month_key(date_string):
    dt = datetime.fromisoformat(date_string)
    return f"{dt.year}-{dt.month:02d}"


def _quarter_key(date_string):
    dt = datetime.fromisoformat(date_string)
    quarter = ((dt.month - 1) // 3) + 1
    return f"{dt.year}-Q{quarter}"


def _year_key(date_string):
    dt = datetime.fromisoformat(date_string)
    return f"{dt.year}"


def _merge_rollup_records(rows, winter_field):
    counts = Counter()
    providers = Counter()
    top_actors = Counter()
    active_agents = set()
    pending_agents = set()
    winter_periods = 0
    total_energy_delta = 0

    for row in rows:
        record = row["operational_record"]
        counts.update(record.get("agent_activity", {}))
        providers.update(record.get("provider_usage", {}))
        top_actors.update(dict(record.get("top_actors", [])))
        active_agents.update(record.get("active_agents", []))
        pending_agents.update(record.get("pending_agents", []))
        if record.get(winter_field, 0) > 0:
            winter_periods += 1
        total_energy_delta += record.get("total_energy_delta", 0)

    return {
        "agent_activity": dict(counts),
        "provider_usage": dict(providers),
        "winter_periods": winter_periods,
        "active_agents": sorted(active_agents),
        "pending_agents": sorted(pending_agents),
        "top_actors": top_actors.most_common(10),
        "total_energy_delta": total_energy_delta,
    }


def build_daily_rollups(reports):
    grouped = {}
    for report in reports:
        key = _date_key(report["generated_at"])
        grouped.setdefault(key, []).append(report)

    rollups = []
    for day, day_reports in sorted(grouped.items()):
        counts = Counter()
        providers = Counter()
        top_actors = Counter()
        active_agents = set()
        pending_agents = set()
        winter_ticks = 0
        total_energy_delta = 0

        for report in day_reports:
            tick_counts = report.get("counts", {})
            counts["active"] += tick_counts.get("active", 0)
            counts["idle"] += tick_counts.get("idle", 0)
            counts["dormant"] += tick_counts.get("dormant", 0)

            if report.get("ecology", {}).get("winter_active"):
                winter_ticks += 1

            if report.get("top_actor") and report["top_actor"] != "none":
                top_actors[report["top_actor"]] += 1

            for summary in report.get("agent_summaries", []):
                agent_id = summary.get("agent_id")
                if not agent_id:
                    continue
                if summary.get("resolved_action"):
                    active_agents.add(agent_id)

            for req in report.get("cognition", {}).get("requests", []):
                counts["cognition_requests"] += 1
                if req.get("agent_id"):
                    pending_agents.add(req["agent_id"])

            for resolved in report.get("cognition", {}).get("resolutions", []):
                counts["cognition_resolutions"] += 1
                providers[resolved.get("provider", "unknown")] += 1
                if resolved.get("cached"):
                    counts["cache_hits"] += 1

            metrics = report.get("broker", {}).get("metrics", {})
            counts["deferred"] += metrics.get("deferred", 0)
            counts["expired_jobs"] += metrics.get("expired", 0)
            counts["cache_expired"] += metrics.get("cache_expired", 0)

            for entry in report.get("entries", []):
                before = entry.get("energy_before")
                after = entry.get("energy_after")
                if before is not None and after is not None:
                    total_energy_delta += after - before

        rollups.append({
            "date": day,
            "tick_count": len(day_reports),
            "operational_record": {
                "agent_activity": dict(counts),
                "provider_usage": dict(providers),
                "winter_ticks": winter_ticks,
                "active_agents": sorted(active_agents),
                "pending_agents": sorted(pending_agents),
                "top_actors": top_actors.most_common(10),
                "total_energy_delta": total_energy_delta,
            },
            "summary_scaffold": {
                "status": "unfilled",
                "note": "Application-specific synthesis can be layered on top of this empirical record.",
            },
        })
    return rollups


def build_weekly_rollups(daily_rollups):
    grouped = {}
    for rollup in daily_rollups:
        key = _week_key(rollup["date"])
        grouped.setdefault(key, []).append(rollup)

    weekly = []
    for week, rows in sorted(grouped.items()):
        merged = _merge_rollup_records(rows, "winter_ticks")

        weekly.append({
            "week": week,
            "day_count": len(rows),
            "source_dates": [row["date"] for row in rows],
            "operational_record": {
                "agent_activity": merged["agent_activity"],
                "provider_usage": merged["provider_usage"],
                "winter_days": merged["winter_periods"],
                "active_agents": merged["active_agents"],
                "pending_agents": merged["pending_agents"],
                "top_actors": merged["top_actors"],
                "total_energy_delta": merged["total_energy_delta"],
            },
            "summary_scaffold": {
                "status": "unfilled",
                "note": "Application-specific synthesis can be layered on top of this empirical record.",
            },
        })
    return weekly


def build_monthly_rollups(daily_rollups):
    grouped = {}
    for rollup in daily_rollups:
        key = _month_key(rollup["date"])
        grouped.setdefault(key, []).append(rollup)

    monthly = []
    for month, rows in sorted(grouped.items()):
        merged = _merge_rollup_records(rows, "winter_ticks")
        monthly.append({
            "month": month,
            "day_count": len(rows),
            "source_dates": [row["date"] for row in rows],
            "operational_record": {
                "agent_activity": merged["agent_activity"],
                "provider_usage": merged["provider_usage"],
                "winter_days": merged["winter_periods"],
                "active_agents": merged["active_agents"],
                "pending_agents": merged["pending_agents"],
                "top_actors": merged["top_actors"],
                "total_energy_delta": merged["total_energy_delta"],
            },
            "summary_scaffold": {
                "status": "unfilled",
                "note": "Application-specific synthesis can be layered on top of this empirical record.",
            },
        })
    return monthly


def build_quarterly_rollups(monthly_rollups):
    grouped = {}
    for rollup in monthly_rollups:
        key = _quarter_key(f"{rollup['month']}-01")
        grouped.setdefault(key, []).append(rollup)

    quarterly = []
    for quarter, rows in sorted(grouped.items()):
        merged = _merge_rollup_records(rows, "winter_days")
        quarterly.append({
            "quarter": quarter,
            "month_count": len(rows),
            "source_months": [row["month"] for row in rows],
            "operational_record": {
                "agent_activity": merged["agent_activity"],
                "provider_usage": merged["provider_usage"],
                "winter_months": merged["winter_periods"],
                "active_agents": merged["active_agents"],
                "pending_agents": merged["pending_agents"],
                "top_actors": merged["top_actors"],
                "total_energy_delta": merged["total_energy_delta"],
            },
            "summary_scaffold": {
                "status": "unfilled",
                "note": "Application-specific synthesis can be layered on top of this empirical record.",
            },
        })
    return quarterly


def build_yearly_rollups(quarterly_rollups):
    grouped = {}
    for rollup in quarterly_rollups:
        key = _year_key(f"{rollup['quarter'].split('-Q')[0]}-01-01")
        grouped.setdefault(key, []).append(rollup)

    yearly = []
    for year, rows in sorted(grouped.items()):
        merged = _merge_rollup_records(rows, "winter_months")
        yearly.append({
            "year": year,
            "quarter_count": len(rows),
            "source_quarters": [row["quarter"] for row in rows],
            "operational_record": {
                "agent_activity": merged["agent_activity"],
                "provider_usage": merged["provider_usage"],
                "winter_quarters": merged["winter_periods"],
                "active_agents": merged["active_agents"],
                "pending_agents": merged["pending_agents"],
                "top_actors": merged["top_actors"],
                "total_energy_delta": merged["total_energy_delta"],
            },
            "summary_scaffold": {
                "status": "unfilled",
                "note": "Application-specific synthesis can be layered on top of this empirical record.",
            },
        })
    return yearly


def persist_rollups(daily_rollups, weekly_rollups, monthly_rollups, quarterly_rollups, yearly_rollups):
    _write_jsonl(get_daily_rollups_path(), daily_rollups)
    _write_jsonl(get_weekly_rollups_path(), weekly_rollups)
    _write_jsonl(get_monthly_rollups_path(), monthly_rollups)
    _write_jsonl(get_quarterly_rollups_path(), quarterly_rollups)
    _write_jsonl(get_yearly_rollups_path(), yearly_rollups)

    for rollup in daily_rollups:
        try:
            api_post("/api/rollups/daily", rollup)
        except Exception:
            break

    for rollup in weekly_rollups:
        try:
            api_post("/api/rollups/weekly", rollup)
        except Exception:
            break

    for rollup in monthly_rollups:
        try:
            api_post("/api/rollups/monthly", rollup)
        except Exception:
            break

    for rollup in quarterly_rollups:
        try:
            api_post("/api/rollups/quarterly", rollup)
        except Exception:
            break

    for rollup in yearly_rollups:
        try:
            api_post("/api/rollups/yearly", rollup)
        except Exception:
            break


def rebuild_rollups():
    reports = load_tick_reports()
    daily = build_daily_rollups(reports)
    weekly = build_weekly_rollups(daily)
    monthly = build_monthly_rollups(daily)
    quarterly = build_quarterly_rollups(monthly)
    yearly = build_yearly_rollups(quarterly)
    persist_rollups(daily, weekly, monthly, quarterly, yearly)
    return {
        "daily": daily,
        "weekly": weekly,
        "monthly": monthly,
        "quarterly": quarterly,
        "yearly": yearly,
    }


if __name__ == "__main__":
    result = rebuild_rollups()
    print(json.dumps({
        "daily_rollups": len(result["daily"]),
        "weekly_rollups": len(result["weekly"]),
        "monthly_rollups": len(result["monthly"]),
        "quarterly_rollups": len(result["quarterly"]),
        "yearly_rollups": len(result["yearly"]),
    }, indent=2))
