import os
import boto3
from boto3.dynamodb.conditions import Key, Attr
from datetime import datetime
from decimal import Decimal
from typing import List
import uuid 
 
REGION = os.getenv("AWS_REGION", "eu-north-1")
ZONES_TABLE = os.getenv("ZONES_TABLE", "Zones")
INCIDENTS_TABLE = os.getenv("INCIDENTS_TABLE", "Incidents")
ZONES_CITY_INDEX = os.getenv("ZONES_CITY_INDEX", "city-index")

dynamodb = boto3.resource("dynamodb", region_name=REGION)
zones_table = dynamodb.Table(ZONES_TABLE)
incidents_table = dynamodb.Table(INCIDENTS_TABLE)
# import json

# Load the H3 hexagons file once
# with open("docs/lebanon_districts_with_h3.geojson", "r") as f:
#     hex_data = json.load(f)

# Organize into a dict: {district_name: [list of hex_ids]}
# city_hex_map = {}
# for feature in hex_data["features"]:
#     district = feature["properties"]["parent_district"]
#     hex_id = feature["properties"]["zone_id"]
#     city_hex_map.setdefault(district, []).append(hex_id)

# def get_zones_by_city(city_name: str):
#     """
#     Return list of H3 hex IDs for a given city/district.
#     """
#     if city_name not in city_hex_map:
#         raise ValueError(f"City '{city_name}' not found in H3 data.")
#     return city_hex_map[city_name]

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
    resp = incidents_table.query(
        KeyConditionExpression=Key("zone_id").eq(zone_id),
        ProjectionExpression="#type, #ts",
        ExpressionAttributeNames={
            "#type": "incident_type",
            "#ts": "timestamp",     # alias the reserved word
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
    try:
        incidents_table.put_item(
            Item={
                "zone_id": zone_id,
                "timestamp": timestamp.isoformat(),
                "type": incident_type,
                "city": city,  #  Store the city
                "reported_by": reported_by,
                "incident_id": str(uuid.uuid4())
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

