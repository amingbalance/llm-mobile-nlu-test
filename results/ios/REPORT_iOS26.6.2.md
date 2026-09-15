# iOS NLU 對照測試報告

## 摘要（iOS 26.6.2 輪，2026-09-15）

**環境**：iPhone 16 Pro Max (iPhone17,2, A18 Pro)、iOS 26.6.2 (23G90)、FoundationModels / `SystemLanguageModel.default`（裝置端，框架無雲端路徑、無模型版本 API）、Xcode 26.6 (17F113)、SDK iOS 26.5。
prompt 逐字讀入（3434 字，sha256 `ab05290577ffa28e…`），temperature 0 / greedy / max 512 tokens，每題每模式 3 次、每次全新 session，warmup 一次。
帳戶 21 / 分類 65 的 enum 由 prompt 檔程式解析（測試包缺 `dev_accounts/dev_categories` JSON）。

### 結論 1：spec 規定的兩種 prompt 放法在 iOS 上無法推論
Apple 的框架在推論前先做語言閘門（等同 `NLLanguageRecognizer` 的主要語言必須在支援清單內）。這份 prompt 因大量 ASCII 識別字被判成**印尼文**，
放 `instructions` 或前置於輸入都在 2 ms 內丟 `unsupportedLanguageOrLocale`，R1/R2 正式結果 **0/8、JSON 合法 0/24**（結果檔 `*_instructions_*`）。
細節與 12 種變體的閘門對照見附件。

### 結論 2：標注為偏差的放法（prompt 內容不變，只改順序）
| 放法 | R1 全對 | R1 中位延遲 | R2(不注入 schema) 全對 | R2 中位延遲 |
|---|---|---|---|---|
| `input_first`：輸入 + 空行 + prompt | 3/8 | 3.35 s | 0/8 | 2.65 s |
| `input_wrapped`：輸入 + 空行 + prompt + 空行 + 輸入 | **4/8** | 3.88 s | 0/8 | 3.34 s |
| R2 注入 schema（`includeSchemaInPrompt=true`，input_first） | — | — | 0/8，c5/c7 爆 context window | 5.79 s |

- 全部 24×N 次 JSON 皆合法（除閘門/context 錯誤），**沒有任何 flip**：Apple 模型在 greedy 下是決定性的，Android 的 102/120 抖動在 iOS 沒出現。
- 冷啟動（第一次建 session 到 warmup 回應）3.7 s。
- 延遲：R1 約 3.2–4.8 s/題，與 Android Gemma 4 E4B 的 3.0–5.5 s 同一量級；R2 不注入 schema 比 R1 快約 0.5 s。

### 結論 3：iOS 模型的失分模式（`input_wrapped` R1 為準）
- **一百二 → 120 正確**（c1），五萬八、兩萬三、一千零八十五、三千三百二十全部正確；中文口語數字不是 Apple 模型的弱點。
- **c4「00878 收在二十一塊九」判成 ADD_EXPENSE**（三種放法、R1/R2 都一樣），和 Gemma E2B 犯的錯同型；Android E4B 答對。
- **硬塞帳戶**：c1 給 `現金`、c7 to_account 給 `現金`（清單裡沒有）；guided 模式下 enum 逼它只能選清單內的值，結果 c7 to_account 變成 `郵儲`（更糟）。
- **c2 薪資>本薪 沒對到**（category null），c8 投資收益>股息 有對到。
- **上週五 → 2026-09-11 正確**（R1 模型自己算的；R2 由程式算也正確）。
- 「沒講日期卻填今天」：R1 c2/c8、R2 全部收入/支出題（輕微違規，分開計）。
- `input_first` 放法下 c4/c5 的輸出是 **few-shot 範例原封照抄**（original_text 都變成範例句），顯示輸入離結尾太遠時範例會蓋過輸入；`input_wrapped` 修正了 c5，c4 仍錯。

