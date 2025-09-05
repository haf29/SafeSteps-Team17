import boto3
import pickle
import base64
import numpy as np
from sklearn.linear_model import LinearRegression
from datetime import datetime
from decimal import Decimal

# DynamoDB client
dynamodb = boto3.resource("dynamodb", region_name="eu-north-1")
zone_history_table = dynamodb.Table("ZonesHistory")
zone_ml_table = dynamodb.Table("ZonesML")

# Zone metadata (from your previous data)
ZONE_METADATA = {
    "892da475943ffff": {
        "boundary": [[Decimal("33.89386865667239"), Decimal("35.48399143862676")],
                     [Decimal("33.89356867535649"), Decimal("35.48207877350664")],
                     [Decimal("33.895444307304615"), Decimal("35.48087618015271")],
                     [Decimal("33.89761991824568"), Decimal("35.481586222207014")],
                     [Decimal("33.89791997226687"), Decimal("35.48349886293388")],
                     [Decimal("33.89604434264372"), Decimal("35.48470148600055")]],
        "center_lat": Decimal("35.48278884253146"),
        "center_lng": Decimal("33.89574431925976"),
        "resolution": 9,
        "area": "AUBMC_Danger_Zone",
        "city": "Beirut",
        "risk_category": "high"
    },
    "892da475947ffff": {
        "boundary": [[Decimal("33.896344377457126"), Decimal("35.48661411055587")],
                     [Decimal("33.89604434264372"), Decimal("35.48470148600055")],
                     [Decimal("33.89791997226687"), Decimal("35.48349886293388")],
                     [Decimal("33.90009563437163"), Decimal("35.484208834712334")],
                     [Decimal("33.900395741890165"), Decimal("35.48612143487084")],
                     [Decimal("33.89852011460085"), Decimal("35.48732408764857")]],
        "center_lat": Decimal("35.48541148474909"),
        "center_lng": Decimal("33.89822003771839"),
        "resolution": 9,
        "area": "AUBMC_Danger_Zone",
        "city": "Beirut",
        "risk_category": "high"
    },
    "892da475973ffff": {
        "boundary": [[Decimal("33.898820202914905"), Decimal("35.48923667162813")],
                     [Decimal("33.89852011460085"), Decimal("35.48732408764857")],
                     [Decimal("33.900395741890165"), Decimal("35.48612143487084")],
                     [Decimal("33.90257145515285"), Decimal("35.48683133636429")],
                     [Decimal("33.90287161617188"), Decimal("35.488743895943514")],
                     [Decimal("33.90099599122528"), Decimal("35.48994657843051")]],
        "center_lat": Decimal("35.48803401611161"),
        "center_lng": Decimal("33.900695860841175"),
        "resolution": 9,
        "area": "AUBMC_Danger_Zone",
        "city": "Beirut",
        "risk_category": "high"
    },
    "892da47590fffff": {
        "boundary": [[Decimal("33.89724455048041"), Decimal("35.492351870697654")],
                     [Decimal("33.89694448137484"), Decimal("35.490439302908555")],
                     [Decimal("33.898820202914905"), Decimal("35.48923667162813")],
                     [Decimal("33.90099599122528"), Decimal("35.48994657843051")],
                     [Decimal("33.90129613304311"), Decimal("35.4918591218234")],
                     [Decimal("33.89942041384033"), Decimal("35.493061782810976")]],
        "center_lat": Decimal("35.49114923668364"),
        "center_lng": Decimal("33.899120302661196"),
        "resolution": 9,
        "area": "AUBMC_Danger_Zone",
        "city": "Beirut",
        "risk_category": "high"
    },
    "892da47590bffff": {
        "boundary": [[Decimal("33.89476866919027"), Decimal("35.48972932049966")],
                     [Decimal("33.894468653588646"), Decimal("35.48781671212741")],
                     [Decimal("33.896344377457126"), Decimal("35.48661411055587")],
                     [Decimal("33.89852011460085"), Decimal("35.48732408764857")],
                     [Decimal("33.898820202914905"), Decimal("35.48923667162813")],
                     [Decimal("33.89694448137484"), Decimal("35.490439302908555")]],
        "center_lat": Decimal("35.48852671619325"),
        "center_lng": Decimal("33.89664442370062"),
        "resolution": 9,
        "area": "AUBMC_Danger_Zone",
        "city": "Beirut",
        "risk_category": "high"
    }
}

# ==============================
# Helpers for model storage
# ==============================
def save_model(zone_id, model):
    serialized = base64.b64encode(pickle.dumps(model)).decode("utf-8")
    zone_ml_table.put_item(
        Item={
            "zone_id": zone_id,
            "timestamp": datetime.utcnow().isoformat(),
            "model_blob": serialized,
            "updated_by": "ml_predictor"
        }
    )

