package app.aming.gemma4.nlu

import com.google.mlkit.genai.schema.guided.GenerableDetail
import com.google.mlkit.genai.schema.guided.GenerableProvider
import kotlin.reflect.KClass

/**
 * Structured-output schema for the cross-platform R2 round, mirroring the iOS
 * guided-generation schema (spec §5). Enum values are GENERATED from
 * nlu_crosstest/dev_accounts_2026-08-22.json / dev_categories_2026-08-22.json — do not edit by hand.
 */
data class VoiceIntentOut(
    val intent: String,
    val amount: Double?,
    val price: Double?,
    val currency: String?,
    val stock: String?,
    val account: String?,
    val from_account: String?,
    val to_account: String?,
    val category: String?,
    val date_text: String?,
    val note: String?,
)

object CrossTestEnums {
    val INTENTS = arrayOf("UPDATE_GOLD_PRICE", "UPDATE_STOCK_PRICE", "ADD_INCOME", "ADD_EXPENSE", "ADD_TRANSFER", "UNKNOWN")
    val CURRENCIES = arrayOf("TWD", "USD")
    val ACCOUNTS = arrayOf("北辰銀", "北辰銀-交割", "北辰銀-美金", "郵儲", "四海商銀", "京銀", "東海銀", "青松銀", "南星銀", "南星銀-美金", "西嶺銀", "青松信用卡", "西嶺信用卡", "南星信用卡", "北辰信用卡", "東海信用卡", "青松黃金存摺", "東海房貸", "青松證-台股", "北辰證-台股", "青松證-美股")
    val CATEGORIES = arrayOf("飲食>早餐", "飲食>午餐", "飲食>晚餐", "飲食>飲料/咖啡", "飲食>宵夜/點心", "飲食>食材採買", "交通>大眾運輸", "交通>計程車/叫車", "交通>加油", "交通>停車/過路費", "交通>車輛保養", "購物>日用品", "購物>服飾", "購物>美妝保養", "購物>3C/家電", "購物>居家用品", "居住>房租/管理費", "居住>水費", "居住>電費", "居住>瓦斯費", "居住>網路/電話", "居住>有線電視", "醫療健康>看診/掛號", "醫療健康>藥品", "醫療健康>保健品", "醫療健康>健身/運動", "娛樂>影音/遊戲", "娛樂>旅遊", "娛樂>嗜好", "娛樂>展演/活動", "訂閱服務>影音/音樂", "訂閱服務>AI/工具", "訂閱服務>雲端/儲存", "訂閱服務>工作軟體", "訂閱服務>會員制", "訂閱服務>網域", "人情>紅白包", "人情>禮物", "人情>捐款", "教育學習>書籍", "教育學習>課程/進修", "教育學習>文具", "金融費用>手續費", "金融費用>利息支出", "金融費用>保險費", "金融費用>稅金", "寵物>飼料/用品", "寵物>醫療/美容", "雜支>零用金", "雜支>其他", "投資損失>股票損失", "投資損失>黃金損失", "薪資>本薪", "薪資>獎金/分紅", "薪資>加班費", "投資收益>股息", "投資收益>黃金收益", "投資收益>利息收入", "投資收益>股票收益", "業外收入>兼職/接案", "業外收入>退款/回饋", "業外收入>禮金收入", "其他收入>中獎/發票", "其他收入>雜項收入", "其他收入>其他收入")
}

/** Registered via META-INF/services for the Prompt API's ServiceLoader lookup. */
class VoiceIntentOutProvider : GenerableProvider {
    override val targetClass: KClass<*> = VoiceIntentOut::class
    override fun getGenerableDetail(): GenerableDetail<*> = GenerableDetail<VoiceIntentOut>(
        "語音記帳意圖解析結果",
        listOf(
            field("intent", nullable = false, description = "意圖", enums = CrossTestEnums.INTENTS),
            numField("amount", "收入/支出/轉帳金額;非金額類意圖給 null"),
            numField("price", "股價或金價;非價格類意圖給 null"),
            field("currency", description = "幣別;沒講給 null", enums = CrossTestEnums.CURRENCIES),
            field("stock", description = "股票名稱或代碼,照聽到的字面;無則 null"),
            field("account", description = "帳戶,必須是清單內確切名稱;對不上給 null", enums = CrossTestEnums.ACCOUNTS),
            field("from_account", description = "轉帳來源帳戶;非轉帳給 null", enums = CrossTestEnums.ACCOUNTS),
            field("to_account", description = "轉帳目的帳戶;非轉帳給 null", enums = CrossTestEnums.ACCOUNTS),
            field("category", description = "分類「父>子」;對不上給 null", enums = CrossTestEnums.CATEGORIES),
            field("date_text", description = "原句的日期字面(如「上週五」「昨天」);沒講日期給 null"),
            field("note", description = "備註;無則 null"),
        ),
    )

    private fun field(
        name: String,
        nullable: Boolean = true,
        description: String,
        enums: Array<String>? = null,
    ) = GenerableDetail.GuideDetail(name, String::class, nullable, description, null, null, null, null, enums, false, null)

    private fun numField(name: String, description: String) =
        GenerableDetail.GuideDetail(name, Double::class, true, description, null, null, null, null, null, false, null)
}
