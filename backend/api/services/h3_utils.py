"""
H3 helpers used across the project.
"""

from typing import Dict, Any, List, Tuple

try:
    import h3  # python-h3
except Exception as e:
    raise RuntimeError("python-h3 is required. Install with: pip install h3") from e


def lonlat_to_latlon(coords: List[Tuple[float, float]]) -> List[Tuple[float, float]]:
    return [(lat, lon) for lon, lat in coords]


# main function called by lambda function
def generate_zone_ids(polygon: Dict[str, Any], resolution: int = 9) -> List[str]:
    if polygon["type"] != "Polygon":
        raise ValueError("Only GeoJSON polygons are supported")

    ring_lonlat = polygon["coordinates"][0]  # use the outer ring only
    ring_latlon = lonlat_to_latlon(ring_lonlat)

    geo_poly_latlon = {"type": "Polygon", "coordinates": [ring_latlon]}

    zone_set = h3.polyfill(geo_poly_latlon, resolution, geo_json_conformant=True)
    return list(zone_set)


def get_hex_boundary(hex_id: str) -> List[List[float]]:
    """
    Convert H3 hexagon ID to GeoJSON boundary used by Frontend
    (returns [[lat, lng], ...])
    """
    return h3.h3_to_geo_boundary(hex_id, geo_json=True)


# NEW: Needed by /report_incident to compute zone_id from a point
def point_to_hex(lat: float, lng: float, resolution: int = 9) -> str:
    """
    Return the H3 hex ID for (lat, lng) at the given resolution.
    Compatible with h3<4 and h3>=4.
    """
    try:  # h3 < 4.x
        return h3.geo_to_h3(lat, lng, resolution)
    except AttributeError:  # h3 >= 4.x
        return h3.latlng_to_cell(lat, lng, resolution)
