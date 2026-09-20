# On-device LLM 語音記帳 NLU 測試：Android Gemma 4 vs iOS Apple Foundation Models

驗證「一句中文語音記帳 → 裝置端 LLM → `intent + slots` JSON」在兩個平台上的可行性、正確率與延遲。
同一份**凍結 prompt**、同一組 8 句輸入、同一套評分，分別跑在

| 平台 | 模型 / 框架 | 測試 app |
|---|---|---|
| Android | Gemma 4 E4B（AICore Developer Preview）／ ML Kit GenAI Prompt API | [`android/`](android/)（Kotlin + Compose） |
| iOS | Apple 裝置端模型（Apple Intelligence）／ FoundationModels | [`ios/`](ios/)（SwiftUI） |

> 背景：這是個人記帳 app（AMing Balance）「語音記帳」功能的前期實驗。模型只做語言層（意圖、slot 抽取），不碰 DB、不執行。
> 程式碼與文件由 Claude Code 協助產生，實測數據在真機上量測（2026-08 ~ 2026-09）。

---

## 1. 一頁結論

**Android Gemma 4 E4B + structured output 是可上線的形態**：8 題 7 對（唯一錯的口語數字「一百二」由 STT 層解決，實質全對）、單句 3.7–4.0 s、72 次推論零 flip。
iOS 的 Apple 裝置端模型在同一份 prompt 下 R1 只有 3–4/8，開 guided generation 反而 0–1/8；而且 **OS 升級會換模型、換手機也會換模型**（iOS 26 → 27 同題答案不同；iPhone 18 Pro Max 被系統分配到 AFM 3 Core Advanced 變體，快到約 2 s，但半數輸出不照 schema 給 `slots`）。

### 2 平台 × 2 模式 矩陣（每題 3 次多數決，全對題數 @ 中位延遲）

| | **R1 純 prompt**（模型 vs 模型） | **R2 structured / guided output**（產品形態） |
|---|---|---|
| **Android** Gemma 4 E4B（Pixel 11 Pro XL, Android 17, TPU） | **6/8** @ 3.2 s，零 flip | **7/8** @ 3.7–4.0 s，零 flip |
| **iOS 26.6.2** Apple FM（iPhone 16 Pro Max, A18 Pro） | 4/8 @ 3.9 s（偏差放法，見下） | 0/8 |
| **iOS 27.0** Apple FM（同一台，升級 OS） | 4/8 @ 5.5 s | 0/8 |
| **iOS 27.0** Apple FM **Core Advanced**（iPhone 18 Pro Max，09-20 補測） | 3/8 @ 2.0 s（24 次中 12 次缺 `slots`） | 1/8 @ 2.7 s |

### R1 逐項對照

