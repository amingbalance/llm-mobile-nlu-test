#!/bin/bash
# Drives the PDF tab: password -> pick file (by name substring) -> doc type -> run.
# Usage: tools/drive_pdf.sh <file-name-substring> [password] [doc-type-label] [mode-label]
FILE_SUB="$1"; PASS="${2:-}"; DOCTYPE="${3:-自動判斷}"; MODE="${4:-自動}"
ADB=${ADB:-adb}   # 找不到 adb 時設環境變數 ADB=/path/to/platform-tools/adb
dump() { $ADB shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; $ADB shell cat /sdcard/ui.xml 2>/dev/null; }
# find_xy <text> [exact] : center of first node whose text contains (or equals) <text>
find_xy() { dump | python3 -c "
import re,sys
xml=sys.stdin.read(); q='$1'; exact='$2'=='exact'
for m in re.finditer(r'<node[^>]*text=\"([^\"]*)\"[^>]*bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"', xml):
    t=m.group(1)
    if (t==q) if exact else (q in t):
        print((int(m.group(2))+int(m.group(4)))//2,(int(m.group(3))+int(m.group(5)))//2); break
"; }
tap_text() { read X Y < <(find_xy "$1" "$2"); if [ -n "$X" ]; then $ADB shell input tap $X $Y; echo "tapped '$1' at $X,$Y"; else echo "NOT FOUND: $1"; return 1; fi; }
# tap_scroll <exact text> : scroll down in small steps until the node is on screen, then tap
tap_scroll() {
  for i in 1 2 3 4 5 6; do
    read X Y < <(find_xy "$1" exact)
    if [ -n "$X" ] && [ "$Y" -lt 2900 ]; then $ADB shell input tap $X $Y; echo "tapped '$1' at $X,$Y"; return 0; fi
    $ADB shell input swipe 600 2000 600 1500 300; sleep 2
  done
  echo "NOT FOUND: $1"; return 1
}

$ADB logcat -c
$ADB shell input keyevent 4; sleep 1; $ADB shell input keyevent 4; sleep 1   # dismiss any picker/dialog
$ADB shell am force-stop app.aming.gemma4; sleep 1
$ADB shell am start -n app.aming.gemma4/.MainActivity >/dev/null; sleep 5
tap_text "PDF 文件" exact || exit 1; sleep 2
dump | grep -q '選擇 PDF' || { echo "ABORT: not on PDF tab"; exit 1; }
if [ -n "$PASS" ]; then
  tap_text "PDF 密碼" || exit 1; sleep 1
  $ADB shell input text "$PASS"; sleep 1
  $ADB shell input keyevent 4; sleep 2   # BACK hides the IME (make sure IME is in English mode!)
  PW=$(dump | grep -oE '<node[^>]*class="android.widget.EditText"[^>]*' | grep -oE 'text="[^"]*"' | head -1)
  echo "password field now: $PW"
fi
tap_text "選擇 PDF" exact || exit 1; sleep 4
dump | grep -q "$FILE_SUB" || { echo "picker not visible, retrying tap"; tap_text "選擇 PDF" exact; sleep 4; }
tap_text "$FILE_SUB" || { echo "picker view:"; dump | grep -oE 'text="[^"]{2,50}"' | head -20; exit 1; }
sleep 5
echo "after load:"; dump | grep -oE 'text="(共 [^"]*|需要密碼[^"]*|開啟失敗[^"]*)"'
tap_scroll "$DOCTYPE"; sleep 1
tap_scroll "$MODE"; sleep 1
tap_scroll "開始解析" || exit 1
PAGES=$(dump | grep -oE '共 [0-9]+ 頁' | grep -oE '[0-9]+'); PAGES=${PAGES:-1}
for t in $(seq 1 120); do
  sleep 5
  N=$($ADB logcat -d -s GemmaNlu 2>/dev/null | grep -cE 'pdf p[0-9]+ (done|failed)')
  [ "$N" -ge "$PAGES" ] && break
done
echo "-- finished after ~$((t*5))s --"
echo "== GemmaNlu log =="
$ADB logcat -d -s GemmaNlu | grep -vE '	at |Caused by'
echo "== text bounds (first 40 per page) =="
$ADB logcat -d -s PdfBounds | sed -E 's/^.*PdfBounds ?: //'
echo "== extracted page text =="
$ADB logcat -d -s PdfText | sed -E 's/^.*PdfText ?: //'
