package top.nekoh2o.player.data.sync

import kotlinx.serialization.json.JsonElement
import top.nekoh2o.player.data.model.Playlist
import top.nekoh2o.player.data.model.Song

/** 歌曲唯一键：source + ":" + (providerMediaId || hash || id)，酷狗 hash 不区分大小写。 */
fun songKey(song: Song): String {
    val hash = if (song.source == "kugou") song.hash.lowercase() else song.hash
    return song.source + ":" + song.providerMediaId.ifBlank { hash.ifBlank { song.id.toString() } }
}

/** 同步用的凭据快照；kgCookies 固定两项（0=原版，1=概念版）。 */
data class Credentials(
    val ncCookie: String = "",
    val kgCookies: List<String> = listOf("", ""),
    val kgPlatform: Int = 0,
    val kgToken: String = ""
) {
    val count: Int get() = (if (ncCookie.isNotBlank()) 1 else 0) + kgCookies.count { it.isNotBlank() }
}

/** 合并 = 双向并集（仅用于首次同步 / 冲突时用户主动选择）；本地条目在前。 */
object SyncMerge {

    fun songs(local: List<Song>, remote: List<Song>): List<Song> {
        val seen = HashSet<String>()
        val out = ArrayList<Song>(local.size + remote.size)
        (local + remote).forEach { if (seen.add(songKey(it))) out.add(it) }
        return out
    }

    fun foreign(local: List<JsonElement>, remote: List<JsonElement>): List<JsonElement> =
        (local + remote).distinct()

    fun history(local: List<Song>, remote: List<Song>): List<Song> =
        songs(local, remote).take(SyncSection.HISTORY_LIMIT)

    fun playlists(local: List<Playlist>, remote: List<Playlist>): List<Playlist> {
        val map = LinkedHashMap<String, Playlist>()
        local.forEach { map[it.id] = it }
        remote.forEach { rp ->
            val existing = map[rp.id]
            map[rp.id] = if (existing == null) rp else existing.copy(
                songs = songs(existing.songs, rp.songs).toMutableList(),
                foreignSongs = foreign(existing.foreignSongs, rp.foreignSongs)
            )
        }
        return map.values.toList()
    }

    /** 每个字段本地非空优先，云端补空缺。 */
    fun credentials(local: Credentials, remote: Credentials): Credentials = Credentials(
        ncCookie = local.ncCookie.ifBlank { remote.ncCookie },
        kgCookies = List(2) { local.kgCookies.getOrElse(it) { "" }.ifBlank { remote.kgCookies.getOrElse(it) { "" } } },
        kgPlatform = if (local.count > 0) local.kgPlatform else remote.kgPlatform,
        kgToken = local.kgToken.ifBlank { remote.kgToken }
    )
}
