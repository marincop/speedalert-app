# speed-alert — 全台測速/科技執法限速提醒

資料層 + 查詢邏輯（平台無關）。App 端只負責：拿 GPS → 呼叫附近查詢 → 播報。

## 資料來源（官方開放資料，免費授權）
| 資料集 | ID | 內容 | 筆數 |
|---|---|---|---|
| 測速執法設置點（警政署） | `7320` | 全國各警察機關測速點 | 1895 |
| 國道公路固定式測速照相 | `13940` | 高速公路 | 176 |

合計 **2071 筆，100% 帶速限與座標**。

尚未納入（各縣市獨立資料集，下一階段 merge）：科技執法/路口多功能、區間測速、違規停車偵測、易肇事路段。

## 檔案
- `build_db.py` — 抓資料、正規化、寫入 SQLite。資源網址由 data.gov.tw API 動態解析，不用硬寫死。
- `nearby.py` — proximity 查詢（bounding-box 預篩 + haversine）。
- `export_geojson.py` — 匯出 app 用的 GeoJSON。
- `data/speed_enforcement.db` / `.geojson`

## 用法
```bash
python3 build_db.py          # 重建 DB
python3 nearby.py 25.09 121.55 -r 800   # 查 GPS 附近測速點
python3 export_geojson.py    # 匯出 GeoJSON
```

## 統一 schema
`cameras(id, source, type, city, district, address, lat, lon, direction, speed_limit, dept, raw_json)`
`type`: `fixed_speed` / `highway_speed` /（未來）`interval_speed` / `tech_enforcement`

## 提醒邏輯（App 端）
1. `watchPosition` 每 1-2 秒取一次定位
2. `nearby(lat, lon, ALERT_RADIUS_M=500)` → 最近測速點
3. 若距離 < 門檻且正在接近（bearing 對得上行進方向）→ TTS 播報「前方 500 公尺測速照相，限速 50」
4. 同一支相機 60 秒內不重複播報

## 已知限制
- 只涵蓋「已公布」點位，不含移動式/員警手持測速。
- 行進方向過濾需要手機羅盤/航向，非所有裝置穩定。
- iOS 背景定位限制嚴格；PWA 無法背景常駐。
