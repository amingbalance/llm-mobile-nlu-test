# iOS 測試 app：語音記帳 NLU（Apple Foundation Models）

用 iOS 26 的 **FoundationModels**（`SystemLanguageModel.default`，Apple Intelligence 裝置端模型）跑同一份語音記帳 NLU 題組，
與 Android Gemma 4 對照。測試設計見 [`../nlu_crosstest/ios_test_design_spec.md`](../nlu_crosstest/ios_test_design_spec.md)。

## 需求

| 項目 | 需求 |
|---|---|
| 裝置 | 支援 Apple Intelligence 的 iPhone / iPad / Mac（iPhone 15 Pro 以上、M 系列）。**實測 iPhone 16 Pro Max（A18 Pro）** |
| 系統 | iOS 26 以上（專案 deployment target 26.5，可自行調低到 26.0）。實測 iOS 26.6.2 與 27.0 |
| 設定 | **設定 → Apple Intelligence 與 Siri → 開啟**，並等模型下載完成；裝置語言 / Siri 語言需在支援清單（繁體中文（台灣）有支援） |
| 開發環境 | Xcode 26 以上（實測 Xcode 26.6）；部署到 iOS 27 裝置需要對應的 Xcode |
| 模擬器 | 可編譯；macOS 26 + Apple Intelligence 開啟時模擬器也能推論，但延遲與行為不代表真機，**數據只在真機上有意義** |

## 建置

1. Xcode 開 `llm_test.xcodeproj`
2. Target `llm_test` → **Signing & Capabilities** → Team 換成自己的；bundle id `app.aming.llm-test` 如需可改（改了要同步改 `tools/pull_results.sh` 的 `BUNDLE`）
3. 選真機 → Run

不需要任何第三方套件，只用 `FoundationModels`、`SwiftUI`、`CryptoKit`、`Network`。

## app 內容

| Tab | 用途 |
|---|---|
| **快速測試** | 單句 → `ExpenseParser`（`@Generable` 簡化 schema）→ 計時（總時間 / 首個回應 / 串流片段數）。最早的速度探測，與對照測試**無關** |
| **對照測試** | 正式 harness（`CrossTest/`）：載入 bundle 內凍結素材、顯示 prompt 字數 / SHA-256 / 可用性；選 R1 / R2、放法、次數；即時 log；結果 JSON 寫到 app 的 **Documents**（「檔案」app 可見，`UIFileSharingEnabled`） |

### 放法（`--placement`）

| 值 | 說明 |
|---|---|
| `instructions` | **spec 主要放法**：凍結 prompt 當 `LanguageModelSession(instructions:)`，user turn 只有輸入句 |
| `prepended` | spec 備案：無 instructions，user turn = prompt + 空行 + 輸入 |
| `input_first` | **偏差**：輸入 + 空行 + prompt。為了繞過 iOS 26 的語言閘門 |
| `input_wrapped` | **偏差**：輸入 + 空行 + prompt + 空行 + 輸入（保留 spec 順序，前面多一份輸入只為過閘門） |

iOS 26.x 兩種 spec 放法都被擋（`unsupportedLanguageOrLocale`，見 [`../results/ios/gate_probe_iOS26.md`](../results/ios/gate_probe_iOS26.md)），要用 `input_wrapped`；iOS 27 用 `instructions`。結果檔的 `env.system_prompt_placement` / `placement_note` 會記下用了哪種。

## 無人值守執行與拉結果

```sh
xcrun devicectl list devices                     # 取得 UDID
xcrun devicectl device process launch --terminate-existing --device <UDID> app.aming.llm-test \
    --autorun R1,R2 --runs 3 --placement instructions [--no-schema-in-prompt]

tools/pull_results.sh <UDID>                     # Documents 裡的 results_*.json → ../results/ios/
```

- `--autorun R1,R2`：要跑的模式；`--runs`：每題次數（1–5）；`--no-schema-in-prompt`：R2 不把 schema 注入 prompt
- 帶 `--autorun` 啟動會直接切到「對照測試」tab；模型未就緒（`modelNotReady`，例如 OS 剛升級在重新下載）時每 10 秒重查，最多等 15 分鐘，狀態寫在 Documents 的 `autorun_status.json`
- 也可以不給 UDID：`tools/pull_results.sh` 會讀環境變數 `IOS_DEVICE`，再不然取 `devicectl list devices` 的第一台

評分（repo 根目錄）：

```sh
tools/score.py results/ios/results_iOS27.0.0_R1_instructions_*.json results/ios/results_iOS27.0.0_R2_*.json -o results/ios/REPORT_xxx.md
```

## 程式結構

| 檔案 | 職責 |
|---|---|
| `llm_test/CrossTest/CrossTestRunner.swift` | harness 本體：載入素材、R1（純字串回應 + 容錯 parse）、R2（`DynamicGenerationSchema`，enum 由 prompt 檔程式解析）、冷啟動量測、環境資訊、存檔 |
| `llm_test/CrossTest/CrossTestModels.swift` | `testcases.json` 與結果 JSON（spec §7）的 Codable 模型 |
| `llm_test/CrossTest/NLUTextTools.swift` | 從 prompt 檔抽帳戶 / 分類清單、R1 輸出 JSON 容錯解析 |
| `llm_test/CrossTest/CrossTestView.swift` | 對照測試 UI + `--autorun` 參數處理 |
| `llm_test/ChineseDateResolver.swift` | R2 的程式日期解析（今天固定 2026-09-15；昨天 / 上週五 / N 天前 / M月D日 / 中文數字…） |
| `llm_test/ExpenseParser.swift`、`ContentView.swift` | 「快速測試」tab |
| `nlu_crosstest/` | 凍結素材的**複本**（bundle resource）。正本在 `../nlu_crosstest/`，改完跑 `../tools/sync_crosstest.sh` |
| `tools/pull_results.sh` | 用 `devicectl` 拉 Documents 的結果檔 |

## 注意事項

- **每次推論用全新的 `LanguageModelSession`**，session 建立與 schema 編譯不計入 `latency_ms`
- **Context 約 4096 token**：`includeSchemaInPrompt=true` 加 65 個分類 enum 會 `exceededContextWindowSize`；harness 會先預檢，爆了自動改 `false` 並在 `env.decoding.includeSchemaNote` 記錄
- **沒有模型版本 API**，只能記 OS build（`env.os_build`）。OS 升級 = 模型可能換，同題答案會變（iOS 26 → 27 實測 c1 120→112、c8 ✓→✗）
- greedy 完全決定性，但 OS 升級後幾小時背景負載會讓延遲偏高；正式數字建議升級後閒置幾小時再量（27.0 上午 9.35 s → 下午 5.5 s）
- iOS 27 的 R1 輸出會包 ```json 圍欄 + 縮排，parser 已處理；字元變多所以每句慢約 1.6 s
- guided generation（R2）在這份 prompt 下 iOS 26 / 27 都 0/8（optional enum 全 null、或硬塞清單值、或 `note` 重複到 token 上限）；要用 guided 得為它重寫 prompt，不能沿用 R1 的
- `SystemLanguageModel(guardrails: .permissiveContentTransformations)` 不影響語言閘門
