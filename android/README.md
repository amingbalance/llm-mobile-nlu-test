# Android 測試 app：語音記帳 NLU（Gemma 4 / AICore）

驗證「一句話 → Gemma 4 → intent + slots JSON」的實驗 app，也是跨平台對照測試的 Android harness。
背景與介面約定見 [`../docs/voice_intent_gemma_handoff.md`](../docs/voice_intent_gemma_handoff.md)，
完整實測與導入建議見 [`../docs/gemma4_feasibility_handoff.md`](../docs/gemma4_feasibility_handoff.md)。

## 技術路線

- **ML Kit GenAI Prompt API**（`com.google.mlkit:genai-prompt:1.0.0-beta4`），走 AICore
- `ModelReleaseStage.PREVIEW` = AICore Developer Preview 的 Gemma 4；`ModelPreference.FAST` = E2B、`FULL` = E4B（本專案定案 E4B）
- 結構化輸出：prompt 附 schema + few-shot，`temperature=0, topK=1, maxOutputTokens=512`；R2 另用 `generateTypedContentRequest` + 手寫 `GenerableProvider`（動態 enum）
- 語音輸入：系統 `SpeechRecognizer`（zh-TW），辨識完直接送解析；文字框也可手動輸入

## 需求

| 項目 | 需求 |
|---|---|
| 裝置 | 有 AICore 的 Pixel。**實測 Pixel 11 Pro XL（Tensor G6, TPU）**：E4B 單句 2.7–5.5 s。Pixel 9 Pro XL 只有 CPU 版：E2B ~23 s/句、E4B 不穩 → 只能驗流程，不能量數據 |
| 系統 | Android 15+（`minSdk 34`）；官方輪在 Android 17 |
| 開發環境 | Android Studio（AGP 9.2.1、Gradle 9.4.1、Kotlin 2.2、JDK 21 由 toolchain 自動下載）、**SDK Platform 37**（`compileSdk 37`） |
| 網路 | Preview 模型 3–5 GB，需 Wi-Fi |

## 裝置前置作業（新裝置一定要做）

### 1. 加入 AICore Developer Preview 測試計畫

沒加入的話 AICore app 裡**不會出現 [Preview] 模型**，Prompt API 的 `checkStatus()` 會丟 `FEATURE_NOT_FOUND`（feature id 646 = Fast / 647 = Full），app 內顯示「此裝置/設定不可用」。