### 結論 4：R2（guided generation）在這份 prompt 下反而更差
- optional enum 欄位（category / account / stock）幾乎一律 null（4 組 R2 中 category 只有 0 次答對），這與昨天快速測試觀察到「optional 欄位傾向 null」一致；可能的原因是 prompt 內已有一套 JSON schema 敘述，與 guided schema 互相干擾。
- 注入 schema 進 prompt 會讓 3434 字的 prompt + 65 個分類 enum 超過 4096 token 的 context（c5/c7 全部 `exceededContextWindowSize`）。
- **對產品的含意**：iOS 上要用 guided generation，prompt 必須為它重寫（去掉 JSON schema 敘述與範例、縮短），這和「兩平台同一份 prompt」的前提衝突，須另開版本。

### 尚未完成 / 建議
1. **iOS 27 輪**：待手機升級後用同一份 harness 重跑（需 Xcode 27 才能部署）。要先確認 iOS 27 的語言閘門是否仍擋這份 prompt。
2. **Android R2** 由 Android 端補齊後才能完成 2×2 矩陣。
3. 若要讓 iOS 走 spec 放法，prompt 需要 v2（降低 ASCII 識別字密度即可過閘門，例如把 intent 名稱改為中文或加中文說明），屬新版本，兩平台需同步重跑。

### 檔案
- 結果 JSON：`results/ios/results_iOS26.6.2_<R1|R2|R2_noschema>_<placement>_<timestamp>.json`（spec §7 格式，含 raw_output）
- 本報告由 `tools/score.py`(repo 根目錄) 產生；harness 為 llm_test app 的「對照測試」tab（可由 Mac 用 `devicectl ... --autorun R1,R2 --runs 3 --placement input_wrapped --no-schema-in-prompt` 無人值守執行）

## 並排比較（正確性 = 多數決全對；延遲 = 中位數 ms）

| # | iOS 26.6.2 R1 [input_wrapped] | iOS 26.6.2 R2 [input_wrapped] schema→prompt=no | iOS 26.6.2 R1 [input_first] | iOS 26.6.2 R2 [input_first] schema→prompt=no | iOS 26.6.2 R2 [input_first] schema→prompt=yes | iOS 26.6.2 R1 [instructions] | iOS 26.6.2 R2 [instructions] schema→prompt=yes | Android R1 (Pixel 11 Pro XL, Gemma 4 E4B) |
|---|---|---|---|---|---|---|---|---|
| c1 | ✗ account · 3364 ms | ✗ amount,category · 3076 ms | ✗ account · 3193 ms | ✗ amount,category · 2437 ms | ✗ amount,category · 5302 ms | ✗ intent,amount,category · 4 ms | ✗ intent,amount,category · 3 ms | ⚠️ amount=102 · 4445 ms |
| c2 | ✗ category · 3374 ms | ✗ category · 3341 ms | ✗ category · 3180 ms | ✗ category · 2486 ms | ✗ category · 5437 ms | ✗ intent,amount,category · 3 ms | ✗ intent,amount,category · 3 ms | ✓ · 3075 ms |
| c3 | ✓ · 3491 ms | ✗ price · 3496 ms | ✓ · 3239 ms | ✗ stock,price · 2830 ms | ✗ intent,stock,price · 5801 ms | ✗ intent,stock,price · 2 ms | ✗ intent,stock,price · 2 ms | ✓ · 4399 ms |
| c4 | ✗ intent,stock,price · 4185 ms | ✗ intent,stock,price · 3086 ms | ✗ intent,stock,price · 3549 ms | ✗ intent,stock,price · 2456 ms | ✗ intent,stock,price · 5646 ms | ✗ intent,stock,price · 2 ms | ✗ intent,stock,price · 1 ms | ✓ · 4456 ms |
| c5 | ✓ · 3813 ms | ✗ price,amount · 3517 ms | ✗ price,currency · 3229 ms | ✗ price,amount · 2961 ms | ✗ intent,price,currency · 5840 ms | ✗ intent,price,currency · 3 ms | ✗ intent,price,currency · 2 ms | ✓ · 4480 ms |
| c6 | ✓ · 4760 ms | ✗ account,category · 3041 ms | ✓ · 4018 ms | ✗ account,category,date · 2718 ms | ✗ intent,account,category · 5872 ms | ✗ intent,amount,account,category,date · 2 ms | ✗ intent,amount,account,category,date · 3 ms | ✓ · 5502 ms |
| c7 | ✗ from_account,to_account · 3937 ms | ✗ to_account · 3452 ms | ✗ to_account · 3464 ms | ✗ from_account,to_account · 2623 ms | ✗ intent,amount,from_account · 5874 ms | ✗ intent,amount,from_account · 2 ms | ✗ intent,amount,from_account · 2 ms | ✓ · 4507 ms |
| c8 | ✓ · 4074 ms | ✗ category · 3337 ms | ✓ · 3579 ms | ✗ category · 2668 ms | ✗ category · 5771 ms | ✗ intent,amount,category · 2 ms | ✗ intent,amount,category · 2 ms | —(未測) |

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

