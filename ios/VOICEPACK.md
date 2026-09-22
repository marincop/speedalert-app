# VOICEPACK — 真人語音包（可替換聲線）

App 播報優先用**語音包**（事先錄好的短音檔，拼接播放）；找不到就退回系統 TTS。

## 檔案放哪
- **打包進 App**：`ios/SpeedAlert/Resources/VoicePack/<token>.m4a`
- **免重編、直接丟**（推薦先這樣測）：App 的 `Documents/VoicePack/<token>.m4a`
  （模擬器路徑：`xcrun simctl get_app_container <UDID> tw.speedalert.app data`/Documents/VoicePack）

格式：`m4a` 優先，也吃 `caf / wav / mp3 / aiff`。

## 要錄的 23 個檔（檔名 = token）

| token | 台詞 | 備註 |
|---|---|---|
| `lead_front` | 前方 | 錨點（有它才算語音包就緒） |
| `unit_m` | 公尺 | |
| `limit_pre` | 限速 | |
| `limit_post` | 公里 | |
| `passed` | 已通過 | |
| `accident_warn` | 請小心駕駛 | |
| `dist_500` | 五百 | |
| `dist_300` | 三百 | |
| `dist_100` | 一百 | |
| `kind_fixed` | 測速照相 | 固定式 + 國道 |
| `kind_interval` | 區間測速 | |
| `kind_tech` | 科技執法 | 路口多功能等 |
| `kind_accident` | 易肇事路段 | |
| `num_25` | 二十五 | |
| `num_30` | 三十 | |
| `num_40` | 四十 | |
| `num_50` | 五十 | |
| `num_60` | 六十 | |
| `num_70` | 七十 | |
| `num_80` | 八十 | |
| `num_90` | 九十 | |
| `num_100` | 一百 | |
| `num_110` | 一百一十 | |

> 錄音建議：**每個檔吞頭尾 0.1s 靜音、口氣一致、取樣一致**（拼接才順）。命名用小寫 token + 副檔名。

## 拼接規則（App 自動組句）
- 接近：`lead_front` + `dist_*` + `unit_m` + `kind_*` + (`limit_pre` + `num_*` + `limit_post`)
  → 「前方 三百 公尺 測速照相 限速 五十 公里」
- 易肇事：`lead_front` + `dist_*` + `unit_m` + `kind_accident` + `accident_warn`
- 通過：`passed` + `kind_*` → 「已通過 測速照相」

## 佔位語音包（測試管線用）
在 Mac 上跑 `./make_voicepack.sh`，會用系統 `say` 產生上面 23 個檔案（品質＝TTS，只為驗證拼接）。
之後把配音員的檔案**同名覆蓋**即可。

## 授權提醒 ⚠️
- 只能用**原創聲線**（找配音員錄新台詞），**不得**模仿/複製特定真人（如名人）或**受著作權保護的角色聲音**（如動畫角色）。商業發佈須取得該配音員/錄音授權。
