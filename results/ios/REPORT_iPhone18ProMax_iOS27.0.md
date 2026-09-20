# iOS NLU 對照測試報告

## 摘要（iPhone 18 Pro Max · iOS 27.0 (24A427) · 2026-09-20）

> **變因註記（必讀）**：16 Pro Max 已 trade in，無法用同一個 binary 重跑。兩機的輪次之間同時存在四個差異，無法拆開歸因：
> 1. **硬體**：iPhone17,2 (A18 Pro) vs iPhone19,7（晶片名稱 API 不提供；app 內實測 6 核、11.2 GB RAM）
> 2. **binary / SDK**：16 Pro Max 全部輪次用 Xcode 26.6 / SDK 26.5 build；18 Pro Max 用 Xcode 27.0 (27A266a) / SDK 27.0 build（harness 邏輯相同，只多了機型對照與檔名前綴）
> 3. **OS build**：同為 iOS 27.0，但 16 Pro Max 是 24A437、18 Pro Max 是 24A427
> 4. **量測日期**：9/15（iOS 27 發布當天）vs 9/20；裝置端模型資產獨立於 OS 更新，框架沒有模型版本 API 可記錄
>
> 為縮小範圍做了兩個輔助實驗（Mac，macOS 27.0 26A428）：
> - 同一份 prompt 在 Mac 上的輸出與 18 Pro Max **逐字相同**（含 c6 的壞 JSON）→ 新行為不是 18 Pro Max 硬體特有。
> - 同一支程式分別標記為 SDK 27.0 與 SDK 26.5（以 `otool` 確認 `LC_BUILD_VERSION`），在同一台 Mac 上輸出**逐字相同** → 在 Mac 上，連結的 SDK 版本不影響模型行為。
>
> **模型變體（2026-09-20 補測，更正先前推論）**：iOS 27 SDK 的 `SystemLanguageModel.variant` 有兩個值：`core3` 與 `coreAdvanced3`。
> 此屬性**唯讀**，整份 SDK 介面沒有任何建構式或函式接受 Variant 當輸入，`GenerationOptions` 也沒有相關開關 → **變體由系統依裝置決定，app 無法指定**。
> - iPhone 18 Pro Max 實測：**`coreAdvanced3`（AFM 3 Core Advanced）**，contextSize **8192**，capabilities = vision / guidedGeneration / toolCalling（無 reasoning）。
>   （本報告的 7 個結果檔產生於 harness 加入變體記錄之前，env 內沒有此欄；變體是同一台手機、同一 OS build 在測試結束 8 分鐘後以 `--status-only` 讀回的。）
> - Mac（M3、16 GB、macOS 27.0）實測同為 `coreAdvanced3` / 8192，與其輸出和 18 Pro Max 逐字相同一致。
> - iPhone 16 Pro Max 的變體**未知**：當時的 binary 以 SDK 26.5 build，沒有這個 API，手機也已不在。依其行為（```json 圍欄、每次都有 slots、iOS 26 時 context 4096）**推測**為 `core3`，未證實。
>
> 因此先前「差異最可能來自模型資產／OS build」的推論應更正為：**最可能是系統給兩台手機分配了不同的模型變體**。
> 結論：兩機的**正確率**比較實質上是在比兩個不同的模型；**延遲**比較則同時受輸出長度影響（見結論 2）。本報告 18 Pro Max 的數字即為 Advanced 變體的成績。

同一份凍結 prompt（3434 字，sha256 `ab05290577ffa28e…`）、同一題組、temperature 0 / greedy / max 512、每題 3 次、每次全新 session。

### 結論 1：正確率（多數決全對）
| 放法 | 18 Pro Max R1 | 18 Pro Max R2 | 16 Pro Max iOS 27 R1 | 16 Pro Max iOS 27 R2 |
|---|---|---|---|---|
| `instructions`（spec） | **3/8** | **1/8** | 4/8 | 0/8 |
| `input_first`（偏差） | 0/8 | 0/8（注入）、0/8（不注入） | 3/8 | 1/8、0/8 |
| `input_wrapped`（偏差） | 0/8 | 0/8（不注入） | 4/8 | 0/8 |

語言閘門在 18 Pro Max 上同樣放行，spec 放法可正常推論，零 flip。

**R1 失分的主因變了：模型常常不輸出 `slots` 物件。** spec 放法 24 次裡有 12 次（c1、c2、c7、c8 各 3 次）JSON 合法但只有 intent / confidence / original_text / normalized_text 就結束，資訊只寫在 normalized_text（不計分）裡。
例：c1 輸出 `"normalized_text":"新增支出 120 元,分類「飲食>午餐」,支付方式現金,日期 2026-09-15"`，金額與分類其實理解正確，但沒有 slots 可評分 → 判錯。16 Pro Max 的 24 次全部都有 slots。
- 有輸出 slots 的三題 c3、c4、c5 全對。**c4「00878 收在二十一塊九」是所有 iOS 輪次中第一次答對**（UPDATE_STOCK_PRICE / 00878 / 21.9）。
- c6 三次都是**壞 JSON**：模型在 normalized_text 字串內寫出 `note="看電影"`，引號提前結束字串。JSON 合法率 21/24（16 Pro Max 為 24/24）。從 normalized_text 可見它把上週五算成 2026-09-10（正確為 09-11）。
- 偏差放法（輸入在前）在這個模型上完全失效（0/8）：c3、c4 直接回 UNKNOWN，c5 金價變 33000。這些放法原本是為了繞過 iOS 26 的語言閘門，iOS 27 已不需要。

**R2（guided generation）**：spec 放法 1/8，c6 全對（金額、南星信用卡、分類、程式算出的 09-11）。其餘題目仍是**硬塞清單內帳戶**（c1 青松信用卡、c2 北辰銀、c7 to_account 青松黃金存摺、c8 青松證-台股），c1 金額 12、c3/c4 intent 判 UNKNOWN。不注入 schema 時 0/8。兩個模型版本的 R2 都不能直接拿這份 prompt 上線。

### 結論 2：延遲—快很多，但一半以上來自「少吐字」
| R1 spec 放法 | 18 Pro Max | 16 Pro Max iOS 27 |
|---|---|---|
| 各題中位延遲的中位數 | **1.97 s** | 5.49 s |
| 平均輸出長度 | 190 字（單行 JSON，無圍欄，半數缺 slots） | 405 字（```json 圍欄 + 縮排） |
| 每字延遲 | 10.4 ms | 13.6 ms |
| 冷啟動 | 4.4 s（首次啟動）；之後 1.8–1.9 s | 4.0–6.4 s |

