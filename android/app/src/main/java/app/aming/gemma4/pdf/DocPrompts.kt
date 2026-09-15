package app.aming.gemma4.pdf

import java.time.LocalDate

enum class DocType(val label: String) {
    AUTO("自動判斷"),
    DIVIDEND("股利通知書"),
    BANK("銀行對帳單"),
    CREDIT_CARD("信用卡對帳單"),
}

enum class PdfMode(val label: String) {
    AUTO("自動"),
    TEXT("文字"),
    IMAGE("圖片"),
}

/** Prompts for extracting structured data from financial PDFs. On-device only. */
object DocPrompts {

    private const val DIVIDEND_SCHEMA = """{"doc_type":"DIVIDEND","stock_name":"股票名稱","stock_code":"股票代碼(台股數字/美股字母)","dividend_type":"現金|股票|混合","ex_dividend_date":"yyyy-MM-dd 或 null","payment_date":"yyyy-MM-dd 發放/入帳日 或 null","shares":持有股數或null,"cash_per_share":每股現金股利或null,"gross_amount":股利總額或null,"tax":扣繳稅額或null,"fee":匯費/手續費或null,"health_insurance":二代健保補充保費或null,"net_amount":實領金額或null,"stock_dividend_shares":配股股數或null,"account":"入帳銀行/帳號末四碼 或 null","currency":"TWD|USD"}"""

    private const val BANK_SCHEMA = """{"doc_type":"BANK","bank":"銀行名稱","account_last4":"帳號末四碼 或 null","currency":"TWD|USD","period_start":"yyyy-MM-dd 或 null","period_end":"yyyy-MM-dd 或 null","opening_balance":期初餘額或null,"closing_balance":期末餘額或null,"transactions":[{"date":"yyyy-MM-dd","description":"摘要/備註","withdrawal":支出金額或null,"deposit":存入金額或null,"balance":餘額或null}]}"""

    private const val CARD_SCHEMA = """{"doc_type":"CREDIT_CARD","bank":"發卡銀行","card_last4":"卡號末四碼 或 null","statement_date":"yyyy-MM-dd 或 null","due_date":"繳款截止日 yyyy-MM-dd 或 null","total_due":本期應繳總額或null,"min_due":最低應繳或null,"currency":"TWD","transactions":[{"date":"消費日 yyyy-MM-dd","post_date":"入帳日 yyyy-MM-dd 或 null","description":"消費明細","amount":台幣金額(退款/繳款為負數),"foreign_amount":外幣金額或null,"foreign_currency":"外幣幣別 或 null"}]}"""

    /** Row grammar hints for Taiwanese card statements once column alignment is lost. */
    private const val CARD_HINTS = """
信用卡消費明細的每一行(文字抽取後欄位已失去對齊)通常是:
<消費日> <入帳日> <消費明細文字> <新臺幣金額> [<消費地 2 碼國別,如 TW/LU/US/JP>] [<幣別 3 碼,如 USD/JPY> <外幣金額>]
- 新臺幣金額 = 該行最後出現的金額;若其後還有「3 碼幣別 + 外幣金額」,外幣才填 foreign_amount/foreign_currency,否則兩者為 null。
- 消費地(2 碼國別)不是幣別,不要填進 foreign_currency。
- 消費明細文字裡夾雜的數字(店號、序號、原始交易金額如「－812.00」「19, RU」)都不是本筆金額。
- 明細文字裡的全形「－」是連字符號,不是負號;amount 只有在帳單金額本身印有負號(如繳款、退款 -18,528)時才為負。
- 一筆交易可能被拆成兩行(例如商店名一行、城市+金額另一行),請合併成一筆。
範例(輸入行 → 對應 JSON 片段):
「2026-07-14 2026-07-16 ALIEXPRESSO7268 19, RU 812 LU」→ {"date":"2026-07-14","post_date":"2026-07-16","description":"ALIEXPRESSO7268 19, RU","amount":812,"foreign_amount":null,"foreign_currency":null}(812 是台幣金額,LU 是消費地)
「2026-07-14 2026-07-16 國外交易服務費－812.00 12」→ {"date":"2026-07-14","post_date":"2026-07-16","description":"國外交易服務費－812.00","amount":12,"foreign_amount":null,"foreign_currency":null}(12 才是本筆金額,「－812.00」屬於明細文字)
「2026-07-23 2026-07-27 高鐵智慧型手機ＩＰｈｏｎA7390」+ 下一行「TAIPEI 440 TW」→ {"date":"2026-07-23","post_date":"2026-07-27","description":"高鐵智慧型手機ＩＰｈｏｎA7390 TAIPEI","amount":440,"foreign_amount":null,"foreign_currency":null}
「2026-05-02 2026-05-03 AMAZON.COM SEATTLE 1,234 US USD 38.50」→ {"amount":1234,"foreign_amount":38.5,"foreign_currency":"USD"}(有 3 碼幣別+外幣金額才填外幣)"""

