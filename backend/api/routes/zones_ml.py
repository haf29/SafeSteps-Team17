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


from fastapi import APIRouter, HTTPException, Query
import boto3
from typing import List, Dict, Any

# DynamoDB client
dynamodb = boto3.resource('dynamodb', region_name='eu-north-1')
zones_ml_table = dynamodb.Table('ZonesML')

@router.get("/zonesml/all")
def get_all_zones_ml(
    limit: int = Query(100, description="Maximum number of records to return"),
    latest_only: bool = Query(True, description="Return only latest prediction per zone")
):
    """
    Get all zones data from ZonesML table with severities, boundaries, and coordinates
    """
    try:
        if latest_only:
            # Get latest prediction for each zone
            zones_data = {}
            
            # Scan all items
            response = zones_ml_table.scan(Limit=limit)
            items = response.get('Items', [])
            
            # Keep only the latest record for each zone
            for item in items:
                zone_id = item['zone_id']
                if zone_id not in zones_data:
                    zones_data[zone_id] = item
                else:
                    # Compare timestamps and keep the latest
                    current_time = zones_data[zone_id]['timestamp']
                    new_time = item['timestamp']
                    if new_time > current_time:
                        zones_data[zone_id] = item
            
            return list(zones_data.values())
        else:
            # Return all records
            response = zones_ml_table.scan(Limit=limit)
            return response.get('Items', [])
            
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/zonesml/zone/{zone_id}")
def get_zone_ml(
    zone_id: str,
    limit: int = Query(100, description="Maximum number of records to return"),
    latest_only: bool = Query(True, description="Return only latest prediction")
):
    """
    Get ZoneML data for a specific zone with severity, boundary, and coordinates
    """
    try:
        if latest_only:
            # Get the most recent prediction for this zone
            response = zones_ml_table.query(
                KeyConditionExpression="zone_id = :zid",
                ExpressionAttributeValues={":zid": zone_id},
                ScanIndexForward=False,  # Most recent first
                Limit=1
            )
            items = response.get('Items', [])
            return items[0] if items else None
            
        else:
            # Get all predictions for this zone
            response = zones_ml_table.query(
                KeyConditionExpression="zone_id = :zid",
                ExpressionAttributeValues={":zid": zone_id},
                ScanIndexForward=False,  # Most recent first
                Limit=limit
            )
            return response.get('Items', [])
            
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/zonesml/geojson")
def get_zones_ml_geojson(
    latest_only: bool = Query(True, description="Return only latest predictions")
):
    """
    Get ZonesML data as GeoJSON format for mapping
    """
    try:
        # Get all zones data
        zones_data = get_all_zones_ml(latest_only=latest_only)
        
        # Convert to GeoJSON format
        geojson = {
            "type": "FeatureCollection",
            "features": []
        }
        
        for zone in zones_data:
            feature = {
                "type": "Feature",
                "properties": {
                    "zone_id": zone['zone_id'],
                    "severity": float(zone['severity']),
                    "city": zone.get('city', ''),
                    "area": zone.get('area', ''),
                    "risk_category": zone.get('risk_category', ''),
                    "resolution": zone.get('resolution', 9),
                    "prediction_time": zone['timestamp'],
                    "is_prediction": zone.get('is_prediction', False)
                },
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [zone['boundary']]
                }
            }
            geojson['features'].append(feature)
        
        return geojson
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/zonesml/geojson/{zone_id}")
def get_zone_ml_geojson(zone_id: str):
    """
    Get GeoJSON for a specific zone from ZonesML
    """
    try:
        zone_data = get_zone_ml(zone_id, latest_only=True)
        
        if not zone_data:
            raise HTTPException(status_code=404, detail="Zone not found")
        
        geojson = {
            "type": "FeatureCollection",
            "features": [{
                "type": "Feature",
                "properties": {
                    "zone_id": zone_data['zone_id'],
                    "severity": float(zone_data['severity']),
                    "city": zone_data.get('city', ''),
                    "area": zone_data.get('area', ''),
                    "risk_category": zone_data.get('risk_category', ''),
                    "resolution": zone_data.get('resolution', 9),
                    "prediction_time": zone_data['timestamp'],
                    "is_prediction": zone_data.get('is_prediction', False)
                },
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [zone_data['boundary']]
                }
            }]
        }
        
        return geojson
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))