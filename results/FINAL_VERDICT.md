# 跨平台 NLU 對照測試 — 最終結論(2026-09-15)

> 數據來源:Android 基準(`nlu_crosstest/README.md` §6)+ iOS 端完整報告(`results/ios/`,
> REPORT_iOS26.6.2 / REPORT_iOS27.0 / REPORT_cross_os)。iOS 逐題結果已由 Android 端用
> `testcases.json` 獨立重新對分驗證,兩邊評分一致。

## R1(model-only,同一份凍結 prompt)總表

| | Android Gemma 4 E4B | iOS 26.6.2 Apple FM | iOS 27.0 Apple FM |
|---|---|---|---|
| 裝置 | Pixel 11 Pro XL(TPU) | iPhone 16 Pro Max(A18 Pro) | 同左,升級 OS |
| prompt 放法 | spec(SystemInstruction) | **偏差**(input_wrapped;spec 放法被語言閘門擋,詳下) | spec(instructions) |
| **全對** | **6/7**(c8 未測) | 4/8 | 4/8 |
| 延遲中位 | 3.0–5.5s | 3.9s | 5.5s |
| 決定性 | temp=0 仍有 102/120 抖動 | **零 flip** | **零 flip** |
| JSON 合法 | 100% | 100% | 100%(多包 ```json 圍欄) |
| c1 一百二 | 102 ✗ | **120 ✓** | 112 ✗ |
| c4 00878 | **✓** | ✗(判支出) | ✗(判金價/UNKNOWN) |
| c7 to=現金(不存在) | **null ✓** | 硬塞「現金」✗ | 硬塞「現金」✗ |
| c8 股息 | 未測 | ✓ | ✗(判改股價) |

## 2×2 完整矩陣(2026-09-15 補齊 Android 官方輪:凍結 prompt、含 c8、8 題 × 3 次)

| | **R1(純 prompt)** | **R2(structured/guided)** |
|---|---|---|
| **Android Gemma 4 E4B**(Pixel 11,Android 17) | **6/8** @ 3.2s(零 flip) | **7/8** @ 3.7–4.0s(零 flip) |
| iOS 26.6.2 Apple FM | 4/8 @ 3.9s(偏差放法) | 0/8 |
| iOS 27.0 Apple FM | 4/8 @ 5.5s | 0/8 |

Android 官方輪細節(`results/android/`):
- R1 6/8:錯 c1(amount=102,STT 已解)與 **c7(這次也硬塞「現金」了**——08-22 曾答 null,證明 prompt-only 防線在臨界案例上不穩)
- **R2 7/8:enum 約束把 c7 修好**(「現金」不在值域,to_account 正確 null);schema 注入(4.0s)與不注入(3.65s)同分——8192 context 塞得下,沒有 iOS 的爆 context / note 迴圈 / 亂塞問題
- 剩下唯一的錯 c1 amount=102 由 STT 數字正規化解決 → **產品形態(R2 + STT)實質 8/8**
- cold start 1.8s;本輪 72 次推論全部零 flip
- 實作:手寫 `GenerableProvider` 註冊 META-INF/services(ServiceLoader 機制實證可行,不需 KSP),enum 由 JSON 程式生成;程式碼在 `android/app/src/main/java/app/aming/gemma4/nlu/CrossTestSchema.kt`、`CrossTest.kt`,adb 一鍵驅動:`am start -n app.aming.gemma4/.MainActivity --es autorun "R1,R2,R2_noschema" --ei runs 3`

## R2(guided generation)— iOS 端

**兩個 OS 皆 0/8,這份 prompt 下不可用。**
- iOS 26:optional enum 幾乎全 null(分類 0 命中);schema 注入 prompt 會爆 4096 context
- iOS 27:不注入 schema → 只生 note+intent 且 note 重複迴圈到 512 token(13–15s,決定性);注入 → enum **硬塞**(帳戶亂填青松系列、c7 from/to 全錯)
- 根因推定:prompt 內的 JSON schema 敘述+few-shot 與 guided schema 互相干擾
- **修正原則(兩平台通用)**:要用 guided/structured output,prompt 必須為它重寫(拿掉 schema 敘述與 JSON 範例、精簡),不能沿用 R1 prompt——Android 補 R2 時照此辦理(prompt v2,另開版本標注)

## 平台層事實(與模型無關但影響產品)

1. **iOS 26 語言閘門**把這份 prompt 判成印尼文直接拒絕(`unsupportedLanguageOrLocale`,2ms),iOS 27 放行——同一 app、同一 prompt,**OS 升級改變可用性與行為**
2. iOS 27 輸出風格改變(```json 圍欄+縮排,+50% 字元 → 慢 ~1.6s),吐字速率其實沒變
3. Apple FM context ≈ 4096 token(schema 注入即爆);Android tokenLimit 8192
4. Apple 模型 greedy 完全決定性(24/24 零 flip);Gemma temp=0 仍會飄
5. iOS 26→27 同題答案變化:c1 120→112(退步)、c8 ✓→✗(退步)、c2 分類 ✗→✓(進步)——**模型跟著 OS 換,無版本 API 可偵測**

## 產品結論

0. **最終答案:Android E4B + structured output = 7/8(扣掉 STT 會解的 c1 實質全對)、3.7–4.0s、零 flip——這就是導入 AMing Balance 的目標形態**。同一招在 iOS 上(guided)反而 0/8,平台差距比模型差距更大
1. **準確率:Gemma 4 E4B 明顯領先**(R1 6/8 vs 4/8),而且贏在記帳最不能錯的地方:不硬塞不存在的帳戶、台股代碼不錯判。iOS 模型的「硬塞現金/青松」型錯誤對記帳是危險錯誤(會入錯帳),不是無害噪音
2. **速度:同條件下兩平台同量級**(3–5.5s)。先前 iOS 0.9–1.2s 的印象來自 R2 guided 短輸出形態——而那個形態正確率 0/8,不能當比較基準
3. **Android 主力路線不變**:E4B + prompt 清單對齊 + (未來)structured output with prompt v2
4. **iOS 若要做**:可行但需 iOS 27+、prompt 需另調(或 v2),且要接受「OS 升級=模型行為變」——這套測試包正好當每次 OS 升級的回歸套件
5. c1 口語數字三平台三個答案(102/120/112),再次確認:**金額數字正規化交給 STT/程式,不交給 LLM**

## 待辦(已全部完成)

- ~~Android R2~~ ✅ 2026-09-15 補齊(見上表)。註:Android R2 沿用凍結 prompt 就已 7/8,prompt v2(精簡版)在 Android 上變成單純的延遲優化選項,不再是正確率必需品;iOS 若要救 R2 才需要 v2
