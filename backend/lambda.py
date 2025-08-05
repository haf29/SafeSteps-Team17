# backend/lambda.py
import json
import os
from datetime import datetime
from botocore.exceptions import ClientError

from api.services.h3_utils import generate_zone_ids
from api.services.severity import calculate_score
from api.db.dynamo import (
    put_zones,
    get_zones_by_city,
    get_incidents_by_hex,
    update_zone_severity,
)


def _now_iso() -> str:
    return datetime.utcnow().isoformat()

def _score_city_once(city: str) -> dict:
    """Compute & persist severity for all zones in a city."""
    zone_ids = get_zones_by_city(city)
    if not zone_ids:
        return {"city": city, "zones_scored": 0, "note": "no zones found for city"}

    updated = 0
    now_iso = _now_iso()
    for zid in zone_ids:
        incidents = get_incidents_by_hex(zid)
        score = calculate_score(incidents) if incidents else 0.0
        update_zone_severity(zid, score, now_iso)
        updated += 1

    return {"city": city, "zones_scored": updated}

def _generate_city_zones(city: str, polygon: dict, resolution: int) -> dict:
    """Generate H3 zones for a polygon and save them under the city."""
    zone_ids = generate_zone_ids(polygon, resolution)
    written = put_zones(zone_ids, city)
    return {"city": city, "zones_written": written, "resolution": resolution}

def lambda_handler(event, context):
    """
    Event contract:

    1) Generate only:
    {
      "action": "generate_zones",
      "city": "Beirut",
      "resolution": 9,
      "polygon": { ... GeoJSON Polygon with [lng,lat] ... }
    }

    2) Score only:
    {
      "action": "score_city",
      "city": "Beirut"
    }

    3) Full refresh (generate then score):
    {
      "action": "refresh_city",
      "city": "Beirut",
      "resolution": 9,
      "polygon": { ... }
    }
    """
    try:
        action = event.get("action")

        if action == "generate_zones":
            city = event["city"]
            poly = event["polygon"]
            res = int(event.get("resolution", 9))
            out = _generate_city_zones(city, poly, res)
            return {"statusCode": 200, "body": json.dumps({"message": "zones generated", **out})}

        elif action == "score_city":
            city = event["city"]
            out = _score_city_once(city)
            return {"statusCode": 200, "body": json.dumps({"message": "zones scored", **out})}

        elif action == "refresh_city":
            city = event["city"]
            poly = event["polygon"]
            res = int(event.get("resolution", 9))
            gen = _generate_city_zones(city, poly, res)
            scr = _score_city_once(city)
            return {
                "statusCode": 200,
                "body": json.dumps({
                    "message": "refresh complete",
                    "generate": gen,
                    "score": scr
                })
            }

        else:
            # Backward compatibility: if no action but polygon provided, assume generate
            if "polygon" in event:
                city = event.get("city", "Unknown")
                res = int(event.get("resolution", 9))
                out = _generate_city_zones(city, event["polygon"], res)
                return {"statusCode": 200, "body": json.dumps({"message": "zones generated (default path)", **out})}

            return {"statusCode": 400, "body": "Missing or invalid 'action' parameter."}

    except KeyError as e:
        return {"statusCode": 400, "body": f"Missing field in request: {str(e)}"}
    except ClientError as err:
        return {"statusCode": 500, "body": str(err)}
    except Exception as exc:
        return {"statusCode": 500, "body": str(exc)}