## results_iOS26.6.2_R1_input_first_20260915-073802.json

- 模式：**R1**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-14T23:36:40Z → 2026-09-14T23:38:02Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 26.6.2 (23G90)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**input_first** — DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim). Reason: FoundationModels language gate rejects the frozen prompt in both spec placements (NLLanguageRecognizer classifies it as Indonesian); putting the Chinese input first flips detection to a supported language
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- 冷啟動：3702 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>amount✓<br>**account✗** got `北辰信用卡` want `null`<br>category✓<br>date✓ | 3193 ms | 3160–3231 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>amount✓<br>account✓<br>**category✗** got `null` want `薪資>本薪`<br>date✓△填今天 | 3180 ms | 3155–3206 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | intent✓<br>stock✓<br>price✓ | 3239 ms | 3211–3252 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `ADD_EXPENSE` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `null` want `21.9` | 3549 ms | 3540–3564 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>**price✗** got `4580` want `3320`<br>**currency✗** got `TWD` want `USD`<br>amount✓ | 3229 ms | 3213–3241 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>amount✓<br>account✓<br>category✓<br>date✓ | 4018 ms | 3997–4023 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>amount✓<br>from_account✓<br>**to_account✗** got `現金` want `null` | 3464 ms | 3453–3466 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>amount✓<br>account✓<br>category✓<br>date✓ | 3579 ms | 3574–3591 | — | 3/3 | — |

**彙總**：全對題數 3/8　JSON 合法率 24/24　各題中位延遲的中位數 3351 ms　flip 題數 0

## results_iOS26.6.2_R2_noschema_input_first_20260915-074252.json

- 模式：**R2**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-14T23:41:46Z → 2026-09-14T23:42:52Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 26.6.2 (23G90)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**input_first** — DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim). Reason: FoundationModels language gate rejects the frozen prompt in both spec placements (NLLanguageRecognizer classifies it as Indonesian); putting the Chinese input first flips detection to a supported language
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512, includeSchemaInPrompt=False
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- enum 來源：dev_accounts/dev_categories JSON not present in package; account (21) and category (65) enums parsed programmatically from system_prompt_zh-TW.txt (account names strip trailing currency parentheses, per prompt note 括號內為幣別)（帳戶 21、分類 65）
- R2 schema 省略欄位：confidence, normalized_text, original_text
- 日期解析器：ChineseDateResolver.swift, today fixed to 2026-09-15, week starts Monday; supports 昨天/前天/大前天/明天/後天、N天前後、(上上|上|這|本|下)(週|星期|禮拜)X、單獨 週X=最近一次(含今天)、M/D、M月D日、YYYY-MM-DD、(上|這|下)個月N號、N號、中文數字
- 冷啟動：4074 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `122.5` want `120`<br>account✓<br>**category✗** got `null` want `飲食>午餐`<br>date✓△填今天 | 2437 ms | 2407–2454 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>amount✓<br>account✓<br>**category✗** got `null` want `薪資>本薪`<br>date✓△填今天 | 2486 ms | 2458–2508 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | intent✓<br>**stock✗** got `null` want `台積電`<br>**price✗** got `null` want `1085` | 2830 ms | 2807–2849 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `ADD_EXPENSE` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `null` want `21.9` | 2456 ms | 2443–2465 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | intent✓<br>**price✗** got `null` want `3320`<br>currency✓<br>**amount✗** got `3200` want `null` | 2961 ms | 2942–3001 | — | 3/3 | — |
| c6 | 上週五看電影三百六 刷南星卡 | intent✓<br>amount✓<br>**account✗** got `null` want `南星信用卡`<br>**category✗** got `null` want `娛樂>影音/遊戲`<br>**date✗** got `2026-09-15` want `2026-09-11` | 2718 ms | 2712–2721 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | intent✓<br>amount✓<br>**from_account✗** got `青松銀` want `西嶺銀`<br>**to_account✗** got `西嶺銀` want `null` | 2623 ms | 2611–2627 | — | 3/3 | — |
| c8 | 股息入帳一千五百塊 | intent✓<br>amount✓<br>account✓<br>**category✗** got `null` want `投資收益>股息`<br>date✓△填今天 | 2668 ms | 2665–2669 | — | 3/3 | — |

