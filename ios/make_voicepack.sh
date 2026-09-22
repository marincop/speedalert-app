#!/usr/bin/env bash
# Generate a PLACEHOLDER voice pack with macOS `say`, so you can test the
# concatenation pipeline before real studio recordings exist.
# Replace the produced files (same names) with the voice actor's recordings.
set -euo pipefail
cd "$(dirname "$0")"

OUT="SpeedAlert/Resources/VoicePack"
mkdir -p "$OUT"
VOICE="${VOICE:-Meijia}"          # zh-TW; list voices: say -v '?' | grep zh_TW

clip() { # token  text
  say -v "$VOICE" -o "$OUT/$1.aiff" "$2"
  afconvert -f m4af -d aac "$OUT/$1.aiff" "$OUT/$1.m4a"
  rm -f "$OUT/$1.aiff"
  echo "  $1.m4a  <- $2"
}

echo "==> generating placeholder voice pack (voice: $VOICE)"
clip lead_front     "前方"
clip unit_m         "公尺"
clip limit_pre      "限速"
clip limit_post     "公里"
clip passed         "已通過"
clip accident_warn  "請小心駕駛"
clip dist_500       "五百"
clip dist_300       "三百"
clip dist_100       "一百"
clip kind_fixed     "測速照相"
clip kind_interval  "區間測速"
clip kind_tech      "科技執法"
clip kind_accident  "易肇事路段"
clip num_25         "二十五"
clip num_30         "三十"
clip num_40         "四十"
clip num_50         "五十"
clip num_60         "六十"
clip num_70         "七十"
clip num_80         "八十"
clip num_90         "九十"
clip num_100        "一百"
clip num_110        "一百一十"
echo "==> done: $(ls "$OUT" | wc -l | tr -d ' ') files in $OUT"
