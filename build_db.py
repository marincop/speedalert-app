#!/usr/bin/env python3
"""Build the Taiwan enforcement database (v2).

Sources (official open data, free license):
  national:
    7320  測速執法設置點（警政署，全國）
    13940 國道公路固定式測速照相地點
  county (科技執法 / 區間測速, fragmented per-city):
    161880 高雄市路口科技執法   -> tech_intersection
    178168 桃園市科技執法設備   -> tech_intersection
    172725 臺中市區間平均速率   -> interval_speed

Records are normalized into:
  cameras          — point enforcement (any kind)
  sections         — interval-speed stretches (start/end, length, limit)
  accident_segments— 易肇事路段 (交通事故熱點)

Notes:
  - Dataset resource URLs rotate; we resolve the *current* download URL
    from the data.gov.tw metadata API instead of hardcoding.
  - Interval-speed detection: 7320 already tags some rows "區間測速" in the
    address field, so we classify those without a separate source.
"""
from __future__ import annotations

import csv
import io
import json
import re
import sqlite3
import ssl
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DB_PATH = ROOT / "data" / "speed_enforcement.db"
UA = "speed-alert/0.1 (+https://data.gov.tw)"

SCHEMA = """
DROP TABLE IF EXISTS cameras;
DROP TABLE IF EXISTS sections;
DROP TABLE IF EXISTS accident_segments;
DROP TABLE IF EXISTS meta;
CREATE TABLE cameras (
    id           INTEGER PRIMARY KEY,
    source       TEXT NOT NULL,
    kind         TEXT NOT NULL,   -- fixed_speed|interval_speed|tech_intersection|tech_other|highway_speed
    city         TEXT,
    district     TEXT,
    address      TEXT,
    lat          REAL NOT NULL,
    lon          REAL NOT NULL,
    direction    TEXT,
    speed_limit  INTEGER,
    dept         TEXT,
    raw_json     TEXT
);
CREATE INDEX idx_cameras_latlon ON cameras(lat, lon);
CREATE INDEX idx_cameras_kind   ON cameras(kind);
CREATE TABLE sections (          -- 區間測速: a monitored stretch
    id          INTEGER PRIMARY KEY,
    source      TEXT NOT NULL,
    name        TEXT,
    city        TEXT,
    speed_limit INTEGER,
    start_lat   REAL, start_lon REAL,
    end_lat     REAL, end_lon   REAL,
    length_m    REAL,
    raw_json    TEXT
);
CREATE TABLE accident_segments ( -- 易肇事路段 / 事故熱點
    id          INTEGER PRIMARY KEY,
    source      TEXT NOT NULL,
    name        TEXT,
    city        TEXT,
    lat         REAL, lon REAL,
    severity    TEXT,
    year        INTEGER,
    raw_json    TEXT
);
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
"""

COUNTY_SOURCES = [
    # (dataset_id, kind)  city-level tech-enforcement datasets
    ("161880", "tech_intersection"),   # 高雄市路口科技執法
    ("166354", "tech_intersection"),   # 高雄市交通局科技執法
    ("178168", "tech_intersection"),   # 桃園市科技執法設備
    ("172725", "interval_speed"),      # 臺中市區間平均速率
    ("178086", "tech_other"),          # 雲林縣科技執法
    ("178357", "tech_other"),          # 雲林縣科技執法(新)
    ("178140", "tech_other"),          # 嘉義縣固定式科技執法
    ("172905", "tech_other"),          # 彰化縣固定式科技執法
    ("172178", "tech_other"),          # 苗栗縣科技執法
    ("172687", "tech_other"),          # 臺東縣固定式+科技執法
    ("128438", "tech_other"),          # 宜蘭縣固定式科學儀器
    ("176021", "tech_other"),          # 南投縣固定式科技執法
    ("83881",  "tech_other"),          # 臺中市科學儀器(固定式)
    ("170673", "tech_other"),          # 臺中市科技執法
]

LAT_COLS = ("Latitude", "latitude", "lat", "緯度", "座標緯度", "y", "Y")
LON_COLS = ("Longitude", "longitude", "lon", "lng", "經度", "座標經度", "x", "X")
ADDR_COLS = ("Address", "address", "設置地點", "設置位置", "地點", "設置地點_取締道路",
             "設置地點_範圍", "設置區域描述", "路口名稱", "位置")
