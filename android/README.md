# SpeedAlert — Android（Kotlin + Jetpack Compose）

iOS 版的 1:1 移植：**離線**、接近測速點時多段語音提醒（500/300/100/0m）。

## 需求
- Android Studio（Ladybug 或更新）/ JDK 17+
- `compileSdk 35`、`minSdk 26`

## 建置
```bash
# 用 Android Studio：Open → 選 android/ 資料夾 → 等 Gradle sync → Run ▶
# 或 CLI（需 Android SDK）：
cd android
gradle wrapper        # 首次若沒有 gradlew（或用 Android Studio 產生）
./gradlew :app:assembleDebug
./gradlew :app:installDebug       # 接手機/模擬器
```

> 註：本專案在 Linux（無 Android SDK）撰寫，**尚未實機編譯驗證**；若 Gradle/AGP 版本不符，Android Studio 會提示自動修正。

## 結構
```
android/app/src/main/
├─ AndroidManifest.xml            # 定位/前景服務權限
├─ assets/app_data.json           # 離線資料（與 iOS 同一份）
├─ java/tw/speedalert/
│  ├─ MainActivity.kt
│  ├─ AppViewModel.kt             # 串接 store/定位/提醒/語音（對應 iOS AppModel）
│  ├─ model/Models.kt             # EnforcementKind/Item（對應 iOS）
│  ├─ data/EnforcementStore.kt    # 讀 assets JSON + 網格就近查詢
│  ├─ alert/AlertEngine.kt        # 多段提醒 + 通過偵測 + 中文語句 + 語音 token
│  ├─ speech/{SpeechService,VoicePack}.kt   # TTS(zh-TW) + 真人語音包
│  ├─ location/{DrivingService,LocationBus}.kt  # 前景服務背景定位
│  └─ ui/{Theme,ContentScreen}.kt # Compose 深色 UI（對應 iOS ContentView）
└─ res/…                          # strings/themes/mipmap 圖示
```

## 語音
- 優先 **真人語音包**：`assets/VoicePack/<token>.m4a`（清單同 iOS `../ios/VOICEPACK.md`）
- 否則退回系統 **TTS zh-TW**

## 與 iOS 的差異
- 定位用 **LocationManager + 前景服務**（iOS 用 CoreLocation 背景模式）。
- 圖示與 App Icon 由 `tools/make_icons.py` 從 iOS 1024 icon 產生。
- 沒有 Foundation JSON quirk，直接用 `org.json` 讀 `app_data.json`（ASCII-safe）。

## 待辦
- 上架用 keystore 設定（`signingConfigs`）。
- 背景提醒調校（Doze/電池優化）、通知權限說明。
