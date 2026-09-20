# 模型設定對照：兩個平台實際呼叫了哪些 API

兩邊都**沒有改模型權重、沒有 fine-tune、沒有外掛 adapter**。能調的只有「選哪個模型、system prompt 怎麼放、解碼參數、要不要結構化輸出」。
下面列的是對照測試（`CrossTest`）實際執行的程式碼，不是示意。prompt v1 凍結輪（2026-09-15 / 09-20）全部用這組設定；之後若有 prompt v2 或不同參數的輪次，會另列一節並標版本。

## 一眼對照

| 項目 | Android：ML Kit GenAI Prompt API（AICore） | iOS：FoundationModels |
|---|---|---|
| 選模型 | `modelConfig { releaseStage = PREVIEW; preference = FULL }` → Gemma 4 **E4B**（`nano-v4-full`）。`FAST` = E2B；`STABLE` = 正式版 Gemini Nano | `SystemLanguageModel.default`，**沒有選擇權**。iOS 27 的 `variant`（`core3` / `coreAdvanced3`）唯讀，由系統依裝置分配 |
| 可用性 | `model.checkStatus()` → `AVAILABLE` / `DOWNLOADABLE` / `DOWNLOADING` / `UNAVAILABLE` | `SystemLanguageModel.default.availability` → `.available` / `.unavailable(deviceNotEligible ｜ appleIntelligenceNotEnabled ｜ modelNotReady)` |
| 模型識別 | `getBaseModelName()` | iOS 27：`variant`、`contextSize`、`capabilities`；iOS 26：無，只能記 OS build |
| Context 上限 | `getTokenLimit()` = **8192**（Pixel 11 Pro XL） | `contextSize` = **8192**（18 Pro Max，Core Advanced）；16 Pro Max 無 API，由 `exceededContextWindowSize` 推得約 4096 |
| system prompt 放法 | `SystemInstruction(prompt)` + `TextPart(input)`（先查 `isSystemPromptAvailable()`，不支援才併入 user text） | `LanguageModelSession(instructions: prompt)` + `respond(to: input)`。iOS 26 被語言閘門擋，另有標注偏差的 `input_first` / `input_wrapped` |
| temperature | `temperature = 0.0f` | `temperature: 0` |
| 取樣 | `topK = 1` | `sampling: .greedy` |
| 最大輸出 | `maxOutputTokens = 512` | `maximumResponseTokens: 512` |
| 其他解碼參數 | 未設定，用預設值 | 未設定，用預設值 |
| 結構化輸出（R2） | `GenerateTypedContentRequest.Builder(base, VoiceIntentOut::class)` + `includeSchemaInPrompt`；schema 由手寫 `GenerableProvider`（`META-INF/services`）提供，enum 由 JSON 程式生成。先查 `isStructuredOutputFeatureAvailable()` | `respond(to:schema:includeSchemaInPrompt:options:)`；`DynamicGenerationSchema` 執行期組出，enum 用 `anyOf:`，可空欄位 `isOptional: true` |
| R2 schema 欄位 | intent、amount、price、currency、stock、account、from_account、to_account、category、date_text、note（**不含** confidence / normalized_text / original_text） | 同左 |
| R2 日期 | 模型只回 `date_text`，Kotlin `resolveDate()` 以 2026-09-15 為今天換算 | 模型只回 `date_text`，`ChineseDateResolver` 以 2026-09-15 為今天換算 |
| Session / 狀態 | 同一個 client 重複使用；每次 `generateContent` 無對話狀態 | **每次推論新建 `LanguageModelSession`**（重用會殘留上一題的對話） |
| Warmup / 冷啟動 | 對照測試：第一次 `generateContent("hi")` 計為冷啟動（含引擎載入）。app 一般路徑用 `model.warmup()` | 第一次建 session 到 warmup 回應完成計為冷啟動，每次 app 啟動量一次 |
| Streaming | 不用 | 對照測試不用（「快速測試」tab 才有串流量 TTFT） |
| 安全 / guardrails | 無可調項 | 預設 guardrails。`guardrails: .permissiveContentTransformations` 試過，**不影響語言閘門** |
| 計時邊界 | `System.nanoTime()` 包住 `generateContent()` | `ContinuousClock` 包住 `respond()`；不含 session 建立與 schema 編譯 |
| 重試 | 無 | 無 |
| 輸出解析（R1） | 抓第一個 `{` 到最後一個 `}`，取 `slots` | 同左（iOS 27 的 ```json 圍欄因此自然被略過） |

**使用者在裝置上要做的設定**（不是程式碼）：Android 要加入 AICore tester group 並在 AICore app 下載 Preview 模型（見 [`../android/README.md`](../android/README.md)）；iOS 要開啟 Apple Intelligence 並等模型下載完（見 [`../ios/README.md`](../ios/README.md)）。

## Android 實際程式碼

出處：[`CrossTest.kt`](../android/app/src/main/java/app/aming/gemma4/nlu/CrossTest.kt)、[`GemmaNlu.kt`](../android/app/src/main/java/app/aming/gemma4/nlu/GemmaNlu.kt)、[`CrossTestSchema.kt`](../android/app/src/main/java/app/aming/gemma4/nlu/CrossTestSchema.kt)。依賴：`com.google.mlkit:genai-prompt:1.0.0-beta4`。

```kotlin
// 1) 選模型：PREVIEW + FULL = Gemma 4 E4B
val model = Generation.getClient(
    generationConfig {
        modelConfig = modelConfig {
            releaseStage = ModelReleaseStage.PREVIEW   // STABLE = 正式版 Gemini Nano
            preference   = ModelPreference.FULL        // FAST = E2B
        }
    }
)

