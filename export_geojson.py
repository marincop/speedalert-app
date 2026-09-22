#!/usr/bin/env python3
"""Export the enforcement DB to GeoJSON for app consumption (map / offline pack)."""
import json
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DB = ROOT / "data" / "speed_enforcement.db"
OUT = ROOT / "data" / "speed_enforcement.geojson"

con = sqlite3.connect(DB)
feats = []
for cid, typ, city, dist, addr, lat, lon, direction, limit in con.execute(
        "SELECT id,type,city,district,address,lat,lon,direction,speed_limit FROM cameras"):
    feats.append({
        "type": "Feature",
        "geometry": {"type": "Point", "coordinates": [lon, lat]},
        "properties": {"id": cid, "type": typ, "city": city, "district": dist,
                       "address": addr, "direction": direction, "speed_limit": limit},
    })
con.close()
OUT.write_text(json.dumps({"type": "FeatureCollection", "features": feats},
                          ensure_ascii=False), encoding="utf-8")
print(f"{len(feats)} features -> {OUT} ({OUT.stat().st_size} bytes)")
