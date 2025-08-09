import json
from typing import List, Dict
from shapely.geometry import Point, shape

from db.dynamo import get_zones_by_city, get_incidents_by_hex
from services.h3_utils import get_hex_boundary
from services.severity import calculate_score, categorize_score

# Keep this EXACTLY as you asked
CITY_FILE = "C:/Users/AliG2/OneDrive/Desktop/Amazon/SafeSteps-Team17/data/cities.json"
print("Resolved CITY_FILE path:", CITY_FILE)


def find_city(lat: float, lng: float) -> str:
    """
    Find which city/district polygon contains the point (lat, lng).
    Uses 'shapeName' from your cities.json properties.
    """
    with open(CITY_FILE, "r", encoding="utf-8") as f:
        city_geo = json.load(f)

    pt = Point(lng, lat)  # shapely expects (x=lon, y=lat)

    for feature in city_geo.get("features", []):
        props = feature.get("properties", {})
        geom_dict = feature.get("geometry")

        if not geom_dict:
            continue  # skip malformed features

        # IMPORTANT: pass the FULL geometry dict, not just coordinates
        poly = shape(geom_dict)

        # 'covers' treats boundary points as inside; 'contains' excludes them
        if poly.covers(pt):
            # your file uses 'shapeName'; fallback to 'name' if ever present
            city_name = props.get("shapeName") or props.get("name") or "Unknown"
            return city_name

    raise ValueError("Location not inside any supported city")


def get_city_zones(lat: float, lng: float, resolution: int = 9) -> Dict:
    """
    1) detect city,
    2) fetch hex IDs,
    3) fetch & score incidents,
    4) attach boundary & color.
    """
    city = find_city(lat, lng)
    hex_ids = get_zones_by_city(city)

    zones: List[Dict] = []
    for hex_id in hex_ids:
        incs = get_incidents_by_hex(hex_id)
        score = calculate_score(incs) if incs else 0.0
        color = categorize_score(score)
        boundary = get_hex_boundary(hex_id)

        zones.append({
            "zone_id": hex_id,
            "boundary": boundary,
            "score": score,
            "color": color
        })

    return {"city": city, "zones": zones}
