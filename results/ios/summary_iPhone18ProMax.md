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
