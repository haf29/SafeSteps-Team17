import boto3
import os
from decimal import Decimal
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional

REGION = os.getenv("AWS_REGION", "eu-north-1")
ZONES_HISTORY_TABLE = os.getenv("ZONES_HISTORY_TABLE", "ZonesHistory")
ZONES_ML_TABLE = os.getenv("ZONES_ML_TABLE", "ZonesML")

dynamodb = boto3.resource('dynamodb', region_name=REGION)
zones_history_table = dynamodb.Table(ZONES_HISTORY_TABLE)
zones_ml_table = dynamodb.Table(ZONES_ML_TABLE)

def add_training_record(zone_id: str, severity: float) -> bool:
    """Add a training record to ZonesHistory"""
    try:
        item = {
            "zone_id": zone_id,
            "timestamp": datetime.utcnow().isoformat(),
            "severity": Decimal(str(severity)),
            "created_at": datetime.utcnow().isoformat()
        }
        
        zones_history_table.put_item(Item=item)
        return True
        
    except Exception as e:
        print(f"Error adding training record: {e}")
        return False

def get_training_history(zone_id: str, days: int = 30) -> List[Dict[str, Any]]:
    """Get training data for a zone"""
    try:
        time_threshold = datetime.utcnow() - timedelta(days=days)
        
        response = zones_history_table.query(
            KeyConditionExpression=boto3.dynamodb.conditions.Key('zone_id').eq(zone_id),
            FilterExpression=boto3.dynamodb.conditions.Attr('timestamp').gte(time_threshold.isoformat()),
            ScanIndexForward=False
        )
        
        return response.get('Items', [])
        
    except Exception as e:
        print(f"Error getting training history: {e}")
        return []

def add_ml_prediction(zone_id: str, predicted_severity: float, confidence: float) -> bool:
    """Add ML prediction to ZonesML table"""
    try:
        item = {
            "zone_id": zone_id,
            "timestamp": datetime.utcnow().isoformat(),
            "predicted_severity": Decimal(str(predicted_severity)),
            "confidence": Decimal(str(confidence)),
            "model_version": "v1.0",
            "created_at": datetime.utcnow().isoformat()
        }
        
        zones_ml_table.put_item(Item=item)
        return True
        
    except Exception as e:
        print(f"Error adding ML prediction: {e}")
        return False