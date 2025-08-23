# backend/api/services/routing.py
from __future__ import annotations

import math
import os
from typing import Any, Dict, Iterable, List, Optional, Tuple, Set

import requests
 
from services.h3_utils import point_to_hex
from services.severity import find_nearest_safe_hex
from db import dynamo  # <- we call dynamo.find_city(...) directly

GOOGLE_MAPS_API_KEY = os.getenv("GOOGLE_MAPS_API_KEY", "").strip()
# If you ever want to bypass Google during dev:
USE_OSRM_ONLY = os.getenv("USE_OSRM_ONLY", "false").lower() == "true"
USE_OSRM_FALLBACK = os.getenv("USE_OSRM_FALLBACK", "true").lower() == "true"

ROUTE_ALPHA = float(os.getenv("ROUTE_ALPHA", "0.6"))
SAMPLE_STEP_METERS = float(os.getenv("ROUTE_SAMPLE_STEP_METERS", "80"))


# ---------------- Geometry helpers ----------------
def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    R = 6371000.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dl / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c


def densify_segment(p1: Tuple[float, float], p2: Tuple[float, float], step_m: float) -> List[Tuple[float, float]]:
    (lat1, lon1), (lat2, lon2) = p1, p2
    d = haversine_m(lat1, lon1, lat2, lon2)
    if d == 0 or step_m <= 0:
        return [p1]
    n = max(1, int(math.ceil(d / step_m)))
    pts = []
    for i in range(n):
        t = i / n
        lat = lat1 + t * (lat2 - lat1)
        lon = lon1 + t * (lon2 - lon1)
        pts.append((lat, lon))
    return pts


