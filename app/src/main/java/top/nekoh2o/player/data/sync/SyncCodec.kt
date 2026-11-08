package top.nekoh2o.player.data.sync

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import top.nekoh2o.player.data.model.Playlist
import top.nekoh2o.player.data.model.SectionMeta
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.data.model.SyncMeta
import top.nekoh2o.player.data.model.UserData

/** 无法在本端解码的云端条目，原样保存以便上传时带回。 */
data class DecodedSongs(val songs: List<Song>, val foreign: List<JsonElement>)
data class DecodedPlaylists(val playlists: List<Playlist>, val foreign: List<JsonElement>)

object SyncCodec {

    /** 显式写出默认值（如 source），但省略 null 字段（pluginSource / pluginData / pc）。 */
    val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
        encodeDefaults = true
        explicitNulls = false
    }

    fun encodeSong(song: Song): JsonElement = json.encodeToJsonElement(Song.serializer(), song)

    fun encodeSongs(songs: List<Song>, foreign: List<JsonElement> = emptyList()): JsonArray =
        JsonArray(songs.map(::encodeSong) + foreign)

    fun decodeSongs(array: JsonElement?): DecodedSongs {
        val songs = ArrayList<Song>()
        val foreign = ArrayList<JsonElement>()
        (array as? JsonArray).orEmpty().forEach { element ->
            val song = decodeSong(element)
            if (song != null) songs.add(song) else foreign.add(element)
        }
        return DecodedSongs(songs, foreign)
    }

    private fun decodeSong(element: JsonElement): Song? {
        val obj = element as? JsonObject ?: return null
        // id 必须是整数，nm/ar 必须是字符串，否则视为本端无法表示的歌曲
        if ((obj["id"] as? JsonPrimitive)?.contentOrNull?.toLongOrNull() == null) return null
        if ((obj["nm"] as? JsonPrimitive)?.isString != true) return null
        if ((obj["ar"] as? JsonPrimitive)?.isString != true) return null
        return runCatching { json.decodeFromJsonElement(Song.serializer(), element) }.getOrNull()
    }

    fun encodePlaylists(playlists: List<Playlist>, foreign: List<JsonElement> = emptyList()): JsonArray =
        JsonArray(playlists.map { pl ->
            JsonObject(mapOf(
                "id" to JsonPrimitive(pl.id),
                "name" to JsonPrimitive(pl.name),
                "songs" to encodeSongs(pl.songs, pl.foreignSongs)
            ))
        } + foreign)

    fun decodePlaylists(array: JsonElement?): DecodedPlaylists {
        val playlists = ArrayList<Playlist>()
        val foreign = ArrayList<JsonElement>()
        (array as? JsonArray).orEmpty().forEach { element ->
            val obj = element as? JsonObject
            val id = (obj?.get("id") as? JsonPrimitive)?.contentOrNull
            val name = (obj?.get("name") as? JsonPrimitive)?.contentOrNull
            val songsEl = obj?.get("songs")
            if (id == null || name == null || (songsEl != null && songsEl !is JsonArray)) {
                foreign.add(element)
                return@forEach
            }
            val decoded = decodeSongs(songsEl)
            playlists.add(Playlist(id, name, decoded.songs.toMutableList(), decoded.foreign))
        }
        return DecodedPlaylists(playlists, foreign)
    }

    fun encodeCredentials(c: Credentials): JsonObject = JsonObject(mapOf(
        "ncCookie" to JsonPrimitive(c.ncCookie),
        "kgCookies" to JsonArray(List(2) { JsonPrimitive(c.kgCookies.getOrElse(it) { "" }) }),
        "kgPlatform" to JsonPrimitive(c.kgPlatform.coerceIn(0, 1)),
        "kgToken" to JsonPrimitive(c.kgToken)
    ))

    fun decodeCredentials(element: JsonElement?): Credentials {
        val obj = element as? JsonObject ?: return Credentials()
        fun str(key: String) = (obj[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull.orEmpty()
        val cookies = (obj["kgCookies"] as? JsonArray).orEmpty()
            .map { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content.orEmpty() }
        return Credentials(
            ncCookie = str("ncCookie"),
            kgCookies = List(2) { cookies.getOrElse(it) { "" } },
            kgPlatform = ((obj["kgPlatform"] as? JsonPrimitive)?.intOrNull ?: 0).coerceIn(0, 1),
            kgToken = str("kgToken")
        )
    }

    /** 缺失的分区不出现在结果中（读取时按 updatedAt = 0 处理）。 */
    fun parseMeta(meta: SyncMeta?): Map<SyncSection, SectionMeta> = buildMap {
        SyncSection.entries.forEach { section -> meta?.sections?.get(section.key)?.let { put(section, it) } }
    }

    fun snapshot(data: UserData, meta: SyncMeta?): CloudSnapshot {
        val credentials = Credentials(
            ncCookie = data.ncCookie,
            kgCookies = List(2) { data.kgCookies.getOrElse(it) { "" } },
            kgPlatform = data.kgPlatform.coerceIn(0, 1),
            kgToken = data.kgToken
        )
        return CloudSnapshot(
            parseMeta(meta),
            mapOf(
                SyncSection.FAVORITES to data.favorites,
                SyncSection.HISTORY to data.history,
                SyncSection.PLAYLISTS to data.playlists,
                SyncSection.CREDENTIALS to encodeCredentials(credentials)
            )
        )
    }

    /** 分区内容的条目数（歌曲/歌单数，凭据为非空项数）。 */
    fun count(section: SyncSection, payload: JsonElement?): Int = when (section) {
        SyncSection.CREDENTIALS -> decodeCredentials(payload).count
        else -> (payload as? JsonArray)?.size ?: 0
    }
}
