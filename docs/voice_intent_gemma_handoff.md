# 語音意圖辨識 Handoff（Gemma 4 實驗用）

> 2026-08-16。目標：語音記帳／語音更新價格，AI 只做意圖與 slot 抽取，APP 做實體對應與執行，
> user 最後只剩「確定」一步。本文件給模型實驗端（Gemma 4）當背景知識與介面約定。

---

## 1. App 概念速覽（AMing Balance）

- 個人記帳 app（Android / Kotlin / Compose / Room），package `app.aming.balance`
- **帳戶類型**：銀行 BANK／現金 CASH／信用卡 CREDIT_CARD／貸款 LOAN／證券 STOCK／黃金存摺 GOLD
- **金額**：內部為 minor unit（Long，TWD 無小數、USD 兩位小數）；幣別跟著帳戶走，主幣別 TWD
- **交易**：收入 INCOME／支出 EXPENSE／轉帳 TRANSFER
  - 收支掛「分類」（兩層樹：父類＋子類，收入/支出各一棵樹，如 餐飲>午餐、投資收益>股息）
  - 轉帳＝fromAccount → toAccount，無分類
- **股票**：證券戶依幣別分 台股(TWD)／美股(USD)
  - 台股代碼＝數字（可帶尾碼字母），如 `2330`、`00878`、`00406A`；美股＝字母 ticker，如 `AAPL`、`NVDA`
  - 價格存 `stock_price` 表（每代碼一筆最新收盤）；**手動價機制**：手動日期「嚴格大於」自動資料日期才生效，之後自動抓到新收盤就接手 → 語音更新價格走這條，不會破壞自動更新
- **黃金存摺**：TWD 帳戶單位＝公克、USD 帳戶＝盎司；金價寫在 stock_price 保留代碼
  - `GOLD`＝TWD／每公克、`XAU`＝USD／每盎司；手動更新同股票的 manual price 機制
- **既有執行層 API**（APP 端已存在，語音流程直接呼叫）：
  - `StockPriceRepository.setManualPrice(code, price)` — 股價與金價共用
  - `TransactionRepository.insert(Transaction)` — 收入/支出/轉帳

---

## 2. 整體流程（六步，責任方標註）

| # | 步驟 | 責任方 | 說明 |
|---|------|--------|------|
| 1 | 語音輸入 → 文字 | 系統 STT | Android SpeechRecognizer（或其他 STT） |
| 2 | 意圖辨識 | **AI (Gemma)** | 文字 → intent + slots + 原句 + 潤飾句（§4 JSON） |
| 3 | 關鍵字決策 | APP | slot 文字 → 實體 id（帳戶暱稱、分類樹、股票名→代碼表 fuzzy match）＋預設值補齊 |
| 4 | 動作確認 | **AI (Gemma)** | 組人話確認句（v0 可先用 APP template，AI 潤飾為加分項） |
| 5 | 執行操作 | APP | 組好 payload（pending，尚未 commit） |
| 6 | 確定／取消 | USER | 一鍵確認 → commit；取消 → 丟棄 |

原則：**AI 不接觸 DB、不做實體對應、不執行**；只做語言層（意圖、抽取、潤飾）。

---

## 3. 意圖定義（v0：5 個 + fallback）

| intent | 說明 | 必要 slots | 選填 slots | 對應動作 |
|--------|------|-----------|-----------|----------|
| `UPDATE_GOLD_PRICE` | 更新黃金價格 | `price` | `currency`（預設 TWD/公克） | setManualPrice("GOLD" 或 "XAU", price) |
| `UPDATE_STOCK_PRICE` | 更新單一股票價格（台/美） | `stock`（代碼或名稱）、`price` | — | setManualPrice(code, price)；台美由代碼樣式判斷（數字=台股、字母=美股），名稱→代碼由 APP 對照表決策 |
| `ADD_INCOME` | 新增收入 | `amount` | `account`、`category`、`date`（預設今天）、`note` | insert INCOME |
| `ADD_EXPENSE` | 新增支出 | `amount` | `account`、`category`、`date`、`note` | insert EXPENSE |
| `ADD_TRANSFER` | 新增轉帳 | `amount`、`from_account`、`to_account` | `date`、`note` | insert TRANSFER |
| `UNKNOWN` | 信心不足／非上述意圖 | — | — | 請 user 重講 |

