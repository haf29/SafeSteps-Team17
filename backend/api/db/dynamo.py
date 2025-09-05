import os
import boto3
from boto3.dynamodb.conditions import Key, Attr
from datetime import datetime
from decimal import Decimal
from typing import List
import uuid 
from typing import Optional, Dict, Any
from services.severity import find_nearest_safe_hex
import json 


REGION = os.getenv("AWS_REGION", "eu-north-1")
ZONES_TABLE = os.getenv("ZONES_TABLE", "Zones")
INCIDENTS_TABLE = os.getenv("INCIDENTS_TABLE", "Incidents")
ZONES_CITY_INDEX = os.getenv("ZONES_CITY_INDEX", "city-index")

dynamodb = boto3.resource("dynamodb", region_name=REGION)
zones_table = dynamodb.Table(ZONES_TABLE)
incidents_table = dynamodb.Table(INCIDENTS_TABLE)
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
    now_iso = datetime.utcnow().isoformat()
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
    add_severity_record(zone_id, severity, updated_by="zones_table_update")

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
    now_iso = datetime.utcnow().isoformat()
    zones_table.update_item(
        Key={"zone_id": zone_id},
        UpdateExpression="SET boundary = :b, boundary_updated_at = :u",
        ExpressionAttributeValues={
            ":b": json.dumps(boundary_coords),
            ":u": now_iso,
        },
    )