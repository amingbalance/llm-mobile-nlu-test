# Gemma 4 on-device 可行性驗證 — Handoff 回 App 端

> 2026-08-22。對應 [voice_intent_gemma_handoff.md](voice_intent_gemma_handoff.md)(2026-08-16 的需求端 handoff)。
> 本文件是模型實驗端的**結案報告**:技術路線、實測數據、prompt 設計、已驗證的對齊策略、PDF 分支的結論,以及給 app 端(AMing Balance)導入時的具體建議。
> 實驗 app 原始碼在本 repo 的 `android/`(package `app.aming.gemma4`),可直接當參考實作。

---

## 0. 一頁結論

| 項目 | 結論 |
|------|------|
| 技術路線 | **ML Kit GenAI Prompt API**(`com.google.mlkit:genai-prompt:1.0.0-beta4`)走 AICore;Preview 通道 = Gemma 4(Fast=E2B / Full=E4B) |
| 模型選擇 | **E4B(`ModelPreference.FULL`)定案**。E2B 快 2.5 倍但會把 ETF 代碼判成金價、日期/分類出錯;多 2 秒換正確率值得 |
| 目標裝置 | **Pixel 11 Pro XL(16G,TPU)**:E4B 單句 **2.7–5.5s**、warmup 38ms。Pixel 9 Pro XL 只能跑 CPU 版:E2B ~23s/句、E4B 不穩(記憶體壓力)→ 功能應 gate 在夠力裝置 |
| 單次推論 | **一次搞定**:intent + slots + 帳戶/分類對齊同一次推論完成,不需兩段式 |
| 帳戶/分類對齊 | **把真實清單放進 prompt 可行且划算**:+600 token、+~1s,輸出直接是清單內的確切名稱或 null |
| 結構化輸出 | 本機 `structuredOutput=true`;runtime 用 ServiceLoader 找 schema provider → **可手寫 provider 在執行期塞 enumValues**(帳戶/分類動態清單),建議 app 端實作 |
| 口語數字 | **STT(Rambler)已把「一百二」轉「120」**,模型端不用再處理;手打文字才會遇到 |
| 整體 UX 預算 | 使用者接受 **10 秒內**完成一次語音操作(需有 UI 回饋);目前 STT→JSON 約 4–5 秒,餘裕充足 |
| PDF 對帳單 | 已驗證技術可行(文字型 PDF + 同格式 few-shot 可 5/5 全對),但**每家銀行要各自調校** → 使用者決定 **DROP**,1~2 年後再看 |

---

## 1. 環境與前置作業

### 1.1 依賴與 API
```kotlin
// build.gradle.kts
implementation("com.google.mlkit:genai-prompt:1.0.0-beta4")   // genai-common 同版會自動帶入

// 建立 client(PREVIEW + FULL = Gemma 4 E4B;之後正式版切 STABLE 即可)
val model = Generation.getClient(generationConfig {
    modelConfig = modelConfig {
        releaseStage = ModelReleaseStage.PREVIEW
        preference   = ModelPreference.FULL
    }
})

// 狀態 / 能力
model.checkStatus()                      // FeatureStatus.AVAILABLE / DOWNLOADABLE / DOWNLOADING / UNAVAILABLE
model.getBaseModelName()                 // "nano-v4-full" / "nano-v4-fast"
model.getTokenLimit()                    // Pixel 11: 8192
model.isSystemPromptAvailable()          // true
model.isStructuredOutputFeatureAvailable() // Pixel 11: true、Pixel 9: false
model.download(): Flow<DownloadStatus>   // app 內觸發下載(但 preview 模型要先在 AICore app 選取)
model.warmup()

// 推論(本實驗定案參數)
val req = generateContentRequest(SystemInstruction(systemText), TextPart(utterance)) {
    temperature = 0.0f; topK = 1; maxOutputTokens = 512
}
val text = model.generateContent(req).candidates.first().text
model.countTokens(req).totalTokens       // 量 prompt 長度用
```
完整包裝見 [`android/app/src/main/java/app/aming/gemma4/nlu/GemmaNlu.kt`](../android/app/src/main/java/app/aming/gemma4/nlu/GemmaNlu.kt)。

