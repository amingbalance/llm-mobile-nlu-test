package app.aming.gemma4

import android.Manifest
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.aming.gemma4.nlu.GemmaNlu
import app.aming.gemma4.nlu.NluRun
import app.aming.gemma4.nlu.VoiceIntentPrompt
import app.aming.gemma4.ui.pdfItems
import app.aming.gemma4.ui.theme.Gemma4Theme
import com.google.mlkit.genai.common.FeatureStatus
import java.util.Locale

class MainActivity : ComponentActivity() {

    private val viewModel: MainViewModel by viewModels()
    private var speechRecognizer: SpeechRecognizer? = null
    private val listening = mutableStateOf(false)

    private val micPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) startListening() else toast("需要麥克風權限才能語音輸入")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        intent?.getStringExtra("autorun")?.let { rounds ->
            viewModel.startCrossTest(rounds, intent.getIntExtra("runs", 3))
        }
        setContent {
            Gemma4Theme {
                MainScreen(
                    viewModel = viewModel,
                    listening = listening.value,
                    onMicClick = { micPermission.launch(Manifest.permission.RECORD_AUDIO) },
                )
            }
        }
    }

    private fun startListening() {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            toast("此裝置沒有可用的語音辨識服務")
            return
        }
        if (speechRecognizer == null) {
            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this).apply {
                setRecognitionListener(object : RecognitionListener {
                    override fun onResults(results: Bundle?) {
                        listening.value = false
                        val text = results
                            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            ?.firstOrNull()
                        if (!text.isNullOrBlank()) {
                            viewModel.inputText = text
                            viewModel.classify(text)
                        }
                    }

                    override fun onError(error: Int) {
                        listening.value = false
                        if (error != SpeechRecognizer.ERROR_CLIENT) {
                            toast("語音辨識失敗(code $error)")
                        }
                    }

                    override fun onReadyForSpeech(params: Bundle?) {}
                    override fun onBeginningOfSpeech() {}
                    override fun onRmsChanged(rmsdB: Float) {}
                    override fun onBufferReceived(buffer: ByteArray?) {}
                    override fun onEndOfSpeech() {}
                    override fun onPartialResults(partialResults: Bundle?) {}
                    override fun onEvent(eventType: Int, params: Bundle?) {}
                })
            }
        }
        listening.value = true
        speechRecognizer?.startListening(
            Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
                )
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "zh-TW")
            }
        )
    }

    private fun toast(message: String) =
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()

    override fun onDestroy() {
        speechRecognizer?.destroy()
        super.onDestroy()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MainScreen(
    viewModel: MainViewModel,
    listening: Boolean,
    onMicClick: () -> Unit,
) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    val pdfPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri -> uri?.let { viewModel.loadPdf(it) } }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        topBar = {
            Column {
                TopAppBar(title = { Text("Gemma 4 可行性測試") })
                TabRow(selectedTabIndex = tab) {
                    Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text("語音 NLU") })
                    Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text("PDF 文件") })
                }
            }
        },
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item { ModelCard(viewModel) }
            if (tab == 0) {
                item { InputCard(viewModel, listening, onMicClick) }
                items(viewModel.history) { run -> ResultCard(run) }
            } else {
                pdfItems(viewModel, onPickFile = { pdfPicker.launch(arrayOf("application/pdf")) })
            }
        }
    }
}

