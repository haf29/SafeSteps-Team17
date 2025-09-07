# backend/api/services/directions.py
from __future__ import annotations

import os
from typing import Dict, Any, Tuple

import requests

GOOGLE_KEY = os.getenv("GOOGLE_MAPS_SERVER_KEY", "").strip()


class DirectionsError(RuntimeError):
    pass


def _map_mode(mode: str) -> str:
    # UI uses walking|driving|cycling
    return "bicycling" if mode == "cycling" else ("walking" if mode == "walking" else "driving")


def google_directions(
    origin: Tuple[float, float],
    destination: Tuple[float, float],
    mode: str = "driving",
) -> Dict[str, Any]:
    """
    Synchronous helper used by routers. Returns the raw Google Directions JSON.
    Requires env var GOOGLE_MAPS_SERVER_KEY.
    """
    if not GOOGLE_KEY:
        raise DirectionsError("GOOGLE_MAPS_SERVER_KEY is not set")

    params = {
        "origin": f"{origin[0]},{origin[1]}",
        "destination": f"{destination[0]},{destination[1]}",
        "mode": _map_mode(mode),
        "region": "lb",  # bias to Lebanon
        "avoid": "ferries",
        "key": GOOGLE_KEY,
    }
    r = requests.get("https://maps.googleapis.com/maps/api/directions/json", params=params, timeout=12)
    r.raise_for_status()
    data = r.json()
    if data.get("status") != "OK" or not data.get("routes"):
        raise DirectionsError(f"Google Directions error: {data.get('status') or 'NO_ROUTE'}")
    return data
