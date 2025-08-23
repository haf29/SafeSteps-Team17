# backend/api/routes/route.py
from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from services.routing import get_safest_reasonable_route, compute_exit_to_nearest_safe
from services import sns_alerts
from db.dynamo import get_zone_by_id

router = APIRouter(prefix="/route", tags=["route"])

class LatLng(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lng: float = Field(..., ge=-180, le=180)

class RouteRequest(BaseModel):
    origin: LatLng
    destination: LatLng
    city: Optional[str] = Field(None, description="City name for bulk severity preload")
    resolution: int = Field(9, ge=1, le=15)
    alternatives: bool = True
    mode: str = Field("walking", description="walking|driving|bicycling|transit")
    alpha: Optional[float] = Field(None, description="0..1 tradeoff between fast and safe (override env)")

class ExitToSafetyRequest(BaseModel):
    position: LatLng
    city: Optional[str] = None
    resolution: int = Field(9, ge=1, le=15)
    safe_threshold: float = Field(3.0, description="Max severity considered 'safe'")
    max_rings: int = Field(4, description="Search radius in hex rings")
    mode: str = Field("walking")
    phone: Optional[str] = Field(None, description="Send SMS to this phone if we are in a red zone")
    topic_arn: Optional[str] = Field(None, description="Publish to SNS topic if we are in a red zone")
    prev_score: Optional[float] = Field(None, description="Previous severity to enable hysteresis")
    up_threshold: float = Field(7.0)
    down_threshold: float = Field(5.0)
    min_jump: float = Field(1.0)

@router.post("/safest")
def safest_route(req: RouteRequest):
    try:
        res = get_safest_reasonable_route(
            origin=(req.origin.lat, req.origin.lng),
            destination=(req.destination.lat, req.destination.lng),
            city=req.city,
            resolution=req.resolution,
            alternatives=req.alternatives,
            mode=req.mode,
            alpha=req.alpha,
        )
        return res
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/exit_to_safety")
def exit_to_safety(req: ExitToSafetyRequest):
    try:
        out = compute_exit_to_nearest_safe(
            lat=req.position.lat,
            lng=req.position.lng,
            city=req.city,
            resolution=req.resolution,
            safe_threshold=req.safe_threshold,
            max_rings=req.max_rings,
            mode=req.mode,
        )
        if not out:
            return {"action": "no_exit_needed_or_not_found", "detail": out}
        if req.phone or req.topic_arn:
            try:
                new_hex = out["start_hex"]
                item = get_zone_by_id(new_hex) or {}
                new_score = float(item.get("severity", 0.0))
                msg_id = sns_alerts.alert_if_needed(
                    city=req.city,
                    zone_id=new_hex,
                    new_score=new_score,
                    prev_score=req.prev_score,
                    phone=req.phone,
                    topic_arn=req.topic_arn,
                    nearest_safe_hex=out["safe_hex"],
                    up_threshold=req.up_threshold,
                    down_threshold=req.down_threshold,
                    min_jump=req.min_jump,
                )
                out["sns_message_id"] = msg_id
            except Exception as sns_e:
                out["sns_error"] = str(sns_e)
        return {"action": "exit", **out}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
