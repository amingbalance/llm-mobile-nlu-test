# 跨平台語音記帳 NLU 對照測試(Android Gemma 4 vs iOS)

> 2026-09-14 制定。目的:**同一份 prompt、同一組輸入、同一套評分**,在 iOS 端(Apple on-device model)重跑 Android(Gemma 4 E4B)已完成的測試,讓兩邊的差異只剩下「模型與其 runtime」。
> Android 端完整背景見 [gemma4_feasibility_handoff.md](../docs/gemma4_feasibility_handoff.md)。

## 1. 測試包內容

| 檔案 | 說明 |
|------|------|
| `system_prompt_zh-TW.txt` | **凍結的 system prompt**(UTF-8,3,434 字):角色、六個 intent、JSON schema、規則、**帳戶清單、收支分類清單**、few-shot。日期已凍結為 **2026-09-15(星期二)**,不要改 |
| `testcases.json` | 8 個測試句 + 預期輸出 + 評分規則(機器可讀) |
| `dev_accounts_2026-08-22.json`、`dev_categories_2026-08-22.json` | 清單原始資料(prompt 內文字由此生成,僅供追溯) |

## 2. 控制變因(兩邊必須一致)

1. **Prompt**:`system_prompt_zh-TW.txt` 整檔逐字使用。平台支援 system role 就放 system,不支援就直接接在使用者輸入前面(中間空一行)——用哪種要記錄在結果裡
2. **輸入**:直接用 `testcases.json` 的 `input` 文字(**打字輸入,不過 STT**,排除語音辨識差異)
3. **解碼參數**:`temperature=0`、greedy(topK=1 或等效)、max output ≥512 token;**不要開** JSON mode / grammar constrained decoding(Android 端沒開,開了就不是同條件)
4. **日期**:prompt 已凍結 2026-09-15,c6 的預期日期(2026-09-11)由此推算;不論實際哪天跑都不要動
5. **次數**:每題跑 3 次(排除單次抖動),正確性取多數決,延遲取中位數;3 次答案不一致(flip)另外記
6. 首次推論前先做一次 warmup(任意短 prompt),warmup 不計入延遲

## 3. 測試句與預期(細節以 `testcases.json` 為準)

| # | 輸入 | intent | 關鍵預期 slots |
|---|------|--------|----------------|
| c1 | 午餐花了一百二 用現金 | ADD_EXPENSE | amount=**120**、account=**null**(清單無現金帳戶)、category=飲食>午餐 |
| c2 | 薪水入帳五萬八 | ADD_INCOME | amount=58000、category=薪資>本薪 |
| c3 | 台積電改成一千零八十五 | UPDATE_STOCK_PRICE | stock=台積電、price=1085 |
| c4 | 00878 收在二十一塊九 | UPDATE_STOCK_PRICE | stock=00878、price=21.9(**不可**判成金價) |
| c5 | 金價一盎司三千三百二十美金 | UPDATE_GOLD_PRICE | price=3320、currency=USD、amount=null |
| c6 | 上週五看電影三百六 刷南星卡 | ADD_EXPENSE | amount=360、account=**南星信用卡**、category=**娛樂>影音/遊戲**、date=**2026-09-11** |
| c7 | 從西嶺轉兩萬三到現金 | ADD_TRANSFER | amount=23000、from=**西嶺銀**、to=**null** |
| c8 | 股息入帳一千五百塊 | ADD_INCOME | amount=1500、category=投資收益>股息 |

評分:`confidence`、`normalized_text`、`note` **不計分**;帳戶/分類必須是清單內**確切名稱**(近似字、多字少字都算錯);「沒講日期卻填當天」記輕微違規分開統計,不算 slot 錯。

## 4. 帳戶清單(prompt 內含,21 個 ACTIVE)

