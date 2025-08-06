import os
import json
from typing import List, Dict
from shapely.geometry import Point, shape

from db.dynamo import get_zones_by_city, get_incidents_by_hex
from services.h3_utils import get_hex_boundary
from services.severity import calculate_score, categorize_score



"Im expecting to get a list of cities from the environment variable"
"aka path to cities GeoJSON file"
CITY_FILE = os.getenv("CITY_POLYGONS_FILE", "docs/cities.json")
with open(CITY_FILE, "r") as f:
    city_geo = json.load(f)

def find_city(lat: float, lng: float) -> str:
    """
    Find which city polygon contains the given point.
    """
    pt = Point(lng, lat)  # shapely expects (x=lon, y=lat)
    for feature in city_geo["features"]:
        city_name = feature["properties"]["name"]
        poly = shape(feature["geometry"])
        if poly.contains(pt):
            return city_name
    raise ValueError("Location not inside any supported city")

def get_city_zones(lat: float, lng: float, resolution: int = 9) -> Dict:
    """
    Main orchestration: 
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
