# backend/api/routes/directions.py
from __future__ import annotations
import os, requests
from fastapi import APIRouter, HTTPException, Query

router = APIRouter(prefix="/route", tags=["route"])

# Lebanon bounds (same as frontend)
_LEB_MIN_LAT, _LEB_MAX_LAT = 33.046, 34.693
_LEB_MIN_LNG, _LEB_MAX_LNG = 35.098, 36.623

def _in_lb(lat: float, lng: float) -> bool:
    return (_LEB_MIN_LAT <= lat <= _LEB_MAX_LAT) and (_LEB_MIN_LNG <= lng <= _LEB_MAX_LNG)

@router.get("/directions")
def directions(
    origin: str = Query(..., description="lat,lng"),
    destination: str = Query(..., description="lat,lng"),
    mode: str = Query("driving", description="driving|walking|cycling"),
):
    """Server-side proxy to Google Directions (avoids CORS, hides key)."""
    try:
        o_lat, o_lng = [float(x) for x in origin.split(",")]
        d_lat, d_lng = [float(x) for x in destination.split(",")]
    except Exception:
        raise HTTPException(400, "Invalid lat,lng format.")

    if not (_in_lb(o_lat, o_lng) and _in_lb(d_lat, d_lng)):
        raise HTTPException(400, "Points must be inside Lebanon.")

    key = os.getenv("GOOGLE_MAPS_SERVER_KEY")
    if not key:
        raise HTTPException(500, "Missing GOOGLE_MAPS_SERVER_KEY")

    gm_mode = "bicycling" if mode == "cycling" else mode  # match app's values

    params = {
        "origin": f"{o_lat},{o_lng}",
        "destination": f"{d_lat},{d_lng}",
        "mode": gm_mode,
        "region": "lb",          # bias to Lebanon
        "avoid": "ferries",
        "alternatives": "false",
        "key": key,
    }

    r = requests.get(
        "https://maps.googleapis.com/maps/api/directions/json",
        params=params,
        timeout=12,
    )
    data = r.json()
    if data.get("status") != "OK":
        raise HTTPException(502, f"Directions error: {data.get('status')} {data.get('error_message','')}")

    # Return both: steps (high fidelity) and overview (compact)
    route = data["routes"][0]
    steps_encoded = [step["polyline"]["points"]
                     for leg in route.get("legs", [])
                     for step in leg.get("steps", [])]
    return {
        "overview_polyline": route["overview_polyline"]["points"],
        "steps_polyline": steps_encoded,
    }