// 2) 狀態與能力
check(model.checkStatus() == FeatureStatus.AVAILABLE)
model.getBaseModelName()                     // "nano-v4-full"
model.getTokenLimit()                        // 8192
model.isSystemPromptAvailable()              // true
model.isStructuredOutputFeatureAvailable()   // Pixel 11: true；Pixel 9: false

// 3) R1：純 prompt
val request = generateContentRequest(SystemInstruction(prompt), TextPart(input)) {
    temperature = 0.0f; topK = 1; maxOutputTokens = 512
}
val raw = model.generateContent(request).candidates.firstOrNull()?.text

// 4) R2：structured output（同一個 base request 再包一層）
val typed = GenerateTypedContentRequest.Builder(request, VoiceIntentOut::class)
    .apply { includeSchemaInPrompt = includeSchema }   // R2 = true；R2_noschema = false
    .build()
val out: VoiceIntentOut? = model.generateContent(typed).candidates.firstOrNull()?.response
```

R2 的值域約束：`VoiceIntentOut` 的 schema 不走 KSP，而是手寫 `GenerableProvider`（`VoiceIntentOutProvider`）註冊在 `resources/META-INF/services/com.google.mlkit.genai.schema.guided.GenerableProvider`，runtime 用 `ServiceLoader` 找到它。intent / currency 是靜態 enum；account / from_account / to_account / category 的 `enumValues` 由帳戶、分類 JSON 程式生成，全部可空。

## iOS 實際程式碼

出處：[`CrossTestRunner.swift`](../ios/llm_test/CrossTest/CrossTestRunner.swift)。只用系統框架 `FoundationModels`。

```swift
// 1) 模型：沒有選擇權，只能問系統給了什麼
let m = SystemLanguageModel.default
m.availability                    // .available / .unavailable(reason)
if #available(iOS 27.0, *) {
    m.variant                     // .core3 / .coreAdvanced3（唯讀）
    m.contextSize                 // 8192（Core Advanced）
    m.capabilities                // vision / guidedGeneration / toolCalling / reasoning
}

// 2) 解碼參數
let options = GenerationOptions(sampling: .greedy, temperature: 0, maximumResponseTokens: 512)

// 3) R1：純 prompt；每次推論都新建 session
let session = LanguageModelSession(instructions: prompt)          // spec 放法
let resp = try await session.respond(to: input, options: options)
// 偏差放法（iOS 26 語言閘門）：LanguageModelSession() + respond(to: input + "\n\n" + prompt [+ "\n\n" + input])

// 4) R2：guided generation，schema 在執行期組出
let account = DynamicGenerationSchema(name: "Account", description: "帳戶清單內的確切名稱", anyOf: accounts)
let root = DynamicGenerationSchema(name: "NLUResult", description: "語音記帳意圖解析結果", properties: [
    .init(name: "intent",  description: "意圖", schema: .init(referenceTo: "Intent")),
    .init(name: "account", description: "帳戶；對不上清單給 null", schema: .init(referenceTo: "Account"), isOptional: true),
    // … amount / price / currency / stock / from_account / to_account / category / date_text / note
])
let schema = try GenerationSchema(root: root, dependencies: [intent, currency, account, category])
let r2 = try await session.respond(to: input, schema: schema,
                                   includeSchemaInPrompt: includeSchema, options: options)
```

iOS 端的 account / category enum 不是手打的，是從凍結 prompt 檔的清單段落程式解析（`NLUTextTools.swift`），共 21 個帳戶、65 個分類。R2 先做一次不計分的預檢：`includeSchemaInPrompt = true` 若丟 `exceededContextWindowSize`，該輪自動改 `false` 並記在結果檔。

## 兩邊「調不到」的東西

- **Android**：Preview 模型要使用者在 AICore app 手動選取下載，app 的 `download()` 觸發不了；TPU / CPU 由裝置決定（Pixel 9 只有 CPU 版）。
- **iOS**：模型變體、模型版本、語言閘門都不受 app 控制。閘門在推論前就拒絕（1–6 ms 丟 `unsupportedLanguageOrLocale`），不屬於 guardrails，關不掉。
- **決定性**：兩邊都用 greedy，沒有另外設 seed。Apple 的 greedy 實測完全決定性（同 OS 上午、下午逐字相同）；Gemma 在 `temperature=0, topK=1` 下 09-15 官方輪零 flip，但 08-22 手測出現過 102 / 120 抖動，所以每題仍跑 3 次取多數決。