---

## 4. AI 輸出約定（JSON）

```json
{
  "intent": "ADD_EXPENSE",
  "confidence": 0.93,
  "original_text": "午餐花了一百二 用現金",
  "normalized_text": "新增支出 120 元，帳戶「現金」，分類「餐飲」",
  "slots": {
    "amount": 120,
    "currency": "TWD",
    "price": null,
    "stock": null,
    "account": "現金",
    "from_account": null,
    "to_account": null,
    "category": "餐飲",
    "date": "2026-08-16",
    "note": null
  }
}
```

規則：
1. `original_text` **原封不動**帶回（含贅字）；`normalized_text` 為潤飾後文句（給確認畫面用）
2. 中文口語數字 → 阿拉伯數字（「一百八十二塊半」→ 182.5；「五萬八」→ 58000）
3. 相對日期（昨天/上週五）→ ISO `yyyy-MM-dd`；沒講日期 → 今天
4. 聽不出的 slot 給 `null`，**不要腦補**；實體對應（現金→哪個帳戶 id）不是 AI 的事
5. 意圖不明或 confidence 低 → `UNKNOWN`
6. 只輸出 JSON，無其他文字（溫度 0、prompt 內附 schema + few-shot）

---

## 5. Few-shot 範例素材

| 語音輸入 | intent | 關鍵 slots |
|----------|--------|-----------|
| 金價更新一下 一克四千五百八 | UPDATE_GOLD_PRICE | price=4580, currency=TWD |
| 台積電改成一千零八十五 | UPDATE_STOCK_PRICE | stock=台積電, price=1085 |
| 輝達現在一百八十二塊半 | UPDATE_STOCK_PRICE | stock=輝達, price=182.5 |
| 00878 收在二十一塊九 | UPDATE_STOCK_PRICE | stock=00878, price=21.9 |
| 午餐花了一百二 用現金 | ADD_EXPENSE | amount=120, account=現金, category=餐飲 |
| 薪水入帳五萬八 | ADD_INCOME | amount=58000, category=薪資 |
| 昨天加油八百五 刷青松卡 | ADD_EXPENSE | amount=850, account=青松卡, date=昨天→ISO, category=交通 |
| 從青松轉三萬到西嶺 | ADD_TRANSFER | amount=30000, from=青松, to=西嶺 |

註：category 允許 AI 給「常識推測」（加油→交通），但 APP 決策層對不上分類樹時一律留空給 user 選，不硬塞。

---

## 6. APP 決策層（step 3）要處理的事

- 帳戶暱稱 fuzzy match（「青松」可能對到 青松銀行/青松信用卡/青松證券 → 依 intent 縮小範圍：轉帳→現金類帳戶優先；刷卡字眼→信用卡）
- 股票名稱 → 代碼：吃現有 stock_code 對照表（含 name overlay）；直接講代碼者直接用
- 金價幣別：講「一克/公克」→ GOLD(TWD)；「盎司」→ XAU(USD)；都沒講 → 預設 TWD
- 分類名 → 分類樹節點；對不上 → 留空
- 多候選／缺必要 slot → 確認畫面上讓 user 補選（仍維持「最多一步確定」的精神，補選即確認）

---

## 7. 技術備註

- Gemma 4 on-device 候選：MediaPipe LLM Inference API（AI Edge）；結構化輸出靠 prompt 附 schema + few-shot、溫度 0
- 價格更新沿用現有 manual price 機制，aming（自動抓價）與 public（純手動）兩個 flavor 行為一致
- 交易寫入即現有 `TransactionRepository.insert`，確認前不落 DB（step 5 只組 payload）
- 待定：語音入口位置（FAB？通知？快捷磚？）、confidence 門檻、是否要免確認白名單（如純價格更新）
