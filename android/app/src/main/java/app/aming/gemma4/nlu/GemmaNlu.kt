package app.aming.gemma4.nlu

import android.graphics.Bitmap
import android.util.Log
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.ImagePart
import com.google.mlkit.genai.prompt.ModelPreference
import com.google.mlkit.genai.prompt.ModelReleaseStage
import com.google.mlkit.genai.prompt.SystemInstruction
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import com.google.mlkit.genai.prompt.generationConfig
import com.google.mlkit.genai.prompt.modelConfig
import kotlinx.coroutines.flow.Flow

/** One inference run against the on-device model (voice-intent flow). */
data class NluRun(
    val input: String,
    val rawOutput: String,
    val result: IntentResult?,
    val latencyMs: Long,
    val finishReason: Int?,
    val error: String? = null,
)

/** Generic generation result shared by the voice and PDF flows. */
data class GenResult(
    val rawOutput: String,
    val latencyMs: Long,
    val finishReason: Int?,
    val inputTokens: Int?,
    val error: String? = null,
)

/**
 * Wraps the ML Kit GenAI Prompt API (AICore).
 * releaseStage PREVIEW + the AICore developer preview opt-in selects Gemma 4;
 * preference chooses E2B (FAST) vs E4B (FULL).
 */
class GemmaNlu(private val preferFull: Boolean, private val previewStage: Boolean) {

    private val model: GenerativeModel = Generation.getClient(
        generationConfig {
            modelConfig = modelConfig {
                releaseStage = if (previewStage) ModelReleaseStage.PREVIEW else ModelReleaseStage.STABLE
                preference = if (preferFull) ModelPreference.FULL else ModelPreference.FAST
            }
        }
    )

    private var systemPromptSupported: Boolean? = null
    var tokenLimit: Int? = null
        private set

    val label: String get() = "${if (preferFull) "FULL" else "FAST"}/${if (previewStage) "PREVIEW" else "STABLE"}"

    suspend fun checkStatus(): Int {
        val status = model.checkStatus()
        if (status == FeatureStatus.AVAILABLE) {
            val sys = runCatching { model.isSystemPromptAvailable() }.getOrNull()
            val structured = runCatching { model.isStructuredOutputFeatureAvailable() }.getOrNull()
            val thinking = runCatching { model.isThinkingModeAvailable() }.getOrNull()
            tokenLimit = runCatching { model.getTokenLimit() }.getOrNull()
            systemPromptSupported = sys
            Log.i(TAG, "caps: systemPrompt=$sys structuredOutput=$structured thinking=$thinking tokenLimit=$tokenLimit")
        }
        return status
    }

    suspend fun baseModelName(): String = runCatching { model.getBaseModelName() }.getOrDefault("(unknown)")

    fun download(): Flow<DownloadStatus> = model.download()

    suspend fun warmup() {
        val startedAt = System.nanoTime()
        runCatching { model.warmup() }
            .onSuccess { Log.i(TAG, "warmup done in ${(System.nanoTime() - startedAt) / 1_000_000} ms") }
            .onFailure { Log.w(TAG, "warmup failed: ${it.message}") }
    }

    private suspend fun useSystemPrompt(): Boolean =
        systemPromptSupported
            ?: runCatching { model.isSystemPromptAvailable() }.getOrDefault(false)
                .also { systemPromptSupported = it }

    /**
     * Generic text(+image) generation. When SystemInstruction is unsupported the
     * system text is folded into the user text.
     */
    suspend fun generate(
        systemText: String,
        userText: String,
        image: Bitmap? = null,
        maxOutputTokens: Int = 512,
        tag: String = "generate",
    ): GenResult {
        val sys = useSystemPrompt()
        val request = when {
            image != null && sys -> generateContentRequest(
                SystemInstruction(systemText), ImagePart(image), TextPart(userText),
            ) { temperature = 0.0f; topK = 1; this.maxOutputTokens = maxOutputTokens }
            image != null -> generateContentRequest(
                ImagePart(image), TextPart("$systemText\n\n$userText"),
            ) { temperature = 0.0f; topK = 1; this.maxOutputTokens = maxOutputTokens }
            sys -> generateContentRequest(
                SystemInstruction(systemText), TextPart(userText),
            ) { temperature = 0.0f; topK = 1; this.maxOutputTokens = maxOutputTokens }
            else -> generateContentRequest(
                TextPart("$systemText\n\n$userText"),
            ) { temperature = 0.0f; topK = 1; this.maxOutputTokens = maxOutputTokens }
        }
        val inputTokens = runCatching { model.countTokens(request).totalTokens }.getOrNull()
        Log.i(TAG, "$tag start [$label] sysPrompt=$sys image=${image != null} inputTokens=$inputTokens")
        val startedAt = System.nanoTime()
        return try {
            val response = model.generateContent(request)
            val latencyMs = (System.nanoTime() - startedAt) / 1_000_000
            val candidate = response.candidates.firstOrNull()
            val raw = candidate?.text.orEmpty()
            Log.i(TAG, "$tag done in $latencyMs ms, finish=${candidate?.finishReason}, raw=$raw")
            GenResult(raw, latencyMs, candidate?.finishReason, inputTokens)
        } catch (e: Exception) {
            val latencyMs = (System.nanoTime() - startedAt) / 1_000_000
            Log.w(TAG, "$tag failed after $latencyMs ms", e)
            GenResult("", latencyMs, null, inputTokens, e.message ?: e.javaClass.simpleName)
        }
    }

    suspend fun classify(utterance: String, systemText: String = VoiceIntentPrompt.systemInstruction()): NluRun {
        Log.i(TAG, "classify start [$label]: $utterance")
        val r = generate(systemText, utterance, maxOutputTokens = 512, tag = "classify")
        return NluRun(
            input = utterance,
            rawOutput = r.rawOutput,
            result = if (r.error == null) IntentResult.parse(r.rawOutput) else null,
            latencyMs = r.latencyMs,
            finishReason = r.finishReason,
            error = r.error,
        )
    }

    fun close() = model.close()

    companion object {
        private const val TAG = "GemmaNlu"

        fun statusLabel(status: Int?): String = when (status) {
            FeatureStatus.AVAILABLE -> "可用"
            FeatureStatus.DOWNLOADABLE -> "可下載(尚未下載)"
            FeatureStatus.DOWNLOADING -> "下載中"
            FeatureStatus.UNAVAILABLE -> "此裝置/設定不可用"
            null -> "檢查中…"
            else -> "未知($status)"
        }
    }
}