    private fun schemaFor(type: DocType): String = when (type) {
        DocType.DIVIDEND -> "輸出 schema:\n$DIVIDEND_SCHEMA"
        DocType.BANK -> "輸出 schema:\n$BANK_SCHEMA"
        DocType.CREDIT_CARD -> "輸出 schema:\n$CARD_SCHEMA\n$CARD_HINTS"
        DocType.AUTO -> """
先判斷文件類型,再依對應 schema 輸出(三選一;都不是就輸出 {"doc_type":"UNKNOWN","reason":"..."}):
股利通知書 → $DIVIDEND_SCHEMA
銀行對帳單 → $BANK_SCHEMA
信用卡對帳單 → $CARD_SCHEMA
$CARD_HINTS
""".trim()
    }

    fun systemInstruction(type: DocType, today: LocalDate = LocalDate.now()): String = """
你是個人記帳 app 的文件解析器,負責從台灣的${if (type == DocType.AUTO) "金融文件" else type.label}中抽取結構化資料。
只輸出一個 JSON 物件,不要 markdown 圍欄、不要任何解釋。今天日期:$today。

${schemaFor(type)}

規則:
1. 金額一律輸出純數字(去掉逗號、幣別符號、NT$),不要字串。
2. 日期一律 yyyy-MM-dd。若仍遇到民國年請換算:西元 = 民國 + 1911(今年民國 ${today.year - 1911} 年 = ${today.year} 年),例如「115/08/09」→「2026-08-09」。
3. 只抽取文件中實際出現的資料;沒有的欄位給 null,不要腦補、不要湊數。
4. 交易明細(transactions)只列出這一頁實際出現的每一筆,順序照文件;一筆都沒有就給 []。
5. 文字中若有表格被拆成多行,請依欄位語意重組成正確的一筆交易。
6. 內容有遮罩(如 ****)就照遮罩後可見的部分填,不要猜。
""".trimIndent()

    fun userTextForText(pageNo: Int, pageCount: Int, text: String): String =
        "以下是文件第 $pageNo/$pageCount 頁的文字內容(民國年日期已預先換算為西元 yyyy-MM-dd),請依規則輸出 JSON:\n\n${normalizeRocDates(text)}"

    /**
     * Deterministically rewrites ROC dates (e.g. 115/08/09, 114.12.31, 民國115年8月9日)
     * to ISO yyyy-MM-dd before the text reaches the model — date arithmetic is not
     * something to leave to an LLM.
     */
    fun normalizeRocDates(text: String): String {
        var out = text
        // 115/08/09 or 115.08.09 or 115-08-09  (ROC year 90..199 → 2001..2110)
        out = Regex("""(?<!\d)(9\d|1\d\d)[/.\-](\d{1,2})[/.\-](\d{1,2})(?!\d)""").replace(out) { m ->
            val y = m.groupValues[1].toInt() + 1911
            "%04d-%02d-%02d".format(y, m.groupValues[2].toInt(), m.groupValues[3].toInt())
        }
        // 民國115年8月9日 / 115年08月09日
        out = Regex("""(?:民國)?(9\d|1\d\d)年(\d{1,2})月(\d{1,2})日""").replace(out) { m ->
            val y = m.groupValues[1].toInt() + 1911
            "%04d-%02d-%02d".format(y, m.groupValues[2].toInt(), m.groupValues[3].toInt())
        }
        return out
    }

    fun userTextForImage(pageNo: Int, pageCount: Int): String =
        "這是文件第 $pageNo/$pageCount 頁的影像,請讀取其中內容並依規則輸出 JSON。"
}
