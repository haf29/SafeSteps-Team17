# backend/api/services/routing.py
from __future__ import annotations

import math
import os
from typing import Any, Dict, Iterable, List, Optional, Tuple

import requests

from services.h3_utils import point_to_hex
from services.severity import find_nearest_safe_hex
from db import dynamo

GOOGLE_MAPS_API_KEY = os.getenv("GOOGLE_MAPS_API_KEY", "")
ROUTE_ALPHA = float(os.getenv("ROUTE_ALPHA", "0.6"))
SAMPLE_STEP_METERS = float(os.getenv("ROUTE_SAMPLE_STEP_METERS", "80"))

def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    R = 6371000.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dl/2)**2
    c = 2*math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R*c

def densify_segment(p1: Tuple[float, float], p2: Tuple[float, float], step_m: float) -> List[Tuple[float,float]]:
    (lat1, lon1), (lat2, lon2) = p1, p2
    d = haversine_m(lat1, lon1, lat2, lon2)
    if d == 0 or step_m <= 0:
        return [p1]
    n = max(1, int(math.ceil(d / step_m)))
    pts = []
    for i in range(n):
        t = i / n
        lat = lat1 + t*(lat2 - lat1)
        lon = lon1 + t*(lon2 - lon1)
        pts.append((lat, lon))
    return pts

def decode_polyline(polyline_str: str) -> List[Tuple[float, float]]:
    index, lat, lng, coordinates = 0, 0, 0, []
    changes = {'lat': 0, 'lng': 0}
    while index < len(polyline_str):
        for unit in ['lat', 'lng']:
            shift, result = 0, 0
            while True:
                b = ord(polyline_str[index]) - 63
                index += 1
                result |= (b & 0x1f) << shift
                shift += 5
                if b < 0x20:
                    break
            if (result & 1):
                changes[unit] = ~(result >> 1)
            else:
                changes[unit] = (result >> 1)
        lat += changes['lat']
        lng += changes['lng']
        coordinates.append((lat / 1e5, lng / 1e5))
    return coordinates

def _get_zone_severity(hex_id: str) -> Optional[float]:
    try:
        item = dynamo.get_zone_by_id(hex_id)
        if not item:
            return None
        return float(item.get("severity")) if "severity" in item else None
    except Exception:
        return None

def _get_city_hex_severities(city: str) -> Dict[str, float]:
    items: List[Dict[str, Any]] = []
    try:
        page, lek = dynamo.get_zones_by_city_with_severity(city_name=city, limit=1000, last_evaluated_key=None)
        items.extend(page or [])
        while lek:
            page, lek = dynamo.get_zones_by_city_with_severity(city_name=city, limit=1000, last_evaluated_key=lek)
            items.extend(page or [])
    except Exception:
        try:
            items = dynamo.get_city_items_all(city)
        except Exception:
            items = []
    mapping: Dict[str, float] = {}
    for it in items:
        zid = it.get("zone_id")
        sev = it.get("severity")
        if zid is not None and sev is not None:
            try:
                mapping[str(zid)] = float(sev)
            except Exception:
                pass
    return mapping

def fetch_directions(origin, destination, *, alternatives=True, mode="walking") -> Dict[str, Any]:
    if not GOOGLE_MAPS_API_KEY:
        raise RuntimeError("GOOGLE_MAPS_API_KEY not configured")
    url = "https://maps.googleapis.com/maps/api/directions/json"
    params = {
        "origin": f"{origin[0]},{origin[1]}",
        "destination": f"{destination[0]},{destination[1]}",
        "mode": mode,
        "alternatives": "true" if alternatives else "false",
        "key": GOOGLE_MAPS_API_KEY,
    }
    resp = requests.get(url, params=params, timeout=20)
    resp.raise_for_status()
    return resp.json()

def extract_routes(google_json: Dict[str, Any]) -> List[Dict[str, Any]]:
    routes = []
    for r in google_json.get("routes", []):
        legs = r.get("legs", [])
        dur = sum(leg.get("duration", {}).get("value", 0) for leg in legs)
        dist = sum(leg.get("distance", {}).get("value", 0) for leg in legs)
        poly = r.get("overview_polyline", {}).get("points")
        pts = decode_polyline(poly) if poly else []
        routes.append({
            "summary": r.get("summary"),
            "duration_sec": dur,
            "distance_m": dist,
            "polyline_points": pts,
            "raw": r,
        })
    return routes

