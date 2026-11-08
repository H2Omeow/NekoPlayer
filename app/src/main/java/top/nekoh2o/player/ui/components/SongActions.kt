package top.nekoh2o.player.ui.components

import androidx.compose.runtime.staticCompositionLocalOf
import top.nekoh2o.player.data.model.Song

/** 歌曲列表的通用操作。界面只依赖这个接口，不直接依赖 ViewModel，便于预览和测试。 */
interface SongActions {
    fun play(song: Song)
    fun playAll(songs: List<Song>)
    fun queue(song: Song)
    fun toggleFav(song: Song)
    fun isFav(song: Song): Boolean
    fun addToPlaylist(song: Song)
}

/** 社区分享入口；未提供时不显示「分享」菜单项。 */
val LocalSongShareHandler = staticCompositionLocalOf<((Song) -> Unit)?> { null }
