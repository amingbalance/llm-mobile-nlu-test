package app.aming.gemma4

import android.app.Application
import android.net.Uri
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.aming.gemma4.nlu.EntityCatalog
import app.aming.gemma4.nlu.GemmaNlu
import app.aming.gemma4.nlu.NluRun
import app.aming.gemma4.pdf.DocPrompts
import app.aming.gemma4.pdf.DocType
import app.aming.gemma4.pdf.LoadedPdf
import app.aming.gemma4.nlu.VoiceIntentPrompt
import app.aming.gemma4.pdf.PdfMode
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** Result of running one PDF page through the model. */
data class PdfPageRun(
    val pageNo: Int,
    val pageCount: Int,
    val modeUsed: PdfMode,
    val textPreview: String,
    val inputTokens: Int?,
    val latencyMs: Long,
    val finishReason: Int?,
    val rawOutput: String,
    val prettyJson: String?,
    val error: String?,
)

class MainViewModel(app: Application) : AndroidViewModel(app) {

    // ---- model / engine -------------------------------------------------
    var preferFull by mutableStateOf(true)
        private set
    var previewStage by mutableStateOf(true)
        private set
    var modelStatus by mutableStateOf<Int?>(null)
        private set
    var baseModelName by mutableStateOf("")
        private set
    var tokenLimit by mutableStateOf<Int?>(null)
        private set
    var downloadInfo by mutableStateOf<String?>(null)
        private set

    private var engine = GemmaNlu(preferFull = preferFull, previewStage = previewStage)

    // ---- voice NLU -----------------------------------------------------
    var busy by mutableStateOf(false)
        private set
    var inputText by mutableStateOf("")
    val history = mutableStateListOf<NluRun>()
    /** Inject the user's real account list + category tree into the prompt. */
    var useCatalog by mutableStateOf(true)
    val catalog: EntityCatalog? = runCatching { EntityCatalog.loadFromAssets(app) }
        .onFailure { android.util.Log.w("GemmaNlu", "catalog load failed", it) }.getOrNull()

    // ---- PDF -----------------------------------------------------------
    var pdf by mutableStateOf<LoadedPdf?>(null)
        private set
    var pdfError by mutableStateOf<String?>(null)
        private set
    var pdfPassword by mutableStateOf("")
    var docType by mutableStateOf(DocType.AUTO)
    var pdfMode by mutableStateOf(PdfMode.AUTO)
    var pdfBusy by mutableStateOf(false)
        private set
    var pdfProgress by mutableStateOf<String?>(null)
        private set
    val pdfRuns = mutableStateListOf<PdfPageRun>()
    private var pendingPdfUri: Uri? = null

    init {
        refreshStatus()
    }

    fun setModelPreference(full: Boolean) {
        if (full == preferFull) return
        preferFull = full
        rebuildEngine()
    }

    fun setStage(preview: Boolean) {
        if (preview == previewStage) return
        previewStage = preview
        rebuildEngine()
    }

    private fun rebuildEngine() {
        engine.close()
        engine = GemmaNlu(preferFull = preferFull, previewStage = previewStage)
        modelStatus = null
        baseModelName = ""
        tokenLimit = null
        refreshStatus()
    }

    fun refreshStatus() {
        viewModelScope.launch {
            modelStatus = runCatching { engine.checkStatus() }.getOrElse { FeatureStatus.UNAVAILABLE }
            if (modelStatus == FeatureStatus.AVAILABLE) {
                baseModelName = engine.baseModelName()
                tokenLimit = engine.tokenLimit
                engine.warmup()
            }
        }
    }

    fun download() {
        viewModelScope.launch {
            downloadInfo = "開始下載…"
            runCatching {
                engine.download().collect { status ->
                    downloadInfo = when (status) {
                        is DownloadStatus.DownloadStarted -> "下載中…"
                        is DownloadStatus.DownloadProgress ->
                            "已下載 %.1f MB".format(status.totalBytesDownloaded / 1024.0 / 1024.0)
                        is DownloadStatus.DownloadCompleted -> null
                        is DownloadStatus.DownloadFailed -> "下載失敗:${status.e.message}"
                        else -> downloadInfo
                    }
                }
            }.onFailure { downloadInfo = "下載失敗:${it.message}" }
            refreshStatus()
        }
    }

