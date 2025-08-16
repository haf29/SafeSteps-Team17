from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query
from services.zone_service import get_city_zones, get_cities

router = APIRouter(tags=["zones"])


@router.get("/hex_zones")
def hex_zones(
    lat: float = Query(..., description="Latitude"),
    lng: float = Query(..., description="Longitude"),
    resolution: int = Query(9, ge=1, le=15, description="H3 resolution (1-15)"),
):
    try:
        return get_city_zones(lat, lng, resolution=resolution)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.get("/cities")
def list_cities():
    return {"cities": get_cities()} 
