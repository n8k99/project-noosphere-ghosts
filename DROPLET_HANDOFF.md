# Droplet Handoff

## Purpose

This file is for the agent running on the droplet to finish the cognition-broker migration once frontier tokens return on **Saturday, March 14, 2026 at 22:00 America/New_York**.

## Current State

The runtime now brokers cognition in-process:

* [`tick_engine.py`](/home/n8k99/project-noosphere-ghosts/tick_engine.py) submits cognition jobs and resolves them through the broker.
* [`cognition_engine.py`](/home/n8k99/project-noosphere-ghosts/cognition_engine.py) manages queueing, cache, local telemetry, and restart recovery.
* Broker jobs now track retry count, expiry, last attempt, and wait ticks.
* Cognitive winter and thaw stability are now explicit runtime states.
* [`provider_adapters.py`](/home/n8k99/project-noosphere-ghosts/provider_adapters.py) supports explicit frontier disable via `FRONTIER_COGNITION_ENABLED=0`.
* [`tick_reporting.py`](/home/n8k99/project-noosphere-ghosts/tick_reporting.py) writes tick reports to the API if available, otherwise to local JSONL.
* [`graph_data.py`](/home/n8k99/project-noosphere-ghosts/graph_data.py) can surface local broker snapshot metadata for visualization.
* [`empirical_rollups.py`](/home/n8k99/project-noosphere-ghosts/empirical_rollups.py) deterministically rebuilds daily and weekly rollups from tick reports.
* [`dual_ledger_notes.py`](/home/n8k99/project-noosphere-ghosts/dual_ledger_notes.py) generates markdown scaffolds for daily/weekly/quarterly/yearly dual-ledger notes.

## Safe Runtime Mode Before Frontier Returns

Run with:

```bash
export FRONTIER_COGNITION_ENABLED=0
export AF64_RUNTIME_DIR=/tmp/noosphere_ghosts
python3 tick_engine.py
```

This will:

* use stub cognition instead of frontier inference
* preserve broker state locally
* write local tick reports if the backend does not yet expose `/api/tick-reports`
* allow queue/defer/cache/recovery behavior to be validated now
* enter explicit cognitive winter automatically when frontier cognition is disabled

## Files Created by Local Fallback

Under `AF64_RUNTIME_DIR`:

* `cognition_broker_state.json`
* `cognition_telemetry.jsonl`
* `tick_reports.jsonl`
* `daily_rollups.jsonl`
* `weekly_rollups.jsonl`
* `monthly_rollups.jsonl`
* `quarterly_rollups.jsonl`
* `yearly_rollups.jsonl`
* `notes/`

## Work To Finish When Frontier Returns

1. Implement backend endpoints:
   * `POST /api/cognition/jobs`
   * `GET /api/cognition/jobs`
   * `PATCH /api/cognition/jobs/:id`
   * `POST /api/cognition/telemetry`
   * `POST /api/tick-reports` or richer `/api/tick-log/batch`
2. Turn on frontier cognition:
   * `export FRONTIER_COGNITION_ENABLED=1`
   * ensure `VENICE_API_KEY` is valid again
3. Validate one controlled tick with live tokens and inspect:
   * job persistence
   * cache-hit behavior
   * provider latency/failures
   * message/task side effects
4. Decide whether cached frontier outputs need TTL semantics.
5. Decide whether to persist queue priority and retry counts explicitly in the backend schema.
6. Decide whether private backend rollup endpoints should be `/api/rollups/daily` and `/api/rollups/weekly` or folded into an existing notes pipeline.

## Known Gaps

* Backend cognition endpoints are not in this repo.
* Tick reports are local-fallback capable, but graph/dashboard ingestion is still early.
* Request/grant linkage exists in tick reports, but downstream consumers are not yet standardized.
* Cognitive winter exists operationally, but its thresholds and downstream ecological effects still need tuning.
* Daily/weekly/monthly/quarterly/yearly empirical rollups and note scaffolds exist locally, but downstream publication into the private notes system is not wired here.

## Recommended Next Code Items

* Add provider-specific cache policies and optional cache invalidation.
* Add richer graph telemetry for queue depth and cognition grants.
* Add systemd service/unit and deploy script if the droplet does not already have one.
