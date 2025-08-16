# scripts/warm_boundaries.py
from __future__ import annotations

from pathlib import Path
import sys
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import List, Dict, Any, Set

# --- Make repo imports work ---
REPO_ROOT = Path(__file__).resolve().parents[1]       # project root
API_DIR   = REPO_ROOT / "backend" / "api"
sys.path.insert(0, str(API_DIR))                      # <-- key line

# Now import using the same short paths your app uses
from db import dynamo as db
from services.h3_utils import get_hex_boundary

# --- Config ---
# Use the same cities file you already use server-side for city detection.
# If yours is "output.json" change the path accordingly.
CITY_FILE = r"C:\Users\AliG2\OneDrive\Desktop\Amazon\SafeSteps-Team17\data\cities.json"

# How many threads to compute boundaries concurrently (tune if you hit DynamoDB throttling)
MAX_WORKERS = 8


def _unique_city_names(gj: Dict[str, Any]) -> List[str]:
    """Extract distinct city/district names from cities GeoJSON."""
    names: Set[str] = set()
    for f in gj.get("features", []):
        props = f.get("properties") or {}
        n = props.get("shapeName") or props.get("name")
        if n:
            names.add(n)
    return sorted(names)


def _ensure_boundaries_for_city(city: str) -> Dict[str, int]:
    """
    1) Pull all zones for the city (zone_id, severity, boundary) via GSI.
    2) For each missing boundary, compute once and cache back to DynamoDB.
    """
    items = db.get_all_zones_by_city_full(city)  # uses city-index & autopaginates
    if not items:
        return {"total": 0, "already_cached": 0, "computed": 0}

    to_compute = [it for it in items if not it.get("boundary")]
    already = len(items) - len(to_compute)
    computed = 0

    if not to_compute:
        return {"total": len(items), "already_cached": already, "computed": 0}

    def _work(hex_id: str):
        # compute and cache; swallow individual failures to keep batch running
        try:
            boundary = get_hex_boundary(hex_id)  # [[lat, lng], ...]
            db.update_zone_boundary(hex_id, boundary)
            return True
        except Exception as e:
            print(f"[{city}] Failed boundary for {hex_id}: {e}")
            return False

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        futures = [pool.submit(_work, it["zone_id"]) for it in to_compute]
        for fut in as_completed(futures):
            if fut.result():
                computed += 1

    return {"total": len(items), "already_cached": already, "computed": computed}


def main():
    with open(CITY_FILE, "r", encoding="utf-8") as f:
        gj = json.load(f)

    cities = _unique_city_names(gj)
    if not cities:
        print("No cities found in cities.json; nothing to do.")
        return

    grand_total = 0
    grand_cached = 0
    grand_computed = 0

    print(f"Found {len(cities)} cities. Warming boundaries...")
    for city in cities:
        stats = _ensure_boundaries_for_city(city)
        grand_total += stats["total"]
        grand_cached += stats["already_cached"]
        grand_computed += stats["computed"]
        print(
            f"{city}: zones={stats['total']}  cached={stats['already_cached']}  computed_now={stats['computed']}"
        )

    print("\nDONE")
    print(f"All zones seen: {grand_total}")
    print(f"Had boundary already: {grand_cached}")
    print(f"Computed & cached now: {grand_computed}")


if __name__ == "__main__":
    main()
