package app.aming.gemma4.nlu

import android.content.Context
import org.json.JSONObject

/**
 * The user's real account list and category tree (exported from AMing Balance),
 * rendered compactly for the prompt so the model can align slots to exact names.
 */
class EntityCatalog(
    val accounts: List<Account>,
    val categories: List<Category>,
) {
    data class Account(val name: String, val type: String, val currency: String, val group: String)
    data class Category(val type: String, val parent: String, val children: List<String>)

    /** 帳戶清單:一行一個「名稱(群組/幣別)」,依群組排序,只含 ACTIVE。 */
    fun accountsText(): String = accounts
        .groupBy { it.group }
        .entries.joinToString("\n") { (group, list) ->
            "$group:" + list.joinToString("、") { a ->
                if (a.currency == "TWD") a.name else "${a.name}(${a.currency})"
            }
        }

    /** 分類清單:「父>子1|子2…」,收入/支出分開。 */
    fun categoriesText(): String {
        fun block(type: String) = categories.filter { it.type == type }.joinToString("\n") { c ->
            if (c.children.isEmpty()) c.parent else "${c.parent}>" + c.children.joinToString("|")
        }
        return "支出分類:\n${block("EXPENSE")}\n收入分類:\n${block("INCOME")}"
    }

    /** Exact "父>子" names, for validating model output app-side. */
    val categoryPaths: Set<String> = categories.flatMap { c ->
        if (c.children.isEmpty()) listOf(c.parent) else c.children.map { "${c.parent}>$it" }
    }.toSet()
    val accountNames: Set<String> = accounts.map { it.name }.toSet()

    companion object {
        fun loadFromAssets(context: Context): EntityCatalog {
            val acc = JSONObject(context.assets.open("dev_accounts.json").bufferedReader().readText())
            val accounts = buildList {
                val arr = acc.getJSONArray("accounts")
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    if (o.optString("status") != "ACTIVE") continue
                    add(Account(o.getString("name"), o.optString("type"), o.optString("currencyCode", "TWD"), if (o.isNull("groupName")) "其他" else o.getString("groupName")))
                }
            }
            val cat = JSONObject(context.assets.open("dev_categories.json").bufferedReader().readText())
            val categories = buildList {
                val arr = cat.getJSONArray("categories")
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    val kids = o.optJSONArray("children")
                    val names = buildList { if (kids != null) for (j in 0 until kids.length()) add(kids.getJSONObject(j).getString("name")) }
                    add(Category(o.optString("type"), o.getString("name"), names))
                }
            }
            return EntityCatalog(accounts, categories)
        }
    }
}
