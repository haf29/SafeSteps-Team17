import os
import json
from typing import List, Dict
from pathlib import Path
from shapely.geometry import Point, shape

from db.dynamo import get_zones_by_city, get_incidents_by_hex
from services.h3_utils import get_hex_boundary
from services.severity import calculate_score, categorize_score

# Use env override if provided; fall back to repo's data/cities.json
CITY_FILE = os.getenv(
    "CITIES_FILE",
    str((Path(__file__).resolve().parents[3] / "data" / "cities.json"))
)
print("Resolved CITY_FILE path:", CITY_FILE)


def find_city(lat: float, lng: float) -> str:
    """
    Find which city/district polygon contains the point (lat, lng).
    Uses 'shapeName' (fallback to 'name') from your cities.json properties.
    """
    with open(CITY_FILE, "r", encoding="utf-8") as f:
        city_geo = json.load(f)

    pt = Point(lng, lat)  # shapely expects (x=lon, y=lat)

    for feature in city_geo.get("features", []):
        props = feature.get("properties", {})
        geom_dict = feature.get("geometry")
        if not geom_dict:
            continue  # skip malformed features

        poly = shape(geom_dict)
        # 'covers' treats boundary points as inside; 'contains' excludes them
        if poly.covers(pt):
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


# NEW — routes/zones.py expects this
def get_cities() -> List[str]:
    """
    Return a unique, sorted list of city/district names present in cities.json.
    Uses 'shapeName' if available, otherwise 'name'.
    """
    with open(CITY_FILE, "r", encoding="utf-8") as f:
        gj = json.load(f)

    names: List[str] = []
    for feat in gj.get("features", []):
        props = feat.get("properties", {}) or {}
        name = props.get("shapeName") or props.get("name")
        if name:
            names.append(name)

    # unique + sorted for stable UI
    return sorted(set(names))
