# services/zone_service.py
from __future__ import annotations

import os, json
from pathlib import Path
from functools import lru_cache
from typing import Any, Dict, List, Tuple

from shapely.geometry import Point, Polygon, shape, box as make_bbox

from db.dynamo import get_city_items_all
from services.severity import categorize_score

# ---- cities.json path (env override allowed) ----
CITY_FILE = os.getenv(
    "CITIES_FILE",
    str((Path(__file__).resolve().parents[3] / "data" / "cities.json"))
)
print("Resolved CITY_FILE path:", CITY_FILE)


# ---------- City polygons (from cities.json) ----------
def _load_city_features() -> List[Dict[str, Any]]:
    with open(CITY_FILE, "r", encoding="utf-8") as f:
        gj = json.load(f)

    feats: List[Dict[str, Any]] = []
    for feat in gj.get("features", []):
        geom = feat.get("geometry")
        if not geom:
            continue
        feats.append({
            "name": feat.get("properties", {}).get("shapeName")
                    or feat.get("properties", {}).get("name"),
            "poly": shape(geom),
        })
    return feats

_CITY_FEATS = _load_city_features()


@lru_cache(maxsize=1)
def get_cities() -> List[str]:
    """Stable, sorted list of city names in cities.json."""
    return sorted({f["name"] for f in _CITY_FEATS})


def _find_city_by_point(lat: float, lng: float) -> str:
    p = Point(lng, lat)  # shapely is (x=lng, y=lat)
    for f in _CITY_FEATS:
        if f["poly"].covers(p):
            return f["name"]
    raise ValueError("Location not inside any supported city")


def _cities_intersecting_bbox(min_lat: float, max_lat: float, min_lng: float, max_lng: float) -> List[str]:
    """Return city names whose polygon intersects the given bbox."""
    bb = make_bbox(min_lng, min_lat, max_lng, max_lat)
    names: List[str] = []
    for f in _CITY_FEATS:
        if f["poly"].intersects(bb):
            names.append(f["name"])
    return names


# ---------- Boundary parsing / conversion ----------
def _parse_boundary_value(raw: Any) -> List[List[float]]:
    """
    DB stores boundary as JSON string like [[lng,lat], ...].
    Accepts str or already-parsed list. Returns list[[lng,lat],...].
    """
    if raw is None:
        return []
    if isinstance(raw, str):
        try:
            arr = json.loads(raw)
        except Exception:
            return []
    else:
        arr = raw
    return arr if isinstance(arr, list) else []


def _lnglat_to_latlng_ring(lnglat: List[List[float]]) -> List[List[float]]:
    """[[lng,lat], ...] -> [[lat,lng], ...]"""
    out: List[List[float]] = []
    for pt in lnglat:
        if isinstance(pt, (list, tuple)) and len(pt) == 2:
            out.append([float(pt[1]), float(pt[0])])
    return out


def _ring_to_polygon_lnglat(latlng_ring: List[List[float]]) -> Polygon | None:
    """Take [[lat,lng],...] ring and build a shapely Polygon (expects (lng,lat))."""
    if not latlng_ring:
        return None
    coords = [(lng, lat) for lat, lng in latlng_ring]
    try:
        return Polygon(coords)
    except Exception:
        return None


def _item_to_zone_payload(it: Dict[str, Any], include_city: bool = True) -> Dict[str, Any]:
    """
    Dynamo item has:
      - zone_id (string)
      - boundary (JSON string of [[lng,lat],...])  <-- our assumption from your table
      - severity (Number)                          <-- optional
      - city (string)
    Returns:
      { zone_id, boundary=[[lat,lng],...], score, color, [city] }
    """
    zid = it.get("zone_id")
    boundary_raw = it.get("boundary")  # JSON string or list
    lnglat = _parse_boundary_value(boundary_raw)
    latlng_ring = _lnglat_to_latlng_ring(lnglat)

    sev = float(it.get("severity", 0) or 0)
    payload = {
        "zone_id": zid,
        "boundary": latlng_ring,
        "score": sev,
        "color": categorize_score(sev),
    }
    if include_city and "city" in it:
        payload["city"] = it["city"]
    return payload


# ---------- Public API used by routes ----------
def get_city_zones(lat: float, lng: float, *, resolution: int = 9) -> Dict[str, Any]:
    """
    Find containing city for (lat,lng), pull all its zones (via GSI),
    and return zones with boundary [[lat,lng],...] + color.
    """
    city = _find_city_by_point(lat, lng)

    rows = get_city_items_all(city, page_limit=1000)  # returns dicts with zone_id, severity, boundary
    zones: List[Dict[str, Any]] = []
    for it in rows:
        zones.append(_item_to_zone_payload(it, include_city=False))

    return {"city": city, "zones": zones}


def get_all_lebanon_zones(*, page_limit: int = 1000, include_city: bool = True) -> Dict[str, Any]:
    """
    Heavy endpoint: return ALL zones for ALL cities in cities.json.
    (Good for client-side warmup cache.)
    """
    all_zones: List[Dict[str, Any]] = []
    for city in get_cities():
        rows = get_city_items_all(city, page_limit=page_limit)
        for it in rows:
            all_zones.append(_item_to_zone_payload(it, include_city=include_city))
    return {"zones": all_zones}


def get_zones_in_bbox(
    min_lat: float,
    max_lat: float,
    min_lng: float,
    max_lng: float,
    *,
    page_limit: int = 1000
) -> Dict[str, Any]:
    """
    Return only zones whose polygon intersects the viewport bbox.
    """
    bb = make_bbox(min_lng, min_lat, max_lng, max_lat)

    zones_out: List[Dict[str, Any]] = []
    # Only query cities that intersect the viewport
    for city in _cities_intersecting_bbox(min_lat, max_lat, min_lng, max_lng):
        rows = get_city_items_all(city, page_limit=page_limit)
        for it in rows:
            payload = _item_to_zone_payload(it, include_city=False)
            poly = _ring_to_polygon_lnglat(payload["boundary"])
            if poly is None:
                continue
            if poly.intersects(bb):
                zones_out.append(payload)

    return {"zones": zones_out}
