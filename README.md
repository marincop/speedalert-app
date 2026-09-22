# SpeedAlert — 全台測速／科技執法／易肇事路段 限速提醒 App

iOS 原生（SwiftUI）行車提醒 App + Python 資料管線。**離線可用**，接近測速點時以**台灣腔語音**多段提醒。

> 狀態：**MVP 可跑** — 資料載入、查詢、多段提醒（500/300/100/0m）、TTS 播報、深色 UI 全部驗證過；TestFlight 待簽章打包（`ios/release.sh` 已備）。

---

## 目錄結構

```
speed-alert/
├─ build_db.py            # 官方開放資料 → SQLite（cameras/sections/accident_segments）
├─ build_accidents.py     # 交通部事故資料 → 550m 網格熱點 → accident_segments（前 400）
├─ export_app_data.py     # 匯出 data/app_data.{plist,json} → 複製進 iOS Resources
├─ export_geojson.py      # 匯出 GeoJSON（給地圖用，選用）
├─ nearby.py              # proximity 查詢範例（CLI）
├─ data/                  # SQLite + plist/json + geojson（產物）
└─ ios/                   # XcodeGen 專案
   ├─ project.yml         # 專案定義（bundle id / team / icon）
   ├─ build.sh            # 編譯驗證（模擬器，免簽章）
   ├─ run_sim.sh          # 建置+安裝+啟動模擬器+截圖+抓 log（UDID 版）
   ├─ release.sh          # archive + export（+ 可選用 API key 上傳 TestFlight）
   ├─ make_voicepack.sh   # 用 macOS say 生「佔位語音包」（驗證拼接用）
   ├─ VOICEPACK.md        # 真人語音包：23 個 token 錄音清單 + 拼接規則
   ├─ tools/make_icon.py  # 產生 AppIcon（PIL，全尺寸）
   └─ SpeedAlert/         # Swift 原始碼 + Assets + Resources(app_data.plist/json)
```

## 資料來源（政府開放資料，免費授權）
| 資料集 | ID | 內容 |
|---|---|---|
| 測速執法設置點（警政署） | 7320 | 全國測速點 |
| 國道公路固定式測速照相 | 13940 | 國道 |
| 各縣市科技執法／區間測速 | 161880/166354/178168/172725/178086/178357/178140/172905/172178/176021/83881/170673 等 | 12 縣市 |
| 114年傷亡道路交通事故資料 | 177136 | 事故逐案（算熱點） |

合計：**2,671 執法點 + 10 區間測速 + 400 事故熱點**。

## 資料管線
```bash
python3 build_db.py          # 重建執法點（網路抓官方資料）
python3 build_accidents.py --zip /path/to/acc.zip   # 重建事故熱點
python3 export_app_data.py   # 匯出 plist/json 進 ios/SpeedAlert/Resources/
```

## iOS 建置 / 執行
```bash
brew install xcodegen
cd ios
./build.sh          # 編譯驗證（模擬器）
./run_sim.sh        # 跑模擬器 + 截圖到 ~/Desktop/speedalert.png + 印 log
TEAM=你的TeamID ./release.sh   # 出 TestFlight IPA
```

## 關鍵設計
- **提醒距離**：500 / 300 / 100 / 0（通過）公尺，每點每次接近只觸發一次；離開 1.5× 後重置。
- **類型**：固定測速、國道、區間測速、路口科技執法、易肇事路段（可個別開關）。
- **語音**：優先**真人語音包**（`VoicePack/`，模組化拼接）；否則退回系統 TTS（zh-TW 美佳）。
- **離線**：資料編譯進 App（`app_data.plist`），執行時不連網。

## 踩雷筆記（接手必看）
- **離線資料用 binary plist**：Foundation 的 JSON 解析器在 iOS 26 會把這份（合法的）UTF-8 JSON 判成不合法 → 改用 `PropertyListDecoder`；JSON 僅後備。
- **app_data.json 必須在 Resources build phase**：`project.yml` 有明確設定。
- **型別嚴格**：plist 的 Int 欄位不能放 Double（曾因 `_build_sections` 欄位錯位把緯度當速限而爆）。
- **Swift `print` 進不了 `log show`**：診斷請用 `NSLog`（`run_sim.sh` 用 `[SpeedAlert]` tag 過濾）。
- **zsh**：給使用者的指令避免 `!`（history expansion）與 `&&` 長鏈，改多行。

## 授權提醒
- 語音包**只能用原創聲線**（配音員錄新台詞）；**不得**模仿特定真人或受著作權保護的角色聲音。
- 資料為政府開放資料，使用請標示來源。