1. 用測試手機上登入的 Google 帳號加入 Google Group **[aicore-experimental](https://groups.google.com/g/aicore-experimental)**
2. 成為 **[Android AICore testing program](https://play.google.com/apps/testing/com.google.android.aicore)** 的 tester（會把該帳號所有支援的裝置都加入）
3. 到 Play 商店把 **AICore** app 更新到 preview 版（版本名帶 `thirdpartyexperimental` / `thirdpartyeap`），Private Compute Services 若有更新也一併更新

### 2. 在 AICore app 選取並下載 Preview 模型

打開 AICore app → **選取模型** → 選一個 **[Preview]** 模型 → 等下載完成。app 內的 `download()` 不會幫你觸發 preview 下載。

```sh
# 直接開到那個畫面
adb shell am start -n com.google.android.aicore/com.google.android.apps.aicore.demo.labs.thirdparty.app.ThirdPartyLabsActivity
```

- Pixel 11 上 Full 套件 5.x GB，**一份同時服務 E4B 與 E2B**（MatFormer 巢狀子模型），不用分別下載
- 下載剛完成時可能短暫出現 `error 8 NOT_AVAILABLE`（config 未就緒）→ force-stop AICore 或等一下；Pixel 9 上 E4B 曾需清 AICore storage 重下
- 首次推論可能要等很久（模型初始化），app 在狀態變可用時會先 `warmup()`；頻繁測試可能遇到 `BUSY`

## 建置與執行

```sh
cd android
./gradlew installDebug          # 或 Android Studio 直接 Run
```

`local.properties`（SDK 路徑）由 Android Studio 自動產生，不進版控。

app 內：
- **模型卡**：Fast / Full 切換、Preview（Gemma 4）/ Stable（Gemini Nano）切換、狀態與下載；`base model:` 顯示實際載入的模型名（`nano-v4-full` = E4B），可確認真的跑在 Gemma 4
- **範例 chips** 一鍵測試；每次解析顯示 intent、confidence、潤飾句、非空 slots、延遲 ms，可展開原始輸出
- **帶入帳戶/分類清單** 開關（A/B 用）
- **PDF 文件** tab：對帳單解析分支（已驗證可行但產品面 DROP，程式保留）

## 跨平台對照測試（無人值守）

素材（凍結 prompt、8 題、帳戶/分類清單）從 `../nlu_crosstest/` 複製到 `app/src/main/assets/`，**不要直接改 assets**，改正本後跑 `../tools/sync_crosstest.sh`。

```sh
# R1 = 純 prompt；R2 = structured output（schema 注入 prompt）；R2_noschema = structured output 不注入
adb shell am start -n app.aming.gemma4/.MainActivity --es autorun "R1,R2,R2_noschema" --ei runs 3
adb logcat -s CrossTest GemmaNlu                  # 進度；ROUND xx DONE 表示該輪寫檔完成
tools/pull_results.sh                              # 把 files/crosstest/results_*.json 拉回 ../results/android/（需 debug build）
```

結果格式照 `../nlu_crosstest/ios_test_design_spec.md` §7；評分用 repo 根目錄的 `tools/score.py`。
官方輪結果在 [`../results/android/`](../results/android/)，結論在 [`../results/FINAL_VERDICT.md`](../results/FINAL_VERDICT.md)。

## 程式結構

| 檔案 | 職責 |
|------|------|
| `nlu/VoiceIntentPrompt.kt` | system prompt（intent 定義、schema、規則、few-shot，注入今天日期） |
| `nlu/EntityCatalog.kt` | 從 `assets/dev_accounts.json` / `dev_categories.json` 產生 prompt 內的帳戶 / 分類清單段落 |
| `nlu/GemmaNlu.kt` | Prompt API 包裝：checkStatus / download / warmup / classify（含延遲計時、logcat `GemmaNlu`） |
| `nlu/IntentResult.kt` | 容錯 JSON 解析（剝 code fence、抓第一個 `{...}`） |
| `nlu/CrossTest.kt` | 對照測試 harness：讀 `assets/crosstest/`，R1 / R2 / R2_noschema，結果寫 `filesDir/crosstest/` |
| `nlu/CrossTestSchema.kt` | R2 的 typed 輸出類別 + 手寫 `GenerableProvider`（enum 由 JSON 程式生成），註冊在 `resources/META-INF/services/` |
| `pdf/`、`ui/PdfScreen.kt` | PDF 對帳單分支（已 DROP，保留） |
| `MainViewModel.kt` / `MainActivity.kt` | 模型設定切換、下載流程、解析歷史、Compose UI + SpeechRecognizer、autorun intent |
| `tools/drive_test.sh "Full (E4B)"` | adb + uiautomator 驅動七句測試，收 `GemmaNlu` log |
| `tools/drive_catalog_ab.sh`、`tools/drive_pdf.sh` | 清單 A/B、PDF 流程驅動（點擊座標以 Pixel 11 為準；輸入法要英文） |
| `tools/pull_results.sh` | 拉對照測試結果 JSON |

`adb` 不在 PATH 時，對 `tools/*.sh` 設環境變數 `ADB=/path/to/platform-tools/adb`。

## 已知事項

- Preview 模型在 Pixel 9 跑 CPU（picker 標示 `[Preview, CPU]`），首次推論很久，且 E4B 會掛
- `temperature=0` 仍可能跨次非決定性（08-22 手測 c1 出現 102/120），對照測試因此每題 3 次取多數決；09-15 官方輪 72 次零 flip
- 沒講日期時有時仍填今天（規則要 null；對記帳無害，評分記輕微違規）
- 之後 Gemini Nano 4 正式版落地時，同一份 code 把 `releaseStage` 改回 `STABLE` 即可
