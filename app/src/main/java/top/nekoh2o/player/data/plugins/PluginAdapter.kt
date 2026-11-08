package top.nekoh2o.player.data.plugins

import top.nekoh2o.player.i18n.NekoI18n.tr

import kotlinx.serialization.json.*
import top.nekoh2o.player.data.model.LyricLine
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.data.repo.AudioQuality
import top.nekoh2o.player.data.repo.ResolvedAudio
import java.nio.ByteBuffer
import java.security.MessageDigest

data class PluginSearchPage(val songs: List<Song>, val hasMore: Boolean)

interface PluginAdapter {
    suspend fun search(source: PluginSource, keyword: String, page: Int): PluginSearchPage
    fun qualities(source: PluginSource, song: Song): List<AudioQuality>
    suspend fun resolve(source: PluginSource, song: Song, quality: AudioQuality): ResolvedAudio?
    suspend fun lyric(source: PluginSource, song: Song): List<LyricLine>
}

internal fun pluginSong(source: PluginSource, item: JsonObject): Song? {
    val mediaId = item.string("id", "songId", "songmid", "hash")
    val title = item.string("title", "name", "songname")
    if (mediaId.isBlank() || title.isBlank()) return null
    val primaryKeys = source.plugin.descriptor.strings("primaryKey")
    val identity = primaryKeys.map { item[it]?.toString().orEmpty() }.takeIf { it.any(String::isNotBlank) }?.joinToString(":") ?: mediaId
    val digest = MessageDigest.getInstance("SHA-256").digest("${source.id}:$identity".toByteArray())
    val artist = item.string("artist", "singer", "author").ifBlank {
        (item["artists"] as? JsonArray)?.mapNotNull { (it as? JsonObject)?.string("name") }?.joinToString(" / ").orEmpty()
    }
    return Song(ByteBuffer.wrap(digest).long, title, artist.ifBlank { tr("未知艺术家") },
        pc = item.string("artwork", "pic", "picUrl", "cover").takeIf { it.isNotBlank() }?.let { if (it.startsWith("//")) "https:$it" else it },
        source = source.id, hash = item.string("hash").ifBlank { mediaId }, albumId = item.string("albumId", "album_id", "album"),
        albumAudioId = item.string("album_audio_id", "albumAudioId").toLongOrNull() ?: 0,
        providerSource = item.string("platform", "_src").ifBlank { source.platform }, providerMediaId = mediaId,
        pluginMetadata = item.toString())
}

internal fun Song.rawPluginItem(): JsonObject = runCatching { Json.parseToJsonElement(pluginMetadata).jsonObject }
    .getOrElse { buildJsonObject { put("id", providerMediaId.ifBlank { hash }); put("title", nm); put("artist", ar) } }

internal fun qualityKey(value: String): String = when (value) {
    "standard", "low", "128", "128k" -> "128k"
    "higher", "192", "192k" -> "192k"
    "exhigh", "standard-high", "320", "320k" -> "320k"
    "lossless", "flac" -> "flac"
    "hires", "high", "flac24bit" -> "flac24bit"
    else -> value
}

internal fun pluginQuality(id: String): AudioQuality {
    val normalized = qualityKey(id)
    val rank = listOf("128k", "192k", "320k", "flac", "flac24bit").indexOf(normalized).coerceAtLeast(0)
    val label = mapOf("128k" to tr("标准 128k"), "192k" to tr("较高 192k"), "320k" to tr("高品质 320k"), "flac" to tr("无损 FLAC"), "flac24bit" to "Hi-Res")[normalized] ?: id
    return AudioQuality(id, label, rank)
}
