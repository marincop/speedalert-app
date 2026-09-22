#!/usr/bin/env python3
"""Derive accident hotspots ("常常肇事路段") from the national crash dataset.

Source: 114年傷亡道路交通事故資料 (dataset 177136) — A1 (fatal) + A2 (injury)
case-level records with WGS84 經度/緯度.

Method: stream the ~600 MB of CSVs, bin every crash into a ~550 m grid cell,
keep the top cells by weighted severity (fatal counts more), and store them as
`accident_segments`. This gives nationwide "hot segment" points in one pass —
no third-party polygon data needed.

Usage: python3 build_accidents.py [--top 400] [--grid 0.005] [--zip /tmp/acc.zip]
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import sqlite3
import zipfile
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DB = ROOT / "data" / "speed_enforcement.db"


def find_col(header: list[str], *names: str) -> int | None:
    for want in names:
        for i, h in enumerate(header):
            if h.strip() == want:
                return i
    return None


def iter_rows(zip_path: Path):
    """Yield (lat, lon, place, city, fatal) for every crash record."""
    with zipfile.ZipFile(zip_path) as z:
        for name in z.namelist():
            if "交通事故資料" not in name or not name.endswith(".csv"):
                continue
            fatal_file = "A1" in name
            with z.open(name) as fh:
                text = io.TextIOWrapper(fh, encoding="utf-8-sig", errors="replace")
                reader = csv.reader(text)
                try:
                    header = next(reader)
                except StopIteration:
                    continue
                ci = find_col(header, "經度")
                cj = find_col(header, "緯度")
                cp = find_col(header, "發生地點")
                cc = find_col(header, "處理單位名稱警局層")
                if ci is None or cj is None:
                    continue
                for row in reader:
                    try:
                        lon = float(row[ci]); lat = float(row[cj])
                    except (ValueError, IndexError):
                        continue
                    if not (21.5 < lat < 25.5 and 119 < lon < 122.5):
                        continue
                    place = row[cp].strip() if cp is not None and cp < len(row) else ""
                    city = row[cc].strip() if cc is not None and cc < len(row) else ""
                    yield lat, lon, place, city, fatal_file


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--zip", default="/tmp/acc.zip")
    ap.add_argument("--top", type=int, default=400)
    ap.add_argument("--grid", type=float, default=0.005)  # ~550 m cell
    a = ap.parse_args()

    cells = defaultdict(lambda: {"n": 0, "fatal": 0, "lat": 0.0, "lon": 0.0,
                                 "places": Counter(), "city": ""})
    total = 0
    for lat, lon, place, city, fatal in iter_rows(Path(a.zip)):
        total += 1
        key = (round(lat / a.grid), round(lon / a.grid))
        c = cells[key]
        c["n"] += 1
        c["fatal"] += 1 if fatal else 0
        c["lat"] += lat
        c["lon"] += lon
        if place:
            c["places"][place] += 1
        if city and not c["city"]:
            c["city"] = city

    # severity score: fatal weighted 5x, injuries 1x
    ranked = sorted(cells.items(),
                    key=lambda kv: kv[1]["fatal"] * 5 + kv[1]["n"], reverse=True)

    con = sqlite3.connect(DB)
    con.execute("DELETE FROM accident_segments")
    rows = []
    for i, (_, c) in enumerate(ranked[:a.top], start=1):
        lat = c["lat"] / c["n"]
        lon = c["lon"] / c["n"]
        name = c["places"].most_common(1)[0][0] if c["places"] else ""
        score = c["fatal"] * 5 + c["n"]
        city = _clean_city(c["city"])
        rows.append((f"npa:177136", f"{name}", city, round(lat, 6), round(lon, 6),
                     f"{c['n']}件(死{c['fatal']})", 2025,
                     json.dumps({"score": score, "cases": c["n"], "fatal": c["fatal"]},
                                ensure_ascii=False)))
    con.executemany(
        "INSERT INTO accident_segments (source,name,city,lat,lon,severity,year,raw_json)"
        " VALUES (?,?,?,?,?,?,?,?)", rows)
    con.commit()
    con.close()
    print(f"parsed {total} crash records -> {len(cells)} cells -> "
          f"top {len(rows)} hotspots stored")
    for r in rows[:8]:
        print(f"   {r[5]:>12} | {r[2]} | {r[1][:30]} | ({r[3]},{r[4]})")


def _clean_city(s: str) -> str:
    for suffix in ("政府警察局", "警察局", "政府"):
        if s.endswith(suffix):
            return s[: -len(suffix)]
    return s


if __name__ == "__main__":
    main()