表面上快 2.8 倍，但輸出只有 47% 長。以每字延遲計，吐字速度約快 24%。而且 18 Pro Max 的短輸出有一部分正是「漏掉 slots」造成的，**不能把 1.97 s 當成「完整正確輸出」的延遲**。有輸出完整 slots 的 c3/c4/c5 中位延遲為 2.1–2.3 s，這比較接近完整回應的真實成本。
R2：spec 放法 2.68 s（16 Pro Max 6.64 s）；不注入 schema 1.39–1.62 s（16 Pro Max 3.55–3.73 s）。R2 的輸出結構由 schema 固定，兩機輸出長度相近，這組 2.4–2.5 倍的差距比 R1 更能反映實際速度差，但仍受上述四個變因影響。

### 與 Android 對照（R1，spec 放法）
| | iPhone 18 Pro Max | iPhone 16 Pro Max (iOS 27) | Pixel 11 Pro XL · Gemma 4 E4B |
|---|---|---|---|
| 全對 | 3/8 | 4/8 | 6/7 |
| 延遲 | 1.5–2.3 s | 5.3–6.5 s | 3.0–5.5 s |
| JSON 合法 | 21/24 | 24/24 | 100% |
| 照 schema 輸出 slots | 12/24 | 24/24 | 是 |
| 00878 | ✓ | ✗ | ✓ |
| 一百二 | normalized_text 寫 120，但無 slots | 112 ✗ | 102 ✗ |
| 決定性 | 零 flip | 零 flip | 會飄 |

