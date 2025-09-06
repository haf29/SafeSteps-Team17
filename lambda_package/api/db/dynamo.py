import os
import boto3
from boto3.dynamodb.conditions import Key, Attr
from datetime import datetime, timezone
from decimal import Decimal
from typing import List
import uuid 
from typing import Optional, Dict, Any
import sys, os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))) #I used absolute paths cuz nothign else works
from services.severity import find_nearest_safe_hex
import json 


REGION = os.getenv("AWS_REGION", "eu-north-1")
ZONES_TABLE = os.getenv("ZONES_TABLE", "Zones")
INCIDENTS_TABLE = os.getenv("INCIDENTS_TABLE", "Incidents")
ZONES_CITY_INDEX = os.getenv("ZONES_CITY_INDEX", "city-index")

dynamodb = boto3.resource("dynamodb", region_name=REGION)
zones_table = dynamodb.Table(ZONES_TABLE)
incidents_table = dynamodb.Table(INCIDENTS_TABLE)
# --- City lookup (used by routing) ------------------------------------------
import json, math, os
from functools import lru_cache
from typing import Dict, Any, List, Tuple, Optional

# tolerant distance helper
def _haversine_km(lat1, lon1, lat2, lon2):
    R = 6371.0088
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lon2 - lon1)
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlmb/2)**2
    return 2*R*math.asin(math.sqrt(a))

@lru_cache(maxsize=1)
def _load_cities() -> List[Dict[str, Any]]:
    """
    Loads cities.json from one of:
      - $CITY_FILE
      - /opt/safesteps/data/cities.json
      - ../data/cities.json (relative to this file)
    Returns a list of city dicts. Each city must have a name and a bbox.
    Supported bbox formats:
      - {'min_lat':..,'min_lng':..,'max_lat':..,'max_lng':..}
      - {'bbox': [min_lng, min_lat, max_lng, max_lat]}  # common GeoJSON-ish
      - {'bbox': [min_lat, min_lng, max_lat, max_lng]}  # tolerant
    """
    candidates = []
    env_path = os.getenv("CITY_FILE")
    if env_path:
        candidates.append(env_path)
    candidates += [
        "/opt/safesteps/data/cities.json",
        os.path.join(os.path.dirname(__file__), "..", "data", "cities.json"),
    ]

    for p in candidates:
        try:
            with open(p, "r", encoding="utf-8") as f:
                data = json.load(f)
                # data may be a dict with "cities" or a list directly
                cities = data.get("cities") if isinstance(data, dict) else data
                if not isinstance(cities, list):
                    continue
                # normalize bbox
                norm = []
                for c in cities:
                    name = c.get("name") or c.get("city") or c.get("id")
                    bbox = c.get("bbox") or c.get("bounds") or c.get("boundary") or c.get("bbox_coords")
                    if isinstance(bbox, dict):
                        min_lat = bbox.get("min_lat") or bbox.get("south") or bbox.get("minLat")
                        min_lng = bbox.get("min_lng") or bbox.get("west")  or bbox.get("minLng")
                        max_lat = bbox.get("max_lat") or bbox.get("north") or bbox.get("maxLat")
                        max_lng = bbox.get("max_lng") or bbox.get("east")  or bbox.get("maxLng")
                    elif isinstance(bbox, (list, tuple)) and len(bbox) == 4:
                        # try to guess ordering
                        a,b,c2,d = bbox
                        # if longitudes look bigger in absolute value, assume [min_lng,min_lat,max_lng,max_lat]
                        if abs(a) > abs(b):  # likely [lng, lat, lng, lat]
                            min_lng, min_lat, max_lng, max_lat = a,b,c2,d
                        else:                # [lat, lng, lat, lng]
                            min_lat, min_lng, max_lat, max_lng = a,b,c2,d
                    else:
                        # try separate keys (legacy)
                        min_lat = c.get("min_lat"); min_lng = c.get("min_lng")
                        max_lat = c.get("max_lat"); max_lng = c.get("max_lng")

                    if None in (name, min_lat, min_lng, max_lat, max_lng):
                        continue
                    norm.append({
                        "name": name,
                        "min_lat": float(min_lat),
                        "min_lng": float(min_lng),
                        "max_lat": float(max_lat),
                        "max_lng": float(max_lng),
                        "center": (
                            (float(min_lat)+float(max_lat))/2.0,
                            (float(min_lng)+float(max_lng))/2.0,
                        ),
                    })
                if norm:
                    # optional: sort for deterministic behavior
                    norm.sort(key=lambda x: x["name"])
                    # log once where we loaded from
                    try:
                        print(f"Resolved CITY_FILE path: {os.path.abspath(p)}")
                    except Exception:
                        pass
                    return norm
        except FileNotFoundError:
            continue
        except Exception as e:
            # don't crash on malformed candidate; try next
            try:
                print(f"Warning: failed to load cities from {p}: {e}")
            except Exception:
                pass
            continue
    # no file found; return empty list so callers can handle gracefully
    return []

