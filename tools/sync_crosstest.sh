#!/bin/sh
# 把 nlu_crosstest/ 的凍結素材同步到兩個平台 app 實際載入的位置。
# 素材只在 nlu_crosstest/ 修改；改完跑一次本腳本。
#   tools/sync_crosstest.sh          # 複製
#   tools/sync_crosstest.sh --check  # 只比對，不一致就 exit 1（可放 CI）
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/nlu_crosstest"
pairs="
$SRC/system_prompt_zh-TW.txt|$ROOT/ios/nlu_crosstest/system_prompt_zh-TW.txt
$SRC/testcases.json|$ROOT/ios/nlu_crosstest/testcases.json
$SRC/system_prompt_zh-TW.txt|$ROOT/android/app/src/main/assets/crosstest/system_prompt_zh-TW.txt
$SRC/testcases.json|$ROOT/android/app/src/main/assets/crosstest/testcases.json
$SRC/dev_accounts_2026-08-22.json|$ROOT/android/app/src/main/assets/dev_accounts.json
$SRC/dev_categories_2026-08-22.json|$ROOT/android/app/src/main/assets/dev_categories.json
"
rc=0
echo "$pairs" | while IFS='|' read -r src dst; do
  [ -z "$src" ] && continue
  if [ "$1" = "--check" ]; then
    if cmp -s "$src" "$dst"; then echo "ok    ${dst#$ROOT/}"; else echo "DIFF  ${dst#$ROOT/}"; exit 1; fi
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"; echo "synced ${dst#$ROOT/}"
  fi
done