### 對產品的含意
- 新模型速度足夠（約 2 秒），理解力看起來不差（c1、c4、c5 的語意都對），但**不守這份 prompt 的輸出格式**。純 prompt 路線在 iOS 上不可靠；guided generation 能保證結構，卻需要為它重寫 prompt（目前的 prompt 會讓它硬塞帳戶）。
- 建議的下一步是 **prompt v2**（兩平台同步）：iOS 端走 guided generation、移除 prompt 內的 JSON schema 敘述與範例、帳戶改為必填加「無」選項（9/14 快速測試驗證過這個做法有效）。這屬新版本，需另開一輪。

### 檔案
`results/ios/results_iPhone19-7_iOS27.0.0_*_20260920-10*.json`（7 個，spec §7 格式含 raw_output）；逐題表見下方各節。

## 並排比較（正確性 = 多數決全對；延遲 = 中位數 ms）

| # | iPhone 18 Pro Max · iOS 27.0.0 R1 [instructions] @02:02Z | iPhone 18 Pro Max · iOS 27.0.0 R2 [instructions] @02:02Z schema→prompt=yes | iPhone 18 Pro Max · iOS 27.0.0 R1 [input_wrapped] @02:07Z | iPhone 18 Pro Max · iOS 27.0.0 R2 [input_wrapped] @02:07Z schema→prompt=no | iPhone 18 Pro Max · iOS 27.0.0 R1 [input_first] @02:04Z | iPhone 18 Pro Max · iOS 27.0.0 R2 [input_first] @02:05Z schema→prompt=yes | iPhone 18 Pro Max · iOS 27.0.0 R2 [input_first] @02:06Z schema→prompt=no | Android R1 (Pixel 11 Pro XL, Gemma 4 E4B) |
|---|---|---|---|---|---|---|---|---|
| c1 | ✗ amount,category · 1816 ms | ✗ amount,account · 2393 ms | ✗ amount,category · 1806 ms | ✗ amount,category · 1691 ms | ✗ intent,amount,category · 1904 ms | ✗ amount,account · 3025 ms | ✗ intent,amount,category · 1261 ms | ⚠️ amount=102 · 4445 ms |
| c2 | ✗ amount,category · 1858 ms | ✗ account · 2639 ms | ✗ amount,category · 2023 ms | ✗ amount,category · 1552 ms | ✗ intent,amount,category · 1831 ms | ✗ intent,amount,account,category · 2679 ms | ✗ intent,amount,category · 1203 ms | ✓ · 3075 ms |
| c3 | ✓ · 2111 ms | ✗ intent,price · 2711 ms | ✗ intent,stock,price · 1814 ms | ✗ intent,stock,price · 1523 ms | ✗ intent,stock,price · 1695 ms | ✗ intent,stock,price · 3055 ms | ✗ intent,stock,price · 1338 ms | ✓ · 4399 ms |
| c4 | ✓ · 2326 ms | ✗ intent,price · 2835 ms | ✗ intent,stock,price · 2433 ms | ✗ intent,stock,price · 1531 ms | ✗ intent,stock,price · 2145 ms | ✗ intent,stock,price · 2861 ms | ✗ intent,stock,price · 1392 ms | ✓ · 4456 ms |
| c5 | ✓ · 2129 ms | ✗ amount · 3328 ms | ✗ price,amount · 2693 ms | ✗ price · 1677 ms | ✗ price · 2258 ms | ✗ price,currency,amount · 3220 ms | ✗ price,currency · 1667 ms | ✓ · 4480 ms |
| c6 | ✗ intent,amount,account,category,date · 2085 ms | ✓ · 2560 ms | ✗ intent,amount,account,category,date · 2283 ms | ✗ amount,account,category,date · 1714 ms | ✗ intent,amount,account,category,date · 2011 ms | ✗ intent,amount,account,category · 2722 ms | ✗ intent,amount,account,category,date · 1440 ms | ✓ · 5502 ms |
| c7 | ✗ amount,from_account · 1500 ms | ✗ to_account · 2328 ms | ✗ from_account,to_account · 2316 ms | ✗ amount,from_account · 1565 ms | ✗ intent,amount,from_account · 1717 ms | ✗ from_account,to_account · 3011 ms | ✗ intent,amount,from_account · 1395 ms | ✓ · 4507 ms |
| c8 | ✗ amount,category · 1858 ms | ✗ account · 2851 ms | ✗ intent,amount,category · 2182 ms | ✗ amount,category · 1714 ms | ✗ account,category · 2594 ms | ✗ account · 3166 ms | ✗ intent,amount,category · 1603 ms | —(未測) |

