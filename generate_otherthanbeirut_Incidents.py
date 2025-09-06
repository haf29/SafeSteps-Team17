import json, random
from datetime import datetime, timedelta, timezone
import h3
import geopandas as gpd
from shapely.geometry import mapping, Polygon, MultiPolygon

INCIDENT_TYPES = [
    "murder","assault","robbery","theft","harassment","vandalism",
    "drone_activity","airstrike","explosion","shooting","kidnapping","other",
]

adm2_path = "LBN_ADM2.geojson"
gdf = gpd.read_file(adm2_path)

# exclude Beirut
non_beirut_gdf = gdf[~gdf["shapeName"].str.contains("Beirut", case=False, na=False)]

resolution = 9
records = []

def polygon_to_geojson(poly: Polygon) -> dict:
    """Return a GeoJSON Polygon (lng,lat) with just the exterior ring."""
    # (optional) fix invalid rings
    if not poly.is_valid:
        poly = poly.buffer(0)
    # exterior coords as [lon, lat]
    exterior = [(float(x), float(y)) for x, y in poly.exterior.coords]
    return {"type": "Polygon", "coordinates": [exterior]}

for _, row in non_beirut_gdf.iterrows():
    city_name = row["shapeName"]
    geom = row.geometry
    if geom is None or geom.is_empty:
        continue

    # Normalize MultiPolygon → list of Polygons
    polygons = []
    if isinstance(geom, Polygon):
        polygons = [geom]
    elif isinstance(geom, MultiPolygon):
        polygons = list(geom.geoms)
    else:
        # Try to coerce (e.g., GeometryCollection)
        try:
            geom = geom.buffer(0)
            polygons = [geom] if isinstance(geom, Polygon) else list(geom.geoms)
        except Exception:
            continue

    hexes = set()
    for poly in polygons:
        try:
            gj = polygon_to_geojson(poly)
            # h3.polyfill expects GeoJSON with [lng, lat]
            hexes.update(h3.polyfill(gj, resolution, geo_json_conformant=True))
        except Exception:
            # skip any odd polygon that still fails
            continue

    for hex_id in hexes:
        for _ in range(random.randint(1, 4)):
            ts = (datetime.now(timezone.utc) - timedelta(
                days=random.randint(0, 365),
                hours=random.randint(0, 23),
                minutes=random.randint(0, 59),
            )).isoformat().replace("+00:00", "Z")

            records.append({
                "zone_id": hex_id,
                "incident_type": random.choice(INCIDENT_TYPES),
                "timestamp": ts,
                "city": city_name,
                "reported_by": random.choice([
                    f"user_{random.randint(100, 999)}@example.com",
                    f"+9617{random.randint(1000000, 9999999)}",
                ]),
            })

with open("other_cities_incidents.json", "w", encoding="utf-8") as f:
    json.dump(records, f, ensure_ascii=False, indent=2)

print(f"Generated {len(records)} incidents → other_cities_incidents.json")
