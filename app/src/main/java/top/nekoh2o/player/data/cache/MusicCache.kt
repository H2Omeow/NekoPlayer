package top.nekoh2o.player.data.cache

import android.content.Context
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.ContentMetadata
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.database.StandaloneDatabaseProvider
import java.io.File

@OptIn(UnstableApi::class)
object MusicCache {

    private const val MAX_CACHE_BYTES = 2L * 1024L * 1024L * 1024L

    @Volatile
    private var instance: SimpleCache? = null

    @Synchronized
    fun init(context: Context) {
        if (instance != null) return

        val appContext = context.applicationContext
        val cacheDirectory = File(appContext.cacheDir, "music")
        instance = runCatching {
            SimpleCache(
                cacheDirectory,
                LeastRecentlyUsedCacheEvictor(MAX_CACHE_BYTES),
                StandaloneDatabaseProvider(appContext)
            )
        }.getOrElse { error ->
            // 上一次进程异常退出可能留下损坏的缓存数据库，清空后重试一次；
            // 仍失败时退化为无缓存播放，不能让整个应用启动失败。
            android.util.Log.e("MusicCache", "缓存初始化失败，清理缓存目录后重试", error)
            runCatching { cacheDirectory.deleteRecursively() }
            runCatching {
                SimpleCache(
                    cacheDirectory,
                    LeastRecentlyUsedCacheEvictor(MAX_CACHE_BYTES),
                    StandaloneDatabaseProvider(appContext)
                )
            }.onFailure {
                android.util.Log.e("MusicCache", "缓存仍不可用，本次启动不启用缓存", it)
            }.getOrNull()
        }
    }

    fun dataSourceFactory(
        upstreamFactory: DataSource.Factory
    ): DataSource.Factory {
        val cache = instance ?: return upstreamFactory

        return CacheDataSource.Factory()
            .setCache(cache)
            .setUpstreamDataSourceFactory(upstreamFactory)
            .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
    }

    fun cacheSpace(): Long = instance?.cacheSpace ?: 0L

    fun cachedKeys(): Set<String> = instance?.keys?.toSet() ?: emptySet()

    /**
     * 判断缓存条目是否已经完整写入。仅检查 keys 会把分片缓存误报为可离线播放，
     * 因此还需要比较缓存记录的内容长度和已缓存字节数。
     */
    fun isFullyCached(key: String): Boolean {
        val cache = instance ?: return false
        val length = ContentMetadata.getContentLength(cache.getContentMetadata(key))
        return length != C.LENGTH_UNSET.toLong() &&
            length > 0L &&
            cache.isCached(key, 0L, length)
    }

    fun cacheKeyForSong(songId: Long): String = songId.toString()
    fun cacheKeyForSong(song: top.nekoh2o.player.data.model.Song): String =
        if (song.source == "netease") cacheKeyForSong(song.id) else song.source + ":" + song.hash.ifEmpty { song.id.toString() }

    /** Prefer the requested cached format, otherwise the highest complete local format. */
    fun offlineKey(song: top.nekoh2o.player.data.model.Song, preferred: String): String? {
        val base = cacheKeyForSong(song)
        val prefix = base + ":quality:"
        val mapped = top.nekoh2o.player.data.repo.SongQualityRepository.preferredFor(song.source, preferred)
        val quality = top.nekoh2o.player.data.repo.SongQualityRepository
        return cachedKeys().filter { it.startsWith(prefix) && isFullyCached(it) }
            .sortedWith(compareByDescending<String> { it.removePrefix(prefix) == mapped }.thenByDescending {
                val id = it.removePrefix(prefix)
                if (song.source == "kugou") quality.kgLabels[id]?.second ?: -1 else quality.ncLevels.indexOf(id)
            }).firstOrNull() ?: base.takeIf { isFullyCached(it) }
    }

    @Synchronized
    fun remove(key: String) {
        val cache = instance ?: return
        runCatching {
            cache.removeResource(key)
        }
    }

    @Synchronized
    fun clear() {
        val cache = instance ?: return
        cache.keys.toList().forEach { key ->
            runCatching {
                cache.removeResource(key)
            }
        }
    }
}