### 1.2 裝置端設定(使用者已完成,新裝置要重做)
1. 加入 aicore-experimental Google group + Android AICore 測試計畫;AICore 更新到 `thirdpartyexperimental` 版
2. **AICore app → 選取模型 → 選一個 [Preview] 模型並下載完成**(否則 `checkStatus()` 丟 FEATURE_NOT_FOUND,feature id Fast=646 / Full=647)
   - 快速開啟:`adb shell am start -n com.google.android.aicore/com.google.android.apps.aicore.demo.labs.thirdparty.app.ThirdPartyLabsActivity`
3. Pixel 11 上 Full 套件 5.xG,**一份同時服務 E4B 與 E2B**(MatFormer 巢狀子模型),不用分別下載
4. 下載剛完成時可能短暫出現 error 8 NOT_AVAILABLE(config 未就緒)→ force-stop AICore 或等一下;Pixel 9 上 E4B 曾需 clear AICore storage 重下載

---

## 2. 語音意圖辨識 — 實測數據

### 2.1 延遲(七句固定測項,`tools/drive_test.sh`)
| 裝置 / 模型 | 每句延遲 | 備註 |
|---|---|---|
| Pixel 9 Pro XL / E2B [Preview, CPU] | 19–29s(avg ~23s) | 連跑越來越慢(熱節流);首次載入 ~30s |
| Pixel 9 Pro XL / E4B [Preview, CPU] | 48–93s 或直接失敗 | 首次載入 93s;跑幾句後 app/AICore 掛掉 → **不可用** |
| **Pixel 11 Pro XL / E4B [Preview, TPU]** | **2.7–4.3s**(首句 5.5s) | warmup 38ms;含 Rambler 重載實測 4.2–4.4s |
| Pixel 11 Pro XL / E2B [Preview, TPU] | 1.2–1.5s | 品質明顯較差(見 2.2) |
| Pixel 11 / E4B + 帳戶分類清單 | 3.1–5.5s | inputTokens 1,192 → 1,795 |

### 2.2 正確率(E4B / Pixel 11)
七句測項:`午餐花了一百二 用現金`、`薪水入帳五萬八`、`台積電改成一千零八十五`、`00878 收在二十一塊九`、`金價一盎司三千三百二十美金`、`上週五看電影三百六 刷南星卡`、`從西嶺轉兩萬三到現金`

- **E4B:6/7**,唯一錯誤是「一百二」→102(臨界案例,同一 prompt 不同次會飄;**真實語音路徑由 STT 解決**,見 2.4)
- E2B:額外錯 `00878` 判成 UPDATE_GOLD_PRICE、`上週五` 日期差一天、分類給「餐飲」(應娛樂)、金價多填 amount → 不採用
- JSON 合法率 100%(finish=STOP),不需要 repair

### 2.3 帳戶/分類清單帶入(A/B,2026-08-22)
資料來源:`nlu_crosstest/dev_accounts_2026-08-22.json`(21 個 ACTIVE 帳戶)、`nlu_crosstest/dev_categories_2026-08-22.json`(13 支出 + 4 收入父類,65 個「父>子」路徑)。壓縮格式見 [`EntityCatalog.kt`](../android/app/src/main/java/app/aming/gemma4/nlu/EntityCatalog.kt):

```
存款:北辰銀、北辰銀-交割、北辰銀-美金(USD)、郵儲、…
信用卡:青松信用卡、西嶺信用卡、南星信用卡、北辰信用卡、東海信用卡
證券:青松證-台股、北辰證-台股、青松證-美股(USD)
支出分類:
飲食>早餐|午餐|晚餐|飲料/咖啡|宵夜/點心|食材採買
交通>大眾運輸|計程車/叫車|加油|停車/過路費|車輛保養
…
```

| | 清單 OFF | 清單 ON |
|---|---|---|
| inputTokens | ~1,192 | ~1,795(+600) |
| 延遲 | 2.6–4.2s | 3.1–5.5s(約 +1s) |
| 「刷南星卡」 | 南星信用卡(自由文字) | **南星信用卡**(清單名) |
| 「看電影」 | 娛樂>影音/遊戲 | **娛樂>影音/遊戲** |
| 「從西嶺轉…到現金」 | 西嶺銀 → 現金 | **西嶺銀 → null**(清單沒有現金帳戶,沒硬塞) |
| 「薪水」/「午餐」 | 薪資>本薪 / 飲食>午餐 | 同 |

