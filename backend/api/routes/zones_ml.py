# zones_ml.py
from __future__ import annotations
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional, Any, List, Dict

import boto3
from botocore.exceptions import ClientError
from boto3.dynamodb.conditions import Key

from services.ml_db_service import add_training_record, get_training_history, add_ml_prediction
from ml_model import predict_zone  # your prediction function

router = APIRouter(tags=["zonesML"])

# ---------- Accept both str and int for zone_id ----------
class ZonePredictionRequest(BaseModel):
    zone_id: Any   # allow str or int; we normalize below
    n_days: int = 1

def _as_int_if_possible(value: Any) -> Optional[int]:
    try:
        return int(value)
    except Exception:
        return None

# ---------- Dynamo setup ----------
dynamodb = boto3.resource("dynamodb", region_name="eu-north-1")
zones_ml_table = dynamodb.Table("ZonesML")

# ---------- Training APIs (unchanged) ----------
@router.post("/zonesml/training/{zone_id}/{severity}")
def add_training_data(zone_id: str, severity: float):
    try:
        success = add_training_record(zone_id, severity)
        if success:
            return {"status": "success", "message": "Training data added"}
        raise HTTPException(status_code=500, detail="Failed to add training data")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/zonesml/training/{zone_id}")
def get_training_data(zone_id: str):
    try:
        history = get_training_history(zone_id)
        return {"zone_id": zone_id, "records": len(history), "data": history}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ---------- Prediction (accept both str/int) ----------
@router.post("/predict-zone")
def predict_zone_endpoint(req: ZonePredictionRequest):
    try:
        # If your model expects int, convert when possible.
        zid_int = _as_int_if_possible(req.zone_id)
        zid_for_model = zid_int if zid_int is not None else req.zone_id
        pred = predict_zone(zid_for_model, n=req.n_days)
        if pred is None:
            raise HTTPException(status_code=404, detail="Not enough data to predict")
        return {"zone_id": req.zone_id, "horizon_days": req.n_days, "predicted_severity": pred}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ---------- Read APIs ----------
@router.get("/zonesml/all")
def get_all_zones_ml(
    limit: int = Query(100, description="Maximum number of records to return"),
    latest_only: bool = Query(True, description="Return only latest prediction per zone"),
):
    """
    Return ZonesML items; if latest_only=True, keep only the newest per zone.
    """
    try:
        response = zones_ml_table.scan(Limit=limit)
        items = response.get("Items", [])

        if not latest_only:
            return items

        zones_latest: Dict[Any, Dict[str, Any]] = {}
        for it in items:
            zid = it["zone_id"]
            prev = zones_latest.get(zid)
            if prev is None or it.get("timestamp", "") > prev.get("timestamp", ""):
                zones_latest[zid] = it
        return list(zones_latest.values())
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/zonesml/zone/{zone_id}")
def get_zone_ml(
    zone_id: str,
    limit: int = Query(100, description="Maximum number of records to return"),
    latest_only: bool = Query(True, description="Return only latest prediction"),
):
    """
    Query by zone_id, trying numeric first (if it looks numeric), then string.
    This avoids 'Condition parameter type does not match schema type'.
    """
    try:
        def _query(val):
            return zones_ml_table.query(
                KeyConditionExpression=Key("zone_id").eq(val),
                ScanIndexForward=False,
                Limit=1 if latest_only else limit,
            )

        # Try numeric first when possible
        tried = []
        zid_int = _as_int_if_possible(zone_id)
        if zid_int is not None:
            tried.append("int")
            resp = _query(zid_int)
            items = resp.get("Items", [])
            if items:
                return items[0] if latest_only else items

        # Fallback to string
        tried.append("str")
        resp = _query(zone_id)
        items = resp.get("Items", [])
        return (items[0] if latest_only else items) if items else (None if latest_only else [])

    except ClientError as e:
        raise HTTPException(status_code=500, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/zonesml/geojson")
def get_zones_ml_geojson(latest_only: bool = Query(True)):
    try:
        zones_data = get_all_zones_ml(latest_only=latest_only)
        fc = {"type": "FeatureCollection", "features": []}
        for z in zones_data:
            fc["features"].append({
                "type": "Feature",
                "properties": {
                    "zone_id": z["zone_id"],
                    "severity": float(z["severity"]),
                    "city": z.get("city", ""),
                    "area": z.get("area", ""),
                    "risk_category": z.get("risk_category", ""),
                    "resolution": z.get("resolution", 9),
                    "prediction_time": z["timestamp"],
                    "is_prediction": z.get("is_prediction", False),
                },
                "geometry": {"type": "Polygon", "coordinates": [z["boundary"]]},
            })
        return fc
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/zonesml/geojson/{zone_id}")
def get_zone_ml_geojson(zone_id: str):
    try:
        z = get_zone_ml(zone_id, latest_only=True)
        if not z:
            raise HTTPException(status_code=404, detail="Zone not found")
        return {
            "type": "FeatureCollection",
            "features": [{
                "type": "Feature",
                "properties": {
                    "zone_id": z["zone_id"],
                    "severity": float(z["severity"]),
                    "city": z.get("city", ""),
                    "area": z.get("area", ""),
                    "risk_category": z.get("risk_category", ""),
                    "resolution": z.get("resolution", 9),
                    "prediction_time": z["timestamp"],
                    "is_prediction": z.get("is_prediction", False),
                },
                "geometry": {"type": "Polygon", "coordinates": [z["boundary"]]},
            }],
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
