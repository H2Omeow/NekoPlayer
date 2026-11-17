package top.nekoh2o.player.data.store

import android.content.Context
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken

data class WatchEntry(
    val bvid: String,
    val aid: Long = 0,
    val cid: Long = 0,
    val title: String = "",
    val cover: String = "",
    val upName: String = "",
    val durationSec: Int = 0,
    val positionMs: Long = 0,
    val updatedAt: Long = 0
) {
    val progress: Float
        get() = if (durationSec <= 0) 0f else (positionMs / 1000f / durationSec).coerceIn(0f, 1f)
}

/** 继续观看 / 观看历史。本地保存，退出 App 不丢。 */
class VideoHistoryStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences("video_history", Context.MODE_PRIVATE)
    private val gson = Gson()

    fun list(): List<WatchEntry> {
        val raw = prefs.getString(KEY, null) ?: return emptyList()
        val type = object : TypeToken<List<WatchEntry>>() {}.type
        return runCatching { gson.fromJson<List<WatchEntry>>(raw, type) }.getOrNull().orEmpty()
            .sortedByDescending { it.updatedAt }
    }

    fun resumeCandidates(limit: Int = 10): List<WatchEntry> =
        list().filter { it.progress > 0.02f && it.progress < 0.95f }.take(limit)

    fun position(bvid: String): Long = list().firstOrNull { it.bvid == bvid }?.positionMs ?: 0L

    fun upsert(entry: WatchEntry) {
        val updated = list().filter { it.bvid != entry.bvid } + entry.copy(updatedAt = System.currentTimeMillis())
        prefs.edit().putString(KEY, gson.toJson(updated.take(MAX))).apply()
    }

    fun remove(bvid: String) {
        val updated = list().filter { it.bvid != bvid }
        prefs.edit().putString(KEY, gson.toJson(updated)).apply()
    }

    fun clear() {
        prefs.edit().remove(KEY).apply()
    }

    private companion object {
        const val KEY = "entries"
        const val MAX = 100
    }
}
