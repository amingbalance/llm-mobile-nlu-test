#!/usr/bin/env python3
"""
評分 / 報告產生器（照 nlu_crosstest/README.md §7、ios_test_design_spec.md §7）

用法（在 repo 根目錄執行）:
  tools/score.py results/ios/results_iOS27.0.0_R1_instructions_*.json \
                 results/android/results_Android17_R1_instructions_*.json -o results/report.md

每個結果檔 → 每題多數決正確性（intent / 各 slot）、延遲中位數、flip 次數、JSON 合法率；
多個檔案 → 並排比較表 + Android 08-22 手測基準（nlu_crosstest/README.md §6）。
iOS 與 Android harness 產出的檔案都能讀；環境欄位缺的以 — 顯示，mode 缺的從檔名推斷。
"""
import argparse, json, statistics, sys, collections, pathlib, re

HERE = pathlib.Path(__file__).resolve().parent.parent          # repo 根目錄
TESTCASES = HERE / "nlu_crosstest" / "testcases.json"

# nlu_crosstest/README.md §6 Android 08-22 手測基準（Pixel 11 Pro XL / Gemma 4 E4B / R1，c8 未測）
ANDROID = {
    "label": "Android R1 手測基準 08-22 (Pixel 11 Pro XL, Gemma 4 E4B)",
    "latency_ms": {"c1": 4445, "c2": 3075, "c3": 4399, "c4": 4456, "c5": 4480, "c6": 5502, "c7": 4507, "c8": None},
    "correct": {"c1": "⚠️ amount=102", "c2": "✓", "c3": "✓", "c4": "✓", "c5": "✓", "c6": "✓", "c7": "✓", "c8": "—(未測)"},
}

def norm(v, want=None):
    """依 expected 的型別正規化：expected 是數字才把數字字串轉成 float；expected 是字串就照字串比（00878 不會變 878）"""
    if v is None: return None
    if isinstance(v, bool): return v
    numeric_expected = isinstance(want, (int, float)) and not isinstance(want, bool)
    if isinstance(v, (int, float)):
        return round(float(v), 6) if (numeric_expected or want is None) else str(v)
    if isinstance(v, str):
        s = v.strip()
        if s == "": return None
        if numeric_expected:
            try: return round(float(s.replace(",", "")), 6)
            except ValueError: return s
        return s
    return v

def majority(values):
    """回傳 (最多數的值, 票數)；值需可 hash（用 json.dumps 當 key）"""
    c = collections.Counter(json.dumps(v, ensure_ascii=False, sort_keys=True) for v in values)
    key, n = c.most_common(1)[0]
    return json.loads(key), n

def mode_from_name(name):
    m = re.search(r"_(R2_noschema|R1|R2)_", name)
    return m.group(1) if m else "?"

def score_file(path, suite):
    data = json.load(open(path, encoding="utf-8"))
    # Android harness 的結果檔沒有 mode/suite_version 等頂層欄位：補上預設值
    data.setdefault("mode", mode_from_name(path.name))
    data.setdefault("suite_version", suite.get("version", "—"))
    data.setdefault("frozen_today", suite["frozen_today"])
    data.setdefault("started_at", "—")
    data.setdefault("finished_at", "—")
    today = data.get("frozen_today") or suite["frozen_today"]
    by_case = collections.defaultdict(list)
    for r in data["runs"]:
        by_case[r["case_id"]].append(r)

    rows = []
    for case in suite["cases"]:
        cid = case["id"]; runs = sorted(by_case.get(cid, []), key=lambda r: r["run"])
        if not runs:
            rows.append({"case": cid, "missing": True}); continue
        fields = ["intent"] + list(case["expected"]["slots"].keys())
        expected = {"intent": case["expected"]["intent"], **case["expected"]["slots"]}
        per_field = {}
        flip_fields = []
        minor_date = 0
        for f in fields:
            want_raw = expected[f]
            vals = [norm(r["parsed"].get(f), want_raw) for r in runs]
            maj, votes = majority(vals)
            want = norm(want_raw, want_raw)
            ok = (maj == want)
            note = ""
            if not ok and f == "date" and want is None and maj == today:
                ok = True; note = "△填今天"
            if len(set(json.dumps(v, ensure_ascii=False) for v in vals)) > 1:
                flip_fields.append(f)
            for v in vals:
                if f == "date" and want is None and v == today: minor_date += 1
            per_field[f] = {"ok": ok, "got": maj, "want": want, "votes": f"{votes}/{len(vals)}", "note": note}
        lat = [r["latency_ms"] for r in runs]
        rows.append({
            "case": cid, "input": case["input"], "runs": len(runs),
            "fields": per_field,
            "all_ok": all(x["ok"] for x in per_field.values()),
            "median_ms": int(statistics.median(lat)), "min_ms": min(lat), "max_ms": max(lat),
            "flips": flip_fields,
            "json_valid": sum(1 for r in runs if r["json_valid"]),
            "errors": [r["error"] for r in runs if r.get("error")],
            "minor_date": minor_date,
        })
    return data, rows