LIMIT_COLS = ("limit", "速限", "速限_公里", "速限(公里)", "速限_公里小時")
DIR_COLS = ("direct", "拍攝方向", "測照行向", "方向", "取締方向")
CITY_COLS = ("CityName", "縣市", "city", "行政區")


# ---------------------------------------------------------------- transport
def _ssl_ctx() -> ssl.SSLContext:
    ctx = ssl.create_default_context()
    ctx.verify_flags &= ~ssl.VERIFY_X509_STRICT  # gov certs w/o SKI
    return ctx


def fetch(url: str) -> bytes:
    url = urllib.parse.quote(url, safe=":/?&=%~+,")
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.read()
    except urllib.error.URLError as e:
        if not isinstance(getattr(e, "reason", None), ssl.SSLError):
            raise
        try:
            with urllib.request.urlopen(req, timeout=60, context=_ssl_ctx()) as r:
                return r.read()
        except urllib.error.URLError:
            return subprocess.run(["curl", "-sL", "-A", UA, url],
                                  check=True, capture_output=True).stdout


def dataset_meta(dataset_id: str) -> dict:
    return json.loads(fetch(f"https://data.gov.tw/api/v2/rest/dataset/{dataset_id}"))["result"]


def download_url(dataset_id: str) -> str:
    dists = dataset_meta(dataset_id).get("distribution", [])
    # prefer CSV over JSON/XML (Chinese-column CSVs map cleanly)
    for want in ("CSV", "ZIP", "JSON", "XML"):
        for dist in dists:
            if (dist.get("resourceFormat") or "").upper() == want \
                    and dist.get("resourceDownloadUrl"):
                return dist["resourceDownloadUrl"]
    for dist in dists:
        if dist.get("resourceDownloadUrl"):
            return dist["resourceDownloadUrl"]
    raise RuntimeError(f"no download url for {dataset_id}")


# ---------------------------------------------------------------- parsing
def to_float(v):
    try:
        f = float(str(v).strip().replace(",", ""))
        return f if f else None
    except (TypeError, ValueError):
        return None


def to_int(v):
    try:
        return int(float(str(v).strip()))
    except (TypeError, ValueError):
        return None


def read_rows(blob: bytes) -> list[dict]:
    if blob[:2] == b"PK":
        with zipfile.ZipFile(io.BytesIO(blob)) as z:
            name = next(n for n in z.namelist() if n.lower().endswith(".csv"))
            blob = z.read(name)
    for enc in ("utf-8-sig", "utf-8", "big5", "cp950"):
        try:
            text = blob.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    else:
        text = blob.decode("utf-8", errors="replace")
    return list(csv.DictReader(io.StringIO(text)))


def pick(row: dict, names) -> str | None:
    for n in names:
        if n in row and row[n] not in (None, ""):
            return str(row[n]).strip()
    return None


def coord(row: dict):
    """Return (lat, lon) or (None, None); handles combined 'lat,lon' columns."""
    lat = to_float(pick(row, LAT_COLS))
    lon = to_float(pick(row, LON_COLS))
    if lat is not None and lon is not None:
        return lat, lon
    for v in row.values():
        m = re.match(r"^\s*(-?\d{1,2}\.\d+)\s*[,; ]\s*(-?\d{1,3}\.\d+)\s*$", str(v))
        if m:
            a, b = float(m.group(1)), float(m.group(2))
            return (a, b) if abs(a) < abs(b) else (b, a)  # lat<lon in TW
    return None, None


def classify_interval(addr: str | None, kind: str) -> str:
    if kind == "interval_speed":
        return "interval_speed"
    if addr and "區間" in addr:
        return "interval_speed"
    return kind


# ---------------------------------------------------------------- normalizers
def norm_national_7320(rows):
    for r in rows:
        city = pick(r, CITY_COLS)
        lat, lon = to_float(r.get("Latitude")), to_float(r.get("Longitude"))
        if not city or city == "設置縣市" or lat is None or lon is None:
            continue
        addr = pick(r, ADDR_COLS)
        yield dict(source="npa:7320", kind=classify_interval(addr, "fixed_speed"),
                   city=city, district=pick(r, ("RegionName",)) or None,
                   address=addr, lat=lat, lon=lon,
                   direction=pick(r, DIR_COLS), speed_limit=to_int(r.get("limit")),
                   dept=pick(r, ("DeptNm",)), raw_json=json.dumps(r, ensure_ascii=False))