**彙總**：全對題數 0/8　JSON 合法率 24/24　各題中位延遲的中位數 2645 ms　flip 題數 0

## results_iOS26.6.2_R2_input_first_20260915-074024.json

- 模式：**R2**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-14T23:38:02Z → 2026-09-14T23:40:24Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 26.6.2 (23G90)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**input_first** — DEVIATION: no instructions; user turn = input + blank line + frozen prompt (verbatim). Reason: FoundationModels language gate rejects the frozen prompt in both spec placements (NLLanguageRecognizer classifies it as Indonesian); putting the Chinese input first flips detection to a supported language
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512, includeSchemaInPrompt=True
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- enum 來源：dev_accounts/dev_categories JSON not present in package; account (21) and category (65) enums parsed programmatically from system_prompt_zh-TW.txt (account names strip trailing currency parentheses, per prompt note 括號內為幣別)（帳戶 21、分類 65）
- R2 schema 省略欄位：confidence, normalized_text, original_text
- 日期解析器：ChineseDateResolver.swift, today fixed to 2026-09-15, week starts Monday; supports 昨天/前天/大前天/明天/後天、N天前後、(上上|上|這|本|下)(週|星期|禮拜)X、單獨 週X=最近一次(含今天)、M/D、M月D日、YYYY-MM-DD、(上|這|下)個月N號、N號、中文數字
- 冷啟動：3702 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | intent✓<br>**amount✗** got `182.5` want `120`<br>account✓<br>**category✗** got `null` want `飲食>午餐`<br>date✓△填今天 | 5302 ms | 5048–5337 | — | 3/3 | — |
| c2 | 薪水入帳五萬八 | intent✓<br>amount✓<br>account✓<br>**category✗** got `null` want `薪資>本薪`<br>date✓△填今天 | 5437 ms | 5313–5521 | — | 3/3 | — |
| c3 | 台積電改成一千零八十五 | **intent✗** got `UPDATE_GOLD_PRICE` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `台積電`<br>**price✗** got `null` want `1085` | 5801 ms | 5764–5853 | — | 3/3 | — |
| c4 | 00878 收在二十一塊九 | **intent✗** got `ADD_EXPENSE` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `null` want `21.9` | 5646 ms | 5621–5665 | — | 3/3 | — |
| c5 | 金價一盎司三千三百二十美金 | **intent✗** got `null` want `UPDATE_GOLD_PRICE`<br>**price✗** got `null` want `3320`<br>**currency✗** got `null` want `USD`<br>amount✓ | 5840 ms | 5823–5879 | — | 0/3 | exceededContextWindowSize |
| c6 | 上週五看電影三百六 刷南星卡 | **intent✗** got `ADD_INCOME` want `ADD_EXPENSE`<br>amount✓<br>**account✗** got `null` want `南星信用卡`<br>**category✗** got `null` want `娛樂>影音/遊戲`<br>date✓ | 5872 ms | 5798–5922 | — | 3/3 | — |
| c7 | 從西嶺轉兩萬三到現金 | **intent✗** got `null` want `ADD_TRANSFER`<br>**amount✗** got `null` want `23000`<br>**from_account✗** got `null` want `西嶺銀`<br>to_account✓ | 5874 ms | 5864–5889 | — | 0/3 | exceededContextWindowSize |
| c8 | 股息入帳一千五百塊 | intent✓<br>amount✓<br>account✓<br>**category✗** got `null` want `投資收益>股息`<br>date✓△填今天 | 5771 ms | 5716–6554 | — | 3/3 | — |