結論:**AI 直接做實體對齊可行**,handoff §2「AI 不做實體對應」可以放寬;app 端只保留「輸出值 ∈ 清單」驗證與 null 補選。

### 2.4 STT 觀察(Pixel 11 Rambler)
- 「早餐現金一百二」→ STT 直接輸出「早餐現金120」;「晚餐北辰卡摩斯300塊」→ 300。**口語數字→阿拉伯數字在 STT 層已完成**,模型規則 3 只剩保險作用
- 真語音全鏈路(Rambler → Gemma → JSON)實測 4.2–4.4s,「摩斯」推成飲食類正確

### 2.5 已知弱點
- 口語數字臨界案例(手打文字路徑)
- 相對日期偶爾差一天(E2B 較常;E4B 七句中正確)
- 沒講日期時有時仍填今天(規則要 null;對記帳無害)
- temperature=0 仍有非決定性(同句不同次結果可能不同)

---

## 3. Prompt 設計(已驗證版本)

完整內容見 [`VoiceIntentPrompt.kt`](../android/app/src/main/java/app/aming/gemma4/nlu/VoiceIntentPrompt.kt)。結構:

1. 角色 + 「只輸出 JSON」
2. 今天日期(含星期,供相對日期推算)
3. 六個 intent 定義(沿用需求 handoff §3)
4. 固定 slots schema(所有欄位必出現,用不到給 null)
5. 規則:original_text 原封帶回、normalized_text 確認句、口語數字、相對日期、不腦補、分類常識對應
6. **(可選)帳戶清單 + 分類清單 + 對應提示**(刷卡→信用卡群組、轉帳預設存款群組、「青松」多義要依語境)
7. few-shot 5 例(金價、美股、支出+相對日期+刷卡、轉帳、UNKNOWN),**帳戶/分類用清單內的真實名稱**

參數:`temperature=0f`、`topK=1`、`maxOutputTokens=512`;系統 prompt 走 `SystemInstruction`(本機支援;若 `isSystemPromptAvailable()=false` 則併入 user text,`GemmaNlu.generate()` 已處理)。

輸出解析:[`IntentResult.kt`](../android/app/src/main/java/app/aming/gemma4/nlu/IntentResult.kt) 容錯(剝 code fence、抓第一個 `{…}`),實測沒觸發過。

---

## 4. 給 App 端的導入建議

1. **單次推論**:STT 文字 → 一次 `generateContent` → intent + slots + 對齊好的帳戶/分類;不要做兩段式
2. **只用 E4B(FULL)**;啟動時 `checkStatus()` + `getBaseModelName()`,非 AVAILABLE 就不顯示語音入口
3. **Feature gate**:AICore 可用 + `isStructuredOutputFeatureAvailable()`(等同「夠力裝置」的代理指標)+ 建議 API 35+;Pixel 9 等級裝置體驗不可用,直接關
4. **結構化輸出(建議 app 端實作)**:
   - `generateTypedContentRequest(baseRequest, VoiceIntentOut::class, includeSchemaInPrompt)` → `TypedCandidate<T>.response`
   - 官方路線:`com.google.mlkit:genai-schema` 的 `@Generable`/`@Guide(enumValues=…)` + KSP `genai-schema-compiler:1.0.0-alpha1`(編譯期 schema)
   - **動態清單的做法**:runtime 以 `java.util.ServiceLoader` 載入 `com.google.mlkit.genai.schema.guided.GenerableProvider`(依 `getTargetClass()` 比對)→ 手寫 provider 註冊在 `META-INF/services/`,`getGenerableDetail()` 用公開建構子組 `GenerableDetail/GuideDetail`,`enumValues` 從 DB 讀帳戶/分類。intent、currency 用靜態 enum;account/from_account/to_account/category 用動態 enum(nullable)
   - 好處:格式與值域由解碼器保證,app 端驗證變成形式上的;`includeSchemaInPrompt=true` 時可能可省掉手寫清單文字(待驗證 token 與準確度)
