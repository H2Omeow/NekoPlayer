package top.nekoh2o.player.data.repo

import android.content.Context
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import top.nekoh2o.player.data.model.Playlist
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.data.net.AndroidProviderPreferences
import top.nekoh2o.player.data.sync.SyncSection
import top.nekoh2o.player.data.sync.SyncStateStore
import top.nekoh2o.player.data.sync.songKey

/**
 * 对应 web 端 localStorage 的三份数据：播放历史、收藏、自定义歌单。
 * 用 SharedPreferences + JSON 持久化。内存持有可变副本，读写同步。
 * 每次用户修改都会更新对应分区的 localUpdatedAt 并发出 [changes]；来自云端的覆盖（replace*）不会。
 */
class LocalStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences("user_data", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }

    val syncState = SyncStateStore(
        AndroidProviderPreferences(context.applicationContext.getSharedPreferences("cloud_sync", Context.MODE_PRIVATE))
    )
    private val _changes = MutableSharedFlow<SyncSection>(extraBufferCapacity = 64, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    val changes: SharedFlow<SyncSection> = _changes

    val history = mutableListOf<Song>()
    val favorites = mutableListOf<Song>()
    val playlists = mutableListOf<Playlist>()
    // 云端存在但本端无法解析的条目，原样保留，上传时带回
    var foreignHistory: List<JsonElement> = emptyList(); private set
    var foreignFavorites: List<JsonElement> = emptyList(); private set
    var foreignPlaylists: List<JsonElement> = emptyList(); private set

    init {
        history.addAll(load(KEY_HISTORY))
        favorites.addAll(load(KEY_FAV))
        playlists.addAll(loadPlaylists())
        foreignHistory = loadForeign(KEY_FOREIGN_HISTORY)
        foreignFavorites = loadForeign(KEY_FOREIGN_FAV)
        foreignPlaylists = loadForeign(KEY_FOREIGN_PL)
    }

    private fun load(key: String): List<Song> =
        runCatching {
            prefs.getString(key, null)?.let { json.decodeFromString<List<Song>>(it) }
        }.getOrNull() ?: emptyList()

    private fun loadPlaylists(): List<Playlist> =
        runCatching {
            prefs.getString(KEY_PL, null)?.let { json.decodeFromString<List<Playlist>>(it) }
        }.getOrNull() ?: emptyList()

    private fun loadForeign(key: String): List<JsonElement> =
        runCatching {
            prefs.getString(key, null)?.let { json.decodeFromString(ListSerializer(JsonElement.serializer()), it) }
        }.getOrNull() ?: emptyList()

    /** 记录该分区被本地修改，并通知同步层。 */
    fun touch(section: SyncSection) {
        syncState.markLocalChanged(section, System.currentTimeMillis())
        _changes.tryEmit(section)
    }

    // ---------- 历史 ----------
    fun addHistory(song: Song) {
        val key = songKey(song)
        history.removeAll { songKey(it) == key }
        history.add(0, song)
        while (history.size > SyncSection.HISTORY_LIMIT) history.removeAt(history.size - 1)
        saveHistory()
    }
    fun saveHistory() { persistHistory(); touch(SyncSection.HISTORY) }
    private fun persistHistory() = prefs.edit().putString(KEY_HISTORY, json.encodeToString(history.toList())).apply()

    // ---------- 收藏 ----------
    fun isFav(song: Song): Boolean { val key = songKey(song); return favorites.any { songKey(it) == key } }
    fun toggleFav(song: Song): Boolean {
        val key = songKey(song)
        val idx = favorites.indexOfFirst { songKey(it) == key }
        val nowFav: Boolean
        if (idx >= 0) { favorites.removeAt(idx); nowFav = false }
        else { favorites.add(0, song); nowFav = true }
        saveFav()
        return nowFav
    }
    fun saveFav() { persistFav(); touch(SyncSection.FAVORITES) }
    private fun persistFav() = prefs.edit().putString(KEY_FAV, json.encodeToString(favorites.toList())).apply()

    // ---------- 自定义歌单 ----------
    fun createPlaylist(name: String): Playlist {
        val pl = Playlist(id = System.currentTimeMillis().toString(), name = name)
        playlists.add(pl)
        savePlaylists()
        return pl
    }
    fun deletePlaylist(index: Int) {
        if (index in playlists.indices) { playlists.removeAt(index); savePlaylists() }
    }
    fun addToPlaylist(index: Int, song: Song): Boolean {
        val pl = playlists.getOrNull(index) ?: return false
        val key = songKey(song)
        if (pl.songs.any { songKey(it) == key }) return false
        pl.songs.add(song); savePlaylists(); return true
    }
    fun removeFromPlaylist(plIndex: Int, songIndex: Int) {
        playlists.getOrNull(plIndex)?.songs?.let {
            if (songIndex in it.indices) { it.removeAt(songIndex); savePlaylists() }
        }
    }
    fun savePlaylists() { persistPlaylists(); touch(SyncSection.PLAYLISTS) }
    private fun persistPlaylists() = prefs.edit().putString(KEY_PL, json.encodeToString(playlists.toList())).apply()

    // ---------- 云端覆盖本地（不更新 localUpdatedAt）----------
    fun replaceHistory(songs: List<Song>, foreign: List<JsonElement>) {
        history.clear(); history.addAll(songs.take(SyncSection.HISTORY_LIMIT))
        foreignHistory = foreign.take((SyncSection.HISTORY_LIMIT - history.size).coerceAtLeast(0))
        persistHistory(); persistForeign(KEY_FOREIGN_HISTORY, foreignHistory)
    }
    fun replaceFavorites(songs: List<Song>, foreign: List<JsonElement>) {
        favorites.clear(); favorites.addAll(songs)
        foreignFavorites = foreign
        persistFav(); persistForeign(KEY_FOREIGN_FAV, foreign)
    }
    fun replacePlaylists(list: List<Playlist>, foreign: List<JsonElement>) {
        playlists.clear(); playlists.addAll(list)
        foreignPlaylists = foreign
        persistPlaylists(); persistForeign(KEY_FOREIGN_PL, foreign)
    }
    private fun persistForeign(key: String, items: List<JsonElement>) =
        prefs.edit().putString(key, json.encodeToString(ListSerializer(JsonElement.serializer()), items)).apply()

    companion object {
        private const val KEY_HISTORY = "my_history"
        private const val KEY_FAV = "my_favorites"
        private const val KEY_PL = "my_playlists"
        private const val KEY_FOREIGN_HISTORY = "foreign_history"
        private const val KEY_FOREIGN_FAV = "foreign_favorites"
        private const val KEY_FOREIGN_PL = "foreign_playlists"
    }
}
