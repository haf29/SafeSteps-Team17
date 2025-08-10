# scripts/seed_zones_from_cities.py
from pathlib import Path
import sys
REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(REPO_ROOT))

import json
import os
from datetime import datetime
import boto3

from backend.api.db import dynamo  # works now

AWS_REGION = os.getenv("AWS_REGION", "eu-north-1")
CITY_FILE = "C:/Users/AliG2/OneDrive/Desktop/Amazon/SafeSteps-Team17/data/output.json"

# Use your safesteps-dev profile; or rely on env vars if you prefer
session = boto3.Session(profile_name="safesteps-dev", region_name=AWS_REGION)
dynamodb = session.resource("dynamodb")

with open(CITY_FILE, "r", encoding="utf-8") as f:
    data = json.load(f)

total_written = 0
for feat in data.get("features", []):
    city = (feat.get("properties") or {}).get("name") or "Unknown"
    zone_ids = (feat.get("properties") or {}).get("zone_ids", [])
    if not zone_ids:
        continue

    written = dynamo.put_zones(zone_ids, city)  # your helper writes them
    print(f"{city}: wrote {written} zones")
    total_written += written

print(f"Done. Total zones written: {total_written}")
