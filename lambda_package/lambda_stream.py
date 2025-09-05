# lambda_stream.py
import os
import json
import sys
from datetime import datetime, timezone

# Make our bundled packages importable
HERE = os.path.dirname(__file__)
sys.path.append(os.path.join(HERE, "lambda_package"))

from api.db.dynamo import get_incidents_by_hex, update_zone_severity  # your existing helpers
from services.severity import calculate_score                        # your scoring

def handler(event, context):
    """
    DynamoDB Streams handler.
    Recomputes severity for every zone_id that appears in the stream batch.
    Idempotent: it recalculates from *all* incidents currently present.
    """
    touched = set()

    # Collect zone_ids referenced in the batch
    for rec in event.get("Records", []):
        if rec.get("eventSource") != "aws:dynamodb":
            continue
        ddb = rec.get("dynamodb", {})

        # Prefer "NewImage", fall back to "OldImage" (deletes/updates)
        img = ddb.get("NewImage") or ddb.get("OldImage") or {}
        zid = (img.get("zone_id") or {}).get("S")
        if zid:
            touched.add(zid)

    if not touched:
        return {"zones_recalculated": 0}

    now_iso = datetime.now(timezone.utc).isoformat()
    updated = 0

    for zid in touched:
        incidents = get_incidents_by_hex(zid) or []
        score = calculate_score(incidents) if incidents else 0.0

        # Persist the new score
        update_zone_severity(
            zone_id=zid,
            severity=score,
            updated_at_iso=now_iso,
        )
        updated += 1

    return {"zones_recalculated": updated}