## results_iPhone19-7_iOS27.0.0_R1_instructions_20260920-100259.json

- 模式：**R1**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-20T02:02:12Z → 2026-09-20T02:02:59Z
- 裝置：iPhone19,7 (iPhone 18 Pro Max)（chip name not exposed by API; 6 cores, 11.2 GB RAM）　OS：iOS 27.0.0 (24A427)　Xcode 2700 (27A266a)　SDK iphoneos27.0
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**instructions** — frozen prompt as LanguageModelSession(instructions:); user turn = input only
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- 冷啟動：4406 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `null` want `120`<br>account✓<br>**category✗** got `null` want `飲食>午餐`<br>date✓ | 1816 ms | 1786–1832 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>**amount✗** got `null` want `58000`<br>account✓<br>**category✗** got `null` want `薪資>本薪`<br>date✓ | 1858 ms | 1822–1902 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | intent✓<br>stock✓<br>price✓ | 2111 ms | 2078–2162 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | intent✓<br>stock✓<br>price✓ | 2326 ms | 2311–2408 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>price✓<br>currency✓<br>amount✓ | 2129 ms | 2124–2155 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | **intent✗** got `null` want `ADD_EXPENSE`<br>**amount✗** got `null` want `360`<br>**account✗** got `null` want `南星信用卡`<br>**category✗** got `null` want `娛樂>影音/遊戲`<br>**date✗** got `null` want `2026-09-11` | 2085 ms | 2047–2096 | — | 0/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>**amount✗** got `null` want `23000`<br>**from_account✗** got `null` want `西嶺銀`<br>to_account✓ | 1500 ms | 1485–1531 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>**amount✗** got `null` want `1500`<br>account✓<br>**category✗** got `null` want `投資收益>股息`<br>date✓ | 1858 ms | 1751–1862 | — | 3/3 | — |

