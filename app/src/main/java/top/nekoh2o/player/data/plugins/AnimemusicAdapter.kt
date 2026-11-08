package top.nekoh2o.player.data.plugins

import top.nekoh2o.player.i18n.NekoI18n.tr

import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import top.nekoh2o.player.data.model.LyricLine
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.data.repo.AudioQuality
import top.nekoh2o.player.data.repo.ResolvedAudio
import top.nekoh2o.player.lyric.LyricParser
import java.io.IOException

class AnimemusicAdapter : PluginAdapter {
    suspend fun request(source: PluginSource, route: String, params: Map<String, String>): JsonObject {
        val base = source.plugin.descriptor.string("api")
        require(validPluginUrl(base)) { tr("音源 api 地址无效") }
        val parsed = base.toHttpUrl()
        val builder = parsed.newBuilder()
        if (!parsed.encodedPath.endsWith("index.php")) builder.encodedPath(parsed.encodedPath.trimEnd('/') + "/index.php")
        builder.setQueryParameter("route", route)
        params.forEach { (key, value) -> builder.setQueryParameter(key, value) }
        val root = Json.parseToJsonElement(PluginHttp.get(builder.build().toString())).jsonObject
        if (root.string("code") != "200" && root["ok"] != JsonPrimitive(true)) throw IOException(tr("音源接口请求失败（{code}）", "code" to (root.string("code").toIntOrNull() ?: 0)))
        return root
    }

    override suspend fun search(source: PluginSource, keyword: String, page: Int): PluginSearchPage {
        val result = request(source, "music/search", mapOf("platform" to source.platform, "keyword" to keyword, "page" to page.toString(), "limit" to "30"))
        val songs = ((result["data"] ?: result["list"]) as? JsonArray).orEmpty().filterIsInstance<JsonObject>().mapNotNull { pluginSong(source, it) }
        val more = (result["hasMore"] as? JsonPrimitive)?.booleanOrNull
            ?: (result["isEnd"] as? JsonPrimitive)?.booleanOrNull?.not() ?: (songs.size >= 30)
        return PluginSearchPage(songs, more && songs.isNotEmpty())
    }

    override fun qualities(source: PluginSource, song: Song): List<AudioQuality> = source.plugin.descriptor.strings("qualities").map(::pluginQuality)

    override suspend fun resolve(source: PluginSource, song: Song, quality: AudioQuality): ResolvedAudio? {
        val result = request(source, "music/url", mapOf("source" to song.providerSource.ifBlank { source.platform },
            "musicId" to song.providerMediaId.ifBlank { song.hash }, "quality" to qualityKey(quality.id)))
        if (result.string("is_free_part").toIntOrNull()?.let { it > 0 } == true || result["freeTrialInfo"]?.let { it != JsonNull } == true) return null
        val url = result.string("url").takeIf(::validPluginUrl) ?: return null
        val actual = qualityKey(result.string("quality").ifBlank { quality.id })
        val available = qualities(source, song).firstOrNull { qualityKey(it.id) == actual } ?: return null
        return ResolvedAudio(available.copy(size = result.string("size").toLongOrNull() ?: 0), url)
    }

    override suspend fun lyric(source: PluginSource, song: Song): List<LyricLine> {
        val bridge = source.plugin.descriptor.strings("lyricBridge")
        if (source.plugin.descriptor["lyricNative"] == JsonPrimitive(false) && bridge.isNotEmpty()) {
            for (platform in bridge) {
                val target = source.copy(platform = platform)
                val match = try { search(target, "${song.nm} ${song.ar}", 1).songs.maxByOrNull { titleScore(song.nm, it.nm) } }
                    catch (failure: CancellationException) { throw failure }
                    catch (_: Exception) { null }
                if (match != null && titleScore(song.nm, match.nm) >= 0.5) {
                    val lines = lyricDirect(target, match)
                    if (lines.isNotEmpty()) return lines
                }
            }
            return emptyList()
        }
        return lyricDirect(source, song)
    }

    private suspend fun lyricDirect(source: PluginSource, song: Song): List<LyricLine> {
        val args = mapOf("platform" to source.platform, "musicId" to song.providerMediaId.ifBlank { song.hash }, "name" to song.nm, "interval" to "200")
        val word = try { request(source, "music/lyric/word", args) }
            catch (failure: CancellationException) { throw failure }
            catch (_: Exception) { null }
        val result = word?.takeIf { it.string("lyric", "lrc").isNotBlank() } ?: request(source, "music/lyric", args)
        return LyricParser.parse(result.string("lyric", "lrc"), result.string("tlyric", "translation"))
    }

    private fun titleScore(title: String, candidate: String): Double {
        fun normalized(value: String) = value.lowercase().filter { it.isLetterOrDigit() }
        val original = normalized(title)
        val other = normalized(candidate)
        if (original.isEmpty() || other.isEmpty()) return 0.0
        if (original == other) return 1.0
        if (original.contains(other) || other.contains(original)) return 0.85
        return original.count { it in other }.toDouble() / original.length * 0.7
    }
}
