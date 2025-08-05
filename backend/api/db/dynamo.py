import os
import boto3
from boto3.dynamodb.conditions import Key

REGION = os.getenv("AWS_REGION", "us-east-1")
ZONES_TABLE = os.getenv("ZONES_TABLE", "zones")
INCIDENTS_TABLE = os.getenv("INCIDENTS_TABLE", "incidents")

dynamodb = boto3.resource("dynamodb", region_name=REGION)
zones_table = dynamodb.Table(ZONES_TABLE)
incidents_table = dynamodb.Table(INCIDENTS_TABLE)

def get_zones_by_city(city_name: str) -> list[str]:
    
    """
    Query the Zones table for all hex IDs belonging to a city.
    returns a list of hex IDs for the city
    """
    resp = zones_table.query(
        KeyConditionExpression=Key("city").eq(city_name),
        ProjectionExpression="zone_id"
        )
    return [item["zone_id"] for item in resp.get("Items", [])]

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


