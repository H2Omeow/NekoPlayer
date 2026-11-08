package top.nekoh2o.player.data.repo

import top.nekoh2o.player.data.net.ApiFactory
import top.nekoh2o.player.i18n.NekoI18n.tr

data class MusicVideo(val id: String, val title: String, val artist: String,
    val artwork: String? = null, val source: String = "netease")

class MvRepository {
    suspend fun search(source: String, keyword: String, page: Int = 1): List<MusicVideo> {
        val response = ApiFactory.animemusic.mvSearch(platformFor(source), keyword, page)
        check(response.code == 200) { tr("内置插件 MV 搜索失败") }
        return response.data.map { MusicVideo(it.id, it.title, it.artist, it.artwork, source) }
    }

    suspend fun url(video: MusicVideo): String? {
        val platform = platformFor(video.source)
        val quality = when (platform) { "wy", "tx" -> "1080"; "kw" -> "MP4BD"; "bilibili" -> "80"; "qishui" -> "1080p"; else -> "" }
        return ApiFactory.animemusic.mvUrl(platform, video.id, quality).takeIf { it.code == 200 }?.url?.takeIf(::httpUrl)
    }

    private fun platformFor(source: String) = when (source) { "netease" -> "wy"; "kugou" -> "kg"; else -> source.removePrefix("animemusic-") }
    private fun httpUrl(value: String) = runCatching { java.net.URI(value).let { it.scheme in listOf("http", "https") && !it.host.isNullOrBlank() && it.userInfo == null } }.getOrDefault(false)
}
