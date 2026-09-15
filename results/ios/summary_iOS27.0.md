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
