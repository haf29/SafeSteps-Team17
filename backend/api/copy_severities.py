import boto3
import os
from decimal import Decimal
from datetime import datetime, timedelta
from typing import List, Dict, Any

# Configuration
REGION = os.getenv("AWS_REGION", "eu-north-1")
ZONES_TABLE = os.getenv("ZONES_TABLE", "Zones")  # Change this to your actual zones table name
SEVERITY_HISTORY_TABLE = os.getenv("SEVERITY_HISTORY_TABLE", "SeverityHistory")

# Initialize DynamoDB
dynamodb = boto3.resource('dynamodb', region_name=REGION)
zones_table = dynamodb.Table(ZONES_TABLE)
severity_history_table = dynamodb.Table(SEVERITY_HISTORY_TABLE)

def get_existing_timestamps(zone_id: str, time_threshold: datetime) -> set:
    """Check if recent records already exist for this zone to avoid duplicates"""
    try:
        # Query for records from the last 24 hours for this zone
        response = severity_history_table.query(
            KeyConditionExpression=boto3.dynamodb.conditions.Key('zone_id').eq(zone_id),
            FilterExpression=boto3.dynamodb.conditions.Attr('timestamp').gte(
                time_threshold.isoformat()
            ),
            ProjectionExpression='timestamp'
        )
        
        # Return set of timestamps (normalized to avoid microsecond differences)
        existing_timestamps = set()
        for item in response.get('Items', []):
            # Normalize timestamp by rounding to seconds (avoid microsecond differences)
            ts = datetime.fromisoformat(item['timestamp'].replace('Z', '+00:00'))
            normalized_ts = ts.replace(microsecond=0).isoformat()
            existing_timestamps.add(normalized_ts)
        
        return existing_timestamps
        
    except Exception as e:
        print(f"Error checking existing timestamps for zone {zone_id}: {e}")
        return set()

def get_all_zones() -> List[Dict[str, Any]]:
    """Scan all zones from the zones table"""
    zones = []
    last_evaluated_key = None
    
    print("Scanning zones table...")
    
    try:
        while True:
            if last_evaluated_key:
                response = zones_table.scan(ExclusiveStartKey=last_evaluated_key)
            else:
                response = zones_table.scan()
            
            zones.extend(response.get('Items', []))
            print(f"Retrieved {len(response.get('Items', []))} zones in this batch")
            
            last_evaluated_key = response.get('LastEvaluatedKey')
            if not last_evaluated_key:
                break
                
        print(f"Total zones found: {len(zones)}")
        return zones
        
    except Exception as e:
        print(f"Error scanning zones table: {e}")
        return []

def copy_zones_to_severity_history():
    """Copy severity data from zones to severity history table, avoiding duplicates"""
    print(f"Starting data copy at {datetime.utcnow().isoformat()}")
    
    # Get all zones
    zones = get_all_zones()
    
    if not zones:
        print("No zones found to process")
        return
    
    success_count = 0
    skip_count = 0
    error_count = 0
    
    print("Starting to copy zones to severity history...")
    
    # Time threshold for duplicate checking (last 24 hours)
    time_threshold = datetime.utcnow() - timedelta(hours=24)
    
    for i, zone in enumerate(zones, 1):
        try:
            # Extract zone_id and severity
            zone_id = zone.get('zone_id') or zone.get('id') or zone.get('h3_index')
            severity = zone.get('severity') or zone.get('score') or zone.get('risk_score') or zone.get('value')
            
            if not zone_id:
                print(f"Skipping zone {i} due to missing zone_id: {zone}")
                error_count += 1
                continue
            
            if severity is None:
                print(f"Skipping zone {zone_id} due to missing severity value")
                error_count += 1
                continue
            
            # Convert severity to Decimal
            try:
                severity_decimal = Decimal(str(severity))
            except Exception as conv_error:
                print(f"Invalid severity value for zone {zone_id}: {severity} - {conv_error}")
                error_count += 1
                continue
            
            # Generate timestamp (normalized to seconds to avoid microsecond differences)
            current_time = datetime.utcnow().replace(microsecond=0)
            ts_str = current_time.isoformat()
            
            # Check if a similar record already exists in the last 24 hours
            existing_timestamps = get_existing_timestamps(zone_id, time_threshold)
            
            # Normalize current timestamp for comparison
            normalized_current_ts = current_time.isoformat()
            
            if normalized_current_ts in existing_timestamps:
                print(f"Skipping zone {zone_id} - similar timestamp already exists in last 24 hours")
                skip_count += 1
                continue
            
            # Add to severity history
            severity_history_table.put_item(
                Item={
                    "zone_id": zone_id,
                    "timestamp": ts_str,
                    "severity": severity_decimal,
                    "updated_by": "copy-script",
                }
            )
            
            success_count += 1
            if success_count % 100 == 0:  # Print progress every 100 records
                print(f"Processed {success_count} zones so far...")
            
        except Exception as e:
            print(f"Error processing zone {i}: {e}")
            error_count += 1
    
    print(f"\nCopy completed!")
    print(f"Successfully copied: {success_count} zones")
    print(f"Skipped (duplicates): {skip_count} zones")
    print(f"Errors: {error_count}")
    print(f"Total processed: {len(zones)} zones")

if __name__ == "__main__":
    copy_zones_to_severity_history()