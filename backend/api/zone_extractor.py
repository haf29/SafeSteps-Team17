"""
Zone extractor aligned with h3==3.7.7 (v3 API).
- Uses h3.polyfill(..., geo_json=True)
- Uses h3.h3_to_geo_boundary / h3.h3_to_geo / h3.geo_to_h3
- Expects GeoJSON rings in [lng, lat] order
"""

import json
from typing import Dict, Any, List, Iterable, Tuple
import h3  # make sure you've installed: pip install "h3==3.7.7"

# ---- GeoJSON (lon, lat) ----
AUBMC_GEOJSON = {
    "type": "FeatureCollection",
    "features": [{
        "type": "Feature",
        "properties": {},
        "geometry": {
            "type": "Polygon",
            "coordinates": [[
                [35.48575336366238, 33.90114263247952],
                [35.48510353322504, 33.899200914308395],
                [35.48185438104451, 33.8994436314978],
                [35.48113956756518, 33.895789316265166],
                [35.4852984823558,  33.89539825480574],
                [35.491016990193856,33.895303860391394],
                [35.49150436302148, 33.89777156573362],
                [35.491878015522474,33.899956032185],
                [35.489554871712585,33.900792047747814],
                [35.48575336366238, 33.90114263247952]
            ]]
        }
    }]
}

def generate_zone_ids(rings: List[List[List[float]]], resolution: int):
    """Return a set of H3 cells covering the polygon (GeoJSON rings in [lng,lat])."""
    geojson_poly = {"type": "Polygon", "coordinates": rings}
    # v3.7.7: only positional args, no geo_json flag
    return h3.polyfill(geojson_poly, resolution)

def h3_boundary_lnglat(hex_id: str) -> List[List[float]]:
    """
    v3 returns boundary as [(lat, lng), ...]; convert to [[lng, lat], ...] for GeoJSON-friendly storage.
    """
    latlng = h3.h3_to_geo_boundary(hex_id)  # list of (lat, lng)
    return [[lng, lat] for (lat, lng) in latlng]

def h3_center_latlng(hex_id: str) -> Tuple[float, float]:
    """Return (lat, lng) of hex center (v3: h3_to_geo)."""
    return h3.h3_to_geo(hex_id)

def latlng_to_cell(lat: float, lng: float, res: int) -> str:
    """v3 name for lat/lng -> cell."""
    return h3.geo_to_h3(lat, lng, res)

def extract_aubmc_zones(resolution: int = 9) -> List[Dict[str, Any]]:
    rings = AUBMC_GEOJSON["features"][0]["geometry"]["coordinates"]
    zone_ids = generate_zone_ids(rings, resolution)
    zones: List[Dict[str, Any]] = []
    for zid in zone_ids:
        boundary = h3_boundary_lnglat(zid)  # [[lng,lat],...]
        center_lat, center_lng = h3_center_latlng(zid)
        zones.append({
            "zone_id": zid,
            "boundary": boundary,
            "center_lat": center_lat,
            "center_lng": center_lng,
            "resolution": resolution,
            "area": "AUBMC_Danger_Zone",
            "city": "Beirut",
            "severity": 0,
            "risk_category": "high",
        })
    return zones

def save_zones_to_json(zones: List[Dict[str, Any]], filename: str = "aubmc_zones.json"):
    with open(filename, "w", encoding="utf-8") as f:
        json.dump(zones, f, indent=2)
    print(f"✅ Saved {len(zones)} zones to {filename}")

def check_location_in_aubmc(lat: float, lng: float, resolution: int = 9) -> Dict[str, Any]:
    zid = latlng_to_cell(lat, lng, resolution)
    aubmc_zone_ids = {z["zone_id"] for z in extract_aubmc_zones(resolution)}
    return {
        "in_aubmc_area": zid in aubmc_zone_ids,
        "zone_id": zid,
        "message": "This location is in the AUBMC danger zone" if zid in aubmc_zone_ids
                   else "This location is outside the AUBMC danger zone",
    }

if __name__ == "__main__":
    print("h3 version:", getattr(h3, "__version__", "?"))
    res = 9
    zones = extract_aubmc_zones(resolution=res)
    print(f"✅ Generated {len(zones)} zones at res {res}")
    save_zones_to_json(zones, "aubmc_zones.json")

    print("\n=== Location Checks ===")
    for lat, lng, label in [
        (33.897, 35.482, "AUBMC Center"),
        (33.899, 35.485, "AUBMC Nearby"),
        (33.880, 35.500, "Far Location"),
        (33.896, 35.481, "Your Incident Location"),
    ]:
        r = check_location_in_aubmc(lat, lng, res)
        print(("✅ INSIDE " if r["in_aubmc_area"] else "❌ OUTSIDE ") + f"{label}: {lat}, {lng} → {r['zone_id']}")
