package top.nekoh2o.player.data.repo

import top.nekoh2o.player.i18n.NekoI18n.tr

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.documentfile.provider.DocumentFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext
import okhttp3.Request
import top.nekoh2o.player.data.model.DownloadedSong
import top.nekoh2o.player.data.model.DownloadStatus
import top.nekoh2o.player.data.model.DownloadTask
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.data.net.ApiFactory
import java.io.File
import java.io.FileOutputStream

/**
 * 歌曲下载管理器：
 *  - 支持多任务并发（每首歌一个协程）
 *  - 实时推送 [tasks] StateFlow 供 UI 展示进度
 *  - Android 10+ 走 MediaStore；低版本写外部存储
 *  - 下载完成后同时保存 .lrc 歌词文件
 *  - 支持 SAF 自定义目录（通过保存的 tree URI 字符串）
 */
object Downloader {

    private const val DEFAULT_SUB_DIR = "NekoPlayer"

    private val _tasks = MutableStateFlow<List<DownloadTask>>(emptyList())
    val tasks: StateFlow<List<DownloadTask>> = _tasks

    /**
     * 加入下载队列并立即开始下载。
     *
     * @param context  应用 Context
     * @param song     要下载的歌曲
     * @param url      音频直链（已通过 resolveDownload 核验下载权限）
     * @param quality  音质标识（standard / higher / exhigh / lossless）
     * @param lrcContent  歌词文本（.lrc 格式），null 表示无歌词不写文件
     * @param dirUri   SAF tree URI 字符串（空串或 null → 用默认目录）
     * @return 下载成功后的 [DownloadedSong]，失败抛异常
     */
    suspend fun download(
        context: Context,
        song: Song,
        url: String,
        quality: String = "exhigh",
        lrcContent: String? = null,
        dirUri: String? = null,
        headers: Map<String, String> = emptyMap()
    ): DownloadedSong = withContext(Dispatchers.IO) {

        val task = DownloadTask(song = song, quality = quality, status = DownloadStatus.QUEUED)
        pushTask(task)

        runCatching {
            // 构造文件名：歌名 - 歌手.ext
            val ext = guessExtension(url)
            val mime = when (ext) { "flac" -> "audio/flac"; "m4a", "mp4" -> "audio/mp4"; "ogg" -> "audio/ogg"; "wav" -> "audio/wav"; else -> "audio/mpeg" }
            val safeName = buildSafeName(song)
            val audioFileName = "$safeName.$ext"
            val lrcFileName   = "$safeName.lrc"

            // 流式写入音频（避免OOM）
            val audioUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                if (!dirUri.isNullOrEmpty()) {
                    downloadStreamSafQ(context, dirUri, audioFileName, mime, url, headers) { prog ->
                        updateTask(song) { it.copy(status = DownloadStatus.DOWNLOADING, progress = prog) }
                    }
                } else {
                    downloadStreamMediaStore(context, audioFileName, mime, url, headers) { prog ->
                        updateTask(song) { it.copy(status = DownloadStatus.DOWNLOADING, progress = prog) }
                    }
                }
            } else {
                downloadStreamPublicDir(audioFileName, url, headers) { prog ->
                    updateTask(song) { it.copy(status = DownloadStatus.DOWNLOADING, progress = prog) }
                }
            }

            // 写入 .lrc
            val lrcPath: String? = if (!lrcContent.isNullOrBlank()) {
                runCatching {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !dirUri.isNullOrEmpty()) {
                        writeSafQText(context, dirUri, lrcFileName, lrcContent)
                    } else {
                        writePublicDirText(lrcFileName, lrcContent)
                    }
                }.getOrNull()
            } else null