@Composable
private fun ModelCard(viewModel: MainViewModel) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text("模型", style = MaterialTheme.typography.titleMedium)
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                SegmentedButton(
                    selected = !viewModel.preferFull,
                    onClick = { viewModel.setModelPreference(false) },
                    shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2),
                ) { Text("Fast (E2B)") }
                SegmentedButton(
                    selected = viewModel.preferFull,
                    onClick = { viewModel.setModelPreference(true) },
                    shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2),
                ) { Text("Full (E4B)") }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Preview 通道(Gemma 4)", style = MaterialTheme.typography.bodyMedium)
                Spacer(Modifier.width(8.dp))
                Switch(
                    checked = viewModel.previewStage,
                    onCheckedChange = { viewModel.setStage(it) },
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "狀態:${GemmaNlu.statusLabel(viewModel.modelStatus)}",
                    style = MaterialTheme.typography.bodyMedium,
                )
                Spacer(Modifier.width(12.dp))
                when (viewModel.modelStatus) {
                    FeatureStatus.DOWNLOADABLE, FeatureStatus.DOWNLOADING ->
                        OutlinedButton(onClick = { viewModel.download() }) { Text("下載模型") }
                    FeatureStatus.UNAVAILABLE ->
                        TextButton(onClick = { viewModel.refreshStatus() }) { Text("重新檢查") }
                    else -> {}
                }
            }
            viewModel.downloadInfo?.let {
                Text(it, style = MaterialTheme.typography.bodySmall)
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
            }
            if (viewModel.baseModelName.isNotEmpty()) {
                Text(
                    "base model:${viewModel.baseModelName}" +
                        (viewModel.tokenLimit?.let { "  ·  token limit $it" } ?: ""),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun InputCard(
    viewModel: MainViewModel,
    listening: Boolean,
    onMicClick: () -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "帶入帳戶/分類清單" + (viewModel.catalog?.let { " (${it.accounts.size} 帳戶 · ${it.categoryPaths.size} 分類)" } ?: " (載入失敗)"),
                    style = MaterialTheme.typography.bodyMedium,
                )
                Spacer(Modifier.width(8.dp))
                Switch(
                    checked = viewModel.useCatalog,
                    onCheckedChange = { viewModel.useCatalog = it },
                    enabled = viewModel.catalog != null,
                )
            }
            OutlinedTextField(
                value = viewModel.inputText,
                onValueChange = { viewModel.inputText = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("輸入一句話(模擬語音轉文字結果)") },
                minLines = 2,
            )
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Button(
                    onClick = { viewModel.classify() },
                    enabled = !viewModel.busy && viewModel.inputText.isNotBlank(),
                ) { Text("解析") }
                OutlinedButton(onClick = onMicClick, enabled = !listening) {
                    Text(if (listening) "聆聽中…" else "🎤 語音")
                }
                if (viewModel.busy) CircularProgressIndicator(modifier = Modifier.size(24.dp))
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                VoiceIntentPrompt.samples.forEach { sample ->
                    AssistChip(
                        onClick = {
                            viewModel.inputText = sample
                            viewModel.classify(sample)
                        },
                        label = { Text(sample, style = MaterialTheme.typography.labelSmall) },
                    )
                }
            }
        }
    }
}

@Composable
private fun ResultCard(run: NluRun) {
    var showRaw by rememberSaveable { mutableStateOf(false) }
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                "「${run.input}」",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            when {
                run.error != null -> Text(
                    "錯誤:${run.error}",
                    color = MaterialTheme.colorScheme.error,
                )
                run.result == null -> Text(
                    "無法解析輸出(非 JSON)",
                    color = MaterialTheme.colorScheme.error,
                )
                else -> {
                    val result = run.result
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Surface(
                            color = if (result.intent == "UNKNOWN")
                                MaterialTheme.colorScheme.errorContainer
                            else MaterialTheme.colorScheme.primaryContainer,
                            shape = MaterialTheme.shapes.small,
                        ) {
                            Text(
                                result.intent,
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                                style = MaterialTheme.typography.labelLarge,
                                fontWeight = FontWeight.Bold,
                            )
                        }
                        Spacer(Modifier.width(8.dp))
                        result.confidence?.let {
                            Text(
                                "conf %.2f".format(it),
                                style = MaterialTheme.typography.labelMedium,
                            )
                        }
                    }
                    result.normalizedText
                        ?.takeIf { it.isNotBlank() }
                        ?.let { Text(it, style = MaterialTheme.typography.titleSmall) }
                    if (result.slots.isNotEmpty()) {
                        HorizontalDivider()
                        result.slots.forEach { (key, value) ->
                            Row {
                                Text(
                                    key,
                                    modifier = Modifier.width(110.dp),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                Text(value, style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "${run.latencyMs} ms" + (run.finishReason?.let { "  ·  finish=$it" } ?: ""),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.width(8.dp))
                if (run.rawOutput.isNotEmpty()) {
                    TextButton(onClick = { showRaw = !showRaw }) {
                        Text(if (showRaw) "隱藏原始輸出" else "原始輸出")
                    }
                }
            }
            if (showRaw && run.rawOutput.isNotEmpty()) {
                Text(
                    run.rawOutput,
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                )
            }
        }
    }
}
