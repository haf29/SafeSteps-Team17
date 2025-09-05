# backfill_all.py  (parallel backfill, no h3)
import os, sys, time, math, random
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor, as_completed

import boto3
from botocore.exceptions import ClientError

# Make our bundled code importable
HERE = os.path.dirname(os.path.abspath(__file__))
API_DIR = os.path.join(HERE, "backend", "api")   # repo layout: ./backend/api/...
sys.path.append(API_DIR)

from lambda_package.api.db.dynamo import get_incidents_by_hex, update_zone_severity
from lambda_package.api.services.severity import calculate_score


# ---------- Tunables via env (all optional) ----------
REGION               = os.getenv("AWS_REGION", "eu-north-1")
INCIDENTS_TABLE      = os.getenv("INCIDENTS_TABLE", "Incidents")
TOTAL_SEGMENTS       = int(os.getenv("TOTAL_SEGMENTS", "8"))          # parallel scan workers
SCAN_LIMIT           = int(os.getenv("SCAN_LIMIT", "1000"))           # items per Scan page
COMPUTE_CONCURRENCY  = int(os.getenv("COMPUTE_CONCURRENCY", "16"))    # parallel compute/update
MAX_RETRIES          = int(os.getenv("MAX_RETRIES", "5"))             # throttling/backoff
# -----------------------------------------------------

dynamodb = boto3.resource("dynamodb", region_name=REGION)
incidents_table = dynamodb.Table(INCIDENTS_TABLE)

# -------- Helpers: retry with jitter for DDB throttling --------
def _sleep_backoff(attempt: int):
    # capped exponential backoff + jitter
    base = min(1.0 * (2 ** attempt), 8.0)
    time.sleep(base * (0.5 + random.random() * 0.5))

def _safe_query_incidents(zid: str):
    for attempt in range(MAX_RETRIES):
        try:
            return get_incidents_by_hex(zid) or []
        except ClientError as e:
            code = e.response.get("Error", {}).get("Code")
            if code in ("ProvisionedThroughputExceededException", "ThrottlingException"):
                _sleep_backoff(attempt)
                continue
            raise
    # last try
    return get_incidents_by_hex(zid) or []

def _safe_update_zone(zid: str, score: float, now_iso: str):
    for attempt in range(MAX_RETRIES):
        try:
            update_zone_severity(zid, score, now_iso)
            return
        except ClientError as e:
            code = e.response.get("Error", {}).get("Code")
            if code in ("ProvisionedThroughputExceededException", "ThrottlingException", "TransactionInProgressException"):
                _sleep_backoff(attempt)
                continue
            raise
    update_zone_severity(zid, score, now_iso)

# -------- Parallel Scan to collect all zone_ids --------
def _scan_segment(segment: int, total_segments: int) -> set[str]:
    """Scan one segment and return a set of zone_ids from that slice."""
    zone_ids: set[str] = set()
    last_evaluated_key = None

    while True:
        kwargs = {
            "ProjectionExpression": "zone_id",
            "Limit": SCAN_LIMIT,
            "Segment": segment,
            "TotalSegments": total_segments,
        }
        if last_evaluated_key:
            kwargs["ExclusiveStartKey"] = last_evaluated_key

        resp = incidents_table.scan(**kwargs)
        for item in resp.get("Items", []):
            zid = item.get("zone_id")
            if zid:
                zone_ids.add(zid)

        last_evaluated_key = resp.get("LastEvaluatedKey")
        if not last_evaluated_key:
            break

    return zone_ids

def _scan_all_zone_ids_parallel(total_segments: int) -> list[str]:
    """Parallel segmented scan -> unique list of zone_ids."""
    all_ids: set[str] = set()
    with ThreadPoolExecutor(max_workers=total_segments) as ex:
        futures = [ex.submit(_scan_segment, i, total_segments) for i in range(total_segments)]
        for fut in as_completed(futures):
            all_ids |= fut.result()
    return list(all_ids)

# -------- Per-zone compute/update (parallel) --------
def _compute_and_update(zid: str, now_iso: str) -> tuple[str, float]:
    incs  = _safe_query_incidents(zid)
    score = calculate_score(incs) if incs else 0.0
    _safe_update_zone(zid, score, now_iso)
    return (zid, score)

# ---------------- Lambda entrypoint ----------------
def handler(event, context):
    """
    Backfill severities for all zones that have incidents.
    - Parallel segmented Scan to collect unique zone_ids
    - Parallel fetch -> score -> update for each zone_id
    Idempotent: re-running recomputes from current data.
    """
    # 1) collect all impacted zones quickly
    zones = _scan_all_zone_ids_parallel(max(1, TOTAL_SEGMENTS))

    now_iso = datetime.now(timezone.utc).isoformat()
    updated = 0
    count = 0
    # 2) compute & update in parallel (with throttling-safe retries)
    with ThreadPoolExecutor(max_workers=max(1, COMPUTE_CONCURRENCY)) as ex:
        futures = [ex.submit(_compute_and_update, zid, now_iso) for zid in zones]
        for fut in as_completed(futures):
            fut.result()         # re-raise on any exception
            count += 1
            if count % 200 == 0:
                print(f"Updated {count}/{len(zones)} zones…")
            # If you want, log/debug the results here:
            # zid, score = fut.result()
            updated += 1

    return {
        "zones_seen": len(zones),
        "zones_recalculated": updated,
        "segments": TOTAL_SEGMENTS,
        "compute_concurrency": COMPUTE_CONCURRENCY,
    }
if __name__ == "__main__":
    result = handler({}, {})
    print(result)