**彙總**：全對題數 0/8　JSON 合法率 18/24　各題中位延遲的中位數 5786 ms　flip 題數 0

## results_iOS26.6.2_R1_instructions_20260915-073628.json

- 模式：**R1**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-14T23:36:27Z → 2026-09-14T23:36:28Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 26.6.2 (23G90)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**instructions** — frozen prompt as LanguageModelSession(instructions:); user turn = input only
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- 冷啟動：21 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次；warmup 錯誤：unsupportedLanguageOrLocale）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | **intent✗** got `null` want `ADD_EXPENSE`<br>**amount✗** got `null` want `120`<br>account✓<br>**category✗** got `null` want `飲食>午餐`<br>date✓ | 4 ms | 3–5 | — | 0/3 | unsupportedLanguageOrLocale |
| c2 | 薪水入帳五萬八 | **intent✗** got `null` want `ADD_INCOME`<br>**amount✗** got `null` want `58000`<br>account✓<br>**category✗** got `null` want `薪資>本薪`<br>date✓ | 3 ms | 3–4 | — | 0/3 | unsupportedLanguageOrLocale |
| c3 | 台積電改成一千零八十五 | **intent✗** got `null` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `台積電`<br>**price✗** got `null` want `1085` | 2 ms | 2–3 | — | 0/3 | unsupportedLanguageOrLocale |
| c4 | 00878 收在二十一塊九 | **intent✗** got `null` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `null` want `21.9` | 2 ms | 2–3 | — | 0/3 | unsupportedLanguageOrLocale |
| c5 | 金價一盎司三千三百二十美金 | **intent✗** got `null` want `UPDATE_GOLD_PRICE`<br>**price✗** got `null` want `3320`<br>**currency✗** got `null` want `USD`<br>amount✓ | 3 ms | 1–4 | — | 0/3 | unsupportedLanguageOrLocale |
| c6 | 上週五看電影三百六 刷南星卡 | **intent✗** got `null` want `ADD_EXPENSE`<br>**amount✗** got `null` want `360`<br>**account✗** got `null` want `南星信用卡`<br>**category✗** got `null` want `娛樂>影音/遊戲`<br>**date✗** got `null` want `2026-09-11` | 2 ms | 1–2 | — | 0/3 | unsupportedLanguageOrLocale |
| c7 | 從西嶺轉兩萬三到現金 | **intent✗** got `null` want `ADD_TRANSFER`<br>**amount✗** got `null` want `23000`<br>**from_account✗** got `null` want `西嶺銀`<br>to_account✓ | 2 ms | 1–3 | — | 0/3 | unsupportedLanguageOrLocale |
| c8 | 股息入帳一千五百塊 | **intent✗** got `null` want `ADD_INCOME`<br>**amount✗** got `null` want `1500`<br>account✓<br>**category✗** got `null` want `投資收益>股息`<br>date✓ | 2 ms | 2–3 | — | 0/3 | unsupportedLanguageOrLocale |

**彙總**：全對題數 0/8　JSON 合法率 0/24　各題中位延遲的中位數 2 ms　flip 題數 0

## results_iOS26.6.2_R2_instructions_20260915-073628.json