- **存款**:北辰銀、北辰銀-交割、北辰銀-美金(USD)、郵儲、四海商銀、京銀、東海銀、青松銀、南星銀、南星銀-美金(USD)、西嶺銀
- **信用卡**:青松信用卡、西嶺信用卡、南星信用卡、北辰信用卡、東海信用卡
- **黃金**:青松黃金存摺
- **其他**:東海房貸
- **證券**:青松證-台股、北辰證-台股、青松證-美股(USD)

註:**沒有「現金」帳戶**——c1/c7 就是在測模型會不會硬塞。

## 5. 收支類別(prompt 內含,13 支出 + 4 收入)

**支出**:
- 飲食 > 早餐 | 午餐 | 晚餐 | 飲料/咖啡 | 宵夜/點心 | 食材採買
- 交通 > 大眾運輸 | 計程車/叫車 | 加油 | 停車/過路費 | 車輛保養
- 購物 > 日用品 | 服飾 | 美妝保養 | 3C/家電 | 居家用品
- 居住 > 房租/管理費 | 水費 | 電費 | 瓦斯費 | 網路/電話 | 有線電視
- 醫療健康 > 看診/掛號 | 藥品 | 保健品 | 健身/運動
- 娛樂 > 影音/遊戲 | 旅遊 | 嗜好 | 展演/活動
- 訂閱服務 > 影音/音樂 | AI/工具 | 雲端/儲存 | 工作軟體 | 會員制 | 網域
- 人情 > 紅白包 | 禮物 | 捐款
- 教育學習 > 書籍 | 課程/進修 | 文具
- 金融費用 > 手續費 | 利息支出 | 保險費 | 稅金
- 寵物 > 飼料/用品 | 醫療/美容
- 雜支 > 零用金 | 其他
- 投資損失 > 股票損失 | 黃金損失

**收入**:
- 薪資 > 本薪 | 獎金/分紅 | 加班費
- 投資收益 > 股息 | 黃金收益 | 利息收入 | 股票收益
- 業外收入 > 兼職/接案 | 退款/回饋 | 禮金收入
- 其他收入 > 中獎/發票 | 雜項收入 | 其他收入

## 6. Android 基準(對照組)

- 裝置:Pixel 11 Pro XL 16G;模型:Gemma 4 E4B(AICore preview,`nano-v4-full`,TPU);API:ML Kit GenAI Prompt API `genai-prompt:1.0.0-beta4`;system prompt 走 `SystemInstruction`;inputTokens ≈ **1,795**(該平台 tokenizer,僅供參考,跨平台 token 數不可比)
- 量測日 2026-08-22(當時 prompt 日期未凍結,c6 預期為 08-14;其餘題目不受日期影響)

| # | 延遲 | 正確性 |
|---|------|--------|
| c1 | 4,445 ms | ⚠️ amount=102(錯);account=null ✓、分類 ✓ |
| c2 | 3,075 ms | ✓ |
| c3 | 4,399 ms | ✓ |
| c4 | 4,456 ms | ✓ |
| c5 | 4,480 ms | ✓(amount 正確為 null) |
| c6 | 5,502 ms | ✓(含日期、帳戶、分類) |
| c7 | 4,507 ms | ✓(to=null 沒硬塞) |
| c8 | —(未測) | — |

同日另一輪 c4/c5 曾測得 ~3.0–3.1s,延遲區間可視為 **3.0–5.5s**(熱況/背景負載影響)。JSON 合法率 100%。
注意:Android 端 temp=0 仍觀察到跨次非決定性(c1 的 102/120 會飄),這正是「每題 3 次」的原因;iOS 端結果若也有 flip,如實記錄即可。

## 7. 結果記錄格式(iOS 端請照填)

環境:裝置型號 / OS 版本 / 模型與框架名稱、版本 / system prompt 放置方式(system role 或前置)/ 解碼參數實際值

每題(×3 次):`case_id, run, latency_ms, json_valid, intent, amount, price, currency, stock, account, from_account, to_account, category, date, raw_output`

彙總:每題多數決正確性(intent / 各 slot 分開)、延遲中位數、flip 次數、JSON 合法率;最後與第 6 節表並排。