            val result = DownloadedSong(
                songId    = song.id,
                song      = song,
                audioUri  = audioUri,
                lrcPath   = lrcPath,
                quality   = quality
            )
            updateTask(song) { it.copy(status = DownloadStatus.DONE, progress = 1f, result = result) }
            result
        }.getOrElse { e ->
            updateTask(song) { it.copy(status = DownloadStatus.FAILED, errorMsg = e.message) }
            throw e
        }
    }

    // ==================== 内部工具 ====================

    private fun pushTask(task: DownloadTask) {
        _tasks.update { list ->
            list.filter { it.song.id != task.song.id || it.song.source != task.song.source } + task
        }
    }

    private fun updateTask(song: Song, transform: (DownloadTask) -> DownloadTask) {
        _tasks.update { list -> list.map { if (it.song.id == song.id && it.song.source == song.source) transform(it) else it } }
    }

    // 流式下载到 MediaStore（Android 10+）
    private fun downloadStreamMediaStore(
        context: Context,
        fileName: String,
        mime: String,
        url: String,
        headers: Map<String, String>,
        onProgress: (Float) -> Unit
    ): String {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_MUSIC}/$DEFAULT_SUB_DIR")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(collection, values) ?: error(tr("无法创建媒体文件"))

        try {
            resolver.openOutputStream(uri)?.use { outputStream ->
                downloadToStream(url, headers, outputStream, onProgress)
            } ?: error(tr("无法写入"))

            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return uri.toString()
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }

    // 流式下载到 SAF 目录（Android 10+）
    private fun downloadStreamSafQ(
        context: Context,
        treeUriStr: String,
        fileName: String,
        mime: String,
        url: String,
        headers: Map<String, String>,
        onProgress: (Float) -> Unit
    ): String {
        val treeUri = Uri.parse(treeUriStr)
        val dir = DocumentFile.fromTreeUri(context, treeUri) ?: error(tr("无法访问下载目录"))
        val existing = dir.findFile(fileName)
        existing?.delete()
        val file = dir.createFile(mime, fileName) ?: error(tr("无法在自定义目录创建文件"))

        try {
            context.contentResolver.openOutputStream(file.uri)?.use { outputStream ->
                downloadToStream(url, headers, outputStream, onProgress)
            } ?: error(tr("无法写入"))
            return file.uri.toString()
        } catch (e: Exception) {
            file.delete()
            throw e
        }
    }

    // 流式下载到公共目录（Android 9 及以下）
    private fun downloadStreamPublicDir(
        fileName: String,
        url: String,
        headers: Map<String, String>,
        onProgress: (Float) -> Unit
    ): String {
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC),
            DEFAULT_SUB_DIR
        )
        if (!dir.exists()) dir.mkdirs()
        val file = File(dir, fileName)

        FileOutputStream(file).use { outputStream ->
            downloadToStream(url, headers, outputStream, onProgress)
        }
        return file.absolutePath
    }

    // 通用流式下载方法（边下载边写入，不占用大量内存）
    private fun downloadToStream(
        url: String,
        headers: Map<String, String>,
        outputStream: java.io.OutputStream,
        onProgress: (Float) -> Unit
    ) {
        val req = Request.Builder().url(url).apply {
            headers.forEach { (name, value) -> header(name, value) }
        }.build()
        ApiFactory.client().newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("HTTP ${resp.code}")
            val body = resp.body ?: error(tr("空响应"))
            val total = body.contentLength().takeIf { it > 0 }
            val inputStream = body.byteStream()

            var downloaded = 0L
            val buffer = ByteArray(8192)

            while (true) {
                val n = inputStream.read(buffer)
                if (n == -1) break
                outputStream.write(buffer, 0, n)
                downloaded += n
                if (total != null) {
                    onProgress((downloaded.toFloat() / total).coerceIn(0f, 1f))
                }
            }
        }
    }

    @Deprecated("使用流式下载方法替代，避免OOM")
    private fun fetchWithProgress(url: String, onProgress: (Float) -> Unit): ByteArray {
        val req = Request.Builder().url(url).build()
        ApiFactory.client().newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("HTTP ${resp.code}")
            val body = resp.body ?: error(tr("空响应"))
            val total = body.contentLength().takeIf { it > 0 }
            val buffer = body.source()
            val out = java.io.ByteArrayOutputStream()
            var read = 0L
            val chunk = ByteArray(8192)
            while (true) {
                val n = buffer.read(chunk)
                if (n == -1) break
                out.write(chunk, 0, n)
                read += n
                if (total != null) onProgress((read.toFloat() / total).coerceIn(0f, 1f))
            }
            return out.toByteArray()
        }
    }

    // MediaStore 写入（已废弃，使用流式下载方法）
    @Deprecated("使用 downloadStreamMediaStore 替代")
    private fun writeMediaStore(context: Context, fileName: String, mime: String, bytes: ByteArray): String {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_MUSIC}/$DEFAULT_SUB_DIR")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(collection, values) ?: error(tr("无法创建媒体文件"))
        resolver.openOutputStream(uri)?.use { it.write(bytes) } ?: error(tr("无法写入"))
        values.clear(); values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return uri.toString()
    }

    // SAF 写入（已废弃，使用流式下载方法）
    @Deprecated("使用 downloadStreamSafQ 替代")
    private fun writeSafQ(context: Context, treeUriStr: String, fileName: String, mime: String, bytes: ByteArray): String {
        val treeUri = Uri.parse(treeUriStr)
        val dir = DocumentFile.fromTreeUri(context, treeUri) ?: error(tr("无法访问下载目录"))
        val existing = dir.findFile(fileName)
        val file = existing ?: dir.createFile(mime, fileName) ?: error(tr("无法在自定义目录创建文件"))
        context.contentResolver.openOutputStream(file.uri)?.use { it.write(bytes) } ?: error(tr("无法写入"))
        return file.uri.toString()
    }

    private fun writeSafQText(context: Context, treeUriStr: String, fileName: String, text: String): String {
        val treeUri = Uri.parse(treeUriStr)
        val dir = DocumentFile.fromTreeUri(context, treeUri) ?: error(tr("无法访问下载目录"))
        val existing = dir.findFile(fileName)
        val file = existing ?: dir.createFile("text/plain", fileName) ?: error(tr("无法创建 lrc 文件"))
        context.contentResolver.openOutputStream(file.uri)?.use { it.write(text.toByteArray()) }
        return file.uri.toString()
    }

    // 旧版本：写公共 Music 目录
    private fun writePublicDir(fileName: String, bytes: ByteArray): String {
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC),
            DEFAULT_SUB_DIR
        )
        if (!dir.exists()) dir.mkdirs()
        val f = File(dir, fileName)
        FileOutputStream(f).use { it.write(bytes) }
        return f.absolutePath
    }

    private fun writePublicDirText(fileName: String, text: String): String {
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC),
            DEFAULT_SUB_DIR
        )
        if (!dir.exists()) dir.mkdirs()
        val f = File(dir, fileName)
        f.writeText(text)
        return f.absolutePath
    }

    private fun buildSafeName(song: Song): String = buildString {
        append(song.nm.ifBlank { "song_${song.id}" })
        if (song.ar.isNotBlank()) append(" - ").append(song.ar)
        append(" [").append(song.source).append("-").append(song.id).append("]")
    }.replace(Regex("[/\\\\:*?\"<>|]"), "_")

    private fun guessExtension(url: String): String {
        // Bilibili audio is served through a proxy path; the real media URL is
        // in the "u" query parameter and ends with .m4s (fragmented MP4 audio).
        val decoded = runCatching { Uri.parse(url).getQueryParameter("u") }.getOrNull()
        val path = (decoded ?: url).substringBefore('?').substringAfterLast('/')
        return when {
            path.endsWith(".flac", true) -> "flac"
            path.endsWith(".mp3", true)  -> "mp3"
            path.endsWith(".m4a", true) -> "m4a"
            path.endsWith(".m4s", true) -> "m4a"
            path.endsWith(".mp4", true) -> "mp4"
            path.endsWith(".ogg", true) -> "ogg"
            path.endsWith(".wav", true) -> "wav"
            else -> "mp3"
        }
    }
}
