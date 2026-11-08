package top.nekoh2o.player.data.plugins

import top.nekoh2o.player.i18n.NekoI18n.tr

import kotlinx.coroutines.withTimeout
import top.nekoh2o.player.PlayerApp
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.data.repo.AudioQuality
import java.io.IOException

class PluginMusicRepository {
    private suspend fun source(id: String): PluginSource {
        PluginStore.awaitReady()
        return PluginStore.source(id) ?: throw IOException(tr("音源已关闭或删除，请在音源管理中检查"))
    }

    private fun adapter(source: PluginSource): PluginAdapter = when (source.plugin.format) {
        "animemusic/1" -> AnimemusicAdapter()
        "lx" -> LxAdapter(PlayerApp.instance)
        else -> CommonJsAdapter(PlayerApp.instance)
    }

    suspend fun search(id: String, keyword: String, page: Int): PluginSearchPage = withTimeout(20_000) {
        val source = source(id)
        adapter(source).search(source, keyword, page)
    }

    suspend fun qualities(song: Song): List<AudioQuality> {
        val source = source(song.source)
        return adapter(source).qualities(source, song)
    }

    suspend fun resolve(song: Song, quality: AudioQuality) = withTimeout(20_000) {
        val source = source(song.source)
        adapter(source).resolve(source, song, quality)
    }

    suspend fun lyric(song: Song) = withTimeout(20_000) {
        val source = source(song.source)
        adapter(source).lyric(source, song)
    }

    suspend fun preferred(song: Song, preference: String): String {
        val source = source(song.source)
        if (source.plugin.format == "musicfree") return when (preference) {
            "standard", "higher" -> "low"
            "exhigh" -> "standard"
            "lossless" -> "high"
            "hires" -> "super"
            else -> preference
        }
        val choices = adapter(source).qualities(source, song)
        return choices.firstOrNull { qualityKey(it.id) == qualityKey(preference) }?.id ?: preference
    }
}
