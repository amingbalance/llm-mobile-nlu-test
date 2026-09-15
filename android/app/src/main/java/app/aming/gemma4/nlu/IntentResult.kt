package app.aming.gemma4.nlu

import org.json.JSONObject

data class IntentResult(
    val intent: String,
    val confidence: Double?,
    val originalText: String?,
    val normalizedText: String?,
    val slots: Map<String, String>,
) {
    companion object {
        private val SLOT_KEYS = listOf(
            "amount", "currency", "price", "stock", "account",
            "from_account", "to_account", "category", "date", "note",
        )

        /**
         * Tolerant parse: strips code fences / surrounding prose, then reads the
         * first {...} block. Returns null if no valid JSON object is found.
         */
        fun parse(raw: String): IntentResult? {
            val start = raw.indexOf('{')
            val end = raw.lastIndexOf('}')
            if (start < 0 || end <= start) return null
            val obj = runCatching { JSONObject(raw.substring(start, end + 1)) }.getOrNull() ?: return null

            val slotsObj = obj.optJSONObject("slots")
            val slots = buildMap {
                if (slotsObj != null) {
                    for (key in SLOT_KEYS) {
                        if (!slotsObj.isNull(key)) {
                            put(key, slotsObj.get(key).toString())
                        }
                    }
                }
            }
            return IntentResult(
                intent = obj.optString("intent", "UNKNOWN"),
                confidence = if (obj.isNull("confidence")) null else obj.optDouble("confidence"),
                originalText = obj.optString("original_text", null),
                normalizedText = obj.optString("normalized_text", null),
                slots = slots,
            )
        }
    }
}