- 模式：**R2**　題組 2026-09-14　今天凍結 2026-09-15　執行 2026-09-14T23:36:28Z → 2026-09-14T23:36:28Z
- 裝置：iPhone17,2 (iPhone 16 Pro Max)（A18 Pro）　OS：iOS 26.6.2 (23G90)　Xcode 2660 (17F113)　SDK iphoneos26.5
- 框架：FoundationModels (SystemLanguageModel.default, on-device)　模型：availability=available; framework exposes no model version API
- prompt 放置：**instructions** — frozen prompt as LanguageModelSession(instructions:); user turn = input only
- prompt 字數 3434　sha256 ab05290577ffa28e…
- 解碼：temperature=0, sampling=greedy (GenerationOptions.SamplingMode.greedy), maximumResponseTokens=512, includeSchemaInPrompt=True（preflight error: unsupportedLanguageOrLocale）
- 雲端 fallback：FoundationModels SystemLanguageModel is on-device only by API design (no cloud/PCC path exists); network reachability at run start recorded in network_reachable_during_run；執行時網路可達=True
- session：new LanguageModelSession(instructions:) per run; session creation and schema compile excluded from latency_ms；每題 3 次
- enum 來源：dev_accounts/dev_categories JSON not present in package; account (21) and category (65) enums parsed programmatically from system_prompt_zh-TW.txt (account names strip trailing currency parentheses, per prompt note 括號內為幣別)（帳戶 21、分類 65）
- R2 schema 省略欄位：confidence, normalized_text, original_text
- 日期解析器：ChineseDateResolver.swift, today fixed to 2026-09-15, week starts Monday; supports 昨天/前天/大前天/明天/後天、N天前後、(上上|上|這|本|下)(週|星期|禮拜)X、單獨 週X=最近一次(含今天)、M/D、M月D日、YYYY-MM-DD、(上|這|下)個月N號、N號、中文數字
- 冷啟動：21 ms（本次 app 啟動第一次建 session 到 warmup 完整回應的 wall-clock（placement 同正式輪；instructions 放法用短 prompt「測試」，其他放法用 c1 輸入）；每次啟動只量一次；warmup 錯誤：unsupportedLanguageOrLocale）

| # | 輸入 | 多數決結果 | 中位延遲 | min–max | flip 欄位 | JSON 合法 | 錯誤 |
|---|------|-----------|---------:|--------:|-----------|:---------:|------|
| c1 | 午餐花了一百二 用現金 | **intent✗** got `null` want `ADD_EXPENSE`<br>**amount✗** got `null` want `120`<br>account✓<br>**category✗** got `null` want `飲食>午餐`<br>date✓ | 3 ms | 2–3 | — | 0/3 | unsupportedLanguageOrLocale |
| c2 | 薪水入帳五萬八 | **intent✗** got `null` want `ADD_INCOME`<br>**amount✗** got `null` want `58000`<br>account✓<br>**category✗** got `null` want `薪資>本薪`<br>date✓ | 3 ms | 2–3 | — | 0/3 | unsupportedLanguageOrLocale |
| c3 | 台積電改成一千零八十五 | **intent✗** got `null` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `台積電`<br>**price✗** got `null` want `1085` | 2 ms | 2–2 | — | 0/3 | unsupportedLanguageOrLocale |
| c4 | 00878 收在二十一塊九 | **intent✗** got `null` want `UPDATE_STOCK_PRICE`<br>**stock✗** got `null` want `00878`<br>**price✗** got `null` want `21.9` | 1 ms | 1–2 | — | 0/3 | unsupportedLanguageOrLocale |
| c5 | 金價一盎司三千三百二十美金 | **intent✗** got `null` want `UPDATE_GOLD_PRICE`<br>**price✗** got `null` want `3320`<br>**currency✗** got `null` want `USD`<br>amount✓ | 2 ms | 1–5 | — | 0/3 | unsupportedLanguageOrLocale |
| c6 | 上週五看電影三百六 刷南星卡 | **intent✗** got `null` want `ADD_EXPENSE`<br>**amount✗** got `null` want `360`<br>**account✗** got `null` want `南星信用卡`<br>**category✗** got `null` want `娛樂>影音/遊戲`<br>**date✗** got `null` want `2026-09-11` | 3 ms | 2–4 | — | 0/3 | unsupportedLanguageOrLocale |
| c7 | 從西嶺轉兩萬三到現金 | **intent✗** got `null` want `ADD_TRANSFER`<br>**amount✗** got `null` want `23000`<br>**from_account✗** got `null` want `西嶺銀`<br>to_account✓ | 2 ms | 1–5 | — | 0/3 | unsupportedLanguageOrLocale |
| c8 | 股息入帳一千五百塊 | **intent✗** got `null` want `ADD_INCOME`<br>**amount✗** got `null` want `1500`<br>account✓<br>**category✗** got `null` want `投資收益>股息`<br>date✓ | 2 ms | 1–5 | — | 0/3 | unsupportedLanguageOrLocale |

