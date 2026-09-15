package app.aming.gemma4.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import app.aming.gemma4.MainViewModel
import app.aming.gemma4.PdfPageRun
import app.aming.gemma4.pdf.DocType
import app.aming.gemma4.pdf.PdfMode
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Candidate

/** PDF tab: pick a statement/notice PDF, extract per page, show structured JSON. */
fun LazyListScope.pdfItems(viewModel: MainViewModel, onPickFile: () -> Unit) {
    item { PdfSetupCard(viewModel, onPickFile) }
    items(viewModel.pdfRuns) { run -> PdfRunCard(run) }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun PdfSetupCard(viewModel: MainViewModel, onPickFile: () -> Unit) {
    val doc = viewModel.pdf
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text("PDF 文件解析", style = MaterialTheme.typography.titleMedium)
            if (!viewModel.pdfSupported) {
                Text(
                    "此裝置低於 Android 15,沒有內建 PDF 文字/密碼 API。",
                    color = MaterialTheme.colorScheme.error,
                )
            }
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedButton(onClick = onPickFile, enabled = viewModel.pdfSupported) { Text("選擇 PDF") }
                if (doc != null) {
                    TextButton(onClick = { viewModel.clearPdf() }) { Text("清除") }
                }
            }
            if (doc != null) {
                val textPages = doc.pages.count { it.text.length >= 40 }
                Text(doc.name, style = MaterialTheme.typography.bodyMedium)
                Text(
                    "共 ${doc.pageCount} 頁 · 文字頁 $textPages · 無文字(掃描)頁 ${doc.pageCount - textPages}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            OutlinedTextField(
                value = viewModel.pdfPassword,
                onValueChange = { viewModel.pdfPassword = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("PDF 密碼(有加密才需要)") },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                trailingIcon = {
                    if (viewModel.pdfError != null) {
                        TextButton(onClick = { viewModel.loadPdf() }) { Text("重試") }
                    }
                },
            )
            viewModel.pdfError?.let {
                Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }

            Text("文件類型", style = MaterialTheme.typography.labelLarge)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                DocType.entries.forEach { type ->
                    FilterChip(
                        selected = viewModel.docType == type,
                        onClick = { viewModel.docType = type },
                        label = { Text(type.label) },
                    )
                }
            }
            Text("輸入方式", style = MaterialTheme.typography.labelLarge)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                PdfMode.entries.forEach { mode ->
                    FilterChip(
                        selected = viewModel.pdfMode == mode,
                        onClick = { viewModel.pdfMode = mode },
                        label = { Text(mode.label) },
                    )
                }
            }
            Text(
                "自動:有文字的頁面走文字,掃描頁走圖片(render 成 Bitmap 餵 ImagePart)",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Button(
                    onClick = { viewModel.runPdf() },
                    enabled = doc != null && !viewModel.pdfBusy &&
                        viewModel.modelStatus == FeatureStatus.AVAILABLE,
                ) { Text("開始解析") }
                if (viewModel.pdfBusy) CircularProgressIndicator(modifier = Modifier.size(24.dp))
            }
            viewModel.pdfProgress?.let {
                Text(it, style = MaterialTheme.typography.bodySmall)
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
            }
        }
    }
}

@Composable
private fun PdfRunCard(run: PdfPageRun) {
    var showText by rememberSaveable { mutableStateOf(false) }
    var showRaw by rememberSaveable { mutableStateOf(false) }
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "第 ${run.pageNo}/${run.pageCount} 頁",
                    style = MaterialTheme.typography.titleSmall,
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    "${run.modeUsed.label} · in ${run.inputTokens ?: "?"} tok · ${run.latencyMs} ms" +
                        when (run.finishReason) {
                            Candidate.FinishReason.MAX_TOKENS -> " · ⚠️ 輸出被截斷"
                            null -> ""
                            else -> " · finish=${run.finishReason}"
                        },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            HorizontalDivider()
            when {
                run.error != null -> Text("錯誤:${run.error}", color = MaterialTheme.colorScheme.error)
                run.prettyJson != null -> Text(
                    run.prettyJson,
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                )
                else -> {
                    Text("無法解析為 JSON,原始輸出:", color = MaterialTheme.colorScheme.error)
                    Text(run.rawOutput, style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace)
                }
            }
            Row {
                if (run.textPreview.isNotEmpty()) {
                    TextButton(onClick = { showText = !showText }) {
                        Text(if (showText) "隱藏擷取文字" else "擷取文字(${run.textPreview.length} 字)")
                    }
                }
                if (run.prettyJson != null && run.rawOutput.isNotEmpty()) {
                    TextButton(onClick = { showRaw = !showRaw }) {
                        Text(if (showRaw) "隱藏原始輸出" else "原始輸出")
                    }
                }
            }
            if (showText) {
                Text(
                    run.textPreview,
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                )
            }
            if (showRaw) {
                Text(
                    run.rawOutput,
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                )
            }
        }
    }
}
