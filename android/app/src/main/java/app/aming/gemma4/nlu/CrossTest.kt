package app.aming.gemma4.nlu

import android.content.Context
import android.os.Build
import android.util.Log
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.GenerateTypedContentRequest
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.ModelPreference
import com.google.mlkit.genai.prompt.ModelReleaseStage
import com.google.mlkit.genai.prompt.SystemInstruction
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import com.google.mlkit.genai.prompt.generationConfig
import com.google.mlkit.genai.prompt.modelConfig
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * Cross-platform comparison harness (spec: nlu_crosstest/ios_test_design_spec.md),
 * mirroring the iOS run: R1 = frozen prompt, plain generation; R2 = structured output
 * (schema injected into prompt) ; R2_noschema = structured output without injection.
 * Triggered via: adb shell am start -n app.aming.gemma4/.MainActivity \
 *   --es autorun "R1,R2,R2_noschema" --ei runs 3
 * Results: filesDir/crosstest/results_Android<ver>_<round>_instructions_<ts>.json (spec §7)
 */
object CrossTest {
    private const val TAG = "CrossTest"
    private val FROZEN_TODAY: LocalDate = LocalDate.of(2026, 9, 15)

    suspend fun run(context: Context, rounds: List<String>, runs: Int): List<String> {
        val prompt = context.assets.open("crosstest/system_prompt_zh-TW.txt").bufferedReader().readText()
        val fixture = JSONObject(context.assets.open("crosstest/testcases.json").bufferedReader().readText())
        val cases = fixture.getJSONArray("cases")
        val model = Generation.getClient(
            generationConfig {
                modelConfig = modelConfig {
                    releaseStage = ModelReleaseStage.PREVIEW
                    preference = ModelPreference.FULL
                }
            }
        )
        val outFiles = mutableListOf<String>()
        try {
            val status = model.checkStatus()
            check(status == FeatureStatus.AVAILABLE) { "model not available: $status" }
            val baseName = runCatching { model.getBaseModelName() }.getOrDefault("?")
            // cold start: first inference including engine load
            val coldT0 = System.nanoTime()
            runCatching { model.generateContent("hi") }
            val coldMs = (System.nanoTime() - coldT0) / 1_000_000
            Log.i(TAG, "warmup/cold start $coldMs ms, baseModel=$baseName")

            for (round in rounds) {
                val recs = JSONArray()
                for (ci in 0 until cases.length()) {
                    val case = cases.getJSONObject(ci)
                    val cid = case.getString("id")
                    val input = case.getString("input")
                    for (runNo in 1..runs) {
                        Log.i(TAG, "[$round] $cid run $runNo start")
                        val rec = when (round) {
                            "R1" -> runR1(model, prompt, input)
                            "R2" -> runR2(model, prompt, input, includeSchema = true)
                            "R2_noschema" -> runR2(model, prompt, input, includeSchema = false)
                            else -> error("unknown round $round")
                        }
                        rec.put("case_id", cid).put("run", runNo)
                        Log.i(TAG, "[$round] $cid run $runNo done in ${rec.optLong("latency_ms")} ms valid=${rec.optBoolean("json_valid")}")
                        recs.put(rec)
                    }
                }
                val env = JSONObject()
                    .put("device", "${Build.MODEL} (${Build.DEVICE}, ${Build.SOC_MODEL ?: ""})")
                    .put("os", "Android ${Build.VERSION.RELEASE} (${Build.ID})")
                    .put("framework", "ML Kit GenAI Prompt API genai-prompt:1.0.0-beta4 (AICore preview, $baseName)")
                    .put("model_id_or_availability", baseName)
                    .put("system_prompt_placement", "instructions")
                    .put("decoding", JSONObject().put("temperature", 0).put("topK", 1).put("maxOutputTokens", 512))
                    .put("cloud_fallback_disabled_how", "AICore is on-device only; no cloud path in Prompt API")
                    .put("session_freshness", "stateless generateContent per request (no conversation state); same client reused")
                    .put(
                        "r2_date_resolver",
                        if (round == "R1") JSONObject.NULL
                        else "CrossTest.resolveDate, today fixed to 2026-09-15, week starts Monday; " +
                            "supports 昨天/前天/大前天/今天/明天/後天、N天前後、(上上|上|這|本|下)(週|星期|禮拜)X、單獨 週X=最近一次(含今天)、M/D、M月D日、YYYY-MM-DD、N號",
                    )
                    .put("r2_schema_note", if (round == "R1") JSONObject.NULL else "confidence/normalized_text 不在 schema(不計分,spec §5 允許)")
                val doc = JSONObject().put("env", env).put("cold_start_ms", coldMs).put("runs", recs)
                val dir = File(context.filesDir, "crosstest").apply { mkdirs() }
                val ts = java.text.SimpleDateFormat("yyyyMMdd-HHmmss", java.util.Locale.US).format(java.util.Date())
                val f = File(dir, "results_Android${Build.VERSION.RELEASE}_${round}_instructions_$ts.json")
                f.writeText(doc.toString(1))
                Log.i(TAG, "ROUND $round DONE -> ${f.absolutePath}")
                outFiles.add(f.absolutePath)
            }
        } finally {
            model.close()
        }
        Log.i(TAG, "ALL DONE files=${outFiles.joinToString()}")
        return outFiles
    }

