# iOS NLU 對照測試報告

## 摘要（iOS 27.0 (24A437) 輪，2026-09-15）

同一個 app binary（Xcode 26.6 build）、同一份 prompt / 題組 / 參數，只換 OS。
上午 08:42–09:15（升級後立即）跑過一遍，**下午 14:10–14:26（升級後 5 小時、手機閒置後）重跑，正式數字以下午為準**；上午各輪保留在本報告後段供對照。

### 結論 1：iOS 27 的語言閘門放行了這份 prompt
spec 主要放法（凍結 prompt 當 `instructions`）在 iOS 26.6.2 每次都被 `unsupportedLanguageOrLocale` 擋下，在 iOS 27.0 完全沒有這個錯誤，
所有輪次 8 題 × 3 次全部推論成功、JSON 合法 24/24、零 flip。**iOS 27 有 spec 合規的正式結果。**

### 結論 2：正確率（多數決全對）— 上午與下午逐題完全相同（greedy 決定性）
| 放法 | R1 | R2 |
|---|---|---|
| `instructions`（spec） | **4/8** | 0/8（schema 注入 prompt，未爆 context） |
| `input_first`（偏差） | 3/8 | 1/8（注入）、0/8（不注入） |
| `input_wrapped`（偏差） | 4/8 | 0/8（不注入） |
| iOS 26.6.2 最佳（`input_wrapped` R1） | 4/8 | 0/8 |
| Android Gemma 4 E4B R1 | 6/7 | — |

spec 放法 R1（4/8）：c2 薪資、c3 台積電、c5 金價 USD、c6 上週五（日期 09-11、南星信用卡、分類）全對。
錯的：c1 一百二 → **112**（Gemma 曾錯成 102 的同型錯；iOS 26 答 120）、c4 00878 判成金價 2190、c7 to_account 硬塞「現金」、c8 股息判成 UPDATE_STOCK_PRICE。

### 結論 3：延遲—升級後背景負載確實存在，但穩定後仍比 iOS 26 慢，主因是輸出變長
| R1 各題中位延遲的中位數 | iOS 26.6.2 | iOS 27 上午第 1 遍 | 上午第 2 遍 | **下午** |
|---|---|---|---|---|
| `instructions`（spec） | 被閘門擋 | 9.35 s | 6.82 s | **5.50 s** |
| `input_wrapped` | 3.94 s | 5.75 s | — | **5.50 s** |
| `input_first` | 3.35 s | 6.57 s | — | **5.50 s** |
| R2 instructions（注入） | 被閘門擋 | 7.51 s | 7.37 s | **6.64 s** |
| R2 不注入 schema | 3.34 s | 3.85 s | — | **3.55–3.73 s** |
| 冷啟動 | 3.7 s | 8.4 s | 4.0 s | 4.3–6.4 s |