def load_model(zone_id):
    resp = zone_ml_table.query(
        KeyConditionExpression="zone_id = :zid",
        ExpressionAttributeValues={":zid": zone_id},
        ScanIndexForward=False,
        Limit=1
    )
    items = resp.get("Items", [])
    if not items or "model_blob" not in items[0]:
        return None
    return pickle.loads(base64.b64decode(items[0]["model_blob"].encode("utf-8")))

# ==============================
# Data fetchers
# ==============================
def fetch_zone_history(zone_id, days=60):
    resp = zone_history_table.query(
        KeyConditionExpression="zone_id = :zid",
        ExpressionAttributeValues={":zid": zone_id},
        Limit=days,
        ScanIndexForward=False
    )
    items = sorted(resp["Items"], key=lambda x: x["timestamp"])
    return [float(i["severity"]) for i in items]

def fetch_all_zone_latest(exclude_id=None):
    neighbors = {}
    for zone_id in ZONE_METADATA.keys():
        if zone_id == exclude_id:
            continue
        resp = zone_history_table.query(
            KeyConditionExpression="zone_id = :zid",
            ExpressionAttributeValues={":zid": zone_id},
            Limit=1,
            ScanIndexForward=False
        )
        items = resp.get("Items", [])
        if items:
            neighbors[zone_id] = float(items[0]["severity"])
    return neighbors

# ==============================
# Training (multi-horizon)
# ==============================
def train_zone_model(zone_id, max_n=7, days=60):
    history = fetch_zone_history(zone_id, days=days)
    if len(history) < max_n + 2:
        print(f"Not enough data for zone {zone_id}")
        return None
    
    X, y = [], []
    for t in range(2, len(history) - max_n):
        own_lag1 = history[t-1]
        own_lag2 = history[t-2]
        neighbors = fetch_all_zone_latest(exclude_id=zone_id)
        neighbor_avg = np.mean(list(neighbors.values())) if neighbors else 0

        for n in range(1, max_n+1):
            if t + n < len(history):
                X.append([own_lag1, own_lag2, neighbor_avg, n])
                y.append(history[t+n])
    
    model = LinearRegression().fit(X, y)
    save_model(zone_id, model)
    return model

# ==============================
# Inference with full data format
# ==============================
def predict_zone(zone_id, n=1, max_age_hours=24):
    """
    Predict zone severity n days ahead and store in ZonesML with full format
    """
    # Check if we have recent prediction
    resp = zone_ml_table.query(
        KeyConditionExpression="zone_id = :zid",
        ExpressionAttributeValues={":zid": zone_id},
        ScanIndexForward=False,
        Limit=1
    )
    items = resp.get("Items", [])
    
    if items and "severity" in items[0]:
        item = items[0]
        ts = datetime.fromisoformat(item["timestamp"])
        age_hours = (datetime.utcnow() - ts).total_seconds() / 3600
        if age_hours <= max_age_hours and item.get("prediction_horizon") == n:
            return float(item["severity"])

    # Run prediction
    model = load_model(zone_id)
    if not model:
        model = train_zone_model(zone_id, max_n=max(7, n))
        if not model:
            return None

    history = fetch_zone_history(zone_id, days=3)
    if len(history) < 2:
        print(f"Not enough history for prediction (zone {zone_id})")
        return None
    
    own_lag1, own_lag2 = history[-1], history[-2]
    neighbors = fetch_all_zone_latest(exclude_id=zone_id)
    neighbor_avg = np.mean(list(neighbors.values())) if neighbors else 0

    X = np.array([[own_lag1, own_lag2, neighbor_avg, n]])
    pred = float(model.predict(X)[0])

    # Get zone metadata
    zone_meta = ZONE_METADATA.get(zone_id, {})
    
    # Save to ZonesML in same format as ZonesHistory
    zone_ml_table.put_item(
        Item={
            "zone_id": zone_id,
            "timestamp": datetime.utcnow().isoformat(),
            "severity": Decimal(str(pred)),
            "boundary": zone_meta.get("boundary", []),
            "center_lat": zone_meta.get("center_lat", Decimal("0")),
            "center_lng": zone_meta.get("center_lng", Decimal("0")),
            "resolution": zone_meta.get("resolution", 9),
            "area": zone_meta.get("area", ""),
            "city": zone_meta.get("city", ""),
            "risk_category": zone_meta.get("risk_category", ""),
            "prediction_horizon": n,
            "updated_by": "ml_predictor",
            "is_prediction": True
        }
    )
    
    return pred

# ==============================
# Example run
# ==============================
if __name__ == "__main__":
    for zone_id in ZONE_METADATA.keys():
        for horizon in [1, 3, 7]:
            pred = predict_zone(zone_id, n=horizon)
            print(f"Zone {zone_id}, {horizon}-day forecast: {pred}")