    // ---- R1: plain generation, tolerant JSON parse ----
    private suspend fun runR1(model: com.google.mlkit.genai.prompt.GenerativeModel, prompt: String, input: String): JSONObject {
        val request = generateContentRequest(SystemInstruction(prompt), TextPart(input)) {
            temperature = 0.0f; topK = 1; maxOutputTokens = 512
        }
        val t0 = System.nanoTime()
        return try {
            val resp = model.generateContent(request)
            val ms = (System.nanoTime() - t0) / 1_000_000
            val raw = resp.candidates.firstOrNull()?.text.orEmpty()
            val parsed = parseR1(raw)
            JSONObject().put("latency_ms", ms).put("json_valid", parsed != null)
                .put("parsed", parsed ?: JSONObject.NULL).put("raw_output", raw)
        } catch (e: Exception) {
            JSONObject().put("latency_ms", (System.nanoTime() - t0) / 1_000_000).put("json_valid", false)
                .put("parsed", JSONObject.NULL).put("raw_output", "ERROR: ${e.message ?: e.javaClass.simpleName}")
        }
    }

    private fun parseR1(raw: String): JSONObject? {
        val s = raw.indexOf('{'); val e = raw.lastIndexOf('}')
        if (s < 0 || e <= s) return null
        val obj = runCatching { JSONObject(raw.substring(s, e + 1)) }.getOrNull() ?: return null
        val slots = obj.optJSONObject("slots") ?: JSONObject()
        val p = JSONObject().put("intent", obj.opt("intent") ?: JSONObject.NULL)
        for (k in listOf("amount", "price", "currency", "stock", "account", "from_account", "to_account", "category", "date", "note")) {
            p.put(k, slots.opt(k) ?: JSONObject.NULL)
        }
        return p
    }

