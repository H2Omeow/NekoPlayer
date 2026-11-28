package top.nekoh2o.player.ui.lyrics

import top.nekoh2o.player.ui.PlaybackProgress

import org.json.JSONArray
import org.json.JSONObject
import top.nekoh2o.player.ui.UiState
import java.security.MessageDigest

fun dynamicLyricsPayload(
    state: UiState,
    progress: PlaybackProgress? = null,
    nowMs: Long = System.currentTimeMillis()
): JSONObject {
    val posMs = progress?.positionMs ?: state.positionMs
    val durMs = progress?.durationMs ?: state.durationMs
    val song = state.current
    val track = song?.let {
        val key = "${it.source}:${it.id}:${it.hash}:${it.providerMediaId}"
        val seed = MessageDigest.getInstance("SHA-256").digest(key.toByteArray())
            .joinToString("") { byte -> "%02x".format(byte.toInt() and 255) }
        JSONObject().put("name", it.nm).put("artist", it.ar)
            .put("coverUrl", JSONObject.NULL).put("seed", seed)
    }
    val lines = JSONArray()
    state.lyrics.forEachIndexed { index, line ->
        val end = maxOf(
            line.time + 0.001,
            state.lyrics.getOrNull(index + 1)?.time
                ?: (durMs / 1000.0).takeIf { it > line.time }
                ?: (line.time + 5),
            line.words.orEmpty().maxOfOrNull { it.start + it.dur } ?: line.time
        )
        val words = JSONArray()
        line.words.orEmpty().forEach { word ->
            words.put(JSONObject().put("text", word.text).put("startTime", word.start)
                .put("endTime", word.start + word.dur))
        }
        lines.put(JSONObject().put("startTime", line.time).put("endTime", end)
            .put("fullText", line.text).put("translation", line.translation.orEmpty())
            .put("words", words))
    }
    return JSONObject()
        .put("track", track ?: JSONObject.NULL)
        .put("lyrics", if (song == null) JSONObject.NULL else JSONObject().put("lines", lines))
        .put("clock", JSONObject().put("positionSec", posMs / 1000.0)
            .put("durationSec", durMs / 1000.0).put("anchoredAtMs", nowMs)
            .put("playing", song != null && state.isPlaying)
            .put("playbackRate", state.settings.playbackSpeed.toDouble()))
        .put("appearance", JSONObject().put("showSubtitleTranslation", true)
            .put("hideTranslationSubtitle", false))
}