| | Android Gemma 4 E4B | iOS 26.6.2（16 Pro Max） | iOS 27.0（16 Pro Max） | iOS 27.0（**18 Pro Max**，Core Advanced） |
|---|---|---|---|---|
| prompt 放法 | spec（`SystemInstruction`） | **偏差**（`input_wrapped`；spec 放法被語言閘門擋） | spec（`instructions`） | spec（`instructions`） |
| 全對 | **6/8** | 4/8 | 4/8 | 3/8 |
| 延遲中位 | 3.2 s（08-22 手測 3.0–5.5 s） | 3.9 s | 5.5 s | **2.0 s**（輸出只有 47% 長） |
| 每字延遲 | 11.4 ms | 14.6 ms | 13.6 ms | 10.4 ms |
| 決定性（temp=0） | 官方輪零 flip；手測曾見 102/120 抖動 | 零 flip | 零 flip | 零 flip |
| JSON 合法 | 100% | 100% | 100%（多包 ```json 圍欄） | 21/24（c6 壞 JSON） |
| 照 schema 輸出 `slots` | 24/24 | 24/24 | 24/24 | **12/24** |
| c1「一百二」 | 102 ✗ | **120 ✓** | 112 ✗ | 讀成 120，但沒輸出 slots ✗ |
| c4「00878 收在二十一塊九」 | **✓** | ✗（判成支出） | ✗（判成金價 / UNKNOWN） | **✓**（iOS 首次答對） |
| c7「轉到現金」（清單無此帳戶） | R1 硬塞 ✗ → **R2 enum 約束修好 ✓** | 硬塞「現金」✗ | 硬塞「現金」✗ | 沒輸出 slots ✗ |
| c8「股息入帳」 | ✓ | ✓ | ✗（判成改股價） | 沒輸出 slots ✗ |

> iPhone 16 Pro Max 與 18 Pro Max 之間同時差了硬體、SDK、OS build、量測日與**模型變體**，不是單一變因的比較；細節見 [`results/ios/summary_iPhone18ProMax.md`](results/ios/summary_iPhone18ProMax.md)。

### 平台層事實（與模型無關，但影響產品）

1. **iOS 26 語言閘門**：FoundationModels 推論前會用 `NLLanguageRecognizer` 判主要語言，這份 prompt 因大量 ASCII 識別字被判成印尼文，`instructions` / 前置兩種 spec 放法都在 2 ms 內丟 `unsupportedLanguageOrLocale`。iOS 27 放行。把輸入句放在最前面（`input_first` / `input_wrapped`）可繞過，結果檔有標注偏差。
2. **Apple FM context 依變體而定**：iPhone 16 Pro Max 約 4096 token，schema 注入 prompt 就爆；iPhone 18 Pro Max 的 Core Advanced 為 8192。Android `tokenLimit` 8192。
3. **iOS 27 輸出風格改變**（```json 圍欄 + 縮排，字元 +50%），吐字速率沒變，但單句慢約 1.6 s。
4. **iOS guided generation 與 prompt 內的 JSON schema 敘述互相干擾**：iOS 26 optional enum 幾乎全 null，iOS 27 改成硬塞清單值或 `note` 欄位重複到 512 token 上限。要用 guided 就要為它重寫 prompt（v2）。
5. **模型跟著 OS 換，沒有版本 API 可偵測**：iOS 26→27 同題 c1 120→112、c8 ✓→✗、c2 分類 ✗→✓。這套測試包正好當每次 OS 升級的回歸套件。
6. **模型變體由系統依裝置分配，app 不能選**：iOS 27 SDK 新增唯讀的 `SystemLanguageModel.variant`（`core3` / `coreAdvanced3`）。iPhone 18 Pro Max 與 M3 Mac 是 `coreAdvanced3`，輸出習慣完全不同（單行 JSON、無圍欄、半數不給 `slots`）；為 iOS 26 語言閘門設計的「輸入在前」偏差放法在它上面 0/8。同一版 app 要同時面對兩種模型。
7. 口語數字「一百二」三個模型三個答案（102 / 120 / 112）：**金額數字正規化交給 STT 或程式，不交給 LLM**。

完整數據與逐題表：[`results/FINAL_VERDICT.md`](results/FINAL_VERDICT.md)、[`results/ios/summary_iPhone18ProMax.md`](results/ios/summary_iPhone18ProMax.md)、[`results/ios/`](results/ios/)、[`results/android/`](results/android/)。

---

## 2. Repo 結構

```
.
├── README.md                    ← 本文件
├── nlu_crosstest/               ← 測試包（唯一的正本）
│   ├── README.md                   測試設計、控制變因、8 題與預期、Android 手測基準
│   ├── ios_test_design_spec.md     R1/R2 定義、不可變事項、結果 JSON 格式
│   ├── system_prompt_zh-TW.txt     凍結 prompt（3,434 字，日期凍結 2026-09-15，不要改）
│   ├── testcases.json              8 題 + 預期 + 評分規則
│   └── dev_accounts_*.json / dev_categories_*.json   帳戶 / 分類清單（prompt 與 enum 由此生成）
├── results/
│   ├── FINAL_VERDICT.md            最終結論（2×2 矩陣、逐題分析）
│   ├── android/                    Android 官方輪結果 JSON（R1 / R2 / R2_noschema）
│   └── ios/                        iPhone 16 Pro Max（iOS 26.6.2 / 27.0）與 iPhone 18 Pro Max（iOS 27.0）結果 JSON + REPORT_*.md + summary_*.md + 語言閘門探測
├── docs/
│   ├── model_settings.md                  兩平台模型設定對照：實際呼叫的 API 與參數
│   ├── voice_intent_gemma_handoff.md      需求端 handoff：intent 定義、JSON 約定、app 決策層
│   └── gemma4_feasibility_handoff.md      Android 可行性結案報告：技術路線、延遲、prompt 設計、導入建議
├── tools/
│   ├── score.py                    評分 / 報告產生器（iOS 與 Android 結果檔都能讀）
│   └── sync_crosstest.sh           把 nlu_crosstest/ 同步到兩個 app 實際載入的位置
├── android/                        Android 測試 app（Gemma 4 / AICore）→ android/README.md
└── ios/                            iOS 測試 app（FoundationModels）→ ios/README.md
```

