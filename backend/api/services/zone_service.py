from functools import lru_cache
import json
from shapely.geometry import shape
import os
import json
from typing import List, Dict, Any 
from pathlib import Path
from shapely.geometry import Point, shape
from shapely.geometry import Polygon

from db.dynamo import (
    get_zones_by_city,
    get_incidents_by_hex,
    get_boundary_for_hex,
    put_boundary_for_hex,
    get_city_items_all
)
from services.h3_utils import get_hex_boundary
from services.severity import calculate_score, categorize_score

# Use env override if provided; fall back to repo's data/cities.json
CITY_FILE = os.getenv(
    "CITIES_FILE",
    str((Path(__file__).resolve().parents[3] / "data" / "cities.json"))
)
print("Resolved CITY_FILE path:", CITY_FILE)
BOUNDARY_RES = int(os.getenv("BOUNDARY_RES", "9"))  # precomputed resolution you warmed

def _load_city_features() -> List[Dict]:
    with open(CITY_FILE, "r", encoding="utf-8") as f:
        gj = json.load(f)
    out = []
    for feat in gj.get("features", []):
        geom = feat.get("geometry")
        if not geom:
            continue
        out.append({
            "name": feat.get("properties", {}).get("shapeName")
                    or feat.get("properties", {}).get("name"),
            "poly": shape(geom),
        })
    return out

_CITY_FEATS = _load_city_features()

def find_city(lat: float, lng: float) -> str:
    pt = Point(lng, lat)
    for f in _CITY_FEATS:
        if f["poly"].covers(pt):
            return f["name"]
    raise ValueError("Location not inside any supported city")
def _parse_boundary(b):
    """
    Boundaries are stored as a JSON string in Dynamo to avoid float/Decimal issues.
    Accept str (JSON) or already-parsed list.
    """
    if not b:
        return None
    if isinstance(b, str):
        try:
            return json.loads(b)
        except Exception:
            return None
    if isinstance(b, list):
        return b
    return None
    
def get_city_zones(lat: float, lng: float, resolution: int = 9) -> Dict:
    """
    FAST READ:
      1) detect city
      2) single (paged) GSI query to get {zone_id, severity, boundary}
      3) map severity -> color and return
    Assumes severity & boundary were precomputed and stored on Zones items.
    """
    city = find_city(lat, lng)

    rows = get_city_items_all(city, page_limit=1000)  # 3.5k rows = ~4 requests

    zones: List[Dict] = []
    for it in rows:
        sev = float(it.get("severity", 0))
        boundary = _parse_boundary(it.get("boundary"))
        zones.append({
            "zone_id": it["zone_id"],
            "boundary": boundary or [],  # should be present if you pre-warmed
            "score": sev,
            "color": categorize_score(sev),
        })

    return {"city": city, "zones": zones}

# Add this to backend/api/services/zone_service.py

from functools import lru_cache

@lru_cache(maxsize=1)
def get_cities() -> list[str]:
    """
    Return a stable, sorted list of city/district names from cities.json.
    Cached so it’s effectively free after first call.
    """
    return sorted({f["name"] for f in _CITY_FEATS})
def _make_zone_payload(item: Dict[str, Any]) -> Dict[str, Any]:
    """Uniform payload builder for a single Zone row."""
    zid = item["zone_id"]
    sev = float(item.get("severity", 0.0))
    boundary = _parse_boundary(item.get("boundary"))

    # Fallbacks if boundary wasn't pre-warmed
    if not boundary:
        cached = get_boundary_for_hex(zid)            # optional DB cache layer
        boundary = cached or get_hex_boundary(zid)    # compute from H3 if needed
        try:
            # Persist for next time (avoid Decimal issues -> store JSON string)
            put_boundary_for_hex(zid, boundary, item.get("boundary_res", 9))
        except Exception:
            pass  # non-fatal

    from services.severity import categorize_score
    return {
        "zone_id": zid,
        "boundary": boundary or [],
        "score": sev,
        "color": categorize_score(sev),
    }

def get_all_lebanon_zones(*, page_limit: int = 1000, include_city: bool = True) -> Dict[str, Any]:
    """
    Return all zones for every city listed in cities.json.
    Uses precomputed severity/boundary if available; otherwise computes boundary and stores it.

    Response shape:
    {
      "cities": [...],
      "zones": [
        { "zone_id": "...", "boundary": [...], "score": 2.3, "color": "#A9D18E", "city": "Beirut" },
        ...
      ]
    }
    """
    cities = get_cities()
    out: List[Dict[str, Any]] = []

    for city in cities:
        rows = get_city_items_all(city, page_limit=page_limit)  # paged under the hood
        for it in rows:
            zone_payload = _make_zone_payload(it)
            if include_city:
                zone_payload["city"] = city
            out.append(zone_payload)

    return {"cities": cities, "zones": out} 


def get_zones_in_bbox(min_lat: float, max_lat: float, min_lng: float, max_lng: float, page_limit: int = 1000):
    bbox = Polygon([
        (min_lng, min_lat),
        (min_lng, max_lat),
        (max_lng, max_lat),
        (max_lng, min_lat),
        (min_lng, min_lat),
    ])

    cities = get_cities()
    out: List[Dict[str, Any]] = []

    for city in cities:
        rows = get_city_items_all(city, page_limit=page_limit)
        for it in rows:
            boundary = _parse_boundary(it.get("boundary"))
            if not boundary:
                continue
            try:
                poly = Polygon(boundary[0])  # assumes GeoJSON-like [[(lng,lat),...]]
                if poly.intersects(bbox):
                    zone_payload = _make_zone_payload(it)
                    zone_payload["city"] = city
                    out.append(zone_payload)
            except Exception:
                continue  # skip invalid geometries

    return {"zones": out}