**彙總**：全對題數 3/8　JSON 合法率 21/24　各題中位延遲的中位數 1971 ms　flip 題數 0　平均輸出 190 字　每字延遲 10.4 ms　缺 slots 物件 12/24　帶```圍欄 0/24

## results_iPhone19-7_iOS27.0.0_R2_instructions_20260920-100407.json

- 模式：**R2**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-20T02:02:59Z → 2026-09-20T02:04:07Z
- 裝置：iPhone19,7 (iPhone 18 Pro Max)（chip name not exposed by API; 6 cores, 11.2 GB RAM）　OS：iOS 27.0.0 (24A427)　Xcode 2700 (27A266a)　SDK iphoneos27.0
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**instructions** — frozen prompt as LanguageModelSession(instructions:); user turn = input only
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512, includeSchemaInPrompt=True
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- enum 來源：dev_accounts/dev_categories JSON not present in package; account (21) and category (65) enums parsed programmatically from system_prompt_zh-TW.txt (account names strip trailing currency parentheses, per prompt note 括號內為幣別)（帳戶 21、分類 65）
- R2 schema 省略欄位：confidence, normalized_text, original_text
- 日期解析器：ChineseDateResolver.swift, today fixed to 2026-09-15, week starts Monday; supports 昨天/前天/大前天/明天/後天、N天前後、(上上|上|這|本|下)(週|星期|禮拜)X、單獨 週X=最近一次(含今天)、M/D、M月D日、YYYY-MM-DD、(上|這|下)個月N號、N號、中文數字
- 冷啟動：4406 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `12` want `120`<br>**account✗** got `青松信用卡` want `null`<br>category✓<br>date✓△填今天 | 2393 ms | 2385–2415 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>amount✓<br>**account✗** got `北辰銀` want `null`<br>category✓<br>date✓△填今天 | 2639 ms | 2638–2651 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | **intent✗** got `UNKNOWN` want `UPDATE_STOCK_PRICE`<br>stock✓<br>**price✗** got `0` want `1085` | 2711 ms | 2637–2712 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `UNKNOWN` want `UPDATE_STOCK_PRICE`<br>stock✓<br>**price✗** got `null` want `21.9` | 2835 ms | 2820–2845 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>price✓<br>currency✓<br>**amount✗** got `0` want `null` | 3328 ms | 3272–3334 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>amount✓<br>account✓<br>category✓<br>date✓ | 2560 ms | 2549–2707 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>amount✓<br>from_account✓<br>**to_account✗** got `青松黃金存摺` want `null` | 2328 ms | 2314–2358 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>amount✓<br>**account✗** got `青松證-台股` want `null`<br>category✓<br>date✓△填今天 | 2851 ms | 2812–2866 | — | 3/3 | — |

**彙總**：全對題數 1/8　JSON 合法率 24/24　各題中位延遲的中位數 2675 ms　flip 題數 0　平均輸出 200 字　每字延遲 13.4 ms

## results_iPhone19-7_iOS27.0.0_R1_input_wrapped_20260920-100758.json

- 模式：**R1**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-20T02:07:06Z → 2026-09-20T02:07:58Z
- 裝置：iPhone19,7 (iPhone 18 Pro Max)（chip name not exposed by API; 6 cores, 11.2 GB RAM）　OS：iOS 27.0.0 (24A427)　Xcode 2700 (27A266a)　SDK iphoneos27.0
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**input_wrapped** — DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim) + blank line + input. The trailing input is the spec 'prepended' order; the leading copy exists only to pass the language gate. Input therefore appears twice
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- 冷啟動：1901 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `null` want `120`<br>account✓<br>**category✗** got `null` want `飲食>午餐`<br>date✓ | 1806 ms | 1750–1821 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>**amount✗** got `null` want `58000`<br>account✓<br>**category✗** got `null` want `薪資>本薪`<br>date✓ | 2023 ms | 1886–2075 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | **intent✗** got `UNKNOWN` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `台積電`<br>**price✗** got `null` want `1085` | 1814 ms | 1707–1912 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `UNKNOWN` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `null` want `21.9` | 2433 ms | 2259–2470 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>**price✗** got `33000` want `3320`<br>currency✓<br>**amount✗** got `33000` want `null` | 2693 ms | 2651–2698 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | **intent✗** got `null` want `ADD_EXPENSE`<br>**amount✗** got `null` want `360`<br>**account✗** got `null` want `南星信用卡`<br>**category✗** got `null` want `娛樂>影音/遊戲`<br>**date✗** got `null` want `2026-09-11` | 2283 ms | 2051–2394 | — | 0/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>amount✓<br>**from_account✗** got `null` want `西嶺銀`<br>**to_account✗** got `現金` want `null` | 2316 ms | 2205–2342 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | **intent✗** got `null` want `ADD_INCOME`<br>**amount✗** got `null` want `1500`<br>account✓<br>**category✗** got `null` want `投資收益>股息`<br>date✓ | 2182 ms | 2156–2249 | — | 0/3 | — |

**彙總**：全對題數 0/8　JSON 合法率 18/24　各題中位延遲的中位數 2232 ms　flip 題數 0　平均輸出 193 字　每字延遲 11.4 ms　缺 slots 物件 9/24　帶```圍欄 0/24