def norm_national_13940(rows):
    for r in rows:
        lat, lon = coord(r)
        if lat is None:
            continue
        yield dict(source="npa:13940", kind="highway_speed",
                   city=pick(r, ("縣市",)), district=pick(r, ("行政區",)),
                   address=pick(r, ("設置地點", "設置區域描述")), lat=lat, lon=lon,
                   direction=pick(r, DIR_COLS), speed_limit=to_int(pick(r, ("速限",))),
                   dept=pick(r, ("管轄單位",)), raw_json=json.dumps(r, ensure_ascii=False))


def norm_county(rows, ds_id: str, kind: str):
    for r in rows:
        lat, lon = coord(r)
        if lat is None:
            continue
        addr = pick(r, ADDR_COLS)
        yield dict(source=f"tw:{ds_id}", kind=classify_interval(addr, kind),
                   city=pick(r, CITY_COLS), district=None, address=addr,
                   lat=lat, lon=lon, direction=pick(r, DIR_COLS),
                   speed_limit=to_int(pick(r, LIMIT_COLS)) or _limit_from_text(addr),
                   dept=None, raw_json=json.dumps(r, ensure_ascii=False))


def _limit_from_text(s: str | None) -> int | None:
    """Interval datasets bury the limit in free text, e.g. '速限50公里'."""
    if not s:
        return None
    m = re.search(r"速限\s*(\d{2,3})", s)
    return int(m.group(1)) if m else None


# ---------------------------------------------------------------- build
BUILDERS = {
    "7320": norm_national_7320,
    "13940": norm_national_13940,
}


def build() -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(DB_PATH)
    con.executescript(SCHEMA)
    counts = {}

    for ds_id, builder in BUILDERS.items():
        url = download_url(ds_id)
        recs = list(builder(read_rows(fetch(url))))
        _insert_cameras(con, recs)
        counts[f"npa:{ds_id}"] = len(recs)
        print(f"[{ds_id}] {len(recs)} rows")

    for ds_id, kind in COUNTY_SOURCES:
        try:
            url = download_url(ds_id)
            recs = list(norm_county(read_rows(fetch(url)), ds_id, kind))
            _insert_cameras(con, recs)
            counts[f"tw:{ds_id}"] = len(recs)
            print(f"[{ds_id}] {kind} -> {len(recs)} rows")
        except Exception as e:  # a broken county source must not kill the build
            print(f"[{ds_id}] SKIP ({e})")

    # interval-speed stretches: derive from any camera classified as interval
    _build_sections(con)

    total = con.execute("SELECT COUNT(*) FROM cameras").fetchone()[0]
    by_kind = dict(con.execute("SELECT kind,COUNT(*) FROM cameras GROUP BY kind"))
    con.execute("INSERT INTO meta VALUES ('built_at', datetime('now'))")
    con.execute("INSERT INTO meta VALUES ('total', ?)", (str(total),))
    con.commit()
    con.close()
    print(f"done: {total} cameras {by_kind}")
    for k, v in counts.items():
        print(f"   {k}: {v}")


def _insert_cameras(con, recs):
    con.executemany(
        """INSERT INTO cameras
           (source,kind,city,district,address,lat,lon,direction,speed_limit,dept,raw_json)
           VALUES (:source,:kind,:city,:district,:address,:lat,:lon,
                   :direction,:speed_limit,:dept,:raw_json)""", recs)


def _build_sections(con):
    """Every interval-speed camera also becomes a monitored stretch record."""
    rows = con.execute(
        "SELECT source,address,city,speed_limit,lat,lon,raw_json FROM cameras "
        "WHERE kind='interval_speed'").fetchall()
    con.executemany(
        "INSERT INTO sections (source,name,city,speed_limit,start_lat,start_lon,raw_json)"
        " VALUES (?,?,?,?,?,?,?)", rows)
    print(f"sections: {len(rows)} interval-speed stretches")


if __name__ == "__main__":
    sys.exit(build())
