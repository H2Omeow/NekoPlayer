package top.nekoh2o.player.data.repo

import top.nekoh2o.player.i18n.NekoI18n.tr

import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.serialization.json.*
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.data.net.*
import java.io.IOException

data class AudioQuality(val id: String, val label: String, val rank: Int, val size: Long = 0, val hash: String = "")
data class ResolvedAudio(val quality: AudioQuality, val url: String, val headers: Map<String, String> = emptyMap())

/** Discovers the track's formats, then checks the current account's actual URL entitlement. */
class SongQualityRepository internal constructor(
    private val discovery: (suspend (Song, Boolean) -> List<AudioQuality>)?,
    private val urlResolver: (suspend (Song, AudioQuality, Boolean) -> ResolvedAudio?)?
) {
    constructor() : this(null, null)
    private val native get() = ApiFactory.nativeMusic
    private suspend fun candidates(song: Song, download: Boolean): List<AudioQuality> {
        discovery?.let { return it(song, download) }
        if (top.nekoh2o.player.data.plugins.PluginStore.isPluginSource(song.source)) {
            return top.nekoh2o.player.data.plugins.PluginMusicRepository().qualities(song)
        }
        CookieStore.awaitReady();ApiFactory.awaitReady()
        if(song.source=="kugou") {
            require(song.hash.matches(Regex("[a-fA-F0-9]{32}"))) { tr("歌曲缺少酷狗 hash，请重新搜索该歌曲") }
            KugouRepository().ensureInitialized()
            val body=ApiFactory.kugou.get("privilege/lite",CookieStore.kgPlatformValue(),mapOf(
                "hash" to song.hash,"album_id" to song.albumId.ifBlank { "0" },"behavior" to if(download) "download" else "play")).kugouBody()
            return kugouCandidates(body)
        }
        val body=native.get("song/music/detail",mapOf("id" to song.id.toString()))
        if(body.text("code")!="200") throw IOException(body.text("message","msg").ifBlank { tr("音质信息获取失败") })
        return neteaseCandidates(body)
    }

    suspend fun resolvePlayback(song: Song, preferred: String): ResolvedAudio? {
        val choices=candidates(song,false)
        val mapped=if (discovery == null && top.nekoh2o.player.data.plugins.PluginStore.isPluginSource(song.source))
            top.nekoh2o.player.data.plugins.PluginMusicRepository().preferred(song, preferred) else preferredFor(song.source,preferred)
        val ordered=choices.sortedWith(compareByDescending<AudioQuality> { it.id==mapped }.thenByDescending { it.rank })
        // If a requested quality silently falls back, retain the fallback only after testing higher supported formats.
        var fallback: ResolvedAudio?=null
        for(choice in ordered) {
            val audio=probeOrNull(song,choice,false)?:continue
            if(audio.quality.id==choice.id) return audio
            if(fallback==null || audio.quality.rank>fallback.quality.rank) fallback=audio
        }
        return fallback
    }

    suspend fun downloadable(song: Song): List<AudioQuality> = coroutineScope {
        val candidates=candidates(song,true)
        val slots=Semaphore(3)
        candidates.map { quality -> async { slots.withPermit { probeOrNull(song,quality,true)?.quality } } }
            .awaitAll().filterNotNull().distinctBy { it.id }.sortedByDescending { it.rank }
    }

    suspend fun resolveDownload(song: Song, id: String): ResolvedAudio? {
        val choices=candidates(song,true)
        val choice=choices.firstOrNull { it.id==id } ?: choices.firstOrNull { it.id==preferredFor(song.source,id) } ?:return null
        return probeOrNull(song,choice,true)?.takeIf { it.quality.id==choice.id }
    }

    private suspend fun probeOrNull(song: Song, choice: AudioQuality, download: Boolean): ResolvedAudio? = try {
        probe(song,choice,download)
    } catch(e: CancellationException) { throw e } catch(e: KugouApiException) {
        if(e.errorCode in setOf(20018,20028)) throw e
        null
    }
      catch(e: retrofit2.HttpException) {
          if (song.source.startsWith("animemusic-") && e.code() in listOf(401,403,429)) throw e
          if(e.code() in listOf(401,403,404)) null else throw e
      }

    private suspend fun probe(song: Song, choice: AudioQuality, download: Boolean): ResolvedAudio? {
        urlResolver?.let { return it(song, choice, download) }
        if (top.nekoh2o.player.data.plugins.PluginStore.isPluginSource(song.source)) {
            return top.nekoh2o.player.data.plugins.PluginMusicRepository().resolve(song, choice)
        }
        if(song.source=="kugou") {
            val body=ApiFactory.kugou.get("song/url",CookieStore.kgPlatformValue(),mapOf(
                "hash" to choice.hash.ifBlank { song.hash },"album_id" to song.albumId.ifBlank { "0" },
                "album_audio_id" to song.albumAudioId.toString(),"quality" to choice.id,
                "behavior" to if(download) "download" else "play")).kugouBody().payload()
            if(body.number("is_free_part","isFreePart","is_freepart")>0 || body.number("is_free_part_url")>0) return null
            val url=KugouRepository.playableUrl(body)?:return null
            val actual=body.text("quality").takeIf { it in kgLabels }?:choice.id
            val format=kgLabels[actual]?:return null
            return ResolvedAudio(AudioQuality(actual,format.first,format.second,body.number("fileSize","filesize","size"),body.text("hash").ifBlank { choice.hash }),url)
        }
        val body=native.get(if(download) "song/download/url/v1" else "song/url/v1",mapOf("id" to song.id.toString(),"level" to choice.id))
        if(body.text("code")!="200") return null
        val data=(body["data"] as? JsonArray)?.filterIsInstance<JsonObject>()?.firstOrNull() ?: (body["data"] as? JsonObject) ?: return null
        return neteaseAudio(data,choice)
    }

    companion object {
        internal val ncLevels=listOf("standard","higher","exhigh","lossless","hires","jyeffect","sky","jymaster","dolby")
        private val ncFields=listOf("l","m","h","sq","hr","je","sk","jm","db")
        private val ncLabels=listOf(tr("标准 128k"),tr("较高 192k"),tr("极高 320k"),tr("无损 SQ"),"Hi-Res",tr("高清臻音"),tr("沉浸环绕声"),tr("超清母带"),tr("臻音全景声"))
        internal val kgLabels=linkedMapOf("128" to (tr("标准 128k") to 0),"320" to (tr("高品质 320k") to 2),"flac" to (tr("无损 FLAC") to 3),
            "high" to ("Hi-Res" to 4),"viper_atmos" to (tr("全景声") to 5),"viper_tape" to (tr("蝰蛇磁带") to 5),
            "viper_clear" to (tr("蝰蛇超清") to 6),"super" to (tr("超清母带") to 7))
        internal fun preferredFor(source: String, preferred: String): String = if (source.startsWith("animemusic-")) mapOf(
            "standard" to "128k", "higher" to "192k", "exhigh" to "320k", "lossless" to "flac", "hires" to "hires"
        )[preferred] ?: preferred else if(source!="kugou") preferred else mapOf(
            "standard" to "128","higher" to "320","exhigh" to "320","lossless" to "flac","hires" to "high",
            "jyeffect" to "viper_clear","sky" to "viper_atmos","jymaster" to "super","dolby" to "viper_atmos")[preferred]?:preferred
        internal fun neteaseCandidates(body: JsonObject): List<AudioQuality> {
            val data=body.obj("data")
            return ncFields.mapIndexedNotNull { index,field ->
                val info=data[field] as? JsonObject ?:return@mapIndexedNotNull null
                if(info.number("size")<=0) null else AudioQuality(ncLevels[index],ncLabels[index],index,info.number("size"))
            }
        }
        internal fun kugouCandidates(body: JsonObject): List<AudioQuality> {
            val track=body.items("data").firstOrNull()?:return emptyList()
            return (listOf(track)+track.items("relate_goods")).mapNotNull { item ->
                val id=item.text("quality");val meta=kgLabels[id]?:return@mapNotNull null
                if(item.number("is_publish","publish")!=1L || item.obj("info").number("filesize")<=0) return@mapNotNull null
                AudioQuality(id,meta.first,meta.second,item.obj("info").number("filesize"),item.text("hash"))
            }.distinctBy { it.id }
        }
        internal fun neteaseAudio(data: JsonObject, choice: AudioQuality): ResolvedAudio? {
            if(data.text("code").let { it.isNotEmpty() && it!="200" }) return null
            if(data["freeTrialInfo"]!=null && data["freeTrialInfo"]!=JsonNull) return null
            val url=data.text("url").takeIf { it.startsWith("https://") || it.startsWith("http://") }?:return null
            val level=data.text("level").ifBlank {
                when(data.number("br")) { in 1..128000 -> "standard"; in 128001..192000 -> "higher";in 192001..320000 -> "exhigh";else -> choice.id }
            }
            val index=ncLevels.indexOf(level);if(index<0) return null
            return ResolvedAudio(AudioQuality(level,ncLabels[index],index,data.number("size")),url)
        }
    }
}
