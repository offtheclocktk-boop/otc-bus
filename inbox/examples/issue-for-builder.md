<!-- Example issue body. Title: [for-builder] Add retry with backoff to the export job   Label: for-builder -->

## Need
Add retry with exponential backoff to the nightly CSV export job in `reports-service`, then report back here.

## Context
- The export fails a few times a week when the storage API returns HTTP 503. A single retry after a short delay would have saved every failure in the last month (see the log summary in the linked run).
- Keep the change small: no new dependencies. Use the existing `retry` helper in `reports_service/util.py`.
- Sam approved the change; it does not need a release, only a merge to `main`.

## Paths
- Job: `reports-service/reports_service/jobs/export_csv.py`
- Helper: `reports-service/reports_service/util.py`
- Tests: `reports-service/tests/jobs/`

## Done when
- Up to 3 retries with backoff (1 s, 2 s, 4 s) on 5xx responses only.
- A unit test covers a 503 followed by success, and a permanent 500.
- One comment here with the PR link and test result, then label `done` and close.

## Owner decision needed
None.
