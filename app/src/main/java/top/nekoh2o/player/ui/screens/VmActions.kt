package top.nekoh2o.player.ui.screens

import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.ui.PlayerViewModel
import top.nekoh2o.player.ui.components.SongActions

/** 把 ViewModel 适配为界面使用的 [SongActions]；「加入歌单」交给调用方弹出选择框。 */
fun PlayerViewModel.songActions(onAddToPlaylist: (Song) -> Unit): SongActions = object : SongActions {
    override fun play(song: Song) = playNow(song)
    override fun playAll(songs: List<Song>) = this@songActions.playAll(songs)
    override fun queue(song: Song) = addToQueue(song)
    override fun toggleFav(song: Song) = this@songActions.toggleFav(song)
    override fun isFav(song: Song): Boolean = this@songActions.isFav(song)
    override fun addToPlaylist(song: Song) = onAddToPlaylist(song)
}
