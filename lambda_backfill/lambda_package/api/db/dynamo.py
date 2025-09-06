# dynamo.py  (MINIMAL: no H3, just the two calls backfill needs)

import os
import boto3
from boto3.dynamodb.conditions import Key
from datetime import datetime, timezone
from decimal import Decimal
from typing import Dict, Any, List, Optional

REGION = os.getenv("AWS_REGION", "eu-north-1")
INCIDENTS_TABLE = os.getenv("INCIDENTS_TABLE", "Incidents")
ZONES_TABLE = os.getenv("ZONES_TABLE", "Zones")

_dynamodb = boto3.resource("dynamodb", region_name=REGION)
_incidents = _dynamodb.Table(INCIDENTS_TABLE)
_zones = _dynamodb.Table(ZONES_TABLE)

def get_incidents_by_hex(zone_id: str) -> List[Dict[str, Any]]:
    resp = _incidents.query(
        KeyConditionExpression=Key("zone_id").eq(zone_id),
        ProjectionExpression="#type, #ts",
        ExpressionAttributeNames={"#type": "incident_type", "#ts": "timestamp"},
    )
    return resp.get("Items", [])

def update_zone_severity(zone_id: str, severity: float, updated_at_iso: Optional[str] = None) -> None:
    if not updated_at_iso:
        updated_at_iso = datetime.now(timezone.utc).isoformat()
    _zones.update_item(
        Key={"zone_id": zone_id},
        UpdateExpression="SET severity = :s, severity_updated_at = :u",
        ExpressionAttributeValues={
            ":s": Decimal(str(round(severity, 3))),
            ":u": updated_at_iso,
        },
    )