def find_city(lat: float, lng: float) -> Optional[str]:
    """
    Returns the city name that contains (lat,lng). If none contain it,
    returns the nearest city's name (by bbox center). If we have no cities,
    returns None.
    """
    cities = _load_cities()
    if not cities:
        return None

    # 1) inside a bbox?
    for c in cities:
        if (c["min_lat"] <= lat <= c["max_lat"]) and (c["min_lng"] <= lng <= c["max_lng"]):
            return c["name"]

    # 2) fallback to nearest center
    best = min(cities, key=lambda c: _haversine_km(lat, lng, c["center"][0], c["center"][1]))
    return best["name"]
# ---------------------------------------------------------------------------

def get_city_items_all(city: str, page_limit: int = 1000) -> List[Dict[str, Any]]:
    """
    FAST PATH: Query the city GSI and return all items with
    {zone_id, severity, boundary, boundary_res}. This does a few paged queries,
    not 1-per-hex calls.
    """
    attrs = {"#z": "zone_id", "#b": "boundary", "#r": "boundary_res"}
    proj = "#z, severity, #b, #r"

    items: List[Dict[str, Any]] = []
    lek: Optional[Dict[str, Any]] = None

    while True:
        kwargs = {
            "IndexName": ZONES_CITY_INDEX,
            "KeyConditionExpression": Key("city").eq(city),
            "ProjectionExpression": proj,
            "ExpressionAttributeNames": attrs,
            "Limit": page_limit,
        }
        if lek:
            kwargs["ExclusiveStartKey"] = lek

        resp = zones_table.query(**kwargs)
        items.extend(resp.get("Items", []))
        lek = resp.get("LastEvaluatedKey")
        if not lek:
            break

    return items
def get_boundary_for_hex(zone_id: str, res: int) -> Optional[List[List[float]]]:
    """
    Read a stored boundary for this hex at the given resolution, if present.
    Expects attributes 'boundary' (list[list[lat,lng]]) and 'boundary_res'.
    """
    resp = zones_table.get_item(
        Key={"zone_id": zone_id},
        ProjectionExpression="#b,#r",
        ExpressionAttributeNames={"#b": "boundary", "#r": "boundary_res"},
    )
    item = resp.get("Item") or {}
    if not item:
        return None
    try:
        if int(item.get("boundary_res", res)) == int(res) and item.get("boundary"):
            return item["boundary"]
    except Exception:
        pass
    return None
def put_boundary_for_hex(zone_id: str, boundary: List[List[float]], res: int) -> None:
    zones_table.update_item(
        Key={"zone_id": zone_id},
        UpdateExpression="SET boundary = :b, boundary_res = :r",
        ExpressionAttributeValues={":b": boundary, ":r": int(res)},
    )
def get_zones_by_city(city_name: str) -> List[str]:
    """
    Return all zone_ids for a city. Prefer GSI query; fall back to scan if needed.
    """
    try:
        resp = zones_table.query(
            IndexName=ZONES_CITY_INDEX,
            KeyConditionExpression=Key("city").eq(city_name),
            ProjectionExpression="zone_id"
        )
        items = resp.get("Items", [])
    except Exception:
        resp = zones_table.scan(
            FilterExpression=Attr("city").eq(city_name),
            ProjectionExpression="zone_id"
        )
        items = resp.get("Items", [])
    return [it["zone_id"] for it in items]


def get_incidents_by_hex(zone_id: str) -> list[dict]:
    resp = incidents_table.query(
        KeyConditionExpression=Key("zone_id").eq(zone_id),
        ProjectionExpression="#type, #ts",
        ExpressionAttributeNames={
            "#type": "incident_type",
            "#ts": "timestamp",  # reserved word, alias it
        },
    )
    return resp.get("Items", [])

