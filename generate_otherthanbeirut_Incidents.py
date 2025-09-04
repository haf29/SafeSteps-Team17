import json
import random
from datetime import datetime, timedelta
import h3
import geopandas as gpd
from shapely.geometry import mapping

# Incident categories
INCIDENT_TYPES = [
    "murder",
    "assault",
    "robbery",
    "theft",
    "harassment",
    "vandalism",
    "drone_activity",
    "airstrike",
    "explosion",
    "shooting",
    "kidnapping",
    "other",
]

# Load Lebanon ADM2 file
adm2_path = "LBN_ADM2.geojson"
gdf = gpd.read_file(adm2_path)

# Exclude Beirut district
non_beirut_gdf = gdf[~gdf["shapeName"].str.contains("Beirut", case=False, na=False)]

resolution = 9
records = []

for _, row in non_beirut_gdf.iterrows():
    city_name = row["shapeName"]
    geom = row.geometry

    # Convert polygon → H3 hexagons
    hexagons = list(h3.polyfill(mapping(geom), resolution))

    for hex_id in hexagons:
        # Decide number of incidents per zone
        for _ in range(random.randint(1, 4)):
            incident_type = random.choice(INCIDENT_TYPES)

            incident = {
                "zone_id": hex_id,
                "incident_type": incident_type,
                "timestamp": (
                    datetime.utcnow()
                    - timedelta(
                        days=random.randint(0, 365),
                        hours=random.randint(0, 23),
                        minutes=random.randint(0, 59),
                    )
                ).isoformat() + "Z",
                "city": city_name,
                "reported_by": random.choice(
                    [
                        f"user_{random.randint(100, 999)}@example.com",
                        f"+9617{random.randint(1000000, 9999999)}",
                    ]
                ),
            }
            records.append(incident)

# Save as JSON
with open("other_cities_incidents.json", "w", encoding="utf-8") as f:
    json.dump(records, f, ensure_ascii=False, indent=2)

print(f"Generated {len(records)} incidents for all other districts → other_cities_incidents.json")
