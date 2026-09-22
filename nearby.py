#!/usr/bin/env python3
"""Proximity queries: given a GPS fix, find nearby enforcement cameras.

This is the exact logic the app's background service will call every fix.
Kept dependency-free (stdlib only) so it drops into Android/Kotlin ports
or a Python backend verbatim.
"""
from __future__ import annotations

import math
import sqlite3
from dataclasses import dataclass
from pathlib import Path

DB_PATH = Path(__file__).resolve().parent / "data" / "speed_enforcement.db"
EARTH_R = 6371000.0  # metres

# Approaching-camera alert distance. 500 m gives ~18 s at 100 km/h to react.
ALERT_RADIUS_M = 500


@dataclass
class Camera:
    id: int
    type: str
    city: str | None
    address: str | None
    lat: float
    lon: float
    direction: str | None
    speed_limit: int | None
    distance_m: float
    bearing_deg: float


def haversine(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_R * math.asin(math.sqrt(a))


def bearing(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Initial bearing (0-360, 0=N) from point 1 to point 2."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dl = math.radians(lon2 - lon1)
    y = math.sin(dl) * math.cos(p2)
    x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return (math.degrees(math.atan2(y, x)) + 360) % 360


def nearby(lat: float, lon: float, radius_m: float = ALERT_RADIUS_M,
           con: sqlite3.Connection | None = None) -> list[Camera]:
    """Return cameras within radius_m, nearest first.

    Uses a cheap bounding-box prefilter (indexed on lat,lon) before the
    exact haversine, so it stays fast on low-end phones / big result sets.
    """
    own = con is None
    con = con or sqlite3.connect(DB_PATH)
    try:
        dlat = radius_m / 111320.0
        dlon = radius_m / (111320.0 * max(math.cos(math.radians(lat)), 1e-6))
        rows = con.execute(
            """SELECT id,type,city,address,lat,lon,direction,speed_limit
               FROM cameras
               WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?""",
            (lat - dlat, lat + dlat, lon - dlon, lon + dlon),
        ).fetchall()
    finally:
        if own:
            con.close()

    out = []
    for cid, typ, city, addr, clat, clon, direction, limit in rows:
        d = haversine(lat, lon, clat, clon)
        if d <= radius_m:
            out.append(Camera(cid, typ, city, addr, clat, clon, direction,
                              limit, round(d, 1), round(bearing(lat, lon, clat, clon), 1)))
    out.sort(key=lambda c: c.distance_m)
    return out


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser(description="find nearby speed cameras")
    ap.add_argument("lat", type=float)
    ap.add_argument("lon", type=float)
    ap.add_argument("-r", "--radius", type=float, default=ALERT_RADIUS_M)
    a = ap.parse_args()

    hits = nearby(a.lat, a.lon, a.radius)
    print(f"{len(hits)} camera(s) within {a.radius:.0f} m")
    for c in hits:
        lim = f"{c.speed_limit} km/h" if c.speed_limit else "?"
        print(f"  {c.distance_m:7.1f} m | {lim:>8} | {c.direction or '?':<8} | "
              f"{c.address or c.city or '?'}  [{c.type}]")