def fmt(v):
    if v is None: return "null"
    if isinstance(v, float) and v == int(v): return str(int(v))
    return str(v)

def md_for(path, data, rows):
    env = data["env"]; g = lambda k, d="—": env.get(k) if env.get(k) is not None else d
    out = []
    out.append(f"## {path.name}\n")
    out.append(f"- 模式：**{data['mode']}**　題組 {data['suite_version']}　今天凍結 {data['frozen_today']}　執行 {data['started_at']} → {data['finished_at']}")
    dev = g("device")
    if env.get("chip_note"): dev += f"（{env['chip_note']}）"
    osline = g("os") + (f" ({env['os_build']})" if env.get("os_build") else "")
    tool = f"　Xcode {env['xcode']}　SDK {env.get('sdk','—')}" if env.get("xcode") else ""
    out.append(f"- 裝置：{dev}　OS：{osline}{tool}")
    out.append(f"- 框架：{g('framework')}　模型：{g('model_id_or_availability')}")
    out.append(f"- prompt 放置：**{g('system_prompt_placement')}** — {g('placement_note', '')}")
    if env.get("system_prompt_chars") or env.get("system_prompt_sha256"):
        out.append(f"- prompt 字數 {g('system_prompt_chars')}　sha256 {str(g('system_prompt_sha256'))[:16]}…")
    d = env.get("decoding", {})
    dec = ", ".join(f"{k}={v}" for k, v in d.items() if k != "includeSchemaNote" and v is not None)
    if d.get("includeSchemaNote"): dec += f"（{d['includeSchemaNote']}）"
    out.append(f"- 解碼：{dec}")
    out.append(f"- 雲端 fallback：{g('cloud_fallback_disabled_how')}；執行時網路可達={env.get('network_reachable_during_run', '—')}")
    runs_n = max((r.get("runs", 0) for r in rows), default=0)
    out.append(f"- session：{g('session_policy', g('session_freshness'))}；每題 {g('runs_per_case', runs_n)} 次")
    if data["mode"].startswith("R2"):
        if env.get("enum_source"):
            out.append(f"- enum 來源：{env['enum_source']}（帳戶 {g('accounts_count')}、分類 {g('categories_count')}）")
        if env.get("r2_schema_omitted_fields"):
            out.append(f"- R2 schema 省略欄位：{', '.join(env['r2_schema_omitted_fields'])}")
        if env.get("r2_schema_note"):
            out.append(f"- R2 schema 備註：{env['r2_schema_note']}")
        out.append(f"- 日期解析器：{g('r2_date_resolver')}")
    cs_note = f"（{data['cold_start_note']}）" if data.get("cold_start_note") else ""
    out.append(f"- 冷啟動：{data.get('cold_start_ms')} ms{cs_note}\n")

    out.append("| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |")
    out.append("|---|------|-----------|---------:|--------:|-----------|:---------:|------|")
    total_ok = 0; total_runs = 0; total_valid = 0; lats = []
    for r in rows:
        if r.get("missing"):
            out.append(f"| {r['case']} | — | 未執行 | | | | | |"); continue
        parts = []
        for f, x in r["fields"].items():
            if x["ok"]:
                parts.append(f"{f}✓{x['note']}")
            else:
                parts.append(f"**{f}✗** got `{fmt(x['got'])}` want `{fmt(x['want'])}`")
        parts_s = "<br>".join(parts)
        flips = ", ".join(r["flips"]) or "—"
        errs = "; ".join(dict.fromkeys(r["errors"])) or "—"
        out.append(f"| {r['case']} | {r['input']} | {parts_s} | {r['median_ms']} ms | {r['min_ms']}–{r['max_ms']} | {flips} | {r['json_valid']}/{r['runs']} | {errs} |")
        total_ok += r["all_ok"]; total_runs += r["runs"]; total_valid += r["json_valid"]; lats.append(r["median_ms"])
    n = sum(1 for r in rows if not r.get("missing"))
    # 平均輸出長度與每字延遲；R1 另計「JSON 合法但沒有 slots 物件」（模型只把資訊寫進 normalized_text）與帶 ``` 圍欄的次數
    all_runs = data["runs"]
    ok_runs = [r for r in all_runs if not r.get("error")]
    mean_chars = (sum(len(r.get("raw_output") or "") for r in ok_runs) / len(ok_runs)) if ok_runs else 0
    med_lat = statistics.median([r["latency_ms"] for r in ok_runs]) if ok_runs else 0
    extra = f"　平均輸出 {mean_chars:.0f} 字　每字延遲 {med_lat/mean_chars:.1f} ms" if mean_chars else ""
    if data["mode"] == "R1":
        no_slots = sum(1 for r in all_runs if r["json_valid"] and '"slots"' not in (r.get("raw_output") or ""))
        fenced = sum(1 for r in all_runs if "```" in (r.get("raw_output") or ""))
        extra += f"　缺 slots 物件 {no_slots}/{len(all_runs)}　帶```圍欄 {fenced}/{len(all_runs)}"
    out.append("")
    out.append(f"**彙總**：全對題數 {total_ok}/{n}　JSON 合法率 {total_valid}/{total_runs}　各題中位延遲的中位數 {int(statistics.median(lats)) if lats else '—'} ms　flip 題數 {sum(1 for r in rows if r.get('flips'))}{extra}\n")
    return "\n".join(out)

