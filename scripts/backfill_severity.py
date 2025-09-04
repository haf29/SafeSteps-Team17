# scripts/backfill_severity.py
from datetime import datetime, timezone
from collections import defaultdict

import boto3
from backend.api.services.severity import calculate_score
from backend.api.services import dynamo

REGION = dynamo.REGION
INCIDENTS_TABLE = dynamo.INCIDENTS_TABLE

dynamodb = boto3.resource("dynamodb", region_name=REGION)
incidents_table = dynamo.dynamodb.Table(INCIDENTS_TABLE)

def scan_incidents():
    items = []
    lek = None
    while True:
        kwargs = {}
        if lek:
            kwargs["ExclusiveStartKey"] = lek
        resp = incidents_table.scan(**kwargs)
        items.extend(resp.get("Items", []))
        lek = resp.get("LastEvaluatedKey")
        if not lek:
            break
    return items

def main():
    all_incidents = scan_incidents()
    by_zone = defaultdict(list)
    for it in all_incidents:
        z = it["zone_id"]
        by_zone[z].append(it)

    now = datetime.now(timezone.utc).isoformat()
    updated = 0
    for zone_id, incs in by_zone.items():
        score = calculate_score(incs)
        dynamo.update_zone_severity(zone_id, score, now)
        updated += 1

    print(f"Updated severities for {updated} zones.")

if __name__ == "__main__":
    main()
