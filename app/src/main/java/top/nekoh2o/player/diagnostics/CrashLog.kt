package top.nekoh2o.player.diagnostics

import android.content.Context
import android.os.Build
import android.util.Log
import java.io.File
import java.io.PrintWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 把未捕获异常写进应用私有目录，方便定位偶发启动闪退。
 * 只保留最近几份，避免长期占用空间。
 */
object CrashLog {
    private const val TAG = "NekoCrash"
    private const val MAX_FILES = 5

    @Volatile
    private var directory: File? = null

    @Volatile
    private var version: String = ""

    fun install(context: Context) {
        val app = context.applicationContext
        directory = File(app.filesDir, "crash").apply { runCatching { mkdirs() } }
        version = runCatching {
            val info = app.packageManager.getPackageInfo(app.packageName, 0)
            info.versionName.orEmpty()
        }.getOrDefault("")

        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            runCatching { write(thread, error) }
            previous?.uncaughtException(thread, error)
        }
    }

    fun latest(): File? {
        val files = directory?.listFiles() ?: return null
        return files.filter { it.isFile && it.name.startsWith("crash-") }
            .maxByOrNull { it.lastModified() }
    }

    private fun write(thread: Thread, error: Throwable) {
        val dir = directory ?: return
        val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
        val file = File(dir, "crash-$stamp-${thread.id}.log")
        file.bufferedWriter().use { writer ->
            writer.appendLine("time=${Date()}")
            writer.appendLine("thread=${thread.name} (${thread.id})")
            writer.appendLine("version=$version")
            writer.appendLine("device=${Build.MANUFACTURER} ${Build.MODEL} (API ${Build.VERSION.SDK_INT})")
            writer.appendLine()
            PrintWriter(writer).use { error.printStackTrace(it) }
        }
        Log.e(TAG, "crash log written to ${file.absolutePath}", error)
        dir.listFiles()
            ?.filter { it.isFile }
            ?.sortedByDescending { it.lastModified() }
            ?.drop(MAX_FILES)
            ?.forEach { runCatching { it.delete() } }
    }
}
