package top.nekoh2o.player.data.repo

import top.nekoh2o.player.i18n.NekoI18n.tr

import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.data.net.AnimemusicApi
import top.nekoh2o.player.data.net.ApiFactory
import top.nekoh2o.player.lyric.LyricParser
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.JsonNull
import java.io.IOException

data class AnimemusicSearchPage(val songs: List<Song>, val hasMore: Boolean)

class AnimemusicRepository(private val api: AnimemusicApi = ApiFactory.animemusic) {
    suspend fun search(platform: String, keyword: String, page: Int = 1, limit: Int = 30): AnimemusicSearchPage {
        val response = api.search(platform, keyword, page, limit)
        if (response.code != 200) throw IOException(tr("内置插件搜索失败（{code}）", "code" to response.code))
        val songs = response.data.mapNotNull { item ->
            val id = item.id.ifBlank { item.songId }
            if (id.isBlank() || item.title.isBlank()) return@mapNotNull null
            Song(
                id = stableId(platform, id),
                nm = item.title,
                ar = item.artist.ifBlank { tr("未知艺术家") },
                pc = item.artwork?.toAbsoluteArtworkUrl(),
                source = "animemusic-$platform",
                hash = id,
                albumId = item.album,
                albumAudioId = item.album_audio_id.toLongOrNull() ?: 0,
                providerSource = platform,
                providerMediaId = id
            )
        }
        return AnimemusicSearchPage(songs, !response.isEnd && songs.isNotEmpty())
    }

    suspend fun resolveAudio(song: Song, quality: String): ResolvedAudio? {
        val platform = song.providerSource.takeIf { it.isNotBlank() } ?: platformFrom(song.source) ?: return null
        val id = song.providerMediaId.ifBlank { song.hash.ifBlank { song.id.toString() } }
        val requested = if (quality == "hires") "flac24bit" else quality
        val response = api.url(platform, id, requested)
        if (response.code in listOf(401, 403, 429)) throw IOException(tr("内置插件服务拒绝请求或请求过于频繁，请稍后重试"))
        if (response.code != 200 || response.is_free_part > 0 ||
            response.freeTrialInfo != null && response.freeTrialInfo != JsonNull) return null
        val url = response.url?.takeIf { value ->
            runCatching { java.net.URI(value).let { it.scheme in listOf("http", "https") && !it.host.isNullOrBlank() && it.userInfo == null } }.getOrDefault(false)
        } ?: return null
        val actual = when (val returned = response.quality.ifBlank { requested }) {
            "flac24bit" -> "hires"
            else -> returned
        }
        val format = qualities.firstOrNull { it.id == actual } ?: return null
        return ResolvedAudio(format.copy(size = response.size), url,
            top.nekoh2o.player.data.plugins.GatewayPlaybackHeaders.forPlatform(platform))
    }

    suspend fun lyric(song: Song): List<top.nekoh2o.player.data.model.LyricLine> {
        var platform = song.providerSource.takeIf { it.isNotBlank() } ?: platformFrom(song.source) ?: return emptyList()
        var id = song.providerMediaId.ifBlank { song.hash.ifBlank { song.id.toString() } }
        var title = song.nm
        if (platform == "bilibili") {
            var best: top.nekoh2o.player.data.net.AnimemusicSong? = null
            var bestScore = 0.0
            var bestPlatform = ""
            for (target in listOf("kw", "wy")) {
                val candidates = try { api.search(target, "${song.nm} ${song.ar}".trim(), 1, 10).data }
                    catch (failure: CancellationException) { throw failure }
                    catch (_: Exception) { emptyList() }
                for (candidate in candidates) {
                    val score = titleScore(song.nm, candidate.title)
                    if (candidate.id.isNotBlank() && score > bestScore) {
                        best = candidate; bestScore = score; bestPlatform = target
                    }
                }
                if (bestScore >= 0.95) break
            }
            val matched = best?.takeIf { bestScore >= 0.5 } ?: return emptyList()
            platform = bestPlatform; id = matched.id; title = matched.title
        }
        val word = try { api.lyricWord(platform, id, title) }
            catch (failure: CancellationException) { throw failure }
            catch (_: Exception) { null }
        val response = word?.takeIf { it.code == 200 && !it.lyric.isNullOrBlank() }
            ?: api.lyric(platform, id, title).takeIf { it.code == 200 } ?: return emptyList()
        val main = response.lyric?.takeIf { it.isNotBlank() } ?: return emptyList()
        return LyricParser.parse(main, response.tlyric)
    }

    companion object {
        const val version = "2.3.1"
        const val author = "惜缘惜梦"
        val qualities = listOf(
            AudioQuality("128k", tr("标准 128k"), 0), AudioQuality("192k", tr("较高 192k"), 1),
            AudioQuality("320k", tr("高品质 320k"), 2), AudioQuality("flac", tr("无损 FLAC"), 3),
            AudioQuality("hires", "Hi-Res", 4)
        )
        val platforms = listOf(
            "kg" to tr("酷狗"), "kw" to tr("酷我"), "wy" to tr("网易"), "tx" to "QQ", "mg" to tr("咪咕"), "bilibili" to tr("B站"), "qishui" to tr("汽水")
        )
        internal fun titleScore(title: String, candidate: String): Double {
            fun normalize(value: String) = value.lowercase().replace(Regex("""[\s\-_·、，,。.！!？?（）()\[\]【】"'’“”：:;；~—]+"""), "")
            val original = normalize(title); val other = normalize(candidate)
            if (original.isBlank() || other.isBlank()) return 0.0
            if (original == other) return 1.0
            if (original.contains(other) || other.contains(original)) return 0.85
            return original.count { it in other }.toDouble() / original.length * 0.7
        }
        fun label(platform: String): String = platforms.firstOrNull { it.first == platform }?.second ?: platform
        fun platformFrom(source: String): String? = source.removePrefix("animemusic-").takeIf { it != source }
        private fun stableId(platform: String, id: String): Long {
            val value = (platform + ":" + id).hashCode().toLong()
            return if (value == 0L) 1L else value
        }
        private fun String.toAbsoluteArtworkUrl(): String = if (startsWith("//")) "https:$this" else this
    }
}
