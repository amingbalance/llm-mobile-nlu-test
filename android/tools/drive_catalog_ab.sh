#!/bin/bash
# A/B: run the 7 sample utterances with the account/category catalog ON, toggle it OFF, run again.
ADB=${ADB:-adb}   # 找不到 adb 時設環境變數 ADB=/path/to/platform-tools/adb
dump() { $ADB shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; $ADB shell cat /sdcard/ui.xml 2>/dev/null; }
find_xy() { dump | python3 -c "
import re,sys
xml=sys.stdin.read(); q='$1'
for m in re.finditer(r'<node[^>]*text=\"([^\"]*)\"[^>]*class=\"([^\"]*)\"[^>]*bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"', xml):
    if q in m.group(1) and 'EditText' not in m.group(2) and int(m.group(6))-int(m.group(4))<200:
        print((int(m.group(3))+int(m.group(5)))//2,(int(m.group(4))+int(m.group(6)))//2); break
"; }
tap() { # scroll down in small steps until the text is on screen (y<2850), then tap; scroll back up afterwards
  for i in 1 2 3 4 5; do
    read X Y < <(find_xy "$1")
    if [ -n "$X" ] && [ "$Y" -lt 2850 ]; then $ADB shell input tap $X $Y; echo "tapped '$1' at $X,$Y"; [ $i -gt 1 ] && { sleep 1; $ADB shell input swipe 600 1200 600 2400 300; sleep 1; }; return 0; fi
    $ADB shell input swipe 600 2200 600 1600 300; sleep 1.5
  done
  echo "NOT FOUND: $1"; $ADB shell input swipe 600 1200 600 2400 300; return 1; }
toggle_catalog() { # tap the Switch on the same row as the label
  dump | python3 -c "
import re,sys
xml=sys.stdin.read()
lab=None
for m in re.finditer(r'<node[^>]*text=\"([^\"]*)\"[^>]*bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"', xml):
    if '帶入帳戶' in m.group(1): lab=(int(m.group(3))+int(m.group(5)))//2; break
best=None
for m in re.finditer(r'<node[^>]*checkable=\"true\"[^>]*bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"', xml):
    cy=(int(m.group(2))+int(m.group(4)))//2
    if lab is not None and abs(cy-lab)<60: best=((int(m.group(1))+int(m.group(3)))//2, cy)
print(*best) if best else print('')
" | { read X Y; [ -n "$X" ] && { $ADB shell input tap $X $Y; echo "toggled catalog switch at $X,$Y"; } || echo "switch NOT FOUND"; }
}
run7() {
  local COUNT=$1
  for chip in "午餐花了一百二" "薪水入帳五萬八" "台積電改成" "00878" "金價一盎司" "上週五看電影" "從西嶺轉兩萬三"; do
    tap "$chip" >/dev/null || echo "chip not found: $chip"
    COUNT=$((COUNT+1))
    for t in $(seq 1 40); do sleep 2; N=$($ADB logcat -d -s GemmaNlu | grep -cE 'classify done|classify failed'); [ "$N" -ge "$COUNT" ] && break; done
  done
}
$ADB logcat -c
$ADB shell am force-stop app.aming.gemma4; $ADB shell am start -n app.aming.gemma4/.MainActivity >/dev/null; sleep 6
echo "== status =="; dump | grep -oE '狀態:[^"]*|base model:[^"]*|帶入帳戶[^"]*'
echo "== RUN A: catalog ON =="; run7 0
echo "== toggle OFF =="; toggle_catalog; sleep 1
echo "== RUN B: catalog OFF =="; run7 7
echo "== log =="
$ADB logcat -d -s GemmaNlu | grep -E 'classify start|inputTokens|classify done|classify failed' | grep -vE '	at ' | sed -E 's/^[0-9: .-]+[0-9]+ +[0-9]+ I GemmaNlu: //'
