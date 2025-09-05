from __future__ import annotations
from fastapi import APIRouter, HTTPException
from services.ml_db_service import add_training_record, get_training_history, add_ml_prediction
from pydantic import BaseModel
from ml_model import predict_zone  # your prediction function

router = APIRouter(tags=["zonesML"])

class ZonePredictionRequest(BaseModel):
    zone_id: int
    n_days: int = 1  # default next day

@router.post("/zonesml/training/{zone_id}/{severity}")
def add_training_data(zone_id: str, severity: float):
    """Add training data to ZonesHistory"""
    try:
        success = add_training_record(zone_id, severity)
        if success:
            return {"status": "success", "message": "Training data added"}
        else:
            raise HTTPException(status_code=500, detail="Failed to add training data")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/zonesml/training/{zone_id}")
def get_training_data(zone_id: str):
    """Get training data for a zone"""
    try:
        history = get_training_history(zone_id)
        return {
            "zone_id": zone_id,
            "records": len(history),
            "data": history
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))



@router.post("/predict-zone")
def predict_zone_endpoint(req: ZonePredictionRequest):
    try:
        pred = predict_zone(req.zone_id, n=req.n_days)
        if pred is None:
            raise HTTPException(status_code=404, detail="Not enough data to predict")
        return {
            "zone_id": req.zone_id,
            "horizon_days": req.n_days,
            "predicted_severity": pred
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