    // ---- R2: structured output; date resolved from date_text by code ----
    private suspend fun runR2(model: com.google.mlkit.genai.prompt.GenerativeModel, prompt: String, input: String, includeSchema: Boolean): JSONObject {
        val base = generateContentRequest(SystemInstruction(prompt), TextPart(input)) {
            temperature = 0.0f; topK = 1; maxOutputTokens = 512
        }
        val typed = GenerateTypedContentRequest.Builder(base, VoiceIntentOut::class)
            .apply { includeSchemaInPrompt = includeSchema }
            .build()
        val t0 = System.nanoTime()
        return try {
            val resp = model.generateContent(typed)
            val ms = (System.nanoTime() - t0) / 1_000_000
            val out = resp.candidates.firstOrNull()?.response
            val p = JSONObject()
            if (out != null) {
                p.put("intent", out.intent)
                    .put("amount", out.amount ?: JSONObject.NULL)
                    .put("price", out.price ?: JSONObject.NULL)
                    .put("currency", out.currency ?: JSONObject.NULL)
                    .put("stock", out.stock ?: JSONObject.NULL)
                    .put("account", out.account ?: JSONObject.NULL)
                    .put("from_account", out.from_account ?: JSONObject.NULL)
                    .put("to_account", out.to_account ?: JSONObject.NULL)
                    .put("category", out.category ?: JSONObject.NULL)
                    .put("date_text", out.date_text ?: JSONObject.NULL)
                    .put("date", out.date_text?.let { resolveDate(it) } ?: JSONObject.NULL)
                    .put("note", out.note ?: JSONObject.NULL)
            }
            JSONObject().put("latency_ms", ms).put("json_valid", out != null)
                .put("parsed", if (out != null) p else JSONObject.NULL)
                .put("raw_output", out?.toString() ?: "(null response)")
        } catch (e: Exception) {
            JSONObject().put("latency_ms", (System.nanoTime() - t0) / 1_000_000).put("json_valid", false)
                .put("parsed", JSONObject.NULL).put("raw_output", "ERROR: ${e.message ?: e.javaClass.simpleName}")
        }
    }

    /** Deterministic zh-TW relative-date resolver, today fixed to 2026-09-15 (Monday-based weeks). */
    fun resolveDate(textRaw: String): String? {
        val text = textRaw.trim()
        val today = FROZEN_TODAY
        val iso = DateTimeFormatter.ISO_LOCAL_DATE
        Regex("""^\d{4}-\d{2}-\d{2}$""").find(text)?.let { return text }
        when (text) {
            "今天" -> return today.format(iso)
            "昨天" -> return today.minusDays(1).format(iso)
            "前天" -> return today.minusDays(2).format(iso)
            "大前天" -> return today.minusDays(3).format(iso)
            "明天" -> return today.plusDays(1).format(iso)
            "後天" -> return today.plusDays(2).format(iso)
        }
        Regex("""^(\d+)天(前|後)$""").find(text)?.let { m ->
            val n = m.groupValues[1].toLong()
            return (if (m.groupValues[2] == "前") today.minusDays(n) else today.plusDays(n)).format(iso)
        }
        val wdMap = mapOf("一" to 1, "二" to 2, "三" to 3, "四" to 4, "五" to 5, "六" to 6, "日" to 7, "天" to 7)
        Regex("""^(上上|上|這|本|下)?(週|星期|禮拜)([一二三四五六日天])$""").find(text)?.let { m ->
            val wd = DayOfWeek.of(wdMap[m.groupValues[3]]!!)
            val thisMonday = today.minusDays((today.dayOfWeek.value - 1).toLong())
            return when (m.groupValues[1]) {
                "上上" -> thisMonday.minusWeeks(2).plusDays((wd.value - 1).toLong())
                "上" -> thisMonday.minusWeeks(1).plusDays((wd.value - 1).toLong())
                "這", "本" -> thisMonday.plusDays((wd.value - 1).toLong())
                "下" -> thisMonday.plusWeeks(1).plusDays((wd.value - 1).toLong())
                else -> { // bare 週X = most recent occurrence (incl. today)
                    var d = thisMonday.plusDays((wd.value - 1).toLong())
                    if (d.isAfter(today)) d = d.minusWeeks(1)
                    d
                }
            }.format(iso)
        }
        Regex("""^(\d{1,2})[/月](\d{1,2})日?$""").find(text)?.let { m ->
            return LocalDate.of(today.year, m.groupValues[1].toInt(), m.groupValues[2].toInt()).format(iso)
        }
        Regex("""^(\d{1,2})號$""").find(text)?.let { m ->
            return LocalDate.of(today.year, today.monthValue, m.groupValues[1].toInt()).format(iso)
        }
        return null
    }
}
