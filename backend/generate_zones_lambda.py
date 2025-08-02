import json
import os 
from datetime import datetime
from typing import List
import boto3 
from botocore.exceptions import ClientError
from api.services.h3_utils import generate_zone_ids 

REGION = os.getenv("AWS_REGION")
ZONES_TABLE = os.getenv("ZONES_TABLE")

dynamodb = boto3.resource("dynamodb", region_name=os.getenv("AWS_REGION"))
zones_table = dynamodb.Table(ZONES_TABLE)

def put_zones(zone_ids: List[str])-> int:
    now_iso = datetime.utcnow().isoformat()
    with zones_table.batch_writer(overwrite_by_pkeys=["zone_id"]) as batch:
        for zone_id in zone_ids:
            batch.put_item(
                Item={
                    "zone_id": zone_id,
                    "created_at": now_iso,
                    "severity": 0,  # default score
                }
            )
    return len(zone_ids)
def lambda_handler(event, context):
    try:
        poly = event["polygon"]
        res = int(event.get("resolution", 9))

        zone_ids = generate_zone_ids(poly, res)
        written = put_zones(zone_ids)

        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "message": "Zones generated successfully",
                    "resolution": res,
                    "zones_written": written,
                }
            ),
        }
    except KeyError:
        return {"statusCode": 400, "body": "Missing 'polygon' in request"}
    except ClientError as err:
        return {"statusCode": 500, "body": str(err)}
    except Exception as exc:
        return {"statusCode": 500, "body": str(exc)}