def put_zones(zone_ids: List[str], city: str) -> int:
    now_iso = datetime.now(timezone.utc).isoformat()
    with zones_table.batch_writer(overwrite_by_pkeys=["zone_id"]) as batch:
        for zone_id in zone_ids:
            batch.put_item(
                Item={
                    "zone_id": zone_id,
                    "city": city,
                    "created_at": now_iso,
                    "severity": 0,  # default score
                }
            )
    return len(zone_ids)

def add_incident(zone_id, incident_type, timestamp, city, reported_by):
    """
    Writes an incident with PK: zone_id, SK: timestamp (ISO8601).
    `timestamp` can be a datetime or an ISO string.
    """
    # normalize timestamp
    if isinstance(timestamp, datetime):
        ts_str = timestamp.isoformat()
    else:
        ts_str = str(timestamp)

    try:
        incidents_table.put_item(
            Item={
                "zone_id": zone_id,
                "timestamp": ts_str,              # SK (reserved word is ok as an attribute name)
                "incident_type": incident_type,   # <-- FIXED to match readers
                "city": city,
                "reported_by": reported_by,
                "incident_id": str(uuid.uuid4()),
            }
        )
        return True
    except Exception as e:
        print("Error adding incident:", e)
        return False

def add_incident_and_update(zone_id: str, incident_type: str, timestamp: str, city: str, reported_by: str):
    ok = dynamo.add_incident(zone_id, incident_type, timestamp, city, reported_by)
    if not ok:
        return False

    # Recalculate severity for this hex from *all* its incidents
    incs = dynamo.get_incidents_by_hex(zone_id)
    score = calculate_score(incs)

    dynamo.update_zone_severity(
        zone_id,
        severity=score,
        updated_at_iso=datetime.now(timezone.utc).isoformat()
    )
    return True

def update_zone_severity(zone_id: str, severity: float, updated_at_iso: str) -> None:
    """Persist the latest severity score and updated_at timestamp."""
    zones_table.update_item(
        Key={"zone_id": zone_id},
        UpdateExpression="SET severity = :s, severity_updated_at = :u",
        ExpressionAttributeValues={
            ":s": Decimal(str(round(severity, 3))),
            ":u": updated_at_iso
        }
    )

def get_zone_by_id(zone_id: str) -> Optional[Dict[str, Any]]:
    """Return the full Zone item or None."""
    resp = zones_table.get_item(Key={"zone_id": zone_id})
    return resp.get("Item")

def get_nearest_safe_hex(start_hex: str) -> str | None:
    return find_nearest_safe_hex(
        start_hex,
        get_severity_by_hex=lambda z: (get_zone_by_id(z) or {}).get("severity"),
        safe_threshold=3.0,
        max_rings=3
    )

def get_zones_by_city_with_severity(
    city_name: str, *, limit: int = 1000, last_evaluated_key: dict | None = None
) -> tuple[list[dict], dict | None]:
    """
    (Keep for completeness, but the new helper below will autopaginate for you.)
    """
    kwargs = {
        "IndexName": ZONES_CITY_INDEX,
        "KeyConditionExpression": Key("city").eq(city_name),
        "ProjectionExpression": "zone_id, severity, boundary",  # <-- include boundary in fast path
        "Limit": limit,
    }
    if last_evaluated_key:
        kwargs["ExclusiveStartKey"] = last_evaluated_key

    resp = zones_table.query(**kwargs)
    return resp.get("Items", []), resp.get("LastEvaluatedKey")
def get_all_zones_by_city_full(city_name: str) -> list[dict]:
    """
    Pull ALL zones for a city via GSI with (zone_id, severity, boundary),
    transparently auto-paginating until done.
    """
    items: list[dict] = []
    lek = None
    while True:
        page, lek = get_zones_by_city_with_severity(city_name, limit=1000, last_evaluated_key=lek)
        items.extend(page or [])
        if not lek:
            break
    return items
def update_zone_boundary(zone_id: str, boundary_coords: list[list[float]]) -> None:
    """
    Cache boundary on the Zone item so we don't recompute H3 boundary next time.
    We store it as a JSON string to avoid float/Decimal headaches.
    """
    now_iso = datetime.now(timezone.utc).isoformat()
    zones_table.update_item(
        Key={"zone_id": zone_id},
        UpdateExpression="SET boundary = :b, boundary_updated_at = :u",
        ExpressionAttributeValues={
            ":b": json.dumps(boundary_coords),
            ":u": now_iso,
        },
    )