- iOS 27 R1 輸出改成 ```json 圍欄 + 縮排的 pretty JSON（instructions 放法 24/24 都帶圍欄），平均 405 字 vs iOS 26 的 270 字。
- 換算每字延遲：iOS 27 instructions 13.6 ms/字，iOS 26 input_wrapped 14.6 ms/字 → **模型吐字速度沒有變慢，慢在 iOS 27 多吐了 50% 的格式字元**。
- 上午與下午都出現的 13–15 s 離群值（R2 不注入 schema：input_first 的 c1/c8、input_wrapped 的 c5/c7）**不是**背景負載：原始輸出顯示模型在 `note` 欄位陷入重複迴圈（「星期二 星期二 …」「投資損失 3320 美金(USD) …」）直到 512 token 上限，上午下午逐字相同，是 iOS 27 guided generation 在這份 prompt 下的決定性退化。

### 結論 4：iOS 27 模型行為與 iOS 26 的差異
- Guided generation（R2）不注入 schema 時，iOS 27 只生成 note + intent 兩欄，且 4 個案例的 note 會重複到 token 上限（見結論 3）。
- Guided generation（R2）注入 schema 時：iOS 26 把 optional enum 留 null，iOS 27 改成**硬塞清單內的值**（c1 帳戶給青松信用卡、c2 給青松銀、c8 給青松證-台股），對記帳更危險。兩個 OS 的 R2 都不能用這份 prompt 上線。
- 中文數字：iOS 27 在 instructions 放法下 c1 答 112，input_first/input_wrapped 下答 182.5（抄範例）；iOS 26 三種放法都答 120。
- c4「00878」兩個 OS 都沒對過（iOS 26 判支出、iOS 27 判金價或 UNKNOWN）。

### 與 Android 對照（R1，spec 放法）
| | iOS 27 Apple 裝置端模型 | Android Gemma 4 E4B |
|---|---|---|
| 全對 | 4/8 | 6/7 |
| 延遲 | 5.3–6.5 s | 3.0–5.5 s |
| 決定性 | 24/24 零 flip | temp=0 仍有 102/120 抖動 |
| JSON 合法 | 24/24 | 100% |
| 一百二 | 112 ✗ | 102 ✗ |
| 00878 | ✗ | ✓ |

### 檔案
下午正式：`results/ios/results_iOS27.0.0_*_20260915-14*.json`；上午：`*_20260915-08*/09*.json`。逐題表見下方各節。

## 並排比較（正確性 = 多數決全對；延遲 = 中位數 ms）

| # | iOS 27.0.0 R1 [instructions] @06:07Z | iOS 27.0.0 R2 [instructions] @06:10Z schema→prompt=yes | iOS 27.0.0 R1 [input_wrapped] @06:21Z | iOS 27.0.0 R2 [input_wrapped] @06:23Z schema→prompt=no | iOS 27.0.0 R1 [input_first] @06:13Z | iOS 27.0.0 R2 [input_first] @06:15Z schema→prompt=yes | iOS 27.0.0 R2 [input_first] @06:18Z schema→prompt=no | iOS 27.0.0 R1 [instructions] @00:38Z | iOS 27.0.0 R1 [instructions] @01:09Z | iOS 27.0.0 R2 [instructions] @00:42Z schema→prompt=yes | iOS 27.0.0 R2 [instructions] @01:12Z schema→prompt=yes | iOS 27.0.0 R1 [input_wrapped] @01:04Z | iOS 27.0.0 R2 [input_wrapped] @01:06Z schema→prompt=no | iOS 27.0.0 R1 [input_first] @00:46Z | iOS 27.0.0 R2 [input_first] @00:49Z schema→prompt=yes | iOS 27.0.0 R2 [input_first] @00:57Z schema→prompt=no | Android R1 (Pixel 11 Pro XL, Gemma 4 E4B) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| c1 | ✗ amount · 5441 ms | ✗ amount,account · 6645 ms | ✗ amount · 5048 ms | ✗ amount,category · 3544 ms | ✗ amount · 4860 ms | ✗ amount,account · 6709 ms | ✗ amount,category · 12933 ms | ✗ amount · 9637 ms | ✗ amount · 6343 ms | ✗ amount,account · 7662 ms | ✗ amount,account · 7471 ms | ✗ amount · 5220 ms | ✗ amount,category · 3711 ms | ✗ amount · 4348 ms | ✗ amount,account · 7793 ms | ✗ amount,category · 15145 ms | ⚠️ amount=102 · 4445 ms |
| c2 | ✓ · 5400 ms | ✗ account · 6636 ms | ✓ · 5068 ms | ✗ amount,category · 3683 ms | ✓ · 5367 ms | ✗ account · 6889 ms | ✗ amount,category · 3554 ms | ✓ · 9508 ms | ✓ · 6711 ms | ✗ account · 7704 ms | ✗ account · 7497 ms | ✓ · 5611 ms | ✗ amount,category · 3809 ms | ✓ · 4968 ms | ✗ account · 8110 ms | ✗ amount,category · 3943 ms | ✓ · 3075 ms |
| c3 | ✓ · 5317 ms | ✗ price · 5667 ms | ✓ · 5010 ms | ✗ stock,price · 3683 ms | ✗ intent,stock · 5035 ms | ✓ · 7723 ms | ✗ intent,stock,price · 3543 ms | ✓ · 9364 ms | ✓ · 6809 ms | ✗ price · 6626 ms | ✗ price · 6229 ms | ✓ · 5379 ms | ✗ stock,price · 3734 ms | ✗ intent,stock · 6174 ms | ✓ · 9092 ms | ✗ intent,stock,price · 3918 ms | ✓ · 4399 ms |
| c4 | ✗ intent,stock,price · 5532 ms | ✗ intent,stock,price · 5125 ms | ✗ intent,stock,price · 5753 ms | ✗ intent,stock,price · 3689 ms | ✗ intent,stock,price · 6253 ms | ✗ intent,stock,price · 7572 ms | ✗ intent,stock,price · 3493 ms | ✗ intent,stock,price · 9350 ms | ✗ intent,stock,price · 6936 ms | ✗ intent,stock,price · 5730 ms | ✗ intent,stock,price · 5678 ms | ✗ intent,stock,price · 5862 ms | ✗ intent,stock,price · 3624 ms | ✗ intent,stock,price · 7404 ms | ✗ intent,stock,price · 8751 ms | ✗ intent,stock,price · 4025 ms | ✓ · 4456 ms |
| c5 | ✓ · 5615 ms | ✗ price · 6344 ms | ✓ · 5211 ms | ✗ price,currency · 13977 ms | ✓ · 6183 ms | ✗ price · 6161 ms | ✗ price,currency · 4930 ms | ✓ · 9359 ms | ✓ · 6870 ms | ✗ price · 6388 ms | ✗ price · 6309 ms | ✓ · 5265 ms | ✗ price,currency · 14396 ms | ✓ · 7125 ms | ✗ price · 7266 ms | ✗ price,currency · 5549 ms | ✓ · 4480 ms |
| c6 | ✓ · 6462 ms | ✗ amount,account · 6849 ms | ✗ account,date · 6512 ms | ✗ amount,account,category,date · 3777 ms | ✗ amount,account,date · 6093 ms | ✗ amount,account · 7247 ms | ✗ amount,account,category,date · 3424 ms | ✓ · 9740 ms | ✓ · 7948 ms | ✗ amount,account · 7452 ms | ✗ amount,account · 7280 ms | ✗ account,date · 6659 ms | ✗ amount,account,category,date · 3894 ms | ✗ amount,account,date · 7176 ms | ✗ amount,account · 8355 ms | ✗ amount,account,category,date · 4010 ms | ✓ · 5502 ms |
| c7 | ✗ to_account · 5397 ms | ✗ from_account,to_account · 6756 ms | ✗ to_account · 6558 ms | ✗ amount,from_account · 14505 ms | ✗ to_account · 5155 ms | ✗ to_account · 6671 ms | ✗ amount,from_account · 3443 ms | ✗ to_account · 7204 ms | ✗ to_account · 6768 ms | ✗ from_account,to_account · 7560 ms | ✗ from_account,to_account · 7463 ms | ✗ to_account · 6615 ms | ✗ amount,from_account · 15027 ms | ✗ to_account · 6147 ms | ✗ to_account · 7725 ms | ✗ amount,from_account · 3934 ms | ✓ · 4507 ms |
| c8 | ✗ intent,category · 6239 ms | ✗ account · 7163 ms | ✓ · 6000 ms | ✗ amount,category · 3792 ms | ✓ · 5542 ms | ✗ account · 7543 ms | ✗ amount,category · 13334 ms | ✗ intent,category · 7321 ms | ✗ intent,category · 6909 ms | ✗ account · 8129 ms | ✗ account · 7949 ms | ✓ · 6110 ms | ✗ amount,category · 3952 ms | ✓ · 6588 ms | ✗ account · 8739 ms | ✗ amount,category · 15146 ms | —(未測) |

## results_iOS27.0.0_R1_instructions_20260915-141012.json

- 模式：**R1**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-15T06:07:55Z → 2026-09-15T06:10:12Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 27.0.0 (24A437)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**instructions** — frozen prompt as LanguageModelSession(instructions:); user turn = input only
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- 冷啟動：6375 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `112` want `120`<br>account✓<br>category✓<br>date✓ | 5441 ms | 5386–5704 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>amount✓<br>account✓<br>category✓<br>date✓ | 5400 ms | 5279–5449 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | intent✓<br>stock✓<br>price✓ | 5317 ms | 5272–5404 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `UPDATE_GOLD_PRICE` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `2190` want `21.9` | 5532 ms | 5439–5542 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>price✓<br>currency✓<br>amount✓ | 5615 ms | 5476–5673 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>amount✓<br>account✓<br>category✓<br>date✓ | 6462 ms | 6414–6554 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>amount✓<br>from_account✓<br>**to_account✗** got `現金` want `null` | 5397 ms | 5375–5689 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | **intent✗** got `UPDATE_STOCK_PRICE` want `ADD_INCOME`<br>amount✓<br>account✓<br>**category✗** got `null` want `投資收益>股息`<br>date✓ | 6239 ms | 6204–6333 | — | 3/3 | — |

**彙總**：全對題數 4/8　JSON 合法率 24/24　各題中位延遲的中位數 5486 ms　flip 題數 0

## results_iOS27.0.0_R2_instructions_20260915-141253.json

- 模式：**R2**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-15T06:10:12Z → 2026-09-15T06:12:53Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 27.0.0 (24A437)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**instructions** — frozen prompt as LanguageModelSession(instructions:); user turn = input only
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512, includeSchemaInPrompt=True
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- enum 來源：dev_accounts/dev_categories JSON not present in package; account (21) and category (65) enums parsed programmatically from system_prompt_zh-TW.txt (account names strip trailing currency parentheses, per prompt note 括號內為幣別)（帳戶 21、分類 65）
- R2 schema 省略欄位：confidence, normalized_text, original_text
- 日期解析器：ChineseDateResolver.swift, today fixed to 2026-09-15, week starts Monday; supports 昨天/前天/大前天/明天/後天、N天前後、(上上|上|這|本|下)(週|星期|禮拜)X、單獨 週X=最近一次(含今天)、M/D、M月D日、YYYY-MM-DD、(上|這|下)個月N號、N號、中文數字
- 冷啟動：6375 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `1100` want `120`<br>**account✗** got `青松信用卡` want `null`<br>category✓<br>date✓ | 6645 ms | 6559–6651 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>amount✓<br>**account✗** got `青松銀` want `null`<br>category✓<br>date✓ | 6636 ms | 6605–6678 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | intent✓<br>stock✓<br>**price✗** got `null` want `1085` | 5667 ms | 5532–5673 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `UNKNOWN` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `null` want `21.9` | 5125 ms | 5096–5554 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>**price✗** got `null` want `3320`<br>currency✓<br>amount✓ | 6344 ms | 6201–6892 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>**amount✗** got `300` want `360`<br>**account✗** got `青松信用卡` want `南星信用卡`<br>category✓<br>date✓ | 6849 ms | 6586–7120 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>amount✓<br>**from_account✗** got `青松銀` want `西嶺銀`<br>**to_account✗** got `西嶺銀` want `null` | 6756 ms | 6657–6776 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>amount✓<br>**account✗** got `青松證-台股` want `null`<br>category✓<br>date✓△填今天 | 7163 ms | 7155–7257 | — | 3/3 | — |

**彙總**：全對題數 0/8　JSON 合法率 24/24　各題中位延遲的中位數 6640 ms　flip 題數 0

## results_iOS27.0.0_R1_input_wrapped_20260915-142332.json

- 模式：**R1**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-15T06:21:17Z → 2026-09-15T06:23:32Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 27.0.0 (24A437)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**input_wrapped** — DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim) + blank line + input. The trailing input is the spec 'prepended' order; the leading copy exists only to pass the language gate. Input therefore appears twice
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- 冷啟動：4572 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `182.5` want `120`<br>account✓<br>category✓<br>date✓ | 5048 ms | 5038–5184 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>amount✓<br>account✓<br>category✓<br>date✓ | 5068 ms | 5057–5157 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | intent✓<br>stock✓<br>price✓ | 5010 ms | 4983–5073 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `UNKNOWN` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `null` want `21.9` | 5753 ms | 5740–5781 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>price✓<br>currency✓<br>amount✓ | 5211 ms | 5153–5268 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>amount✓<br>**account✗** got `南星銀` want `南星信用卡`<br>category✓<br>**date✗** got `2026-09-13` want `2026-09-11` | 6512 ms | 6446–6514 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>amount✓<br>from_account✓<br>**to_account✗** got `現金` want `null` | 6558 ms | 6539–6582 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>amount✓<br>account✓<br>category✓<br>date✓△填今天 | 6000 ms | 5984–6079 | — | 3/3 | — |

**彙總**：全對題數 4/8　JSON 合法率 24/24　各題中位延遲的中位數 5482 ms　flip 題數 0

## results_iOS27.0.0_R2_noschema_input_wrapped_20260915-142608.json

- 模式：**R2**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-15T06:23:32Z → 2026-09-15T06:26:08Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 27.0.0 (24A437)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**input_wrapped** — DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim) + blank line + input. The trailing input is the spec 'prepended' order; the leading copy exists only to pass the language gate. Input therefore appears twice
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512, includeSchemaInPrompt=False
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- enum 來源：dev_accounts/dev_categories JSON not present in package; account (21) and category (65) enums parsed programmatically from system_prompt_zh-TW.txt (account names strip trailing currency parentheses, per prompt note 括號內為幣別)（帳戶 21、分類 65）
- R2 schema 省略欄位：confidence, normalized_text, original_text
- 日期解析器：ChineseDateResolver.swift, today fixed to 2026-09-15, week starts Monday; supports 昨天/前天/大前天/明天/後天、N天前後、(上上|上|這|本|下)(週|星期|禮拜)X、單獨 週X=最近一次(含今天)、M/D、M月D日、YYYY-MM-DD、(上|這|下)個月N號、N號、中文數字
- 冷啟動：4572 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `null` want `120`<br>account✓<br>**category✗** got `null` want `飲食>午餐`<br>date✓ | 3544 ms | 3538–3660 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>**amount✗** got `null` want `58000`<br>account✓<br>**category✗** got `null` want `薪資>本薪`<br>date✓ | 3683 ms | 3602–3746 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | intent✓<br>**stock✗** got `null` want `台積電`<br>**price✗** got `null` want `1085` | 3683 ms | 3663–3795 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `UNKNOWN` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `null` want `21.9` | 3689 ms | 3621–3804 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>**price✗** got `null` want `3320`<br>**currency✗** got `null` want `USD`<br>amount✓ | 13977 ms | 13911–14098 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>**amount✗** got `null` want `360`<br>**account✗** got `null` want `南星信用卡`<br>**category✗** got `null` want `娛樂>影音/遊戲`<br>**date✗** got `null` want `2026-09-11` | 3777 ms | 3765–3791 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>**amount✗** got `null` want `23000`<br>**from_account✗** got `null` want `西嶺銀`<br>to_account✓ | 14505 ms | 14272–14562 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>**amount✗** got `null` want `1500`<br>account✓<br>**category✗** got `null` want `投資收益>股息`<br>date✓ | 3792 ms | 3713–4000 | — | 3/3 | — |

**彙總**：全對題數 0/8　JSON 合法率 24/24　各題中位延遲的中位數 3733 ms　flip 題數 0

## results_iOS27.0.0_R1_input_first_20260915-141518.json

- 模式：**R1**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-15T06:13:05Z → 2026-09-15T06:15:18Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 27.0.0 (24A437)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**input_first** — DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim). Reason: FoundationModels language gate rejects the frozen prompt in both spec placements (NLLanguageRecognizer classifies it as Indonesian); putting the Chinese input first flips detection to a supported language
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- 冷啟動：4323 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `182.5` want `120`<br>account✓<br>category✓<br>date✓ | 4860 ms | 4341–5057 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>amount✓<br>account✓<br>category✓<br>date✓ | 5367 ms | 5352–5466 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | **intent✗** got `UPDATE_GOLD_PRICE` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `台積電`<br>price✓ | 5035 ms | 4988–5071 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `UPDATE_GOLD_PRICE` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `2109` want `21.9` | 6253 ms | 6079–6300 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>price✓<br>currency✓<br>amount✓ | 6183 ms | 6178–6228 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>**amount✗** got `36000` want `360`<br>**account✗** got `南星銀` want `南星信用卡`<br>category✓<br>**date✗** got `2026-09-12` want `2026-09-11` | 6093 ms | 6040–6126 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>amount✓<br>from_account✓<br>**to_account✗** got `現金` want `null` | 5155 ms | 5093–5222 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>amount✓<br>account✓<br>category✓<br>date✓ | 5542 ms | 5530–5656 | — | 3/3 | — |

**彙總**：全對題數 3/8　JSON 合法率 24/24　各題中位延遲的中位數 5454 ms　flip 題數 0

## results_iOS27.0.0_R2_input_first_20260915-141814.json

- 模式：**R2**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-15T06:15:18Z → 2026-09-15T06:18:14Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 27.0.0 (24A437)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**input_first** — DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim). Reason: FoundationModels language gate rejects the frozen prompt in both spec placements (NLLanguageRecognizer classifies it as Indonesian); putting the Chinese input first flips detection to a supported language
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512, includeSchemaInPrompt=True
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- enum 來源：dev_accounts/dev_categories JSON not present in package; account (21) and category (65) enums parsed programmatically from system_prompt_zh-TW.txt (account names strip trailing currency parentheses, per prompt note 括號內為幣別)（帳戶 21、分類 65）
- R2 schema 省略欄位：confidence, normalized_text, original_text
- 日期解析器：ChineseDateResolver.swift, today fixed to 2026-09-15, week starts Monday; supports 昨天/前天/大前天/明天/後天、N天前後、(上上|上|這|本|下)(週|星期|禮拜)X、單獨 週X=最近一次(含今天)、M/D、M月D日、YYYY-MM-DD、(上|這|下)個月N號、N號、中文數字
- 冷啟動：4323 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `182.5` want `120`<br>**account✗** got `青松信用卡` want `null`<br>category✓<br>date✓ | 6709 ms | 6577–6753 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>amount✓<br>**account✗** got `北辰銀` want `null`<br>category✓<br>date✓ | 6889 ms | 6844–6996 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | intent✓<br>stock✓<br>price✓ | 7723 ms | 7646–7799 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `ADD_EXPENSE` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `青松證-台股` want `00878`<br>**price✗** got `null` want `21.9` | 7572 ms | 7523–7634 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>**price✗** got `null` want `3320`<br>currency✓<br>amount✓ | 6161 ms | 6135–6277 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>**amount✗** got `3600` want `360`<br>**account✗** got `南星銀` want `南星信用卡`<br>category✓<br>date✓ | 7247 ms | 7078–7315 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>amount✓<br>from_account✓<br>**to_account✗** got `西嶺銀` want `null` | 6671 ms | 6600–6723 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>amount✓<br>**account✗** got `青松證-台股` want `null`<br>category✓<br>date✓△填今天 | 7543 ms | 7403–7699 | — | 3/3 | — |

**彙總**：全對題數 1/8　JSON 合法率 24/24　各題中位延遲的中位數 7068 ms　flip 題數 0

## results_iOS27.0.0_R2_noschema_input_first_20260915-142103.json

- 模式：**R2**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-15T06:18:24Z → 2026-09-15T06:21:03Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 27.0.0 (24A437)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**input_first** — DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim). Reason: FoundationModels language gate rejects the frozen prompt in both spec placements (NLLanguageRecognizer classifies it as Indonesian); putting the Chinese input first flips detection to a supported language
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512, includeSchemaInPrompt=False
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- enum 來源：dev_accounts/dev_categories JSON not present in package; account (21) and category (65) enums parsed programmatically from system_prompt_zh-TW.txt (account names strip trailing currency parentheses, per prompt note 括號內為幣別)（帳戶 21、分類 65）
- R2 schema 省略欄位：confidence, normalized_text, original_text
- 日期解析器：ChineseDateResolver.swift, today fixed to 2026-09-15, week starts Monday; supports 昨天/前天/大前天/明天/後天、N天前後、(上上|上|這|本|下)(週|星期|禮拜)X、單獨 週X=最近一次(含今天)、M/D、M月D日、YYYY-MM-DD、(上|這|下)個月N號、N號、中文數字
- 冷啟動：4314 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `null` want `120`<br>account✓<br>**category✗** got `null` want `飲食>午餐`<br>date✓ | 12933 ms | 12907–13082 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>**amount✗** got `null` want `58000`<br>account✓<br>**category✗** got `null` want `薪資>本薪`<br>date✓ | 3554 ms | 3467–3632 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | **intent✗** got `UPDATE_GOLD_PRICE` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `台積電`<br>**price✗** got `null` want `1085` | 3543 ms | 3417–3597 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `UPDATE_GOLD_PRICE` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `null` want `21.9` | 3493 ms | 3426–3556 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>**price✗** got `null` want `3320`<br>**currency✗** got `null` want `USD`<br>amount✓ | 4930 ms | 4915–4970 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>**amount✗** got `null` want `360`<br>**account✗** got `null` want `南星信用卡`<br>**category✗** got `null` want `娛樂>影音/遊戲`<br>**date✗** got `null` want `2026-09-11` | 3424 ms | 3377–3524 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>**amount✗** got `null` want `23000`<br>**from_account✗** got `null` want `西嶺銀`<br>to_account✓ | 3443 ms | 3432–3573 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>**amount✗** got `null` want `1500`<br>account✓<br>**category✗** got `null` want `投資收益>股息`<br>date✓ | 13334 ms | 13125–13414 | — | 3/3 | — |

**彙總**：全對題數 0/8　JSON 合法率 24/24　各題中位延遲的中位數 3548 ms　flip 題數 0

## results_iOS27.0.0_R1_instructions_20260915-084208.json

- 模式：**R1**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-15T00:38:37Z → 2026-09-15T00:42:08Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 27.0.0 (24A437)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**instructions** — frozen prompt as LanguageModelSession(instructions:); user turn = input only
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- 冷啟動：8399 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `112` want `120`<br>account✓<br>category✓<br>date✓ | 9637 ms | 6814–9664 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>amount✓<br>account✓<br>category✓<br>date✓ | 9508 ms | 9392–9550 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | intent✓<br>stock✓<br>price✓ | 9364 ms | 9203–9401 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `UPDATE_GOLD_PRICE` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `2190` want `21.9` | 9350 ms | 9103–9699 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>price✓<br>currency✓<br>amount✓ | 9359 ms | 8993–9698 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>amount✓<br>account✓<br>category✓<br>date✓ | 9740 ms | 8800–9950 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>amount✓<br>from_account✓<br>**to_account✗** got `現金` want `null` | 7204 ms | 7104–7246 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | **intent✗** got `UPDATE_STOCK_PRICE` want `ADD_INCOME`<br>amount✓<br>account✓<br>**category✗** got `null` want `投資收益>股息`<br>date✓ | 7321 ms | 7278–7751 | — | 3/3 | — |

**彙總**：全對題數 4/8　JSON 合法率 24/24　各題中位延遲的中位數 9361 ms　flip 題數 0

## results_iOS27.0.0_R1_instructions_20260915-091220.json

- 模式：**R1**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-15T01:09:34Z → 2026-09-15T01:12:20Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 27.0.0 (24A437)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**instructions** — frozen prompt as LanguageModelSession(instructions:); user turn = input only
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- 冷啟動：4028 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `112` want `120`<br>account✓<br>category✓<br>date✓ | 6343 ms | 6256–6376 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>amount✓<br>account✓<br>category✓<br>date✓ | 6711 ms | 6598–6721 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | intent✓<br>stock✓<br>price✓ | 6809 ms | 6728–6843 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `UPDATE_GOLD_PRICE` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `2190` want `21.9` | 6936 ms | 6833–7048 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>price✓<br>currency✓<br>amount✓ | 6870 ms | 6796–6976 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>amount✓<br>account✓<br>category✓<br>date✓ | 7948 ms | 7944–8105 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>amount✓<br>from_account✓<br>**to_account✗** got `現金` want `null` | 6768 ms | 6761–6803 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | **intent✗** got `UPDATE_STOCK_PRICE` want `ADD_INCOME`<br>amount✓<br>account✓<br>**category✗** got `null` want `投資收益>股息`<br>date✓ | 6909 ms | 6881–6945 | — | 3/3 | — |

**彙總**：全對題數 4/8　JSON 合法率 24/24　各題中位延遲的中位數 6839 ms　flip 題數 0

## results_iOS27.0.0_R2_instructions_20260915-084508.json

- 模式：**R2**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-15T00:42:08Z → 2026-09-15T00:45:08Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 27.0.0 (24A437)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**instructions** — frozen prompt as LanguageModelSession(instructions:); user turn = input only
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512, includeSchemaInPrompt=True
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- enum 來源：dev_accounts/dev_categories JSON not present in package; account (21) and category (65) enums parsed programmatically from system_prompt_zh-TW.txt (account names strip trailing currency parentheses, per prompt note 括號內為幣別)（帳戶 21、分類 65）
- R2 schema 省略欄位：confidence, normalized_text, original_text
- 日期解析器：ChineseDateResolver.swift, today fixed to 2026-09-15, week starts Monday; supports 昨天/前天/大前天/明天/後天、N天前後、(上上|上|這|本|下)(週|星期|禮拜)X、單獨 週X=最近一次(含今天)、M/D、M月D日、YYYY-MM-DD、(上|這|下)個月N號、N號、中文數字
- 冷啟動：8399 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `1100` want `120`<br>**account✗** got `青松信用卡` want `null`<br>category✓<br>date✓ | 7662 ms | 7589–7730 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>amount✓<br>**account✗** got `青松銀` want `null`<br>category✓<br>date✓ | 7704 ms | 7548–7772 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | intent✓<br>stock✓<br>**price✗** got `null` want `1085` | 6626 ms | 6479–6629 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `UNKNOWN` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `null` want `21.9` | 5730 ms | 5728–5762 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>**price✗** got `null` want `3320`<br>currency✓<br>amount✓ | 6388 ms | 6341–6413 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>**amount✗** got `300` want `360`<br>**account✗** got `青松信用卡` want `南星信用卡`<br>category✓<br>date✓ | 7452 ms | 7376–7547 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>amount✓<br>**from_account✗** got `青松銀` want `西嶺銀`<br>**to_account✗** got `西嶺銀` want `null` | 7560 ms | 7401–7562 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>amount✓<br>**account✗** got `青松證-台股` want `null`<br>category✓<br>date✓△填今天 | 8129 ms | 7981–8192 | — | 3/3 | — |

**彙總**：全對題數 0/8　JSON 合法率 24/24　各題中位延遲的中位數 7506 ms　flip 題數 0

## results_iOS27.0.0_R2_instructions_20260915-091516.json

- 模式：**R2**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-15T01:12:20Z → 2026-09-15T01:15:16Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 27.0.0 (24A437)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**instructions** — frozen prompt as LanguageModelSession(instructions:); user turn = input only
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512, includeSchemaInPrompt=True
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- enum 來源：dev_accounts/dev_categories JSON not present in package; account (21) and category (65) enums parsed programmatically from system_prompt_zh-TW.txt (account names strip trailing currency parentheses, per prompt note 括號內為幣別)（帳戶 21、分類 65）
- R2 schema 省略欄位：confidence, normalized_text, original_text
- 日期解析器：ChineseDateResolver.swift, today fixed to 2026-09-15, week starts Monday; supports 昨天/前天/大前天/明天/後天、N天前後、(上上|上|這|本|下)(週|星期|禮拜)X、單獨 週X=最近一次(含今天)、M/D、M月D日、YYYY-MM-DD、(上|這|下)個月N號、N號、中文數字
- 冷啟動：4028 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `1100` want `120`<br>**account✗** got `青松信用卡` want `null`<br>category✓<br>date✓ | 7471 ms | 7345–7472 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>amount✓<br>**account✗** got `青松銀` want `null`<br>category✓<br>date✓ | 7497 ms | 7406–7513 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | intent✓<br>stock✓<br>**price✗** got `null` want `1085` | 6229 ms | 6227–6424 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `UNKNOWN` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `null` want `21.9` | 5678 ms | 5677–5792 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>**price✗** got `null` want `3320`<br>currency✓<br>amount✓ | 6309 ms | 6294–6434 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>**amount✗** got `300` want `360`<br>**account✗** got `青松信用卡` want `南星信用卡`<br>category✓<br>date✓ | 7280 ms | 7214–7424 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>amount✓<br>**from_account✗** got `青松銀` want `西嶺銀`<br>**to_account✗** got `西嶺銀` want `null` | 7463 ms | 7455–7469 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>amount✓<br>**account✗** got `青松證-台股` want `null`<br>category✓<br>date✓△填今天 | 7949 ms | 7864–7954 | — | 3/3 | — |

**彙總**：全對題數 0/8　JSON 合法率 24/24　各題中位延遲的中位數 7371 ms　flip 題數 0

## results_iOS27.0.0_R1_input_wrapped_20260915-090636.json

- 模式：**R1**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-15T01:04:15Z → 2026-09-15T01:06:36Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 27.0.0 (24A437)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**input_wrapped** — DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim) + blank line + input. The trailing input is the spec 'prepended' order; the leading copy exists only to pass the language gate. Input therefore appears twice
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- 冷啟動：5384 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `182.5` want `120`<br>account✓<br>category✓<br>date✓ | 5220 ms | 4971–5693 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>amount✓<br>account✓<br>category✓<br>date✓ | 5611 ms | 5542–5670 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | intent✓<br>stock✓<br>price✓ | 5379 ms | 5264–5428 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `UNKNOWN` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `null` want `21.9` | 5862 ms | 5814–5947 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>price✓<br>currency✓<br>amount✓ | 5265 ms | 5223–5344 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>amount✓<br>**account✗** got `南星銀` want `南星信用卡`<br>category✓<br>**date✗** got `2026-09-13` want `2026-09-11` | 6659 ms | 6637–6774 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>amount✓<br>from_account✓<br>**to_account✗** got `現金` want `null` | 6615 ms | 6541–7161 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>amount✓<br>account✓<br>category✓<br>date✓△填今天 | 6110 ms | 6074–6191 | — | 3/3 | — |

**彙總**：全對題數 4/8　JSON 合法率 24/24　各題中位延遲的中位數 5736 ms　flip 題數 0

## results_iOS27.0.0_R2_noschema_input_wrapped_20260915-090917.json

- 模式：**R2**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-15T01:06:36Z → 2026-09-15T01:09:17Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 27.0.0 (24A437)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**input_wrapped** — DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim) + blank line + input. The trailing input is the spec 'prepended' order; the leading copy exists only to pass the language gate. Input therefore appears twice
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512, includeSchemaInPrompt=False
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- enum 來源：dev_accounts/dev_categories JSON not present in package; account (21) and category (65) enums parsed programmatically from system_prompt_zh-TW.txt (account names strip trailing currency parentheses, per prompt note 括號內為幣別)（帳戶 21、分類 65）
- R2 schema 省略欄位：confidence, normalized_text, original_text
- 日期解析器：ChineseDateResolver.swift, today fixed to 2026-09-15, week starts Monday; supports 昨天/前天/大前天/明天/後天、N天前後、(上上|上|這|本|下)(週|星期|禮拜)X、單獨 週X=最近一次(含今天)、M/D、M月D日、YYYY-MM-DD、(上|這|下)個月N號、N號、中文數字
- 冷啟動：5384 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `null` want `120`<br>account✓<br>**category✗** got `null` want `飲食>午餐`<br>date✓ | 3711 ms | 3695–3754 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>**amount✗** got `null` want `58000`<br>account✓<br>**category✗** got `null` want `薪資>本薪`<br>date✓ | 3809 ms | 3645–3812 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | intent✓<br>**stock✗** got `null` want `台積電`<br>**price✗** got `null` want `1085` | 3734 ms | 3712–3758 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `UNKNOWN` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `null` want `21.9` | 3624 ms | 3614–3803 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>**price✗** got `null` want `3320`<br>**currency✗** got `null` want `USD`<br>amount✓ | 14396 ms | 14072–14519 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>**amount✗** got `null` want `360`<br>**account✗** got `null` want `南星信用卡`<br>**category✗** got `null` want `娛樂>影音/遊戲`<br>**date✗** got `null` want `2026-09-11` | 3894 ms | 3797–4038 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>**amount✗** got `null` want `23000`<br>**from_account✗** got `null` want `西嶺銀`<br>to_account✓ | 15027 ms | 14790–15313 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>**amount✗** got `null` want `1500`<br>account✓<br>**category✗** got `null` want `投資收益>股息`<br>date✓ | 3952 ms | 3952–4185 | — | 3/3 | — |

**彙總**：全對題數 0/8　JSON 合法率 24/24　各題中位延遲的中位數 3851 ms　flip 題數 0

## results_iOS27.0.0_R1_input_first_20260915-084917.json

- 模式：**R1**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-15T00:46:45Z → 2026-09-15T00:49:17Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 27.0.0 (24A437)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**input_first** — DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim). Reason: FoundationModels language gate rejects the frozen prompt in both spec placements (NLLanguageRecognizer classifies it as Indonesian); putting the Chinese input first flips detection to a supported language
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- 冷啟動：4370 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `182.5` want `120`<br>account✓<br>category✓<br>date✓ | 4348 ms | 4195–4453 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>amount✓<br>account✓<br>category✓<br>date✓ | 4968 ms | 4898–6199 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | **intent✗** got `UPDATE_GOLD_PRICE` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `台積電`<br>price✓ | 6174 ms | 5996–7545 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `UPDATE_GOLD_PRICE` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `2109` want `21.9` | 7404 ms | 7194–7487 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>price✓<br>currency✓<br>amount✓ | 7125 ms | 7116–7148 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>**amount✗** got `36000` want `360`<br>**account✗** got `南星銀` want `南星信用卡`<br>category✓<br>**date✗** got `2026-09-12` want `2026-09-11` | 7176 ms | 7048–7675 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>amount✓<br>from_account✓<br>**to_account✗** got `現金` want `null` | 6147 ms | 6036–6241 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>amount✓<br>account✓<br>category✓<br>date✓ | 6588 ms | 6557–6648 | — | 3/3 | — |

**彙總**：全對題數 3/8　JSON 合法率 24/24　各題中位延遲的中位數 6381 ms　flip 題數 0

## results_iOS27.0.0_R2_input_first_20260915-085243.json

- 模式：**R2**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-15T00:49:17Z → 2026-09-15T00:52:43Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 27.0.0 (24A437)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**input_first** — DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim). Reason: FoundationModels language gate rejects the frozen prompt in both spec placements (NLLanguageRecognizer classifies it as Indonesian); putting the Chinese input first flips detection to a supported language
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512, includeSchemaInPrompt=True
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- enum 來源：dev_accounts/dev_categories JSON not present in package; account (21) and category (65) enums parsed programmatically from system_prompt_zh-TW.txt (account names strip trailing currency parentheses, per prompt note 括號內為幣別)（帳戶 21、分類 65）
- R2 schema 省略欄位：confidence, normalized_text, original_text
- 日期解析器：ChineseDateResolver.swift, today fixed to 2026-09-15, week starts Monday; supports 昨天/前天/大前天/明天/後天、N天前後、(上上|上|這|本|下)(週|星期|禮拜)X、單獨 週X=最近一次(含今天)、M/D、M月D日、YYYY-MM-DD、(上|這|下)個月N號、N號、中文數字
- 冷啟動：4370 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `182.5` want `120`<br>**account✗** got `青松信用卡` want `null`<br>category✓<br>date✓ | 7793 ms | 7787–7808 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>amount✓<br>**account✗** got `北辰銀` want `null`<br>category✓<br>date✓ | 8110 ms | 8100–8114 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | intent✓<br>stock✓<br>price✓ | 9092 ms | 8971–9121 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `ADD_EXPENSE` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `青松證-台股` want `00878`<br>**price✗** got `null` want `21.9` | 8751 ms | 8734–9017 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>**price✗** got `null` want `3320`<br>currency✓<br>amount✓ | 7266 ms | 7241–7334 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>**amount✗** got `3600` want `360`<br>**account✗** got `南星銀` want `南星信用卡`<br>category✓<br>date✓ | 8355 ms | 8286–8523 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>amount✓<br>from_account✓<br>**to_account✗** got `西嶺銀` want `null` | 7725 ms | 7598–7818 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>amount✓<br>**account✗** got `青松證-台股` want `null`<br>category✓<br>date✓△填今天 | 8739 ms | 8617–8829 | — | 3/3 | — |

**彙總**：全對題數 1/8　JSON 合法率 24/24　各題中位延遲的中位數 8232 ms　flip 題數 0

## results_iOS27.0.0_R2_noschema_input_first_20260915-090045.json

- 模式：**R2**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-15T00:57:44Z → 2026-09-15T01:00:45Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 27.0.0 (24A437)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**input_first** — DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim). Reason: FoundationModels language gate rejects the frozen prompt in both spec placements (NLLanguageRecognizer classifies it as Indonesian); putting the Chinese input first flips detection to a supported language
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512, includeSchemaInPrompt=False
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- enum 來源：dev_accounts/dev_categories JSON not present in package; account (21) and category (65) enums parsed programmatically from system_prompt_zh-TW.txt (account names strip trailing currency parentheses, per prompt note 括號內為幣別)（帳戶 21、分類 65）
- R2 schema 省略欄位：confidence, normalized_text, original_text
- 日期解析器：ChineseDateResolver.swift, today fixed to 2026-09-15, week starts Monday; supports 昨天/前天/大前天/明天/後天、N天前後、(上上|上|這|本|下)(週|星期|禮拜)X、單獨 週X=最近一次(含今天)、M/D、M月D日、YYYY-MM-DD、(上|這|下)個月N號、N號、中文數字
- 冷啟動：8802 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `null` want `120`<br>account✓<br>**category✗** got `null` want `飲食>午餐`<br>date✓ | 15145 ms | 14710–15223 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>**amount✗** got `null` want `58000`<br>account✓<br>**category✗** got `null` want `薪資>本薪`<br>date✓ | 3943 ms | 3870–4341 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | **intent✗** got `UPDATE_GOLD_PRICE` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `台積電`<br>**price✗** got `null` want `1085` | 3918 ms | 3904–4116 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `UPDATE_GOLD_PRICE` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `null` want `21.9` | 4025 ms | 4002–4071 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>**price✗** got `null` want `3320`<br>**currency✗** got `null` want `USD`<br>amount✓ | 5549 ms | 5450–5559 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>**amount✗** got `null` want `360`<br>**account✗** got `null` want `南星信用卡`<br>**category✗** got `null` want `娛樂>影音/遊戲`<br>**date✗** got `null` want `2026-09-11` | 4010 ms | 3873–4023 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>**amount✗** got `null` want `23000`<br>**from_account✗** got `null` want `西嶺銀`<br>to_account✓ | 3934 ms | 3906–4083 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>**amount✗** got `null` want `1500`<br>account✓<br>**category✗** got `null` want `投資收益>股息`<br>date✓ | 15146 ms | 15012–15264 | — | 3/3 | — |

**彙總**：全對題數 0/8　JSON 合法率 24/24　各題中位延遲的中位數 4017 ms　flip 題數 0
