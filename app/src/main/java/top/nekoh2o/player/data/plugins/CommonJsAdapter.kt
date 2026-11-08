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

open class CommonJsAdapter(context: Context) : PluginAdapter {
    private val runtime = PluginRuntime(context)

    protected suspend fun invoke(source: PluginSource, method: String, vararg args: JsonElement): JsonElement {
        val result = runtime.run(source.plugin, method, JsonArray(args.toList()))
        if (result.storage != source.plugin.storage) PluginStore.saveStorage(source.plugin, result.storage)
        return result.value
    }

    override suspend fun search(source: PluginSource, keyword: String, page: Int): PluginSearchPage {
        val response = invoke(source, "search", JsonPrimitive(keyword), JsonPrimitive(page), JsonPrimitive("music")).jsonObject
        val songs = (response["data"] as? JsonArray).orEmpty().filterIsInstance<JsonObject>().mapNotNull { pluginSong(source, it) }
        return PluginSearchPage(songs, response["isEnd"] == JsonPrimitive(false) && songs.isNotEmpty())
    }

    override fun qualities(source: PluginSource, song: Song): List<AudioQuality> {
        val raw = song.rawPluginItem()
        val declared = source.plugin.descriptor.strings("qualities").ifEmpty {
            if (source.plugin.format == "musicfree") listOf("low", "standard", "high", "super")
            else listOf("128k", "320k", "flac")
        }
        val available = (raw["qualities"] as? JsonObject)?.keys
        val supported = declared.filter { available.isNullOrEmpty() || it in available }
        return supported.map { key ->
            when (key) {
                "low" -> AudioQuality(key, tr("标准 128k"), 0)
                "standard" -> AudioQuality(key, tr("高品质 320k"), 2)
                "high" -> AudioQuality(key, tr("无损 FLAC"), 3)
                "super" -> AudioQuality(key, "Hi-Res", 4)
                else -> pluginQuality(key)
            }
        }
    }

    override suspend fun resolve(source: PluginSource, song: Song, quality: AudioQuality): ResolvedAudio? {
        val value = invoke(source, "getMediaSource", song.rawPluginItem(), JsonPrimitive(quality.id))
        if (value == JsonNull) return null
        val response = value as? JsonObject ?: return null
        if (response.string("ekey", "cek").isNotBlank()) throw IOException(tr("该音源返回加密音频，Android 暂不支持解密"))
        val url = response.string("url").takeIf(::validPluginUrl) ?: return null
        val actual = response.string("quality").ifBlank { quality.id }
        val headers = (response["headers"] as? JsonObject).orEmpty().mapNotNull { (key, item) ->
            (item as? JsonPrimitive)?.contentOrNull?.let { key to it }
        }.toMap().toMutableMap()
        response.string("userAgent").takeIf { it.isNotBlank() }?.let { headers["User-Agent"] = it }
        require(headers.all { (name, value) ->
            name.matches(Regex("^[!#$%&'*+.^_`|~0-9A-Za-z-]+$")) && '\r' !in value && '\n' !in value
        }) { tr("音源返回无效的媒体请求头") }
        return ResolvedAudio(qualities(source, song).firstOrNull { it.id == actual } ?: return null, url, headers)
    }

    override suspend fun lyric(source: PluginSource, song: Song): List<LyricLine> {
        if (!source.plugin.descriptor.strings("capabilities").contains("getLyric")) return emptyList()
        val value = invoke(source, "getLyric", song.rawPluginItem())
        if (value == JsonNull) return emptyList()
        if (value is JsonPrimitive) return LyricParser.parse(value.content, null)
        val response = value.jsonObject
        val inline = response.string("rawLrc", "lyric")
        val remote = response.string("lrc")
        val original = inline.ifBlank { remote }
        val main = if (validPluginUrl(original)) PluginHttp.get(original) else original
        val translated = response.string("translation", "rawTranslation", "tlyric")
        val translation = if (validPluginUrl(translated)) PluginHttp.get(translated) else translated
        return LyricParser.parse(main, translation)
    }
}
