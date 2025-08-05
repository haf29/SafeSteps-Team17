import os
import boto3
from boto3.dynamodb.conditions import Key, Attr
from datetime import datetime
from decimal import Decimal
from typing import List

REGION = os.getenv("AWS_REGION", "us-east-1")
ZONES_TABLE = os.getenv("ZONES_TABLE", "zones")
INCIDENTS_TABLE = os.getenv("INCIDENTS_TABLE", "incidents")
ZONES_CITY_INDEX = os.getenv("ZONES_CITY_INDEX", "city-index")

dynamodb = boto3.resource("dynamodb", region_name=REGION)
zones_table = dynamodb.Table(ZONES_TABLE)
incidents_table = dynamodb.Table(INCIDENTS_TABLE)

def get_zones_by_city(city_name: str) -> List[str]:
    """
    Return all zone_ids for a city.
    Prefers GSI query on city; falls back to table scan if GSI not present.
    """
    try:
        resp = zones_table.query(
            IndexName=ZONES_CITY_INDEX,
            KeyConditionExpression=Key("city").eq(city_name),
            ProjectionExpression="zone_id"
        )
        items = resp.get("Items", [])
    except Exception:
        # Fallback (more expensive): scan filter by city
        resp = zones_table.scan(
            FilterExpression=Attr("city").eq(city_name),
            ProjectionExpression="zone_id"
        )
        items = resp.get("Items", [])
    return [it["zone_id"] for it in items]
def get_incidents_by_hex(zone_id: str) -> list[dict]:
    """
    Query the Incidents table for all incidents in a given hex.
    returns a list of incident array of dictionaries
    """
    resp = incidents_table.query(
        KeyConditionExpression=Key("zone_id").eq(zone_id),
        ProjectionExpression="incident_type, timestamp"
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

