from datetime import datetime
from typing import List, Dict

# Severity weights per incident type
SEVERITY_WEIGHTS: dict[str, float] = {
    "murder": 10.0,
    "assault": 7.0,
    "theft": 4.0,
    "harassment": 2.0
}
def get_decay(timestamp_iso: str, half_life_days: int = 7) -> float:
    """
    Exponential decay factor based on how many days old the incident is.
    """
    incident_dt = datetime.fromisoformat(timestamp_iso)
    age_days = (datetime.utcnow() - incident_dt).days
    return 0.5 ** (age_days / half_life_days)

def calculate_score(incidents: List[Dict]) -> float:
    """
    Sum up (weight × decay) for all incidents, capped at 10.
    """
    total = 0.0
    for inc in incidents:
        typ = inc.get("incident_type", "").lower()
        weight = SEVERITY_WEIGHTS.get(typ, 1.0)
        decay = get_decay(inc.get("timestamp"))
        total += weight * decay
    return min(total, 10.0)

def categorize_score(score: float) -> str:
    """
    Convert a numeric score into a color category.
    """
    if score <= 3:
        return "green"
    elif score <= 6:
        return "yellow"
    return "red"