#!/bin/bash
# SpeedFilter 假軌跡測試（不需要模擬器、不需要真車）。
#
# 用法：cd ios && ./SpeedFilterTests/run.sh
#
# 為什麼測這個：顯示車速的過濾邏輯過去只能靠老闆真的開車去驗證，
# 每次改完都要上路。編成 macOS 命令列程式後可以餵合成軌跡先驗，
# 通過了再交給人測。
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/../SpeedAlert/Location/SpeedFilter.swift"
OUT="$(mktemp -d)"
xcrun swiftc -O -o "$OUT/run" "$APP" "$HERE/main.swift"
"$OUT/run"
