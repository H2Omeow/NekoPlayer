package top.nekoh2o.player.ui.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import top.nekoh2o.player.PlayerApp
import top.nekoh2o.player.data.model.Playlist
import top.nekoh2o.player.data.model.Song

/**
 * 收藏与歌单管理 ViewModel
 * 负责：收藏管理、歌单管理（创建、删除、添加、移除）
 */
class LibraryViewModel(app: Application) : AndroidViewModel(app) {

    private val local = (app as PlayerApp).localStore

    /**
     * 切换收藏状态
     * @return 当前是否已收藏
     */
    fun toggleFavorite(song: Song): Boolean {
        return local.toggleFav(song)
    }

    /**
     * 检查是否已收藏
     */
    fun isFavorite(song: Song): Boolean {
        return local.isFav(song)
    }

    /**
     * 获取收藏列表
     */
    fun getFavorites(): List<Song> {
        return local.favorites.toList()
    }

    /**
     * 获取播放历史
     */
    fun getHistory(): List<Song> {
        return local.history.toList()
    }

    /**
     * 获取所有歌单
     */
    fun getPlaylists(): List<Playlist> {
        return local.playlists.toList()
    }

    /**
     * 创建新歌单
     */
    fun createPlaylist(name: String) {
        local.createPlaylist(name)
    }

    /**
     * 删除歌单
     */
    fun deletePlaylist(index: Int) {
        local.deletePlaylist(index)
    }

    /**
     * 添加歌曲到歌单
     * @return 是否成功（false 表示歌曲已在歌单中）
     */
    fun addToPlaylist(playlistIndex: Int, song: Song): Boolean {
        return local.addToPlaylist(playlistIndex, song)
    }

    /**
     * 从歌单移除歌曲
     */
    fun removeFromPlaylist(playlistIndex: Int, songIndex: Int) {
        local.removeFromPlaylist(playlistIndex, songIndex)
    }

    /**
     * 批量导入网易云红心歌曲到收藏
     */
    fun importNeteaseHeartToLocal(songs: List<Song>) {
        songs.forEach { song ->
            if (!local.isFav(song)) {
                local.toggleFav(song)
            }
        }
    }

    /**
     * 批量导入网易云播放记录到历史
     */
    fun importNeteaseRecordToLocal(songs: List<Song>) {
        songs.forEach { local.addHistory(it) }
    }
}
