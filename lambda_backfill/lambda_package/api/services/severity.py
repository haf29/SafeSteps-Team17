# severity.py  (NO H3 IMPORTS)

from __future__ import annotations
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

# weights & caps (same as your project)
SEVERITY_WEIGHTS: dict[str, float] = {
    "murder": 10.0, "assault": 7.0, "robbery": 5.5, "theft": 4.0,
    "harassment": 2.0, "vandalism": 2.5, "drone_activity": 1.5,
    "airstrike": 9.0, "explosion": 6.5, "shooting": 8.0,
    "kidnapping": 7.5, "other": 1.0,
}
DEFAULT_WEIGHT = 1.0
SCORE_CAP = 5.0

def _parse_ts(value: Any) -> Optional[datetime]:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, (int, float)):
        ts = float(value) / 1000.0 if value > 1e12 else float(value)
        return datetime.fromtimestamp(ts, tz=timezone.utc)
    if isinstance(value, str):
        s = value.strip()
        if s.endswith("Z"):
            s = s[:-1]
        try:
            dt = datetime.fromisoformat(s)
            return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
        except Exception:
            return None
    return None

def get_decay(timestamp_iso: str, half_life_days: int = 7) -> float:
    ts = _parse_ts(timestamp_iso)
    if ts is None:
        return 0.4
    age_sec = (datetime.now(timezone.utc) - ts).total_seconds()
    age_days = max(0.0, age_sec / 86400.0)
    return 0.5 ** (age_days / max(1e-6, float(half_life_days)))

def calculate_score(incidents: List[Dict]) -> float:
    total = 0.0
    for inc in incidents:
        typ = str(inc.get("incident_type", "")).lower().strip()
        weight = SEVERITY_WEIGHTS.get(typ, DEFAULT_WEIGHT)
        decay = get_decay(inc.get("timestamp"))
        total += weight * decay
    return min(total, SCORE_CAP)