    fun startCrossTest(rounds: String, runs: Int) {
        viewModelScope.launch {
            android.util.Log.i("CrossTest", "autorun rounds=$rounds runs=$runs")
            runCatching {
                app.aming.gemma4.nlu.CrossTest.run(getApplication(), rounds.split(',').map { it.trim() }.filter { it.isNotEmpty() }, runs)
            }.onFailure { android.util.Log.e("CrossTest", "FAILED", it) }
        }
    }

    fun classify(text: String = inputText) {
        val utterance = text.trim()
        if (utterance.isEmpty() || busy) return
        viewModelScope.launch {
            busy = true
            val system = VoiceIntentPrompt.systemInstruction(catalog = if (useCatalog) catalog else null)
            history.add(0, engine.classify(utterance, system))
            busy = false
        }
    }

    // ---- PDF flow --------------------------------------------------------

    val pdfSupported: Boolean get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM

    /** Opens the picked PDF (re-tries with the current password when called again). */
    fun loadPdf(uri: Uri? = pendingPdfUri) {
        uri ?: return
        pendingPdfUri = uri
        if (!pdfSupported) {
            pdfError = "需要 Android 15(API 35)以上才支援內建 PDF 解析"
            return
        }
        viewModelScope.launch {
            pdfError = null
            pdfRuns.clear()
            pdf?.close(); pdf = null
            val password = pdfPassword.takeIf { it.isNotBlank() }
            runCatching {
                withContext(Dispatchers.IO) { LoadedPdf.open(getApplication(), uri, password) }
            }.onSuccess { pdf = it }
                .onFailure { e ->
                    pdfError = when (e) {
                        is SecurityException -> "需要密碼或密碼錯誤(${e.message})"
                        else -> "開啟失敗:${e.message ?: e.javaClass.simpleName}"
                    }
                }
        }
    }

    fun clearPdf() {
        pdf?.close(); pdf = null
        pdfRuns.clear()
        pdfError = null
        pendingPdfUri = null
    }

    fun runPdf() {
        val doc = pdf ?: return
        if (pdfBusy || modelStatus != FeatureStatus.AVAILABLE) return
        viewModelScope.launch {
            pdfBusy = true
            pdfRuns.clear()
            val system = DocPrompts.systemInstruction(docType)
            for (page in doc.pages) {
                val pageNo = page.index + 1
                val mode = when (pdfMode) {
                    PdfMode.TEXT -> PdfMode.TEXT
                    PdfMode.IMAGE -> PdfMode.IMAGE
                    PdfMode.AUTO -> if (page.text.length >= 40) PdfMode.TEXT else PdfMode.IMAGE
                }
                pdfProgress = "第 $pageNo/${doc.pageCount} 頁(${mode.label})推論中…"
                android.util.Log.i("PdfText", "page $pageNo (${page.text.length} chars):\n${page.text}")
                val result = if (mode == PdfMode.TEXT) {
                    engine.generate(
                        systemText = system,
                        userText = DocPrompts.userTextForText(pageNo, doc.pageCount, page.text),
                        maxOutputTokens = 2048,
                        tag = "pdf p$pageNo",
                    )
                } else {
                    val bitmap = withContext(Dispatchers.IO) { doc.renderPage(page.index) }
                    engine.generate(
                        systemText = system,
                        userText = DocPrompts.userTextForImage(pageNo, doc.pageCount),
                        image = bitmap,
                        maxOutputTokens = 2048,
                        tag = "pdf p$pageNo",
                    )
                }
                pdfRuns.add(
                    PdfPageRun(
                        pageNo = pageNo,
                        pageCount = doc.pageCount,
                        modeUsed = mode,
                        textPreview = page.text,
                        inputTokens = result.inputTokens,
                        latencyMs = result.latencyMs,
                        finishReason = result.finishReason,
                        rawOutput = result.rawOutput,
                        prettyJson = prettyJson(result.rawOutput),
                        error = result.error,
                    )
                )
            }
            pdfProgress = null
            pdfBusy = false
        }
    }

    private fun prettyJson(raw: String): String? {
        val start = raw.indexOf('{')
        val end = raw.lastIndexOf('}')
        if (start < 0 || end <= start) return null
        return runCatching { JSONObject(raw.substring(start, end + 1)).toString(2) }.getOrNull()
    }

    override fun onCleared() {
        pdf?.close()
        engine.close()
    }
}