**彙總**：全對題數 0/8　JSON 合法率 0/24　各題中位延遲的中位數 2 ms　flip 題數 0

# 附件：Apple FoundationModels 語言閘門對凍結 prompt 的行為（2026-09-15）

環境：macOS 26.6.2 (Apple Silicon, Apple Intelligence 開啟) 與 iPhone 16 Pro Max iOS 26.6.2 行為一致；
`SystemLanguageModel.default.supportedLanguages` 含 zh-Hant-TW、zh-Hant-HK、zh-Hans-CN、en、ja、ko … 共 23 種。

## 現象
凍結 prompt `system_prompt_zh-TW.txt`（3434 字）不論放 `instructions` 或前置於使用者輸入，每次請求都在 1–6 ms 內丟出
`LanguageModelSession.GenerationError.unsupportedLanguageOrLocale("Unsupported language.")`，模型完全沒有推論。

## 規律（Mac 上以 maximumResponseTokens=1 只測閘門）
失敗 ⇔ `NLLanguageRecognizer.dominantLanguage` 判成 **id（印尼文，未支援）**；判成 en / zh-Hant / it 等支援語言就放行。
prompt 內大量 ASCII 識別字（`UPDATE_GOLD_PRICE`、`slot`、`amount`、`account`、JSON schema、範例 JSON）讓偵測落在 id 0.35 / en 0.22 之間。

| 變體 | NL 判定 | 閘門 |
|---|---|---|
| 凍結 prompt 當 instructions，輸入當 prompt（spec 主要放法） | id | FAIL |
| 凍結 prompt + 空行 + 輸入（spec 備案：前置） | id | FAIL |
| **輸入 + 空行 + 凍結 prompt**（輸入在前） | en | PASS |
| 「測試」+ 空行 + 凍結 prompt | id | FAIL |
| 前 10 行（intent 定義）單獨 | id | FAIL |
| 前 30 行（含帳戶清單） | zh-Hant | PASS |
| 去掉範例段 | zh-Hant | PASS |
| 範例段單獨 | en | PASS |
| 前 200 字 | zh-Hant | PASS |
| 前 500 字 | id | FAIL |
| `SystemLanguageModel(guardrails: .permissiveContentTransformations)` | id | FAIL（閘門不屬於 guardrails） |
| 凍結 prompt 放進 Transcript 歷史 | id | FAIL |

8 題輸入逐題驗證：instructions / 前置 兩種放法 8 題全 FAIL；輸入在前 8 題全 PASS。

## 對測試的影響
- spec §2 允許的兩種放法在 iOS 端都無法讓模型推論，R1/R2 在 spec 放法下的正式結果為 0/8（全部 unsupportedLanguageOrLocale），已如實產出結果檔。
- 另開一輪 **標注為偏差** 的「輸入在前」放法（prompt 內容逐字不變，只是順序：輸入、空行、凍結 prompt；無 instructions），
  結果檔 `system_prompt_placement = "input_first"`、`placement_note` 註明原因。與 Android 對照時須註明此差異。
- 若要讓 iOS 走 spec 放法，唯一的解法是改 prompt（例如減少 ASCII 識別字密度），這屬於新版本 prompt，需另開一輪並兩平台同步。
