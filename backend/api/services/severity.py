from __future__ import annotations
from datetime import datetime, timezone
from typing import List, Dict, Any, Optional, Callable



import h3  # type: ignore

    
# Severity weights per incident type
SEVERITY_WEIGHTS: dict[str, float] = {
    "murder": 10.0,
    "assault": 7.0,
    "robbery": 5.5,
    "theft": 4.0,
    "harassment": 2.0,
    "vandalism": 2.5,
    "drone_activity": 1.5,
    "airstrike": 9.0,
    "explosion": 6.5,
    "shooting": 8.0,
    "kidnapping": 7.5,
    "other": 1.0,
}
DEFAULT_WEIGHT = 1.0
SCORE_CAP = 3.0
try:
    import h3  # h3>=4
    _HAS_H3 = True
    def _rings_by_distance(center: str, k: int):
        # returns list-of-lists (distance 0..k)
        return h3.k_ring_distances(center, k)
except Exception:
    try:
        from h3 import h3 as h3v3  # old h3-py
        _HAS_H3 = True
        def _rings_by_distance(center: str, k: int):
            # emulate k_ring_distances for v3
            rings = [set([center])]
            for dist in range(1, k + 1):
                rings.append(h3v3.k_ring(center, dist) - set.union(*rings))
            # Convert to list-of-sets to match v4-ish shape
            return [list(r) for r in rings]
    except Exception:
        _HAS_H3 = False

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
    if score < 1:
        return "#00FF00"
    elif score < 2:
        return "#FFFF00"
    return "#FF000"

def find_nearest_safe_hex(
    origin_hex: str,
    *,
    safe_threshold: float = 5.0,
    max_rings: int = 4,
    get_severity_by_hex: Optional[Callable[[str], Optional[float]]] = None,
    city: Optional[str] = None,   # accepted for backwards compatibility; ignored here
) -> Optional[str]:
    """
    Return the first hex (starting from origin, expanding ring-by-ring) whose severity
    is <= safe_threshold. If severity for a hex is unknown, that hex is skipped.

    We avoid deprecated h3.k_ring_distances and instead use grid_disk to build rings.
    """
    # 0) check current location first
    if get_severity_by_hex:
        sev0 = get_severity_by_hex(origin_hex)
        if sev0 is not None and sev0 <= safe_threshold:
            return origin_hex

    # prev_disk keeps everything already examined (distance < k)
    prev_disk = {origin_hex}

    for k in range(1, int(max_rings) + 1):
        # all cells within distance k
        disk_k = set(h3.grid_disk(origin_hex, k))   # works in h3 v3 & v4
        # new ring = cells at exactly distance k
        ring_k = disk_k - prev_disk

        if not ring_k:
            prev_disk = disk_k
            continue

        if get_severity_by_hex is None:
            # if no lookup func was given, treat "exists" as safe — usually you *do* pass a lookup
            return next(iter(ring_k))

        for cell in ring_k:
            sev = get_severity_by_hex(cell)
            if sev is not None and sev <= safe_threshold:
                return cell

        prev_disk = disk_k

    return None