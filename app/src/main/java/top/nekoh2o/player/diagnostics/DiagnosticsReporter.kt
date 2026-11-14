package top.nekoh2o.player.diagnostics

import android.content.Context
import android.os.Build
import android.os.SystemClock
import top.nekoh2o.player.PlayerApp
import top.nekoh2o.player.data.cache.MusicCache
import top.nekoh2o.player.data.plugins.PluginStore
import top.nekoh2o.player.data.repo.DownloadIndex
import top.nekoh2o.player.data.repo.LocalStore
import top.nekoh2o.player.data.store.SettingsStore
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** 生成可分享的诊断文本：设备、版本、设置摘要、运行日志与崩溃记录。 */
object DiagnosticsReporter {

    fun versionName(context: Context): String = runCatching {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        "${info.versionName.orEmpty()} ($code)"
    }.getOrDefault("unknown")

    fun build(context: Context): String {
        val app = context.applicationContext
        val settings = runCatching { SettingsStore(app).load() }.getOrNull()
        val store = (app as? PlayerApp)?.localStore
            ?: runCatching { LocalStore(app) }.getOrNull()
        val downloads = runCatching { DownloadIndex.all().size }.getOrDefault(0)
        val cached = runCatching { MusicCache.cachedKeys().size }.getOrDefault(0)
        val pluginCount = runCatching { PluginStore.state.value.plugins.size }.getOrDefault(0)
        val metrics = app.resources.displayMetrics
        val runtime = Runtime.getRuntime()

        return buildString {
            appendLine("NekoPlayer diagnostics export")
            appendLine("exported: ${timestamp()}")
            appendLine("version: ${versionName(app)}")
            appendLine("package: ${app.packageName}")
            appendLine("platform: android")
            appendLine("device: ${Build.MANUFACTURER} ${Build.MODEL} (${Build.DEVICE})")
            appendLine("android: ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
            appendLine("abis: ${Build.SUPPORTED_ABIS.joinToString()}")
            appendLine("locale: ${Locale.getDefault().toLanguageTag()}")
            appendLine("timezone: ${TimeZone.getDefault().id}")
            appendLine("screen: ${metrics.widthPixels}x${metrics.heightPixels} @ ${metrics.density}")
            appendLine("pid: ${android.os.Process.myPid()}, uptime: ${SystemClock.elapsedRealtime() / 1000}s")
            appendLine(
                "memory: max=${runtime.maxMemory() / 1024 / 1024}MB, " +
                    "used=${(runtime.totalMemory() - runtime.freeMemory()) / 1024 / 1024}MB, " +
                    "free=${runtime.freeMemory() / 1024 / 1024}MB"
            )
            appendLine(
                "settings: quality=${settings?.audioQuality ?: "?"}, " +
                    "cache=${settings?.cacheEnabled ?: "?"}, " +
                    "language=${settings?.language ?: "?"}, " +
                    "audio_engine=${settings?.audioEffects?.engine ?: "?"}, " +
                    "floating_lyrics=${settings?.floatingLyricEnabled ?: "?"}, " +
                    "social_push=${settings?.socialPushEnabled ?: "?"}"
            )
            appendLine(
                "data: favorites=${store?.favorites?.size ?: 0}, " +
                    "history=${store?.history?.size ?: 0}, " +
                    "playlists=${store?.playlists?.size ?: 0}, " +
                    "downloads=$downloads, cache_entries=$cached, plugins=$pluginCount"
            )
            appendLine("note: login credentials and cookies are not included; secrets in logs are redacted.")
            appendLine()

            val logs = AppLog.tail(512 * 1024)
            if (logs.isNotBlank()) {
                appendLine("######## runtime log")
                appendLine(logs)
                appendLine()
            }

            val crashes = CrashLog.all()
            if (crashes.isNotEmpty()) {
                appendLine("######## crash logs")
                for (file in crashes) {
                    appendLine("---- ${file.name} (${file.lastModified()}) ----")
                    appendLine(readTail(file, 256 * 1024))
                    appendLine()
                }
            }
        }
    }

    private fun timestamp(): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssZ", Locale.US).format(Date())

    private fun readTail(file: File, maxBytes: Int): String = runCatching {
        val length = file.length()
        val start = (length - maxBytes).coerceAtLeast(0)
        file.inputStream().use { input ->
            if (start > 0) input.skip(start)
            AppLog.redact(String(input.readBytes(), Charsets.UTF_8))
        }
    }.getOrElse { "读取失败：${it.message}" }
}
