# iOS 端 LLM 測試設計準則(語音記帳 NLU 對照)

> 2026-09-14 制定。給 iOS 端實作者(AI agent)照此規範寫測試 harness。
> 測試素材(凍結 prompt、題組、評分規則)在同目錄:`system_prompt_zh-TW.txt`、`testcases.json`、`README.md`。
> 本次要在 **iOS 26.6.2 與 iOS 27** 各跑一輪,產出 2(OS)× 2(模式)= 4 組結果。

---

## 1. 兩種模式(兩者都要跑)

| 模式 | 定義 | 回答的問題 |
|------|------|-----------|
| **R1 model-only** | 純 prompt。凍結 prompt 逐字使用、**不開 guided generation**、日期交給模型算 | 模型本身 vs Gemma 4 E4B 誰強(Android 基準即此模式) |
| **R2 best-mode** | 開 **guided generation**(schema + enum 約束)、**日期改由程式解析** | 產品實際上線形態的速度與準確率 |

R1/R2 的輸入題組、次數、計時方式完全相同,只差輸出約束與日期處理。

## 2. 不可變事項(違反任一條,該輪結果作廢)

1. **Prompt**:`system_prompt_zh-TW.txt` 整檔逐字讀入(UTF-8),不增刪一字。放在 instructions/system 位置;若框架不支援,前置於使用者輸入(空一行),用哪種記錄下來
2. **輸入**:`testcases.json` 的 `input` 字串直接送入,不過 STT、不做任何前處理
3. **日期凍結**:prompt 內「今天日期:2026-09-15(星期二)」不許改。R2 的程式日期解析也以 2026-09-15 為「今天」
4. **解碼**:temperature=0;有 topK/topP 就設成等效 greedy(topK=1);max output tokens ≥ 512。實際可設定的參數與值全部記錄
5. **每題每模式跑 3 次**;每次推論**必須用全新的 session/context**(不可重用——前一題的對話殘留會汙染結果)
6. **On-device only**:確認走裝置端模型,雲端 fallback(若有)必須關閉並記錄確認方式
7. 正式計時前先做一次 warmup(任意短 prompt);warmup 不計入,但**冷啟動時間單獨記一筆**(每個 OS 一次:從第一次建 session 到第一個回應完成)

## 3. 計時邊界

- `latency_ms` = 送出該次請求 → 收到**完整**回應(最後一個 token)為止的 wall-clock
- 不含 session 建立、schema 編譯、prompt 檔讀取
- 若 API 只有 streaming,取「送出 → 最終 token」;一併記下「送出 → 首 token」當附加資料(選填)

## 4. R1 實作規格

- 輸出解析:抓回應中第一個 `{` 到最後一個 `}` 之間的內容 parse JSON(與 Android 端同樣容錯);parse 失敗記 `json_valid=false`,原文照存
- 不做任何 retry:失敗就是該次結果

## 5. R2 實作規格(guided generation)

Schema 欄位(對應 `testcases.json` 的 slots):

| 欄位 | 型別 | 約束 |
|------|------|------|
| intent | enum | UPDATE_GOLD_PRICE / UPDATE_STOCK_PRICE / ADD_INCOME / ADD_EXPENSE / ADD_TRANSFER / UNKNOWN |
| amount, price | Double? | — |
| currency | enum? | TWD / USD |
| stock | String? | 照字面 |
| account, from_account, to_account | enum? | **21 個帳戶名**(值域從 `dev_accounts_2026-08-22.json` 取 status=ACTIVE 的 `name`,**用程式生成,禁止手打**,避免打錯字) |
| category | enum? | **65 個「父>子」路徑**(從 `dev_categories_2026-08-22.json` 生成:`父名>子名`;無子類則父名) |
| date_text | String? | 原句的日期字面(如「上週五」「昨天」);**沒講日期給 null** |
| note | String? | — |

- **日期**:模型只回 `date_text`,由程式以「今天=2026-09-15」用行事曆運算解析成 ISO(上週五→2026-09-11、昨天→2026-09-14…),解析結果當作該次的 `date` 參與評分。解析器規則要附在結果報告裡
- prompt 仍用同一份凍結檔(規則裡的 JSON schema 敘述與 guided schema 或有重疊,不用改;維持與 R1 同 prompt 才可歸因)
- confidence / normalized_text 可以留在 schema 裡也可拿掉(不計分),但要記錄你的選擇

## 6. iOS 26.6.2 vs iOS 27

- 兩個 OS 都跑 R1 + R2 完整題組(8 題 × 3 次)
- 記錄:裝置型號、OS build、framework(FoundationModels 等)、模型可用性 API 的回報值、可取得的模型版本識別(有什麼記什麼)
- 若兩個 OS 在**不同實體裝置**上跑,必須註明兩台的型號/晶片——晶片不同時延遲不可直接互比,只比正確率
- 同一份 harness 程式碼跑兩個 OS,不要各寫一份

## 7. 結果交付格式

每組(OS × 模式)一個 JSON:`results_<os>_<R1|R2>.json`

```json
{
  "env": {"device":"", "os":"", "framework":"", "model_id_or_availability":"", "system_prompt_placement":"instructions|prepended", "decoding":{"temperature":0, "...":"實際值"}, "cloud_fallback_disabled_how":""},
  "cold_start_ms": 0,
  "runs": [
    {"case_id":"c1","run":1,"latency_ms":0,"first_token_ms":null,"json_valid":true,
     "parsed":{"intent":"","amount":null,"price":null,"currency":null,"stock":null,"account":null,"from_account":null,"to_account":null,"category":null,"date":null,"note":null},
     "raw_output":""}
  ]
}
```

彙總表(每組):每題 intent/各 slot 多數決正確性(對照 `testcases.json` expected)、延遲中位數、flip 次數、JSON 合法率。評分細則照 `testcases.json.scoring`(confidence/normalized_text/note 不計分;「沒講日期卻填今天」記輕微違規不算錯)。

## 8. 禁止事項

- 不改 prompt、不加 few-shot、不加 retry/self-correction
- R1 不開任何格式約束;R2 之外不做 date 程式解析
- 不因某題表現差而調整後重跑(要調整就是新版本,另開一輪並標注)

## 9. 對照組現況(Android)

- R1 基準已完成:見 `README.md` §6(Gemma 4 E4B / Pixel 11 / 3.0–5.5s;c8 未測)
- Android R2(ML Kit structured output,`@Generable`/`@Guide` + 動態 enum)由 Android 端另補,屆時 2 平台 × 2 模式對齊成完整矩陣
