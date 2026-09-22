#!/usr/bin/env python3
"""Export an app-ready offline dataset for the iOS app.

Outputs BOTH:
  data/app_data.plist  (binary property list — primary; parsed by PropertyListDecoder)
  data/app_data.json   (fallback; parsed by JSONDecoder)
and copies them into ios/SpeedAlert/Resources/.

Why plist: Foundation's JSON parser rejected our otherwise-valid UTF-8 JSON on
iOS 26; the plist parser is rock-solid for bundled data. plists have no null,
so `None` fields are omitted (Swift optionals decode as nil).
"""
from __future__ import annotations

import json
import plistlib
import shutil
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DB = ROOT / "data" / "speed_enforcement.db"
OUT_JSON = ROOT / "data" / "app_data.json"
OUT_PLIST = ROOT / "data" / "app_data.plist"
IOS_RES = ROOT / "ios" / "SpeedAlert" / "Resources"


def strip_none(o):
    if isinstance(o, dict):
        return {k: strip_none(v) for k, v in o.items() if v is not None}
    if isinstance(o, list):
        return [strip_none(v) for v in o]
    return o


def main() -> None:
    con = sqlite3.connect(DB)
    meta = dict(con.execute("SELECT key, value FROM meta"))

    cameras = [
        {"id": int(i), "kind": k, "lat": float(lat), "lon": float(lon),
         "limit": (int(lim) if lim is not None else None),
         "dir": d, "addr": a, "city": c}
        for i, k, lat, lon, lim, d, a, c in con.execute(
            "SELECT id,kind,lat,lon,speed_limit,direction,address,city FROM cameras")
    ]
    sections = [
        {"id": int(i), "name": n, "city": c,
         "limit": (int(lim) if lim is not None else None),
         "lat": float(la), "lon": float(lo), "endLat": None, "endLon": None,
         "length": (float(ln) if ln is not None else None)}
        for i, n, c, lim, la, lo, ln in con.execute(
            "SELECT id,name,city,speed_limit,start_lat,start_lon,length_m FROM sections")
    ]
    accidents = [
        {"id": int(i), "name": n, "city": c, "lat": float(la), "lon": float(lo), "severity": s}
        for i, n, c, la, lo, s in con.execute(
            "SELECT id,name,city,lat,lon,severity FROM accident_segments")
    ]
    con.close()

    payload = {
        "schema": 1,
        "built_at": meta.get("built_at"),
        "cameras": cameras,
        "sections": sections,
        "accidents": accidents,
    }

    # JSON (ASCII-safe to dodge any raw-UTF8 parser quirks)
    OUT_JSON.write_text(json.dumps(payload, ensure_ascii=True, separators=(",", ":")),
                        encoding="utf-8")

    # Binary plist (primary)
    with OUT_PLIST.open("wb") as fh:
        plistlib.dump(strip_none(payload), fh, fmt=plistlib.FMT_BINARY)

    if IOS_RES.exists():
        shutil.copy(OUT_JSON, IOS_RES / "app_data.json")
        shutil.copy(OUT_PLIST, IOS_RES / "app_data.plist")
        print(f"copied -> {IOS_RES}")

    print(f"{len(cameras)} cameras, {len(sections)} sections, {len(accidents)} accidents")
    print(f"  json : {OUT_JSON.stat().st_size} bytes")
    print(f"  plist: {OUT_PLIST.stat().st_size} bytes")


if __name__ == "__main__":
    main()
