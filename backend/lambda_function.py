# backend/lambda_function.py
import json
from datetime import datetime, timezone
from typing import List, Dict, Optional, Any

from botocore.exceptions import ClientError

# --- your services/db ---
from api.services.severity import (
    calculate_score,
    find_nearest_safe_hex,
)
from api.db.dynamo import (
    get_zones_by_city,          # -> List[str]
    get_incidents_by_hex,       # -> List[dict]
    update_zone_severity,       # -> None
    get_zone_by_id,             # -> Optional[dict]
    # (optional) if you add this later, the code below will use it automatically:
    # get_zones_by_city_paged,  # -> (List[str], last_evaluated_key)
)

# Try to detect if a paged variant exists in your db layer.
try:
    from api.db.dynamo import get_zones_by_city_paged  # type: ignore
    _HAS_PAGED = True
except Exception:
    _HAS_PAGED = False


# ------------------------
# helpers
# ------------------------
def _now_iso() -> str:
    # Use timezone-aware UTC to be consistent with your severity utils
    return datetime.now(timezone.utc).isoformat()


def _score_zone_ids(zone_ids: List[str], *, dry_run: bool = False) -> Dict[str, Any]:
    """
    Compute & (optionally) persist severity for specific zone IDs.
    Returns {"zones_scored": int, "updated": int}
    """
    updated = 0
    computed = 0
    now_iso = _now_iso()

    for zid in zone_ids:
        # incidents may be empty; that's fine — score will be 0.0
        incidents = get_incidents_by_hex(zid)
        score = calculate_score(incidents) if incidents else 0.0
        computed += 1

        if not dry_run:
            update_zone_severity(zid, score, now_iso)
            updated += 1

    return {"zones_scored": computed, "updated": updated}


def _score_city_slice(city: str, all_zone_ids: List[str], start_index: int, limit: Optional[int], *, dry_run: bool) -> Dict[str, Any]:
    """Slice a Python list (fallback paging)."""
    if limit is None or limit <= 0:
        page = all_zone_ids[start_index:]
        next_index = None
    else:
        end = min(start_index + limit, len(all_zone_ids))
        page = all_zone_ids[start_index:end]
        next_index = end if end < len(all_zone_ids) else None

    page_result = _score_zone_ids(page, dry_run=dry_run)

    return {
        "city": city,
        "zones_scored": page_result["zones_scored"],
        "updated": page_result["updated"],
        "next_start_index": next_index,  # pass this back to continue
        "total_in_city": len(all_zone_ids),
    }


def _score_city_paged(city: str, limit: Optional[int], start_index: int, *, dry_run: bool) -> Dict[str, Any]:
    """
    Score a city with either:
      - real DynamoDB paging (if you later implement get_zones_by_city_paged),
      - or Python slicing fallback (current behavior).
    """
    if _HAS_PAGED:
        # If you later add get_zones_by_city_paged(city, limit, last_evaluated_key),
        # you can wire it here (keeping start_index as a simple cursor for now).
        # Placeholder behavior: fall back to list for now.
        pass

    # Fallback path (current): just take the full list then slice.
    all_zone_ids = get_zones_by_city(city) or []
    if not all_zone_ids:
        return {"city": city, "zones_scored": 0, "updated": 0, "note": "no zones found for city"}

    return _score_city_slice(city, all_zone_ids, start_index, limit, dry_run=dry_run)


def _nearest_safe_hex(start_hex: str, *, safe_threshold: float = 3.0, max_rings: int = 3) -> Optional[str]:
    """
    Use your severity helper to walk neighbors via H3 and find a hex whose
    stored Zones.severity <= threshold.
    """
    def _get_severity_by_hex(z: str) -> Optional[float]:
        item = get_zone_by_id(z) or {}
        # Zones.severity was stored as Decimal via boto3; JSON/float safe:
        sev = item.get("severity")
        try:
            return float(sev) if sev is not None else None
        except Exception:
            return None

    return find_nearest_safe_hex(
        start_hex,
        safe_threshold=safe_threshold,
        max_rings=max_rings,
        get_severity_by_hex=_get_severity_by_hex,
    )


# ------------------------
# Lambda entrypoint
# ------------------------
def lambda_handler(event, context):
    """
    Supported actions:

    1) score_city (paged; safe for big data)
       {
         "action": "score_city",
         "city": "Beirut",
         "limit": 1000,           # optional page size; default = all remaining
         "start_index": 0,        # optional cursor; default = 0
         "dry_run": false         # optional: compute only (no writes)
       }

    2) score_zone_ids (targeted list)
       {
         "action": "score_zone_ids",
         "zone_ids": ["892db1...", "..."],
         "dry_run": false
       }

    3) nearest_safe_hex (path finding using stored severity)
       {
         "action": "nearest_safe_hex",
         "start_hex": "892db1.....",
         "safe_threshold": 3.0,   # optional
         "max_rings": 3           # optional
       }
    """
    try:
        action = (event or {}).get("action")

        if action == "score_zone_ids":
            zone_ids = event.get("zone_ids") or []
            if not isinstance(zone_ids, list) or not zone_ids:
                return {"statusCode": 400, "body": "Provide non-empty 'zone_ids' array."}

            dry_run = bool(event.get("dry_run", False))
            out = _score_zone_ids(zone_ids, dry_run=dry_run)
            return {"statusCode": 200, "body": json.dumps({"message": "zones scored", **out})}

        elif action == "score_city":
            city = event.get("city")
            if not city:
                return {"statusCode": 400, "body": "Missing 'city'."}

            limit = event.get("limit")  # int | None
            start_index = int(event.get("start_index", 0))
            dry_run = bool(event.get("dry_run", False))

            out = _score_city_paged(city, limit, start_index, dry_run=dry_run)
            return {"statusCode": 200, "body": json.dumps({"message": "paged score complete", **out})}

        elif action == "nearest_safe_hex":
            start_hex = event.get("start_hex")
            if not start_hex:
                return {"statusCode": 400, "body": "Missing 'start_hex'."}

            safe_threshold = float(event.get("safe_threshold", 3.0))
            max_rings = int(event.get("max_rings", 3))

            result = _nearest_safe_hex(start_hex, safe_threshold=safe_threshold, max_rings=max_rings)
            return {
                "statusCode": 200,
                "body": json.dumps({
                    "message": "nearest safe hex computed",
                    "start_hex": start_hex,
                    "nearest_safe_hex": result
                })
            }

        else:
            return {
                "statusCode": 400,
                "body": "Missing or invalid 'action'. Use 'score_city', 'score_zone_ids', or 'nearest_safe_hex'."
            }

    except ClientError as err:
        # surfaces AWS errors (DynamoDB, etc.)
        return {"statusCode": 500, "body": str(err)}
    except Exception as exc:
        # last-resort catcher so Lambda doesn’t throw 502 without details
        return {"statusCode": 500, "body": str(exc)}
