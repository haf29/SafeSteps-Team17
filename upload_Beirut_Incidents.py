# upload_Beirut_Incidents.py
"""
Bulk-upload Beirut incidents from a JSON file into DynamoDB using the existing
add_incident() helper in backend/api/services/dynamo.py.

Usage:
  python upload_Beirut_Incidents.py --file beirut_incidents.json [--dry-run]

Env vars (same as dynamo.py):
  AWS_REGION=eu-north-1
  INCIDENTS_TABLE=Incidents
  ZONES_TABLE=Zones
"""
import os
import sys
import json
import time
import argparse
from datetime import datetime

# Allow importing sibling "services" package
THIS_DIR = os.path.dirname(os.path.abspath(__file__))
BACKEND_API_DIR = os.path.join(THIS_DIR, "backend", "api")
SERVICES_DIR = os.path.join(BACKEND_API_DIR, "services")
if SERVICES_DIR not in sys.path:
    sys.path.append(SERVICES_DIR)
if BACKEND_API_DIR not in sys.path:
    sys.path.append(BACKEND_API_DIR)

# Import the existing helper
from backend.api.db.dynamo import add_incident  # noqa: E402


def iso_or_passthrough(ts: str) -> str:
    """
    Ensure timestamp is ISO-8601. If it's already ISO, keep it. If it's epoch,
    convert. Otherwise, return as string (dynamo.add_incident accepts strings).
    """
    if not ts:
        return datetime.utcnow().isoformat()

    s = str(ts).strip()

    # Try epoch seconds
    if s.isdigit():
        try:
            return datetime.utcfromtimestamp(int(s)).isoformat()
        except Exception:
            pass

    # Try parse/validate ISO
    try:
        # If this fails it will raise ValueError; we then just return s as-is.
        _ = datetime.fromisoformat(s.replace("Z", "+00:00"))
        return s
    except Exception:
        return s


def main():
    parser = argparse.ArgumentParser(description="Upload Beirut incidents JSON to DynamoDB.")
    parser.add_argument("--file", "-f", default="other_cities_incidents.json",
                        help="Path to JSON file (list of incident objects).")
    parser.add_argument("--dry-run", action="store_true",
                        help="Validate and print, but do not write to DynamoDB.")
    parser.add_argument("--sleep", type=float, default=0.0,
                        help="Optional delay (seconds) between writes to be gentle.")
    args = parser.parse_args()

    path = os.path.abspath(args.file)
    if not os.path.exists(path):
        print(f"Error: file not found: {path}")
        sys.exit(1)

    with open(path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            print(f"JSON parse error: {e}")
            sys.exit(1)

    if not isinstance(data, list):
        print("Error: JSON root must be a list of incident objects.")
        sys.exit(1)

    total = len(data)
    ok = 0
    skipped = 0
    for i, rec in enumerate(data, 1):
        zone_id       = (rec.get("zone_id") or "").strip()
        incident_type = (rec.get("incident_type") or "").strip()
        timestamp     = iso_or_passthrough(rec.get("timestamp"))
        city          = (rec.get("city") or "").strip()
        reported_by   = (rec.get("reported_by") or "").strip()

        # Basic validation (same fields present in your JSON)
        if not (zone_id and incident_type and city and reported_by):
            print(f"[{i}/{total}] SKIP (missing required fields): {rec}")
            skipped += 1
            continue

        if args.dry_run:
            print(f"[{i}/{total}] DRY-RUN add_incident("
                  f"zone_id='{zone_id}', type='{incident_type}', ts='{timestamp}', "
                  f"city='{city}', by='{reported_by}')")
            ok += 1
            continue

        try:
            if add_incident(zone_id, incident_type, timestamp, city, reported_by):
                ok += 1
                if args.sleep > 0:
                    time.sleep(args.sleep)
            else:
                print(f"[{i}/{total}] FAILED to add: {rec}")
        except Exception as e:
            print(f"[{i}/{total}] ERROR {e} for record: {rec}")

    print(f"\nDone. Success: {ok}  Skipped: {skipped}  Total read: {total}")


if __name__ == "__main__":
    main()
