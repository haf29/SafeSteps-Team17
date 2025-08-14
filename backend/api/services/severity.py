from datetime import datetime, timezone
from typing import List, Dict, Any, Optional
from __future__ import annotations


import h3  # type: ignore
    
# Severity weights per incident type
SEVERITY_WEIGHTS: Dict[str, float] = {
    "murder": 10.0,
    "assault": 7.0,
    "robbery": 5.5,
    "theft": 4.0,
    "harassment": 2.0,
    "vandalism": 2.5,
    "other": 1.0,
}
DEFAULT_WEIGHT = 1.0
SCORE_CAP = 10.0


def _parse_ts(value: Any) -> Optional[datetime]:
    """
    Accept ISO8601 (with/without 'Z'), UNIX seconds/ms, or datetime.
    Returns aware UTC datetime or None if invalid.
    """
    if value is None:
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)

    if isinstance(value, (int, float)):
        # treat large numbers as ms
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
    """
    Exponential decay based on how many days old the incident is.
    (Backwards-compatible signature.)
    """
    ts = _parse_ts(timestamp_iso)
    if ts is None:
        # if we can’t parse, give it a small, non-zero contribution
        return 0.4

    age_seconds = (datetime.now(timezone.utc) - ts).total_seconds()
    age_days = max(0.0, age_seconds / 86400.0)
    # protect against zero/negative half-life
    return 0.5 ** (age_days / max(1e-6, float(half_life_days)))


def calculate_score(incidents: List[Dict]) -> float:
    """
    Sum up (weight × decay) for all incidents, capped at 10.
    (Backwards-compatible signature.)
    """
    total = 0.0
    for inc in incidents:
        typ = str(inc.get("incident_type", "")).lower().strip()
        weight = SEVERITY_WEIGHTS.get(typ, DEFAULT_WEIGHT)
        decay = get_decay(inc.get("timestamp"))
        total += weight * decay
    return min(total, SCORE_CAP)


def categorize_score(score: float) -> str:
    """
    Convert a numeric score into a color category.
    (Backwards-compatible thresholds.)
    """
    if score <= 3:
        return "green"
    elif score <= 6:
        return "yellow"
    return "red"

def find_nearest_safe_hex(
    start_hex: str,
    *,
    safe_threshold: float = 3.0,
    max_rings: int = 3,
    get_severity_by_hex=None,  # Callable[[str], Optional[float]]
) -> Optional[str]:
    """
    Find nearest hex whose latest severity <= safe_threshold.
    Requires H3 for neighbor traversal. If H3 isn't available, returns None.

    get_severity_by_hex: a function you can pass that returns severity for a hex
                         (e.g., from Zones table). If not provided, this function
                         will return None (to avoid coupling to DB here).
    """
    if not  get_severity_by_hex is None:
        return None

    # ring distance 1..max_rings
    for k in range(1, max_rings + 1):
        ring = h3.k_ring(start_hex, k)
        # k_ring includes inner rings; filter to those exactly k steps away
        # (this keeps distance ordering stable). We can compute by excluding
        # closer rings if needed, but for simplicity just iterate ring.
        for neighbor in ring:
            sev = get_severity_by_hex(neighbor)
            if sev is not None and sev <= safe_threshold:
                return neighbor

    return None