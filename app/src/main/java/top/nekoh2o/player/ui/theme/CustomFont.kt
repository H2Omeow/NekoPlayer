package top.nekoh2o.player.ui.theme

import top.nekoh2o.player.i18n.NekoI18n.tr

import android.content.Context
import android.graphics.Typeface
import android.net.Uri
import android.provider.OpenableColumns
import androidx.compose.ui.text.font.FontFamily
import java.io.File

/** Local TTF / OTF fonts chosen by the user. The file is copied into the app
 *  directory so the original document can be moved or deleted safely. */
object CustomFont {
    private const val MAX_BYTES = 64L * 1024 * 1024
    private const val PREFIX = "font-"

    data class Installed(val path: String, val name: String)

    fun install(context: Context, uri: Uri): Installed {
        val displayName = displayName(context, uri)
        val extension = displayName.substringAfterLast('.', "").lowercase().ifBlank {
            when (context.contentResolver.getType(uri)?.lowercase()) {
                "font/ttf", "application/x-font-ttf" -> "ttf"
                "font/otf", "application/vnd.ms-opentype" -> "otf"
                else -> ""
            }
        }
        if (extension != "ttf" && extension != "otf") {
            throw IllegalArgumentException(tr("请选择 TTF 或 OTF 字体文件。"))
        }
        val base = displayName.substringBeforeLast('.')
            .replace(Regex("[^\\p{L}\\p{N}._-]+"), "_")
            .take(60)
            .ifBlank { "custom" }
        // A unique name forces Compose to reload when the same font is picked
        // again, and lets the old copy be removed after a successful install.
        val target = File(
            context.filesDir,
            "$PREFIX$base-${System.currentTimeMillis()}.$extension",
        )
        val temporary = File(context.filesDir, "${target.name}.part")
        try {
            var total = 0L
            context.contentResolver.openInputStream(uri)?.use { input ->
                temporary.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > MAX_BYTES) {
                            throw IllegalArgumentException(tr("字体文件超过 64MB。"))
                        }
                        output.write(buffer, 0, read)
                    }
                }
            } ?: throw IllegalArgumentException(tr("无法读取字体文件。"))
            if (total <= 0L) throw IllegalArgumentException(tr("字体文件为空。"))
            if (!temporary.renameTo(target)) {
                target.delete()
                if (!temporary.renameTo(target)) {
                    throw IllegalArgumentException(tr("无法保存字体文件。"))
                }
            }
            // Reject files that the platform cannot parse before saving the path.
            if (Typeface.createFromFile(target) == null) {
                throw IllegalArgumentException(tr("字体文件无法解析，请换一个 TTF / OTF 文件。"))
            }
            context.filesDir.listFiles()
                ?.filter { it.name.startsWith(PREFIX) && it != target }
                ?.forEach { it.delete() }
            return Installed(target.absolutePath, displayName)
        } catch (failure: IllegalArgumentException) {
            throw failure
        } catch (_: Exception) {
            throw IllegalArgumentException(tr("字体文件无法解析，请换一个 TTF / OTF 文件。"))
        } finally {
            temporary.delete()
        }
    }

    fun load(path: String): FontFamily? = loadTypeface(path)?.let { FontFamily(it) }

    fun loadTypeface(path: String): Typeface? {
        if (path.isBlank()) return null
        val file = File(path)
        if (!file.isFile) return null
        return try {
            Typeface.createFromFile(file)
        } catch (_: Exception) {
            null
        }
    }

    /** Removes a previously installed font; paths outside the app directory are ignored. */
    fun clear(context: Context, path: String) {
        val file = File(path)
        if (file.parentFile?.absolutePath == context.filesDir.absolutePath) {
            file.delete()
        }
    }

    private fun displayName(context: Context, uri: Uri): String {
        runCatching {
            context.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val name = cursor.getString(0)
                    if (!name.isNullOrBlank()) return name
                }
            }
        }
        return uri.lastPathSegment ?: "font.ttf"
    }
}
