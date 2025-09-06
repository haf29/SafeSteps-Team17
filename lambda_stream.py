# lambda_stream.py
from datetime import datetime, timezone

# Reuse your project code so severity math & Dynamo access stay in one place
from api.services.severity import calculate_score
from api.db.dynamo import get_incidents_by_hex, update_zone_severity

def handler(event, context):
    # Collect affected zone_ids from stream batch
    touched = set()
    for rec in event.get("Records", []):
        if rec.get("eventSource") != "aws:dynamodb":
            continue

        # INSERT/MODIFY => use NewImage; REMOVE => use OldImage
        ddb = rec.get("dynamodb", {}) or {}
        image = ddb.get("NewImage") or ddb.get("OldImage") or {}
        zid = (image.get("zone_id") or {}).get("S")
        if zid:
            touched.add(zid)

    # Recompute each zone from *all* current incidents (idempotent)
    now_iso = datetime.now(timezone.utc).isoformat()
    updated = 0
    for zid in touched:
        incidents = get_incidents_by_hex(zid) or []  # query by zone_id
        score = calculate_score(incidents) if incidents else 0.0
        update_zone_severity(zid, score, now_iso)   # persists to Zones
        updated += 1

    return {"zones_recalculated": updated}
