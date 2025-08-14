# backend/lambda_function.py
import json
from datetime import datetime
from botocore.exceptions import ClientError

from api.services.severity import calculate_score
from api.db.dynamo import (
    get_zones_by_city,            # returns List[str]  (existing)
    update_zone_severity,
    get_incidents_by_hex,
    # OPTIONAL: if you add it later, uncomment and use inside _score_city_paged
    # get_zones_by_city_paged,    # returns (List[str], last_evaluated_key)
)

def _now_iso() -> str:
    return datetime.utcnow().isoformat()

def _score_zone_ids(zone_ids: list[str]) -> dict:
    """Compute & persist severity for specific zone IDs."""
    updated = 0
    now_iso = _now_iso()
    for zid in zone_ids:
        incidents = get_incidents_by_hex(zid)
        score = calculate_score(incidents) if incidents else 0.0
        update_zone_severity(zid, score, now_iso)
        updated += 1
    return {"zones_scored": updated}

def _score_city_paged(city: str, limit: int | None = None, start_index: int = 0) -> dict:
    """
    Score a city in chunks. This version slices a full list returned by get_zones_by_city().
    For *large* cities, prefer implementing get_zones_by_city_paged in your dynamo layer
    so you can use real DynamoDB pagination (ExclusiveStartKey).
    """
    all_zone_ids = get_zones_by_city(city) or []
    if not all_zone_ids:
        return {"city": city, "zones_scored": 0, "note": "no zones found for city"}

    # Slice the list to create a "page"
    if limit is None or limit <= 0:
        page = all_zone_ids[start_index:]
        next_index = None
    else:
        end = min(start_index + limit, len(all_zone_ids))
        page = all_zone_ids[start_index:end]
        next_index = end if end < len(all_zone_ids) else None

    page_result = _score_zone_ids(page)
    return {
        "city": city,
        "zones_scored": page_result["zones_scored"],
        "next_start_index": next_index,  # call again with this to continue
        "total_in_city": len(all_zone_ids),
    }

def lambda_handler(event, context):
    """
    Actions:

    1) score_city (paged):
       {
         "action": "score_city",
         "city": "Beirut",
         "limit": 1000,             # optional, default: all remaining
         "start_index": 0           # optional, default: 0; pass back "next_start_index" to continue
       }

       Response includes "next_start_index" if there is more work.

    2) score_zone_ids (targeted):
       {
         "action": "score_zone_ids",
         "zone_ids": ["892db1...", "..."]
       }

    3) generate_zones / refresh_city:
       Kept for backward compatibility, but they do nothing now because zones are pre-seeded.
    """
    try:
        action = (event or {}).get("action")

        if action == "score_zone_ids":
            zone_ids = event.get("zone_ids") or []
            if not isinstance(zone_ids, list) or not zone_ids:
                return {"statusCode": 400, "body": "Provide non-empty 'zone_ids' array."}
            out = _score_zone_ids(zone_ids)
            return {"statusCode": 200, "body": json.dumps({"message": "zones scored", **out})}

        elif action == "score_city":
            city = event.get("city")
            if not city:
                return {"statusCode": 400, "body": "Missing 'city'."}
            limit = event.get("limit")  # int | None
            start_index = int(event.get("start_index", 0))
            out = _score_city_paged(city, limit, start_index)
            return {"statusCode": 200, "body": json.dumps({"message": "paged score complete", **out})}

        # Back-compat: no-ops for generation/refresh now that DB is seeded
        elif action in ("generate_zones", "refresh_city"):
            return {
                "statusCode": 200,
                "body": json.dumps({
                    "message": f"'{action}' is disabled; zones are pre-seeded. Use 'score_city' or 'score_zone_ids'."
                })
            }

        else:
            return {
                "statusCode": 400,
                "body": "Missing or invalid 'action'. Use 'score_city' or 'score_zone_ids'."
            }

    except ClientError as err:
        return {"statusCode": 500, "body": str(err)}
    except Exception as exc:
        return {"statusCode": 500, "body": str(exc)}
 