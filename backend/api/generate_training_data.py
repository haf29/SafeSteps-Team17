import boto3
import random
import json
from datetime import datetime, timedelta
from decimal import Decimal

# Configuration
REGION = 'eu-north-1'
ZONES_HISTORY_TABLE = 'ZonesHistory'

dynamodb = boto3.resource('dynamodb', region_name=REGION)
table = dynamodb.Table(ZONES_HISTORY_TABLE)

# Zones with boundaries data
AUBMC_ZONES = [
    {
        "zone_id": "892da475943ffff",
        "boundary": [
            [Decimal("33.89386865667239"), Decimal("35.48399143862676")],
            [Decimal("33.89356867535649"), Decimal("35.48207877350664")],
            [Decimal("33.895444307304615"), Decimal("35.48087618015271")],
            [Decimal("33.89761991824568"), Decimal("35.481586222207014")],
            [Decimal("33.89791997226687"), Decimal("35.48349886293388")],
            [Decimal("33.89604434264372"), Decimal("35.48470148600055")]
        ],
        "center_lat": Decimal("35.48278884253146"),
        "center_lng": Decimal("33.89574431925976"),
        "resolution": 9,
        "area": "AUBMC_Danger_Zone",
        "city": "Beirut",
        "risk_category": "high"
    },
    {
        "zone_id": "892da475947ffff",
        "boundary": [
            [Decimal("33.896344377457126"), Decimal("35.48661411055587")],
            [Decimal("33.89604434264372"), Decimal("35.48470148600055")],
            [Decimal("33.89791997226687"), Decimal("35.48349886293388")],
            [Decimal("33.90009563437163"), Decimal("35.484208834712334")],
            [Decimal("33.900395741890165"), Decimal("35.48612143487084")],
            [Decimal("33.89852011460085"), Decimal("35.48732408764857")]
        ],
        "center_lat": Decimal("35.48541148474909"),
        "center_lng": Decimal("33.89822003771839"),
        "resolution": 9,
        "area": "AUBMC_Danger_Zone",
        "city": "Beirut",
        "risk_category": "high"
    },
    {
        "zone_id": "892da475973ffff",
        "boundary": [
            [Decimal("33.898820202914905"), Decimal("35.48923667162813")],
            [Decimal("33.89852011460085"), Decimal("35.48732408764857")],
            [Decimal("33.900395741890165"), Decimal("35.48612143487084")],
            [Decimal("33.90257145515285"), Decimal("35.48683133636429")],
            [Decimal("33.90287161617188"), Decimal("35.488743895943514")],
            [Decimal("33.90099599122528"), Decimal("35.48994657843051")]
        ],
        "center_lat": Decimal("35.48803401611161"),
        "center_lng": Decimal("33.900695860841175"),
        "resolution": 9,
        "area": "AUBMC_Danger_Zone",
        "city": "Beirut",
        "risk_category": "high"
    },
    {
        "zone_id": "892da47590fffff",
        "boundary": [
            [Decimal("33.89724455048041"), Decimal("35.492351870697654")],
            [Decimal("33.89694448137484"), Decimal("35.490439302908555")],
            [Decimal("33.898820202914905"), Decimal("35.48923667162813")],
            [Decimal("33.90099599122528"), Decimal("35.48994657843051")],
            [Decimal("33.90129613304311"), Decimal("35.4918591218234")],
            [Decimal("33.89942041384033"), Decimal("35.493061782810976")]
        ],
        "center_lat": Decimal("35.49114923668364"),
        "center_lng": Decimal("33.899120302661196"),
        "resolution": 9,
        "area": "AUBMC_Danger_Zone",
        "city": "Beirut",
        "risk_category": "high"
    },
    {
        "zone_id": "892da47590bffff",
        "boundary": [
            [Decimal("33.89476866919027"), Decimal("35.48972932049966")],
            [Decimal("33.894468653588646"), Decimal("35.48781671212741")],
            [Decimal("33.896344377457126"), Decimal("35.48661411055587")],
            [Decimal("33.89852011460085"), Decimal("35.48732408764857")],
            [Decimal("33.898820202914905"), Decimal("35.48923667162813")],
            [Decimal("33.89694448137484"), Decimal("35.490439302908555")]
        ],
        "center_lat": Decimal("35.48852671619325"),
        "center_lng": Decimal("33.89664442370062"),
        "resolution": 9,
        "area": "AUBMC_Danger_Zone",
        "city": "Beirut",
        "risk_category": "high"
    }
]

def generate_severity():
    """Generate left-skewed severity between 0-2 (mean ~2)"""
    severity = random.betavariate(3, 1) * 2
    return Decimal(str(round(severity, 2)))

def generate_training_data():
    """Generate sparse data: 1 record per zone per week for 2 months"""
    records = []
    
    # 2 months = 8 weeks
    for week in range(12, 0, -1):
        base_date = datetime.utcnow() - timedelta(weeks=week)
        
        for zone in AUBMC_ZONES:
            # Random day within the week
            day_offset = timedelta(days=random.randint(0, 6))
            # Random time within the day
            time_offset = timedelta(
                hours=random.randint(9, 22),
                minutes=random.randint(0, 59)
            )
            
            timestamp = (base_date + day_offset + time_offset).isoformat()
            severity = generate_severity()
            
            # Create record with all zone data
            record = {
                'zone_id': zone['zone_id'],
                'timestamp': timestamp,
                'severity': severity,
                'updated_by': 'synthetic_data',
                'boundary': zone['boundary'],
                'center_lat': zone['center_lat'],
                'center_lng': zone['center_lng'],
                'resolution': zone['resolution'],
                'area': zone['area'],
                'city': zone['city'],
                'risk_category': zone['risk_category']
            }
            records.append(record)
    
    return records

def upload_to_dynamodb(records):
    """Upload records to DynamoDB"""
    with table.batch_writer() as batch:
        for record in records:
            batch.put_item(Item=record)
    print(f"Uploaded {len(records)} records to {ZONES_HISTORY_TABLE}")

# First check table schema
print("Checking table schema...")
response = table.meta.client.describe_table(TableName=ZONES_HISTORY_TABLE)
key_schema = response['Table']['KeySchema']
print(f"Table key schema: {key_schema}")

# Generate and upload data
print("Generating training data...")
training_data = generate_training_data()
print(f"Generated {len(training_data)} records")

print("Uploading to DynamoDB...")
upload_to_dynamodb(training_data)
print("✅ Data generation complete!")