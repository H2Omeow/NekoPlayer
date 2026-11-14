package top.nekoh2o.player.ui.viewmodel

import top.nekoh2o.player.i18n.NekoI18n.tr

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import top.nekoh2o.player.data.model.DownloadTask
import top.nekoh2o.player.data.model.DownloadedSong
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.data.repo.DownloadIndex
import top.nekoh2o.player.data.repo.Downloader
import top.nekoh2o.player.data.repo.MusicRepository
import top.nekoh2o.player.diagnostics.AppLog
import top.nekoh2o.player.ui.manager.LyricManager

/**
 * 下载管理 ViewModel
 * 负责：下载任务管理、已下载列表、下载目录设置
 */
class DownloadViewModel(app: Application) : AndroidViewModel(app) {

    private val repo = MusicRepository()

    /**
     * 下载任务实时进度流
     */
    val downloadTasks: StateFlow<List<DownloadTask>> = Downloader.tasks

    /**
     * 获取所有已下载歌曲
     */
    fun getDownloadedSongs(): List<DownloadedSong> {
        return DownloadIndex.all()
    }

    /**
     * 下载歌曲（音频 + 歌词）
     * @return 成功返回 true，失败返回 false 并附带错误信息
     */
    suspend fun downloadSong(
        song: Song,
        quality: String,
        downloadDirUri: String?,
        onSuccess: () -> Unit,
        onError: (String) -> Unit
    ) {
        if (DownloadIndex.isDownloaded(song)) {
            onError(tr("已下载过该歌曲"))
            return
        }

        val audio = try { top.nekoh2o.player.data.repo.SongQualityRepository().resolveDownload(song, quality) }
        catch (e: kotlinx.coroutines.CancellationException) { throw e }
        catch (e: Exception) { onError(e.message ?: tr("音质核验失败")); return }
        val url = audio?.url
        if (url == null) {
            onError(tr("当前账号无法下载所选音质，请刷新音质列表"))
            return
        }

        // 拉取歌词一并保存为 .lrc
        val lrcText = runCatching {
            val lines = repo.lyric(song)
            if (lines.isEmpty()) null else LyricManager.buildLrcText(lines)
        }.getOrNull()

        val dirUri = downloadDirUri?.ifBlank { null }

        val result = runCatching {
            Downloader.download(getApplication(), song, url, audio.quality.id, lrcText, dirUri, audio.headers)
        }.getOrElse {
            AppLog.warn("download", "下载失败 source=${song.source} id=${song.id}", it)
            onError(tr("下载失败：{reason}", "reason" to it.message))
            return
        }

        DownloadIndex.add(result)
        onSuccess()
    }

    /**
     * 删除已下载歌曲（文件 + 索引）
     */
    fun removeDownloaded(song: Song) {
        val downloaded = DownloadIndex.get(song) ?: return

        // 删除音频文件
        runCatching {
            val audioUri = Uri.parse(downloaded.audioUri)
            if (audioUri.scheme == "content") {
                getApplication<Application>().contentResolver.delete(audioUri, null, null)
            } else {
                java.io.File(downloaded.audioUri).delete()
            }
        }.onFailure { e ->
            android.util.Log.w("DownloadViewModel", "删除音频文件失败: ${e.message}")
        }

        // 删除歌词文件
        downloaded.lrcPath?.let { lrcPath ->
            runCatching {
                val lrcUri = Uri.parse(lrcPath)
                if (lrcUri.scheme == "content") {
                    getApplication<Application>().contentResolver.delete(lrcUri, null, null)
                } else {
                    java.io.File(lrcPath).delete()
                }
            }.onFailure { e ->
                android.util.Log.w("DownloadViewModel", "删除歌词文件失败: ${e.message}")
            }
        }

        DownloadIndex.remove(song)
    }
}
