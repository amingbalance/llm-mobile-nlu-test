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