5. **CachedContext / PromptPrefix**:規則 + 清單是固定的,快取後每句只 prefill 使用者那句話,可把清單帶來的 +1s 吃回來(`isCachingFeatureAvailable()` 先確認)
6. **確認畫面**:模型的 `normalized_text` 已可直接顯示;推論的 3–5 秒正好拿來顯示 STT 文字讓使用者掃一眼,JSON 到了疊上確認卡,體感無等待
7. **決策層保留**:輸出值 ∉ 清單 → 留空給使用者選;必要 slot 缺 → 補選即確認;股票名稱→代碼仍由 app 對照表處理(模型只帶回字面)
8. **錯誤處理**:DOWNLOADABLE 時引導去 AICore 下載(preview 期需在 AICore app 選模型);error 8 → 提示稍後重試;推論 >15s 視為逾時
9. 正式版 Gemini Nano 4 落地後,`releaseStage = STABLE` 即可,其餘不動

---

## 5. PDF 對帳單分支(已驗證、已 DROP)

**做了什麼**:測試 app 第二個 tab「PDF 文件」,Android 15 內建 PDF API 零依賴(`PdfRenderer(pfd, LoadParams.setPassword)` 解密、`Page.getTextContents()` 抽文字、render Bitmap 餵 `ImagePart`),股利通知書/銀行對帳單/信用卡對帳單三組 schema prompt,逐頁推論。程式:[`pdf/LoadedPdf.kt`](../android/app/src/main/java/app/aming/gemma4/pdf/LoadedPdf.kt)、[`pdf/DocPrompts.kt`](../android/app/src/main/java/app/aming/gemma4/pdf/DocPrompts.kt)、[`ui/PdfScreen.kt`](../android/app/src/main/java/app/aming/gemma4/ui/PdfScreen.kt)。

**實測(東海信用卡 e-對帳單,3 頁文字型,5 筆交易)**:
- 文字模式:每頁 3.7s / 8.7s / 1.6s,JSON 全合法,筆數與跨行明細重組一開始就對
- 民國年:模型會算錯(115→2025)→ **app 端 regex 確定性轉西元**後全對(`DocPrompts.normalizeRocDates`)
- 欄位錯置(台幣金額 vs 明細內數字 vs 消費地代碼):行文法規則無效,**同格式 few-shot 4 行範例才修好(5/5 全對)**
- 圖片模式:整頁壓到 ~724 token,幻覺銀行名、捏造交易 → 不可用
- `getTextContents()` 整頁只回 1 個 block、bounds 為空 → 拿不到版面座標(若要座標可研究 `searchText()` 回傳的 bounds)

**為何 DROP**:每家銀行格式不同、各自要調 few-shot,且抽文字失去版面對齊是根本限制;對「高端自用」功能 ROI 不夠。1~2 年後若 API 給座標或模型視覺夠看整頁再回頭。

---

## 6. 實驗 app 地圖與工具

| 路徑 | 內容 |
|------|------|
| `android/app/src/main/java/app/aming/gemma4/nlu/` | `GemmaNlu.kt`(Prompt API 包裝、計時 log)、`VoiceIntentPrompt.kt`、`EntityCatalog.kt`、`IntentResult.kt` |
| `android/app/src/main/java/app/aming/gemma4/pdf/` | PDF 分支(已 drop,保留) |
| `android/app/src/main/assets/dev_accounts.json`、`dev_categories.json` | 使用者真實帳戶/分類匯出(2026-08-22) |
| `MainActivity.kt` / `MainViewModel.kt` | Compose UI:模型切換、狀態/下載、文字+SpeechRecognizer 輸入、清單開關、結果卡 |
| `android/tools/drive_test.sh "Full (E4B)"` | adb 驅動七句測試,收 logcat(`adb logcat -s GemmaNlu`) |
| `android/tools/drive_catalog_ab.sh`、`android/tools/drive_pdf.sh` | 清單 A/B、PDF 流程驅動(UI 自動化在 Pixel 11 上需注意底部手勢列與輸入法為英文) |
| `logs/` | 測試截圖、catalog A/B log、對帳單樣本(含個人資料,**未收入 repo**) |
| build | `cd android && ./gradlew installDebug`(compileSdk 37、minSdk 34) |

---

## 7. 未完成 / 交給 app 端決定

- Structured output(typed + 動態 enum provider)的實作與驗證
- CachedContext 實測(是否支援 preview 模型、省多少)
- 各帳戶類型的交易欄位格式 → 定稿最終輸出 schema(使用者說要整理給 app 端)
- 語音入口位置、confidence 門檻、免確認白名單(需求 handoff §7 待定項,本實驗未涉及)
- 擴充 intent(修改/刪除交易)— 效能已證明夠,是產品決策
