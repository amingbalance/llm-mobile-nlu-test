# iOS NLU 對照測試報告

## 並排比較（正確性 = 多數決全對；延遲 = 中位數 ms）

| # | iOS 27.0.0 R1 [instructions] @06:07Z | iOS 26.6.2 R1 [input_wrapped] @23:43Z | iOS 27.0.0 R1 [input_wrapped] @06:21Z | iOS 27.0.0 R2 [instructions] @06:10Z schema→prompt=yes | iOS 26.6.2 R2 [input_wrapped] @23:44Z schema→prompt=no | iOS 27.0.0 R2 [input_wrapped] @06:23Z schema→prompt=no | Android R1 (Pixel 11 Pro XL, Gemma 4 E4B) |
|---|---|---|---|---|---|---|---|
| c1 | ✗ amount · 5441 ms | ✗ account · 3364 ms | ✗ amount · 5048 ms | ✗ amount,account · 6645 ms | ✗ amount,category · 3076 ms | ✗ amount,category · 3544 ms | ⚠️ amount=102 · 4445 ms |
| c2 | ✓ · 5400 ms | ✗ category · 3374 ms | ✓ · 5068 ms | ✗ account · 6636 ms | ✗ category · 3341 ms | ✗ amount,category · 3683 ms | ✓ · 3075 ms |
| c3 | ✓ · 5317 ms | ✓ · 3491 ms | ✓ · 5010 ms | ✗ price · 5667 ms | ✗ price · 3496 ms | ✗ stock,price · 3683 ms | ✓ · 4399 ms |
| c4 | ✗ intent,stock,price · 5532 ms | ✗ intent,stock,price · 4185 ms | ✗ intent,stock,price · 5753 ms | ✗ intent,stock,price · 5125 ms | ✗ intent,stock,price · 3086 ms | ✗ intent,stock,price · 3689 ms | ✓ · 4456 ms |
| c5 | ✓ · 5615 ms | ✓ · 3813 ms | ✓ · 5211 ms | ✗ price · 6344 ms | ✗ price,amount · 3517 ms | ✗ price,currency · 13977 ms | ✓ · 4480 ms |
| c6 | ✓ · 6462 ms | ✓ · 4760 ms | ✗ account,date · 6512 ms | ✗ amount,account · 6849 ms | ✗ account,category · 3041 ms | ✗ amount,account,category,date · 3777 ms | ✓ · 5502 ms |
| c7 | ✗ to_account · 5397 ms | ✗ from_account,to_account · 3937 ms | ✗ to_account · 6558 ms | ✗ from_account,to_account · 6756 ms | ✗ to_account · 3452 ms | ✗ amount,from_account · 14505 ms | ✓ · 4507 ms |
| c8 | ✗ intent,category · 6239 ms | ✓ · 4074 ms | ✓ · 6000 ms | ✗ account · 7163 ms | ✗ category · 3337 ms | ✗ amount,category · 3792 ms | —(未測) |

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

## results_iOS26.6.2_R1_input_wrapped_20260915-074450.json

- 模式：**R1**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-14T23:43:17Z → 2026-09-14T23:44:50Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 26.6.2 (23G90)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**input_wrapped** — DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim) + blank line + input. The trailing input is the spec 'prepended' order; the leading copy exists only to pass the language gate. Input therefore appears twice
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- 冷啟動：3807 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>amount✓<br>**account✗** got `現金` want `null`<br>category✓<br>date✓ | 3364 ms | 3320–3412 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>amount✓<br>account✓<br>**category✗** got `null` want `薪資>本薪`<br>date✓△填今天 | 3374 ms | 3343–3402 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | intent✓<br>stock✓<br>price✓ | 3491 ms | 3469–3510 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `ADD_EXPENSE` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `null` want `21.9` | 4185 ms | 4174–4185 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>price✓<br>currency✓<br>amount✓ | 3813 ms | 3583–4012 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>amount✓<br>account✓<br>category✓<br>date✓ | 4760 ms | 4759–4761 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>amount✓<br>**from_account✗** got `null` want `西嶺銀`<br>**to_account✗** got `現金` want `null` | 3937 ms | 3933–3970 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>amount✓<br>account✓<br>category✓<br>date✓△填今天 | 4074 ms | 4072–4076 | — | 3/3 | — |

**彙總**：全對題數 4/8　JSON 合法率 24/24　各題中位延遲的中位數 3875 ms　flip 題數 0

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

## results_iOS26.6.2_R2_noschema_input_wrapped_20260915-074612.json

- 模式：**R2**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-14T23:44:50Z → 2026-09-14T23:46:12Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 26.6.2 (23G90)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**input_wrapped** — DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim) + blank line + input. The trailing input is the spec 'prepended' order; the leading copy exists only to pass the language gate. Input therefore appears twice
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512, includeSchemaInPrompt=False
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- enum 來源：dev_accounts/dev_categories JSON not present in package; account (21) and category (65) enums parsed programmatically from system_prompt_zh-TW.txt (account names strip trailing currency parentheses, per prompt note 括號內為幣別)（帳戶 21、分類 65）
- R2 schema 省略欄位：confidence, normalized_text, original_text
- 日期解析器：ChineseDateResolver.swift, today fixed to 2026-09-15, week starts Monday; supports 昨天/前天/大前天/明天/後天、N天前後、(上上|上|這|本|下)(週|星期|禮拜)X、單獨 週X=最近一次(含今天)、M/D、M月D日、YYYY-MM-DD、(上|這|下)個月N號、N號、中文數字
- 冷啟動：3807 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `122.5` want `120`<br>account✓<br>**category✗** got `null` want `飲食>午餐`<br>date✓△填今天 | 3076 ms | 3064–3101 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>amount✓<br>account✓<br>**category✗** got `null` want `薪資>本薪`<br>date✓△填今天 | 3341 ms | 3339–3356 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | intent✓<br>stock✓<br>**price✗** got `null` want `1085` | 3496 ms | 3493–3498 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `ADD_EXPENSE` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `null` want `21.9` | 3086 ms | 3076–3089 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>**price✗** got `null` want `3320`<br>currency✓<br>**amount✗** got `3320` want `null` | 3517 ms | 3515–3545 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>amount✓<br>**account✗** got `null` want `南星信用卡`<br>**category✗** got `null` want `娛樂>影音/遊戲`<br>date✓ | 3041 ms | 3040–3098 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>amount✓<br>from_account✓<br>**to_account✗** got `郵儲` want `null` | 3452 ms | 3451–3479 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>amount✓<br>account✓<br>**category✗** got `null` want `投資收益>股息`<br>date✓△填今天 | 3337 ms | 3325–3351 | — | 3/3 | — |

**彙總**：全對題數 0/8　JSON 合法率 24/24　各題中位延遲的中位數 3339 ms　flip 題數 0

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