## results_iPhone19-7_iOS27.0.0_R2_noschema_input_wrapped_20260920-100839.json

- 模式：**R2**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-20T02:07:58Z → 2026-09-20T02:08:39Z
- 裝置：iPhone19,7 (iPhone 18 Pro Max)（chip name not exposed by API; 6 cores, 11.2 GB RAM）　OS：iOS 27.0.0 (24A427)　Xcode 2700 (27A266a)　SDK iphoneos27.0
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**input_wrapped** — DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim) + blank line + input. The trailing input is the spec 'prepended' order; the leading copy exists only to pass the language gate. Input therefore appears twice
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512, includeSchemaInPrompt=False
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- enum 來源：dev_accounts/dev_categories JSON not present in package; account (21) and category (65) enums parsed programmatically from system_prompt_zh-TW.txt (account names strip trailing currency parentheses, per prompt note 括號內為幣別)（帳戶 21、分類 65）
- R2 schema 省略欄位：confidence, normalized_text, original_text
- 日期解析器：ChineseDateResolver.swift, today fixed to 2026-09-15, week starts Monday; supports 昨天/前天/大前天/明天/後天、N天前後、(上上|上|這|本|下)(週|星期|禮拜)X、單獨 週X=最近一次(含今天)、M/D、M月D日、YYYY-MM-DD、(上|這|下)個月N號、N號、中文數字
- 冷啟動：1901 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `null` want `120`<br>account✓<br>**category✗** got `null` want `飲食>午餐`<br>date✓△填今天 | 1691 ms | 1680–1731 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>**amount✗** got `null` want `58000`<br>account✓<br>**category✗** got `null` want `薪資>本薪`<br>date✓△填今天 | 1552 ms | 1513–1573 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | **intent✗** got `UNKNOWN` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `台積電`<br>**price✗** got `null` want `1085` | 1523 ms | 1496–1525 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `UNKNOWN` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `null` want `21.9` | 1531 ms | 1482–1541 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>**price✗** got `null` want `3320`<br>currency✓<br>amount✓ | 1677 ms | 1654–1736 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>**amount✗** got `null` want `360`<br>**account✗** got `null` want `南星信用卡`<br>**category✗** got `null` want `娛樂>影音/遊戲`<br>**date✗** got `2026-09-10` want `2026-09-11` | 1714 ms | 1658–1747 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>**amount✗** got `null` want `23000`<br>**from_account✗** got `null` want `西嶺銀`<br>to_account✓ | 1565 ms | 1540–1597 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>**amount✗** got `null` want `1500`<br>account✓<br>**category✗** got `null` want `投資收益>股息`<br>date✓△填今天 | 1714 ms | 1692–1750 | — | 3/3 | — |

**彙總**：全對題數 0/8　JSON 合法率 24/24　各題中位延遲的中位數 1621 ms　flip 題數 0　平均輸出 85 字　每字延遲 19.1 ms

## results_iPhone19-7_iOS27.0.0_R1_input_first_20260920-100501.json

