package app.aming.gemma4.pdf

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.LoadParams
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import androidx.annotation.RequiresApi

data class PdfPage(val index: Int, val text: String, val widthPt: Int, val heightPt: Int)

/**
 * A PDF opened with the Android 15+ (API 35) built-in PDF API — zero dependencies.
 * Password-protected files are supported via [LoadParams]; text is pulled with
 * Page.getTextContents(); pages can be rendered to bitmaps for the image path.
 */
@RequiresApi(Build.VERSION_CODES.VANILLA_ICE_CREAM)
class LoadedPdf private constructor(
    val name: String,
    private val pfd: ParcelFileDescriptor,
    private val renderer: PdfRenderer,
    val pages: List<PdfPage>,
) : AutoCloseable {

    val pageCount: Int get() = pages.size

    /** Renders a page onto a white bitmap whose longer side is [maxSide] px. */
    fun renderPage(index: Int, maxSide: Int = 1280): Bitmap {
        renderer.openPage(index).use { page ->
            val scale = maxSide.toFloat() / maxOf(page.width, page.height)
            val w = (page.width * scale).toInt().coerceAtLeast(1)
            val h = (page.height * scale).toInt().coerceAtLeast(1)
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            bmp.eraseColor(Color.WHITE)
            page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            return bmp
        }
    }

    override fun close() {
        runCatching { renderer.close() }
        runCatching { pfd.close() }
    }

    companion object {
        /** Opens [uri]; throws SecurityException on a missing/incorrect password. */
        fun open(context: Context, uri: Uri, password: String?): LoadedPdf {
            val name = displayName(context, uri) ?: uri.lastPathSegment ?: "document.pdf"
            val pfd = context.contentResolver.openFileDescriptor(uri, "r")
                ?: throw IllegalStateException("無法開啟檔案")
            val params = LoadParams.Builder()
                .apply { if (!password.isNullOrEmpty()) setPassword(password) }
                .build()
            val renderer = try {
                PdfRenderer(pfd, params)
            } catch (e: Exception) {
                pfd.close(); throw e
            }
            val pages = (0 until renderer.pageCount).map { i ->
                renderer.openPage(i).use { page ->
                    val contents = runCatching { page.textContents }.getOrDefault(emptyList())
                    android.util.Log.i("PdfBounds", "page ${i + 1}: ${contents.size} text contents, page ${page.width}x${page.height}pt")
                    contents.take(40).forEachIndexed { idx, c ->
                        android.util.Log.i("PdfBounds", "  #$idx bounds=${c.bounds.joinToString { b -> "[%.0f,%.0f-%.0f,%.0f]".format(b.left, b.top, b.right, b.bottom) }} text=${c.text.take(60).replace("\n", "⏎")}")
                    }
                    val text = contents.joinToString("\n") { it.text }
                    PdfPage(i, text.trim(), page.width, page.height)
                }
            }
            return LoadedPdf(name, pfd, renderer, pages)
        }

        private fun displayName(context: Context, uri: Uri): String? =
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
    }
}
