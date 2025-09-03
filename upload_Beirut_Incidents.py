import boto3
import json
from decimal import Decimal
from pathlib import Path

# DynamoDB table name
TABLE_NAME = "Incidents"

# Load data
json_file = Path("beirut_incidents.json")
with open(json_file, "r", encoding="utf-8") as f:
    incidents = json.load(f)

# Convert float → Decimal (DynamoDB requirement)
def replace_floats(obj):
    if isinstance(obj, float):
        return Decimal(str(obj))
    if isinstance(obj, dict):
        return {k: replace_floats(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [replace_floats(v) for v in obj]
    return obj

incidents = replace_floats(incidents)

# Connect to DynamoDB
dynamodb = boto3.resource("dynamodb", region_name="eu-north-1")  # change region if needed
table = dynamodb.Table(TABLE_NAME)

# Batch write
with table.batch_writer() as batch:
    for item in incidents:
        batch.put_item(Item=item)

print(f"✅ Uploaded {len(incidents)} incidents to DynamoDB table '{TABLE_NAME}'")
