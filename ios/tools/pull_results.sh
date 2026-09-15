#!/bin/zsh
# 把 iPhone 上 llm_test app Documents 裡的 results_*.json 拉回 ../results/ios/
# 用法：ios/tools/pull_results.sh [device-udid]
#   device-udid 可省略：改讀環境變數 IOS_DEVICE；都沒有就用 `xcrun devicectl list devices` 的第一台
set -e
cd "$(dirname "$0")/.."
BUNDLE=app.aming.llm-test
OUT=../results/ios
DEVICE="${1:-${IOS_DEVICE:-}}"
if [ -z "$DEVICE" ]; then
  DEVICE=$(xcrun devicectl list devices 2>/dev/null | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1)
  [ -z "$DEVICE" ] && { echo "找不到裝置：請傳入 UDID 或設定 IOS_DEVICE（xcrun devicectl list devices）"; exit 1; }
fi
mkdir -p "$OUT"
rm -rf "$OUT/_pull"; mkdir -p "$OUT/_pull"
xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
  --source Documents --destination "$OUT/_pull" 2>&1 | grep -iE "error" || true
find "$OUT/_pull" -name 'results_*.json' -exec cp {} "$OUT/" \;
rm -rf "$OUT/_pull"
ls -1 "$OUT"/results_*.json 2>/dev/null || echo "(no result files)"
