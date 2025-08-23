from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query
from services.zone_service import get_city_zones, get_cities, get_all_lebanon_zones

router = APIRouter(tags=["zones"])

@router.get("/hex_zones_lebanon")
def hex_zones_lebanon(
    page_limit: int = Query(1000, ge=100, le=2000, description="Page size per city GSI query"),
    include_city: bool = Query(True, description="Attach 'city' on every zone object"),
):
    """
    Heavy endpoint. Returns ALL H3 zones (with boundary, score, color) for all cities in cities.json.
    Intended for first-run cache warmup on the client (Hive).
    """
    try:
        return get_all_lebanon_zones(page_limit=page_limit, include_city=include_city)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

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
