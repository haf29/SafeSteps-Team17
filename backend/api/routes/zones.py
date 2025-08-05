from fastapi import APIRouter, HTTPException, Query
from typing import Dict
from api.services.zone_service import get_city_zones

#create a router for the zones
router = APIRouter(tags=["zones"])

"this is the endpoint for the zones"
@router.get("/hex_zones", response_model=Dict)

def hex_zones(
    lat: float = Query(..., description="User latitude"),
    lng: float = Query(..., description="User longitude"),
    resolution: int = Query(9, description="H3 resolution, default=9")
):
    """
    Returns hexagons for the city containing (lat,lng), 
    each with boundary coords, severity score, and color.
    """
    try:
        return get_city_zones(lat, lng, resolution)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))