def decode_polyline(polyline_str: str) -> List[Tuple[float, float]]:
    index, lat, lng, coordinates = 0, 0, 0, []
    changes = {"lat": 0, "lng": 0}
    while index < len(polyline_str):
        for unit in ["lat", "lng"]:
            shift, result = 0, 0
            while True:
                b = ord(polyline_str[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20:
                    break
            changes[unit] = ~(result >> 1) if (result & 1) else (result >> 1)
        lat += changes["lat"]
        lng += changes["lng"]
        coordinates.append((lat / 1e5, lng / 1e5))
    return coordinates


# ---------------- Severity lookups ----------------
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
        page, lek = dynamo.get_zones_by_city_with_severity(
            city_name=city, limit=1000, last_evaluated_key=None
        )
        items.extend(page or [])
        while lek:
            page, lek = dynamo.get_zones_by_city_with_severity(
                city_name=city, limit=1000, last_evaluated_key=lek
            )
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


def _merge_severity_maps(cities: Iterable[str]) -> Dict[str, float]:
    merged: Dict[str, float] = {}
    for c in cities:
        if not c:
            continue
        cm = _get_city_hex_severities(c)
        for k, v in cm.items():
            if k not in merged:
                merged[k] = v
    return merged


# ---------------- City detection (direct via Dynamo) ----------------
def _detect_initial_cities(
    origin: Tuple[float, float], destination: Tuple[float, float]
) -> Tuple[Optional[str], Set[str]]:
    """
    Returns (primary_city, cities_to_merge).
    If both same -> that city; if different -> prefer origin but merge both.
    """
    co = dynamo.find_city(origin[0], origin[1])  # <- direct call
    cd = dynamo.find_city(destination[0], destination[1])
    if co and cd:
        if co == cd:
            return co, {co}
        return co, {co, cd}
    if co or cd:
        return (co or cd), {c for c in (co, cd) if c}
    return None, set()


def _collect_cities_along_routes(
    routes: List[Dict[str, Any]], max_samples_per_route: int = 5
) -> Set[str]:
    cities: Set[str] = set()
    if not routes:
        return cities
    for r in routes:
        pts = r.get("polyline_points") or []
        if not pts:
            continue
        step = max(1, len(pts) // max_samples_per_route)
        for i in range(0, len(pts), step):
            lat, lng = pts[i]
            c = dynamo.find_city(lat, lng)  # <- direct call
            if c:
                cities.add(c)
    return cities


# ---------------- Google Routes v2 ----------------
def _parse_duration_seconds(s: Optional[str]) -> int:
    if not s or not isinstance(s, str) or not s.endswith("s"):
        try:
            return int(float(s or 0))
        except Exception:
            return 0
    try:
        return int(float(s[:-1]))
    except Exception:
        return 0


def fetch_routes_v2(
    origin: Tuple[float, float],
    destination: Tuple[float, float],
    *,
    alternatives: bool = True,
    mode: str = "walking",
) -> Dict[str, Any]:
    if not GOOGLE_MAPS_API_KEY:
        raise RuntimeError("GOOGLE_MAPS_API_KEY not configured")

    mode_map = {
        "walking": "WALK",
        "driving": "DRIVE",
        "bicycling": "BICYCLE",
        "two_wheeler": "TWO_WHEELER",
        "transit": "TRANSIT",
    }
    travel_mode = mode_map.get(mode.lower(), "WALK")

    url = "https://routes.googleapis.com/directions/v2:computeRoutes"
    headers = {
        "X-Goog-Api-Key": GOOGLE_MAPS_API_KEY,
        "X-Goog-FieldMask": "routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline",
        "Content-Type": "application/json",
    }
    body = {
        "origin": {"location": {"latLng": {"latitude": origin[0], "longitude": origin[1]}}},
        "destination": {"location": {"latLng": {"latitude": destination[0], "longitude": destination[1]}}}
        ,
        "travelMode": travel_mode,
        "computeAlternativeRoutes": bool(alternatives),
    }

    resp = requests.post(url, headers=headers, json=body, timeout=20)
    if resp.status_code >= 400:
        raise RuntimeError(f"Google Routes v2 {resp.status_code}: {resp.text}")
    data = resp.json()

    if not isinstance(data, dict) or not data.get("routes"):
        msg = data.get("error", {}).get("message") if isinstance(data, dict) else None
        raise RuntimeError(f"Google Routes v2 returned no routes. {msg or ''}".strip())
    return data


def extract_routes_v2(google_json: Dict[str, Any]) -> List[Dict[str, Any]]:
    routes: List[Dict[str, Any]] = []
    for r in google_json.get("routes", []):
        dur_sec = _parse_duration_seconds(r.get("duration"))
        dist_m = int(r.get("distanceMeters") or 0)
        enc = r.get("polyline", {}).get("encodedPolyline")
        pts = decode_polyline(enc) if enc else []
        if pts:
            routes.append(
                {
                    "summary": "GoogleRoutesV2",
                    "duration_sec": dur_sec,
                    "distance_m": dist_m,
                    "polyline_points": pts,
                    "raw": r,
                }
            )
    return routes


# ---------------- Polyline -> hex -> score ----------------
def polyline_to_hexes(
    points: List[Tuple[float, float]], *, resolution: int = 9, step_m: float = SAMPLE_STEP_METERS
) -> List[str]:
    ordered: List[str] = []

    def add_hex(lat, lon):
        hz = point_to_hex(lat, lon, resolution=resolution)
        if not ordered or ordered[-1] != hz:
            ordered.append(hz)

    if not points:
        return ordered
    for i in range(len(points) - 1):
        p1, p2 = points[i], points[i + 1]
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
    avg = sum(scores) / len(scores) if scores else 0.0
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


# ---------------- Exit-to-safety ----------------
def compute_exit_to_nearest_safe(
    origin: Tuple[float, float],
    *,
    city: Optional[str],
    resolution: int = 9,
    max_rings: int = 8,
    mode: str = "walking",
    alpha: Optional[float] = None,
) -> Dict[str, Any]:
    """
    If user is inside a risky hex, find nearest safe H3 cell (searching outwards),
    then route from origin to that safe point.
    Returns: { safe_hex, safe_point:{lat,lng}, origin_hex, route:{chosen,candidates} }
    """
    o_lat, o_lng = float(origin[0]), float(origin[1])
    origin_hex = point_to_hex(o_lat, o_lng, resolution=resolution)

    try:
        safe_hex = find_nearest_safe_hex(origin_hex, city=city, max_rings=max_rings)  # type: ignore
    except TypeError:
        safe_hex = find_nearest_safe_hex(origin_hex)  # type: ignore

    if not safe_hex:
        raise RuntimeError("No nearby safe zone found around the current location")

    try:
        from services.h3_utils import hex_to_center  # type: ignore
        s_lat, s_lng = hex_to_center(str(safe_hex))  # type: ignore
        s_lat, s_lng = float(s_lat), float(s_lng)
    except Exception:
        import h3  # type: ignore

        s_lat, s_lng = h3.h3_to_geo(str(safe_hex))  # type: ignore
        s_lat, s_lng = float(s_lat), float(s_lng)

    result = get_safest_reasonable_route(
        (o_lat, o_lng),
        (s_lat, s_lng),
        city=city,
        resolution=resolution,
        mode=mode,
        alpha=alpha,
        alternatives=True,
    )

    return {
        "safe_hex": str(safe_hex),
        "safe_point": {"lat": s_lat, "lng": s_lng},
        "origin_hex": origin_hex,
        "route": result,
    }


# ---------------- Main entry: safest reasonable route ----------------
def get_safest_reasonable_route(
    origin: Tuple[float, float],
    destination: Tuple[float, float],
    *,
    city: Optional[str] = None,
    resolution: int = 9,
    alternatives: bool = True,
    mode: str = "walking",
    alpha: Optional[float] = None,
) -> Dict[str, Any]:
    """
    1) Pull Google Routes v2 candidates.
    2) If city not provided, detect via origin/destination; if cross-city, merge maps.
    3) Sample each candidate to gather any additional cities crossed and merge those too.
    4) Score candidates and choose best with alpha tradeoff.
    """
    data = fetch_routes_v2(origin, destination, alternatives=alternatives, mode=mode)
    routes = extract_routes_v2(data)
    if not routes:
        raise RuntimeError("Directions returned no routes for the given origin/destination/mode")

    primary_city = city
    merge_cities: Set[str] = set()

    if not primary_city:
        primary_city, initial = _detect_initial_cities(origin, destination)
        merge_cities |= initial

    # Find extra cities along candidates
    merge_cities |= _collect_cities_along_routes(routes)

    # Build severity map
    if primary_city:
        severity_map = _get_city_hex_severities(primary_city)
        merge_cities.discard(primary_city)
        if merge_cities:
            extra = _merge_severity_maps(merge_cities)
            for k, v in extra.items():
                if k not in severity_map:
                    severity_map[k] = v
    else:
        severity_map = _merge_severity_maps(merge_cities)

    candidates: List[Dict[str, Any]] = []
    for r in routes:
        hexes = polyline_to_hexes(r["polyline_points"], resolution=resolution)
        score = score_route_hexes(hexes, severity_map)
        candidates.append(
            {
                "summary": r["summary"],
                "duration_sec": r["duration_sec"],
                "distance_m": r["distance_m"],
                "hexes": hexes,
                "score": score,
                "raw": r["raw"],
            }
        )

    chosen = choose_best_route(candidates, alpha=alpha if alpha is not None else ROUTE_ALPHA)
    return {
        "chosen": chosen,
        "candidates": candidates,
        "cities_used": sorted(list({c for c in merge_cities if c} | ({primary_city} if primary_city else set()))),
        "primary_city": primary_city,
    }
