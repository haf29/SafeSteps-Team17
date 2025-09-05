from decimal import Decimal
from datetime import datetime
import boto3
import os
from typing import List, Dict, Any, Optional

REGION = os.getenv("AWS_REGION", "eu-north-1")
SEVERITY_HISTORY_TABLE = os.getenv("SEVERITY_HISTORY_TABLE", "SeverityHistory")

dynamodb = boto3.resource("dynamodb", region_name=REGION)
severity_history_table = dynamodb.Table(SEVERITY_HISTORY_TABLE)


def add_severity_record(zone_id: str, severity: float, updated_by: Optional[str] = None) -> bool:
    """Add a single severity record for a zone."""
    ts_str = datetime.utcnow().isoformat()
    try:
        severity_history_table.put_item(
            Item={
                "zone_id": zone_id,
                "timestamp": ts_str,
                "severity": Decimal(str(severity)),
                "updated_by": updated_by or "system",
            }
        )
        return True
    except Exception as e:
        print("Error adding severity record:", e)
        return False


def get_severity_history(zone_id: str, limit: int = 100) -> List[Dict[str, Any]]:
    """Return latest severity history for a zone, sorted by timestamp descending."""
    resp = severity_history_table.query(
        KeyConditionExpression=boto3.dynamodb.conditions.Key("zone_id").eq(zone_id),
        Limit=limit,
        ScanIndexForward=False,  # descending
    )
    return resp.get("Items", [])
