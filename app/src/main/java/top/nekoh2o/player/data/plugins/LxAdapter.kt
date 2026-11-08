package top.nekoh2o.player.data.plugins

import top.nekoh2o.player.i18n.NekoI18n.tr

import android.content.Context
import kotlinx.serialization.json.*
import top.nekoh2o.player.data.model.LyricLine
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.data.repo.AudioQuality
import top.nekoh2o.player.data.repo.ResolvedAudio
import top.nekoh2o.player.lyric.LyricParser
import java.io.IOException

class LxAdapter(context: Context) : CommonJsAdapter(context) {
    override suspend fun search(source: PluginSource, keyword: String, page: Int): PluginSearchPage {
        val platform = if (source.platform == "qq") "tx" else source.platform
        val catalog = PluginStore.sources().firstOrNull { it.plugin.format == "animemusic/1" && it.platform == platform }
            ?: throw IOException(tr("LX 仅提供解析；请启用对应 Animemusic 来源以搜索歌曲"))
        val result = AnimemusicAdapter().search(catalog, keyword, page)
        return result.copy(songs = result.songs.map { song ->
            val raw = song.rawPluginItem()
            val metadata = buildJsonObject {
                raw.forEach { (key, value) -> put(key, value) }
                put("source", source.platform); put("name", song.nm); put("singer", song.ar)
                put("songId", raw["songId"] ?: JsonPrimitive(song.providerMediaId))
                put("hash", raw["hash"] ?: JsonPrimitive(song.hash))
                put("songmid", raw["songmid"] ?: JsonPrimitive(song.providerMediaId))
                put("albumId", raw["albumId"] ?: JsonPrimitive(song.albumId))
            }
            pluginSong(source, metadata)!!.copy(providerSource = source.platform)
        })
    }

    override fun qualities(source: PluginSource, song: Song): List<AudioQuality> {
        val descriptor = (source.plugin.descriptor["sources"] as? JsonObject)?.get(source.platform) as? JsonObject ?: return emptyList()
        return descriptor.strings("qualitys").map(::pluginQuality)
    }

    private suspend fun request(source: PluginSource, song: Song, action: String, type: String = ""): JsonElement {
        val descriptor = (source.plugin.descriptor["sources"] as? JsonObject)?.get(source.platform) as? JsonObject
        if (descriptor?.strings("actions")?.contains(action) != true) return JsonNull
        val info = buildJsonObject { put("musicInfo", song.rawPluginItem()); if (type.isNotBlank()) put("type", type) }
        return invoke(source, "lxRequest", JsonPrimitive(source.platform), JsonPrimitive(action), info)
    }

    override suspend fun resolve(source: PluginSource, song: Song, quality: AudioQuality): ResolvedAudio? {
        val result = request(source, song, "musicUrl", quality.id)
        val url = (result as? JsonPrimitive)?.contentOrNull ?: (result as? JsonObject)?.string("url").orEmpty()
        return if (validPluginUrl(url)) ResolvedAudio(quality, url) else null
    }

    override suspend fun lyric(source: PluginSource, song: Song): List<LyricLine> {
        val result = request(source, song, "lyric")
        if (result == JsonNull) return emptyList()
        if (result is JsonPrimitive) return LyricParser.parse(result.content, null)
        return LyricParser.parse(result.jsonObject.string("lyric", "lrc"), result.jsonObject.string("tlyric", "translation"))
    }
}
