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