**測試包只在 `nlu_crosstest/` 修改。** 兩個 app 讀的是它的複本（`ios/nlu_crosstest/`、`android/app/src/main/assets/`），改完跑 `tools/sync_crosstest.sh`；`tools/sync_crosstest.sh --check` 可確認複本沒有走樣。

---

## 3. 快速上手

### Android（詳見 [`android/README.md`](android/README.md)）

1. **裝置**：有 AICore 的 Pixel（實測 Pixel 11 Pro XL，Android 17）。Pixel 9 系列只能跑 CPU 版，E2B 一句 ~23 s、E4B 不穩，只能拿來驗流程。
2. **加入 AICore Developer Preview 測試計畫**（沒做這步，Preview 模型不會出現在 AICore app 裡，`checkStatus()` 會丟 `FEATURE_NOT_FOUND`）：
   - 用測試手機登入的 Google 帳號加入 [aicore-experimental](https://groups.google.com/g/aicore-experimental) Google Group
   - 成為 [Android AICore testing program](https://play.google.com/apps/testing/com.google.android.aicore) 的 tester
   - 到 Play 商店把 **AICore** app 更新到 preview 版（版本名帶 `thirdpartyexperimental` / `thirdpartyeap`）
3. **在 AICore app 裡選一個 [Preview] 模型並等它下載完**（約 3–5 GB，需 Wi-Fi）：
   ```sh
   adb shell am start -n com.google.android.aicore/com.google.android.apps.aicore.demo.labs.thirdparty.app.ThirdPartyLabsActivity
   ```
4. Android Studio 開 `android/`，`Run`；或 `cd android && ./gradlew installDebug`（Gradle 9.4 / AGP 9.2 / JDK 21 會自動下載；需要 compileSdk 37 的 SDK Platform）。
5. app 內選 **Full (E4B)** + **Preview**，等狀態變「可用」，點範例 chip 或用麥克風。
6. 對照測試（8 題 × 3 次，無人值守）：
   ```sh
   adb shell am start -n app.aming.gemma4/.MainActivity --es autorun "R1,R2,R2_noschema" --ei runs 3
   adb logcat -s CrossTest GemmaNlu        # 看進度
   android/tools/pull_results.sh           # 結果 JSON 拉回 results/android/
   ```

### iOS（詳見 [`ios/README.md`](ios/README.md)）

1. **裝置**：支援 Apple Intelligence 的 iPhone（A17 Pro 以上；實測 iPhone 16 Pro Max、iPhone 18 Pro Max），iOS 26 以上，設定裡 **Apple Intelligence 已開啟且模型下載完成**。模擬器可以編譯，但數據只在真機上有意義。
2. **Xcode 27 以上**（harness 用到 iOS 27 SDK 的 `SystemLanguageModel.variant`，Xcode 26 編不過；仍可裝到 iOS 26 裝置）開 `ios/llm_test.xcodeproj`，到 Signing & Capabilities 換成自己的 Team（bundle id `app.aming.llm-test` 也可能要改）。
3. 跑到手機上：「快速測試」tab 是單句解析＋計時；「對照測試」tab 是正式 harness（R1 / R2、放法、次數可選），結果寫在 app 的 Documents（可在「檔案」app 看到）。
4. 無人值守 + 拉結果：
   ```sh
   xcrun devicectl list devices
   xcrun devicectl device process launch --terminate-existing --device <UDID> app.aming.llm-test \
       --autorun R1,R2 --runs 3 --placement instructions          # iOS 26.x 請改 --placement input_wrapped
   ios/tools/pull_results.sh <UDID>                                # 結果 JSON 拉回 results/ios/
   # 只想知道這台被分配到哪個模型變體：把 --autorun … 換成 --status-only，再看 Documents/autorun_status.json 的 modelVariant
   ```
5. 評分（在 repo 根目錄；只需 Python 3.8+ 標準函式庫，Mac 上也可 `uv run tools/score.py …`）：
   ```sh
   tools/score.py results/ios/results_iOS27.0.0_R1_instructions_*.json results/android/results_Android17_R1_*.json -o results/report.md
   ```

---

## 4. 各平台注意事項

### Android / AICore

- **一定要先加入 tester group 才下載得到 Preview 模型**（上面步驟 2）。`ModelReleaseStage.PREVIEW` = Gemma 4；`ModelPreference.FAST` = E2B、`FULL` = E4B。正式版 Gemini Nano 4 落地後把 `releaseStage` 改成 `STABLE` 即可。
- Preview 模型**要先在 AICore app 裡手動選取並下載**，app 內的 `download()` 不會幫你觸發 preview 下載。Pixel 11 上 Full 套件一份同時服務 E4B 與 E2B。
- 剛下載完可能短暫出現 `error 8 NOT_AVAILABLE`（config 未就緒）→ force-stop AICore 或等一下再試；Pixel 9 上曾需清 AICore storage 重下。
- 首次推論可能要等很久（模型初始化），app 已在可用時先 `warmup()`。頻繁測試可能遇到 `BUSY`。
- **延遲只在 TPU 裝置上有意義**：Pixel 9 Pro XL 是 CPU 版（picker 標示 `[Preview, CPU]`），E4B 會因記憶體壓力掛掉。功能 gate 建議用 `isStructuredOutputFeatureAvailable()` 當「夠力裝置」代理指標。
- `temperature=0` 仍可能跨次非決定性（08-22 手測 c1 出現 102/120 飄動；09-15 官方輪 72 次零 flip），所以每題跑 3 次取多數決。
- 結構化輸出動態 enum：不用 KSP，手寫 `GenerableProvider` 註冊在 `META-INF/services/`，enum 值由 JSON 程式生成（`nlu/CrossTestSchema.kt`）。
- `android/tools/drive_*.sh` 用 uiautomator 點 UI，座標是 Pixel 11 的；換裝置要注意底部手勢列與輸入法（要英文）。

### iOS / FoundationModels

- 需要 **Apple Intelligence 已開啟**，且裝置語言 / Siri 語言在支援清單內（繁中台灣有支援）。`SystemLanguageModel.default.availability` 會回 `deviceNotEligible` / `appleIntelligenceNotEnabled` / `modelNotReady`；OS 剛升級後模型會重新下載，harness 會每 10 秒重查最多 15 分鐘。
- **iOS 26.x 會用語言閘門擋掉這份 prompt**（判成印尼文）。要在 iOS 26 跑，`--placement` 用 `input_wrapped`（或 `input_first`），並在報告裡註明偏差；iOS 27 用 spec 的 `instructions`。
- **Context 依變體而定**（`core3` 推測 4096、`coreAdvanced3` 8192）：4096 的機器上 `includeSchemaInPrompt=true` 加 65 個分類 enum 會爆；harness 有預檢，爆了自動改 `false` 並記錄。
- **模型版本只能間接得知**：iOS 27 起可讀 `SystemLanguageModel.variant`（唯讀，app 不能選），結果檔 `env.model_id_or_availability` 會記；iOS 26 只能記 OS build。OS 升級或換機型 = 模型可能換，結果要重跑。
- **Core Advanced（iPhone 18 Pro Max）的失分模式是格式**：半數回應 JSON 合法但沒有 `slots` 物件、c6 出現壞 JSON；「輸入在前」偏差放法在它上面 0/8，iOS 27 請一律用 `instructions`。
- greedy 完全決定性（同 OS 上午 / 下午逐字相同），但升級後幾小時內背景負載會讓延遲偏高，正式數字建議升級後閒置幾小時再量。
- 每次推論都要**全新 `LanguageModelSession`**，殘留對話會汙染結果。
- 「快速測試」tab 的 `ExpenseParser` 用的是另一套簡化 schema / prompt，與對照測試無關，只是最早的速度探測。

### 模型設定（兩平台實際呼叫的 API）

兩邊都沒有改模型權重，能調的只有選模型、prompt 放法、解碼參數、結構化輸出。完整對照與實際程式碼見 [`docs/model_settings.md`](docs/model_settings.md)。

| 項目 | Android（ML Kit GenAI Prompt API） | iOS（FoundationModels） |
|---|---|---|
| 選模型 | `modelConfig { releaseStage = PREVIEW; preference = FULL }` → Gemma 4 E4B | `SystemLanguageModel.default`；變體由系統分配，app 不能選 |
| system prompt | `SystemInstruction(prompt)` + `TextPart(input)` | `LanguageModelSession(instructions: prompt)` + `respond(to: input)` |
| 解碼 | `temperature = 0.0f; topK = 1; maxOutputTokens = 512` | `GenerationOptions(sampling: .greedy, temperature: 0, maximumResponseTokens: 512)` |
| 結構化輸出（R2） | `GenerateTypedContentRequest.Builder(base, VoiceIntentOut::class)` + `includeSchemaInPrompt`，手寫 `GenerableProvider` 動態 enum | `respond(to:schema:includeSchemaInPrompt:options:)`，`DynamicGenerationSchema` 動態 enum |
| Context 上限 | `getTokenLimit()` = 8192 | `contextSize` = 8192（Core Advanced）；16 Pro Max 約 4096 |
| Session | 同一 client、每次請求無狀態 | 每次推論新建 `LanguageModelSession` |
| 其他 | 無重試、無 streaming、其餘解碼參數用預設 | 同左；預設 guardrails |

### 兩邊共通

- `system_prompt_zh-TW.txt` 內的日期已凍結為 **2026-09-15（星期二）**，c6「上週五」預期 2026-09-11 由此推算；不管實際哪天跑都不要改。
- 解碼參數：`temperature=0`、greedy（`topK=1`）、max output ≥ 512；R1 **不要開** JSON mode / guided。
- 帳戶 / 分類必須是清單內**確切名稱**；清單裡**沒有「現金」**，c1 / c7 就是在測模型會不會硬塞。
- 評分不看 `confidence` / `normalized_text` / `note`；「沒講日期卻填今天」記輕微違規、不算錯。

---

## 5. 資料說明

- `nlu_crosstest/dev_accounts_*.json`、`dev_categories_*.json` 來自作者記帳 app 的匯出（只保留名稱、群組、類型、幣別；額度、利率等欄位已移除）。**帳戶名稱已匿名化**：銀行名稱以同字數的虛構名稱整體替換（北辰、青松、南星、西嶺、東海、京銀、四海商銀、郵儲），prompt、題組、程式 enum、結果檔與報告全部一致替換，prompt 字數維持 3,434，但結果檔內記錄的 `system_prompt_sha256` 是替換前的值。要換成自己的清單：改這兩個檔 → 重新生成 prompt 內的清單段落與 `CrossTestSchema.kt` 的 enum → 跑 `tools/sync_crosstest.sh` → 視為新版本 prompt，兩平台同步重跑。
- 結果 JSON 內含模型原始輸出（`raw_output`），格式見 `nlu_crosstest/ios_test_design_spec.md` §7。

---

## 6. 授權

MIT License，見 [`LICENSE`](LICENSE)。程式碼、測試包與結果都可以自由取用、驗證、重跑；歡迎回報你在其他裝置 / OS 版本上的結果。
本專案是 **AMing Balance** 記帳 app「語音記帳」功能的前期驗證。
