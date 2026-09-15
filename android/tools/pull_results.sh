#!/bin/sh
# 把手機上對照測試(CrossTest)寫在 app 私有目錄的 results_*.json 拉回 ../results/android/
# 需要 debug build(run-as 只對 debuggable app 有效)。用法:android/tools/pull_results.sh
set -e
ADB=${ADB:-adb}
PKG=app.aming.gemma4
OUT="$(cd "$(dirname "$0")/.." && pwd)/../results/android"
mkdir -p "$OUT"
FILES=$($ADB shell run-as $PKG ls files/crosstest 2>/dev/null | tr -d '\r' | grep '^results_.*\.json$' || true)
[ -z "$FILES" ] && { echo "手機上沒有結果檔(files/crosstest 為空)"; exit 1; }
for f in $FILES; do
  $ADB shell run-as $PKG cat "files/crosstest/$f" > "$OUT/$f"
  echo "pulled $f"
done
ls -1 "$OUT"/results_*.json
