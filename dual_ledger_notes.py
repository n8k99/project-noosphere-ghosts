#!/usr/bin/env python3
"""Generate dual-ledger markdown note scaffolds from empirical rollups."""

import json
import os

from runtime_paths import (
    ensure_runtime_dir,
    get_daily_rollups_path,
    get_notes_dir,
    get_quarterly_rollups_path,
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


def _render_operational_record(record):
    lines = ["## Operational Record", ""]
    lines.append("### Agent Activity")
    for key, value in sorted(record.get("agent_activity", {}).items()):
        lines.append(f"- {key}: {value}")
    lines.append("")
    lines.append("### Provider Usage")
    for key, value in sorted(record.get("provider_usage", {}).items()):
        lines.append(f"- {key}: {value}")
    lines.append("")
    lines.append(f"### Total Energy Delta\n- {record.get('total_energy_delta', 0)}")
    lines.append("")
    lines.append("### Top Actors")
    for actor, count in record.get("top_actors", []):
        lines.append(f"- {actor}: {count}")
    lines.append("")
    return "\n".join(lines)


def _render_narrative_projection(projection):
    return "\n".join([
        "## Narrative Projection",
        "",
        f"Status: {projection.get('status', 'unfilled')}",
        "",
        projection.get("note", "Narrative projection not yet authored."),
        "",
    ])


def _write_note(subdir, name, body):
    ensure_runtime_dir()
    notes_dir = os.path.join(get_notes_dir(), subdir)
    os.makedirs(notes_dir, exist_ok=True)
    path = os.path.join(notes_dir, f"{name}.md")
    with open(path, "w", encoding="utf-8") as f:
        f.write(body)


def _note_body(title, source_key, source_value, rollup):
    header = [
        f"# {title}",
        "",
        f"- Source: {source_key} `{source_value}`",
        "",
    ]
    return "\n".join(header + [
        _render_operational_record(rollup.get("operational_record", {})),
        _render_narrative_projection(rollup.get("narrative_projection", {})),
    ])


def generate_notes():
    daily = _read_jsonl(get_daily_rollups_path())
    weekly = _read_jsonl(get_weekly_rollups_path())
    quarterly = _read_jsonl(get_quarterly_rollups_path())
    yearly = _read_jsonl(get_yearly_rollups_path())

    for row in daily:
        _write_note("daily", row["date"], _note_body("Daily Dual-Ledger Note", "date", row["date"], row))
    for row in weekly:
        _write_note("weekly", row["week"], _note_body("Weekly Dual-Ledger Note", "week", row["week"], row))
    for row in quarterly:
        _write_note("quarterly", row["quarter"], _note_body("Quarterly Dual-Ledger Note", "quarter", row["quarter"], row))
    for row in yearly:
        body = _note_body("Yearly Dual-Ledger Note", "year", row["year"], row)
        dual = row.get("dual_ledger", {})
        body += "\n".join([
            "## Dual Ledger Status",
            "",
            f"- operational_record_ready: {dual.get('operational_record_ready', False)}",
            f"- narrative_projection_ready: {dual.get('narrative_projection_ready', False)}",
            "",
        ])
        _write_note("yearly", row["year"], body)


if __name__ == "__main__":
    generate_notes()
