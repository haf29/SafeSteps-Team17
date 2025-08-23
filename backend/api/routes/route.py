# backend/api/routes/route.py
from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from services.routing import get_safest_reasonable_route, compute_exit_to_nearest_safe
from services import sns_alerts
from db.dynamo import get_zone_by_id
from services.severity import find_nearest_safe_hex
from services.h3_utils import point_to_hex, hex_to_center
from db import dynamo

def _severity_lookup(hex_id: str) -> Optional[float]:
    item = dynamo.get_zone_by_id(hex_id)
    if not item:
        return None
    try:
        return float(item.get("severity")) if "severity" in item else None
    except Exception:
        return None
router = APIRouter(prefix="/route", tags=["route"])


class LatLng(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lng: float = Field(..., ge=-180, le=180)


class RouteRequest(BaseModel):
    origin: LatLng
    destination: LatLng
    city: Optional[str] = Field(None, description="City preselection; omit to auto-detect/merge")
    resolution: int = Field(9, ge=1, le=15)
    alternatives: bool = True
    mode: str = Field("walking", description="walking|driving|bicycling|transit")
    alpha: Optional[float] = Field(None, description="0..1 tradeoff between fast and safe (override env)")


class ExitToSafetyRequest(BaseModel):
    position: LatLng
    city: Optional[str] = None
    resolution: int = Field(9, ge=1, le=15)
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
    """
    If current position is in/near a risky zone, find the nearest safe hex
    (scanning outward ring-by-ring) and draw a route to it. Optionally send SNS.
    """
    try:
        # 1) Compute the user's current hex at the requested resolution
        user_hex = point_to_hex(req.position.lat, req.position.lng, resolution=req.resolution)

        # 2) Find nearest safe hex by severity threshold
        safe_hex = find_nearest_safe_hex(
            user_hex,
            safe_threshold=req.down_threshold,    # "safe" means <= this severity
            max_rings=req.max_rings,
            get_severity_by_hex=_severity_lookup,
        )

        if not safe_hex:
            return {
                "action": "no_exit_needed_or_not_found",
                "detail": f"No safe hex found within {req.max_rings} rings using threshold {req.down_threshold}."
            }

        # 3) Convert the target safe hex to lat/lng
        safe_lat, safe_lng = hex_to_center(safe_hex)

        # 4) Build a route from Point A to this safe Point B
        route = get_safest_reasonable_route(
            origin=(req.position.lat, req.position.lng),
            destination=(safe_lat, safe_lng),
            city=req.city,                 # helps severity scoring if your scorer is city-indexed
            resolution=req.resolution,
            alternatives=False,            # we only need the chosen route to exit
            mode=req.mode,
            alpha=None,                    # use default alpha unless you want to override
        )

        out = {
            "safe_hex": safe_hex,
            "safe_target": {"lat": safe_lat, "lng": safe_lng},
            "route": route,  # contains chosen + candidates
        }

        # 5) Optional: send an SNS alert (SMS or topic) if phone/topic provided
        if req.phone or req.topic_arn:
            try:
                # use the first hex of the chosen path as "current/next" zone
                chosen = route.get("chosen") or {}
                first_hex = (chosen.get("hexes") or [None])[0]
                item = get_zone_by_id(first_hex) or {}
                new_score = float(item.get("severity", 0.0))

                msg_id = sns_alerts.alert_if_needed(
                    city=req.city,
                    zone_id=first_hex,
                    new_score=new_score,
                    prev_score=req.prev_score,
                    phone=req.phone,
                    topic_arn=req.topic_arn,
                    nearest_safe_hex=safe_hex,
                    up_threshold=req.up_threshold,
                    down_threshold=req.down_threshold,
                    min_jump=req.min_jump,
                )
                out["sns_message_id"] = msg_id
            except Exception as sns_e:
                out["sns_error"] = str(sns_e)

        return {"action": "exit", **out}

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))