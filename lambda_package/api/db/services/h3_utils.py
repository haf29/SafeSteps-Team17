"""
H3 helpers used across the project.
"""

from typing import Dict, Any, List, Tuple

import h3


def lonlat_to_latlon(coords: List[Tuple[float, float]]) -> List[Tuple[float, float]]:

    return [(lat, lon) for lon, lat in coords]

#main function called by lambda function
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
    """
    return h3.h3_to_geo_boundary(hex_id, geo_json=True)