- 模式：**R1**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-20T02:04:13Z → 2026-09-20T02:05:01Z
- 裝置：iPhone19,7 (iPhone 18 Pro Max)（chip name not exposed by API; 6 cores, 11.2 GB RAM）　OS：iOS 27.0.0 (24A427)　Xcode 2700 (27A266a)　SDK iphoneos27.0
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**input_first** — DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim). Reason: FoundationModels language gate rejects the frozen prompt in both spec placements (NLLanguageRecognizer classifies it as Indonesian); putting the Chinese input first flips detection to a supported language
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- 冷啟動：1843 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | **intent✗** got `UNKNOWN` want `ADD_EXPENSE`<br>**amount✗** got `null` want `120`<br>account✓<br>**category✗** got `null` want `飲食>午餐`<br>date✓ | 1904 ms | 1847–1935 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | **intent✗** got `UNKNOWN` want `ADD_INCOME`<br>**amount✗** got `null` want `58000`<br>account✓<br>**category✗** got `null` want `薪資>本薪`<br>date✓ | 1831 ms | 1813–1859 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | **intent✗** got `UNKNOWN` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `台積電`<br>**price✗** got `null` want `1085` | 1695 ms | 1681–1705 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `UNKNOWN` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `null` want `21.9` | 2145 ms | 2101–2149 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>**price✗** got `33200` want `3320`<br>currency✓<br>amount✓ | 2258 ms | 2251–2262 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | **intent✗** got `null` want `ADD_EXPENSE`<br>**amount✗** got `null` want `360`<br>**account✗** got `null` want `南星信用卡`<br>**category✗** got `null` want `娛樂>影音/遊戲`<br>**date✗** got `null` want `2026-09-11` | 2011 ms | 1973–2058 | — | 0/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | **intent✗** got `UNKNOWN` want `ADD_TRANSFER`<br>**amount✗** got `null` want `23000`<br>**from_account✗** got `null` want `西嶺銀`<br>to_account✓ | 1717 ms | 1640–1725 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>amount✓<br>**account✗** got `北辰銀` want `null`<br>**category✗** got `收入>投資收益` want `投資收益>股息`<br>date✓△填今天 | 2594 ms | 2586–2615 | — | 3/3 | — |

