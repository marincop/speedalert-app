# SpeedAlert（iOS）— 全台測速／科技執法／易肇事路段提醒

SwiftUI 原生 iOS App。**離線可用**：所有資料點編譯進 App，執行時不連網。
提醒類型：固定／國道測速、**區間測速**、**路口科技執法**、**易肇事路段**。
提醒距離：**500 / 300 / 100 / 0（通過）** 公尺，多段語音播報。

## 目錄
```
ios/
├─ project.yml                     # XcodeGen 專案定義
├─ SpeedAlert/
│  ├─ Info.plist                   # 背景定位 + 背景音訊權限
│  ├─ SpeedAlertApp.swift
│  ├─ Models/EnforcementItem.swift # 資料模型 + JSON 解碼
│  ├─ Data/EnforcementStore.swift  # 離線載入 + 網格索引 + 就近查詢
│  ├─ Location/LocationService.swift
│  ├─ Alert/AlertEngine.swift      # 多段提醒 + 通過偵測 + 中文語句
│  ├─ Speech/SpeechService.swift   # zh-TW（台灣腔）TTS
│  ├─ App/AppModel.swift           # 串接：定位→查詢→提醒→語音
│  └─ Views/{ContentView,SettingsView}.swift
└─ README.md
```

## 建置（需要 macOS + Xcode）
```bash
brew install xcodegen          # 一次性
cd ios
xcodegen generate              # 由 project.yml 產生 SpeedAlert.xcodeproj
open SpeedAlert.xcodeproj
```
1. Xcode → 選 target `SpeedAlert` → Signing & Capabilities → 選你的 **Team**（並在 `project.yml` 填 `DEVELOPMENT_TEAM`）。
2. 接上 iPhone，選該裝置，按 ▶︎ 執行。
3. 首次啟動會要求定位權限 → 選 **永遠允許**（背景提醒需要）。
4. 背景模式已在 Info.plist 開好 `location` 與 `audio`。

> 註：程式碼在 Linux 上撰寫，**尚未在 Xcode 編譯驗證**；若編譯有誤，多半是 API 版本差異，回報即可修。

## 語音（台灣腔）
- 內建 `AVSpeechSynthesisVoice(language: "zh-TW")` → **美佳（Mei-Jia）**，台灣國語，離線、免費、免 API key。
- 想要更好聽：iOS 設定 ▸ 輔助使用 ▸ 朗讀內容 ▸ 聲音 ▸ 中文（台灣）→ 下載 **增強／進階** 版本，App 會自動優先選用。
- 想要「真人錄音語音包」：可另外錄製固定語句（500/300/100m、通過、各種限速）打包成音檔；`SpeechService` 已預留可替換點。

## 提醒邏輯
1. `LocationService` 每次定位（背景也收）
2. `EnforcementStore.nearby()` 取 600m 內資料點（含種類過濾）
3. `AlertEngine` 對每點在 500/300/100m 各觸發一次；距離由小變大且 <60m → 判定「通過」觸發 0m
4. `SpeechService` 播報，例：**「前方三百公尺測速照相，限速五十公里」**、**「已通過區間測速」**
5. 同一點離開 1.5× 最大門檻後重置 → 下一趟再提醒

## 資料
- 由 `../build_db.py` 產生，`../export_app_data.py` 匯出成 `SpeedAlert/Resources/app_data.json`。
- 目前涵蓋：警政署全國測速（7320）、國道（13940）、桃園／高雄科技執法、臺中區間測速。
- 待補：其餘縣市科技執法、違停偵測、易肇事路段（交通部）。