def polyline_to_hexes(points: List[Tuple[float,float]], *, resolution: int = 9, step_m: float = SAMPLE_STEP_METERS) -> List[str]:
    ordered: List[str] = []
    def add_hex(lat, lon):
        hz = point_to_hex(lat, lon, resolution=resolution)
        if not ordered or ordered[-1] != hz:
            ordered.append(hz)
    if not points:
        return ordered
    for i in range(len(points)-1):
        p1, p2 = points[i], points[i+1]
        for (lat, lon) in densify_segment(p1, p2, step_m):
            add_hex(lat, lon)
    add_hex(points[-1][0], points[-1][1])
    return ordered

def score_route_hexes(route_hexes: Iterable[str], severity_map: Dict[str, float]) -> Dict[str, Any]:
    scores: List[float] = []
    for h in route_hexes:
        if h in severity_map:
            scores.append(severity_map[h])
        else:
            sev = _get_zone_severity(h)
            if sev is not None:
                scores.append(sev)
    avg = sum(scores)/len(scores) if scores else 0.0
    mx = max(scores) if scores else 0.0
    return {"avg_severity": avg, "max_severity": mx, "samples": len(scores)}

def choose_best_route(candidates: List[Dict[str, Any]], *, alpha: float = 0.6) -> Dict[str, Any]:
    if not candidates:
        raise ValueError("No route candidates to choose from")
    max_dur = max(c["duration_sec"] for c in candidates) or 1
    max_avg = max(c["score"]["avg_severity"] for c in candidates) or 1
    for c in candidates:
        nd = c["duration_sec"] / max_dur
        ns = c["score"]["avg_severity"] / max_avg if max_avg > 0 else 0.0
        c["cost"] = alpha * nd + (1 - alpha) * ns
    return sorted(candidates, key=lambda x: x["cost"])[0]

def get_safest_reasonable_route(
    origin: Tuple[float,float],
    destination: Tuple[float,float],
    *,
    city: Optional[str] = None,
    resolution: int = 9,
    alternatives: bool = True,
    mode: str = "walking",
    alpha: Optional[float] = None,
) -> Dict[str, Any]:
    data = fetch_directions(origin, destination, alternatives=alternatives, mode=mode)
    routes = extract_routes(data)
    severity_map: Dict[str, float] = _get_city_hex_severities(city) if city else {}
    candidates: List[Dict[str, Any]] = []
    for r in routes:
        hexes = polyline_to_hexes(r["polyline_points"], resolution=resolution)
        score = score_route_hexes(hexes, severity_map)
        out = {
            "summary": r["summary"],
            "duration_sec": r["duration_sec"],
            "distance_m": r["distance_m"],
            "hexes": hexes,
            "score": score,
            "raw": r["raw"],
        }
        candidates.append(out)
    chosen = choose_best_route(candidates, alpha=alpha if alpha is not None else ROUTE_ALPHA)
    return {"chosen": chosen, "candidates": candidates}

def compute_exit_to_nearest_safe(
    lat: float,
    lng: float,
    *,
    city: Optional[str] = None,
    resolution: int = 9,
    safe_threshold: float = 3.0,
    max_rings: int = 4,
    mode: str = "walking",
) -> Optional[Dict[str, Any]]:
    current_hex = point_to_hex(lat, lng, resolution=resolution)
    def _sev(h: str) -> Optional[float]:
        s = _get_zone_severity(h); return s
    safe_hex = find_nearest_safe_hex(
        start_hex=current_hex,
        get_severity_by_hex=_sev,
        safe_threshold=safe_threshold,
        max_rings=max_rings,
    )
    if not safe_hex:
        return None
    try:
        import h3
        try:
            lat1, lon1 = h3.cell_to_latlng(current_hex)
            lat2, lon2 = h3.cell_to_latlng(safe_hex)
        except AttributeError:
            lat1, lon1 = h3.h3_to_geo(current_hex)
            lat2, lon2 = h3.h3_to_geo(safe_hex)
    except Exception:
        return {"start_hex": current_hex, "safe_hex": safe_hex, "route_result": None}
    res = get_safest_reasonable_route(
        origin=(lat1, lon1),
        destination=(lat2, lon2),
        city=city,
        resolution=resolution,
        alternatives=False,
        mode=mode,
    )
    return {"start_hex": current_hex, "safe_hex": safe_hex, "route_result": res}