**彙總**：全對題數 0/8　JSON 合法率 21/24　各題中位延遲的中位數 1957 ms　flip 題數 0　平均輸出 192 字　每字延遲 10.2 ms　缺 slots 物件 12/24　帶```圍欄 0/24

## results_iPhone19-7_iOS27.0.0_R2_input_first_20260920-100616.json

- 模式：**R2**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-20T02:05:01Z → 2026-09-20T02:06:16Z
- 裝置：iPhone19,7 (iPhone 18 Pro Max)（chip name not exposed by API; 6 cores, 11.2 GB RAM）　OS：iOS 27.0.0 (24A427)　Xcode 2700 (27A266a)　SDK iphoneos27.0
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**input_first** — DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim). Reason: FoundationModels language gate rejects the frozen prompt in both spec placements (NLLanguageRecognizer classifies it as Indonesian); putting the Chinese input first flips detection to a supported language
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512, includeSchemaInPrompt=True
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- enum 來源：dev_accounts/dev_categories JSON not present in package; account (21) and category (65) enums parsed programmatically from system_prompt_zh-TW.txt (account names strip trailing currency parentheses, per prompt note 括號內為幣別)（帳戶 21、分類 65）
- R2 schema 省略欄位：confidence, normalized_text, original_text
- 日期解析器：ChineseDateResolver.swift, today fixed to 2026-09-15, week starts Monday; supports 昨天/前天/大前天/明天/後天、N天前後、(上上|上|這|本|下)(週|星期|禮拜)X、單獨 週X=最近一次(含今天)、M/D、M月D日、YYYY-MM-DD、(上|這|下)個月N號、N號、中文數字
- 冷啟動：1843 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `122.5` want `120`<br>**account✗** got `青松信用卡` want `null`<br>category✓<br>date✓ | 3025 ms | 2999–3056 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | **intent✗** got `UNKNOWN` want `ADD_INCOME`<br>**amount✗** got `0` want `58000`<br>**account✗** got `北辰銀` want `null`<br>**category✗** got `飲食>早餐` want `薪資>本薪`<br>date✓ | 2679 ms | 2634–2696 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | **intent✗** got `UNKNOWN` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `一千零八十五` want `台積電`<br>**price✗** got `0` want `1085` | 3055 ms | 3022–3058 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `UNKNOWN` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `null` want `21.9` | 2861 ms | 2854–2884 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>**price✗** got `4580` want `3320`<br>**currency✗** got `TWD` want `USD`<br>**amount✗** got `0` want `null` | 3220 ms | 3213–3486 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | **intent✗** got `UNKNOWN` want `ADD_EXPENSE`<br>**amount✗** got `0` want `360`<br>**account✗** got `南星銀` want `南星信用卡`<br>**category✗** got `null` want `娛樂>影音/遊戲`<br>date✓ | 2722 ms | 2712–2853 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>amount✓<br>**from_account✗** got `青松銀` want `西嶺銀`<br>**to_account✗** got `西嶺銀` want `null` | 3011 ms | 2970–3079 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>amount✓<br>**account✗** got `青松證-台股` want `null`<br>category✓<br>date✓ | 3166 ms | 3131–3193 | — | 3/3 | — |

**彙總**：全對題數 0/8　JSON 合法率 24/24　各題中位延遲的中位數 3018 ms　flip 題數 0　平均輸出 203 字　每字延遲 14.9 ms

## results_iPhone19-7_iOS27.0.0_R2_noschema_input_first_20260920-100700.json

- 模式：**R2**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-20T02:06:24Z → 2026-09-20T02:07:00Z
- 裝置：iPhone19,7 (iPhone 18 Pro Max)（chip name not exposed by API; 6 cores, 11.2 GB RAM）　OS：iOS 27.0.0 (24A427)　Xcode 2700 (27A266a)　SDK iphoneos27.0
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**input_first** — DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim). Reason: FoundationModels language gate rejects the frozen prompt in both spec placements (NLLanguageRecognizer classifies it as Indonesian); putting the Chinese input first flips detection to a supported language
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512, includeSchemaInPrompt=False
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- enum 來源：dev_accounts/dev_categories JSON not present in package; account (21) and category (65) enums parsed programmatically from system_prompt_zh-TW.txt (account names strip trailing currency parentheses, per prompt note 括號內為幣別)（帳戶 21、分類 65）
- R2 schema 省略欄位：confidence, normalized_text, original_text
- 日期解析器：ChineseDateResolver.swift, today fixed to 2026-09-15, week starts Monday; supports 昨天/前天/大前天/明天/後天、N天前後、(上上|上|這|本|下)(週|星期|禮拜)X、單獨 週X=最近一次(含今天)、M/D、M月D日、YYYY-MM-DD、(上|這|下)個月N號、N號、中文數字
- 冷啟動：1927 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | **intent✗** got `UNKNOWN` want `ADD_EXPENSE`<br>**amount✗** got `null` want `120`<br>account✓<br>**category✗** got `null` want `飲食>午餐`<br>date✓△填今天 | 1261 ms | 1253–1269 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | **intent✗** got `UNKNOWN` want `ADD_INCOME`<br>**amount✗** got `null` want `58000`<br>account✓<br>**category✗** got `null` want `薪資>本薪`<br>date✓△填今天 | 1203 ms | 1184–1228 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | **intent✗** got `UNKNOWN` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `台積電`<br>**price✗** got `null` want `1085` | 1338 ms | 1323–1360 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `UNKNOWN` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `null` want `21.9` | 1392 ms | 1349–1409 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>**price✗** got `null` want `3320`<br>**currency✗** got `TWD` want `USD`<br>amount✓ | 1667 ms | 1654–1729 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | **intent✗** got `UNKNOWN` want `ADD_EXPENSE`<br>**amount✗** got `null` want `360`<br>**account✗** got `null` want `南星信用卡`<br>**category✗** got `null` want `娛樂>影音/遊戲`<br>**date✗** got `2026-09-15` want `2026-09-11` | 1440 ms | 1429–1470 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | **intent✗** got `UNKNOWN` want `ADD_TRANSFER`<br>**amount✗** got `null` want `23000`<br>**from_account✗** got `null` want `西嶺銀`<br>to_account✓ | 1395 ms | 1394–1406 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | **intent✗** got `ADD_EXPENSE` want `ADD_INCOME`<br>**amount✗** got `null` want `1500`<br>account✓<br>**category✗** got `null` want `投資收益>股息`<br>date✓△填今天 | 1603 ms | 1590–1628 | — | 3/3 | — |

**彙總**：全對題數 0/8　JSON 合法率 24/24　各題中位延遲的中位數 1393 ms　flip 題數 0　平均輸出 76 字　每字延遲 18.2 ms
