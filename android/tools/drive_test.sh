#!/bin/bash
# Drives the NLU test app on a connected device: selects the given model
# segment, waits for AVAILABLE, taps each sample chip and waits for its
# inference to finish, then prints the GemmaNlu logcat (timings + raw JSON).
# Usage: tools/drive_test.sh ["Full (E4B)" | "Fast (E2B)"]
MODEL="${1:-Full (E4B)}"
ADB=${ADB:-adb}   # 找不到 adb 時設環境變數 ADB=/path/to/platform-tools/adb

dump() { $ADB shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; $ADB shell cat /sdcard/ui.xml 2>/dev/null; }

tap_text() {
  dump | python3 -c "
import re,sys
xml=sys.stdin.read()
for m in re.finditer(r'text=\"([^\"]*)\"[^>]*bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"', xml):
    if '$1' in m.group(1):
        x=(int(m.group(2))+int(m.group(4)))//2; y=(int(m.group(3))+int(m.group(5)))//2
        print(x,y); break
" | { read X Y; [ -n "$X" ] && $ADB shell input tap $X $Y && echo "tapped '$1' at $X,$Y" || echo "NOT FOUND: $1"; }
}

status_text() { dump | grep -oE '狀態:[^"]*' | head -1; }

$ADB logcat -c
$ADB shell am force-stop app.aming.gemma4
$ADB shell am start -n app.aming.gemma4/.MainActivity >/dev/null
sleep 5
tap_text "$MODEL"
for i in $(seq 1 10); do
  sleep 3
  S=$(status_text)
  echo "status: $S"
  case "$S" in *可用*) break ;; esac
done
case "$(status_text)" in
  *可用*) ;;
  *) echo "ABORT: model not available"; exit 1 ;;
esac
dump | grep -oE 'base model:[^"]*'

COUNT=0
for chip in "午餐花了一百二" "薪水入帳五萬八" "台積電改成" "00878" "金價一盎司" "上週五看電影" "從西嶺轉兩萬三"; do
  tap_text "$chip"
  COUNT=$((COUNT+1))
  DONE=0
  for t in $(seq 1 60); do
    sleep 3
    N=$($ADB logcat -d -s GemmaNlu 2>/dev/null | grep -cE 'classify done|classify failed')
    if [ "$N" -ge "$COUNT" ]; then DONE=1; break; fi
  done
  echo "-- run $COUNT done=$DONE after $((t*3))s --"
done
echo "== GemmaNlu log =="
$ADB logcat -d -s GemmaNlu | grep -vE '	at |Caused by'
