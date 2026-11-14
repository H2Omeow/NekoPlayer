package top.nekoh2o.player.diagnostics

import android.content.Context
import android.util.Log
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 轻量运行日志：写入应用私有目录，按天/大小滚动，最多保留几份。
 * 导出诊断信息时与崩溃日志一起提供，便于定位播放、网络和启动问题。
 * 日志内容在落盘前统一脱敏，避免把 Cookie、令牌或带参数的地址带出去。
 */
object AppLog {
    private const val TAG = "NekoAppLog"
    private const val MAX_BYTES = 512L * 1024L
    private const val MAX_FILES = 3
    private const val MAX_ENTRY_CHARS = 16 * 1024

    @Volatile
    private var directory: File? = null

    @Volatile
    private var installed = false

    private val urlQuery = Regex(
        """(\b[a-z][a-z0-9+.-]*://[^\s?#"'<>]*)\?[^\s"'<>]*""",
        RegexOption.IGNORE_CASE
    )
    private val headerLine = Regex(
        """((?:proxy-)?authorization|set-cookie|cookie)(["']?\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\r\n]*)""",
        RegexOption.IGNORE_CASE
    )
    private val secretField = Regex(
        """(["']?[\w.-]*(?:token|secret|passw(?:or)?d|api[_-]?key|music_u|sessionid|session_id|credential)[\w.-]*["']?)(\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;&}\]]+)""",
        RegexOption.IGNORE_CASE
    )
    private val bearer = Regex("""\bBearer\s+[\w.~+/=-]+""", RegexOption.IGNORE_CASE)

    fun install(context: Context) {
        if (installed) return
        val app = context.applicationContext
        directory = File(app.filesDir, "logs").apply { runCatching { mkdirs() } }
        installed = true
        info("app", "process started, version=${DiagnosticsReporter.versionName(app)}")
    }

    fun info(tag: String, message: String) = write("INFO", tag, message)

    fun warn(tag: String, message: String, error: Throwable? = null) =
        write("WARN", tag, message, error)

    fun error(tag: String, message: String, error: Throwable? = null) =
        write("ERROR", tag, message, error)

    fun files(): List<File> = directory?.listFiles()
        ?.filter { it.isFile && it.name.startsWith("app-") && it.name.endsWith(".log") }
        ?.sortedBy { it.lastModified() }
        ?: emptyList()

    /** 最近 [maxBytes] 字节的日志，按时间从旧到新拼接。 */
    fun tail(maxBytes: Int = 512 * 1024): String {
        val entries = files()
        if (entries.isEmpty()) return ""
        val buffer = ByteArrayOutputStream()
        for (file in entries) {
            val content = runCatching { file.readBytes() }.getOrNull() ?: continue
            buffer.write("==== ${file.name} ====\n".toByteArray(Charsets.UTF_8))
            buffer.write(content)
            if (content.isNotEmpty() && content.last() != '\n'.code.toByte()) {
                buffer.write('\n'.code)
            }
        }
        val raw = buffer.toByteArray()
        if (raw.isEmpty()) return ""
        val start = (raw.size - maxBytes.coerceAtLeast(1024)).coerceAtLeast(0)
        return buildString {
            if (start > 0) append("...(仅显示末尾 ${raw.size - start} 字节)\n")
            append(String(raw, start, raw.size - start, Charsets.UTF_8))
        }
    }

    /** 将文本中的凭据和 URL 查询参数替换为占位符。 */
    fun redact(text: String): String = text
        .replace(urlQuery) { match -> "${match.groupValues[1]}?<redacted>" }
        .replace(headerLine) { match -> "${match.groupValues[1]}${match.groupValues[2]}<redacted>" }
        .replace(secretField) { match -> "${match.groupValues[1]}${match.groupValues[2]}<redacted>" }
        .replace(bearer, "Bearer <redacted>")

    @Synchronized
    private fun write(level: String, tag: String, message: String, error: Throwable? = null) {
        val root = directory ?: return
        try {
            val now = Date()
            var body = message
            if (error != null) {
                body += "\n  error: ${error}"
                val trace = StringWriter().also { error.printStackTrace(PrintWriter(it)) }.toString()
                if (trace.isNotBlank()) body += "\n$trace"
            }
            body = redact(body)
            if (body.length > MAX_ENTRY_CHARS) {
                body = body.substring(0, MAX_ENTRY_CHARS) + "\n  ...(truncated)"
            }
            val timestamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US).format(now)
            val entry = "$timestamp [$level] [$tag] $body\n"
            val day = SimpleDateFormat("yyyyMMdd", Locale.US).format(now)
            val file = File(root, "app-$day.log")
            if (file.exists() && file.length() + entry.toByteArray(Charsets.UTF_8).size > MAX_BYTES) {
                val rotated = File(
                    root,
                    "app-$day-${SimpleDateFormat("HHmmss", Locale.US).format(now)}-${now.time % 1000}.log"
                )
                runCatching { file.renameTo(rotated) }
            }
            file.appendText(entry, Charsets.UTF_8)
            prune(root)
        } catch (failure: Exception) {
            Log.w(TAG, "运行日志写入失败: ${failure.message}")
        }
    }

    private fun prune(root: File) {
        root.listFiles()
            ?.filter { it.isFile && it.name.startsWith("app-") && it.name.endsWith(".log") }
            ?.sortedByDescending { it.lastModified() }
            ?.drop(MAX_FILES)
            ?.forEach { runCatching { it.delete() } }
    }
}