def md_compare(all_results):
    out = ["## 並排比較（正確性 = 多數決全對；延遲 = 中位數 ms）\n"]
    def lab(d):
        started = d.get("started_at", "") or ""
        # 同 OS/模式/放法可能有多遍（例如升級後立即 vs 數小時後），用開始時間區分（UTC）
        dev = d['env'].get('device', '?')
        if '(' in dev:   # iOS: "iPhone19,7 (iPhone 18 Pro Max)" → 行銷名稱；Android: "Pixel 11 Pro XL (kodiak, …)" → 括號前
            inner = dev[dev.index('(')+1:dev.rindex(')')]
            dev = inner if dev.startswith(("iPhone", "iPad", "Mac")) else dev[:dev.index('(')].strip()
        l = f"{dev} · {d['env'].get('os','?')} {d['mode']} [{d['env'].get('system_prompt_placement','?')}]"
        if len(started) >= 16: l += f" @{started[11:16]}Z"
        dec = d['env'].get('decoding', {})
        if d['mode'].startswith('R2') and dec.get('includeSchemaInPrompt') is not None:
            l += " schema→prompt=" + ("yes" if dec['includeSchemaInPrompt'] else "no")
        return l
    labels = [lab(d) for _, d, _ in all_results] + [ANDROID["label"]]
    out.append("| # | " + " | ".join(labels) + " |")
    out.append("|---|" + "|".join(["---"] * len(labels)) + "|")
    for i, case in enumerate(all_results[0][2]):
        cid = case["case"]; cells = []
        for _, d, rows in all_results:
            r = rows[i]
            if r.get("missing"): cells.append("—"); continue
            bad = [f for f, x in r["fields"].items() if not x["ok"]]
            mark = "✓" if not bad else "✗ " + ",".join(bad)
            cells.append(f"{mark} · {r['median_ms']} ms")
        a_lat = ANDROID["latency_ms"].get(cid); a_ok = ANDROID["correct"].get(cid, "—")
        cells.append(f"{a_ok} · {a_lat} ms" if a_lat else a_ok)
        out.append(f"| {cid} | " + " | ".join(cells) + " |")
    out.append("")
    return "\n".join(out)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("-o", "--out")
    ap.add_argument("--prepend", help="放在報告最前面的 markdown（摘要）")
    ap.add_argument("--append", help="附在報告最後的 markdown（附件）")
    a = ap.parse_args()
    suite = json.load(open(TESTCASES, encoding="utf-8"))
    all_results = []
    parts = ["# NLU 對照測試報告\n"]
    for f in a.files:
        p = pathlib.Path(f)
        data, rows = score_file(p, suite)
        all_results.append((p, data, rows))
        parts.append(md_for(p, data, rows))
    if len(all_results) >= 1:
        parts.insert(1, md_compare(all_results))
    if a.prepend: parts.insert(1, pathlib.Path(a.prepend).read_text(encoding="utf-8"))
    if a.append: parts.append(pathlib.Path(a.append).read_text(encoding="utf-8"))
    text = "\n".join(parts)
    if a.out:
        pathlib.Path(a.out).write_text(text, encoding="utf-8"); print(f"written {a.out}")
    print(text)

if __name__ == "__main__":
    main()
