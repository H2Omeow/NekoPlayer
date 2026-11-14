package top.nekoh2o.player.diagnostics

import android.content.Context
import com.google.gson.GsonBuilder
import com.google.gson.JsonArray
import com.google.gson.JsonNull
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import top.nekoh2o.player.PlayerApp
import top.nekoh2o.player.data.plugins.PluginStore
import top.nekoh2o.player.data.repo.DownloadIndex
import top.nekoh2o.player.data.repo.LocalStore
import top.nekoh2o.player.data.store.SettingsStore
import top.nekoh2o.player.data.sync.SyncCodec
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 导出可迁移的应用数据 JSON：设置、收藏、历史、歌单、播放状态、下载索引与音源配置。
 * 刻意不包含登录凭据、Cookie、插件密钥、插件脚本及任何音频文件。
 */
object AppDataExporter {

    suspend fun build(context: Context): String = withContext(Dispatchers.IO) {
        val app = context.applicationContext
        val gson = GsonBuilder().setPrettyPrinting().serializeNulls().create()
        val root = JsonObject().apply {
            addProperty("format", "nekoplayer.data")
            addProperty("version", 1)
            addProperty("appVersion", DiagnosticsReporter.versionName(app))
            addProperty("platform", "android")
            addProperty("exportedAt", timestamp())
            addProperty("notes", "登录凭据、插件密钥、脚本和音频文件不会包含在此导出中。")
        }

        val settingsStore = SettingsStore(app)
        val settings = runCatching { settingsStore.load() }.getOrNull()
        root.add("settings", settings?.let { gson.toJsonTree(it) } ?: JsonNull.INSTANCE)

        runCatching {
            val store = (app as? PlayerApp)?.localStore
                ?: LocalStore(app)
            val library = JsonObject().apply {
                add("favorites", parse(SyncCodec.encodeSongs(store.favorites.toList(), store.foreignFavorites)))
                add("history", parse(SyncCodec.encodeSongs(store.history.toList(), store.foreignHistory)))
                add("playlists", parse(SyncCodec.encodePlaylists(store.playlists.toList(), store.foreignPlaylists)))
            }
            root.add("library", library)
        }.onFailure {
            AppLog.warn("export", "读取音乐库导出数据失败", it)
        }

        val downloads = JsonArray().apply {
            runCatching { DownloadIndex.all() }.getOrDefault(emptyList()).forEach { entry ->
                add(JsonObject().apply {
                    addProperty("songId", entry.songId)
                    add("song", gson.toJsonTree(entry.song))
                    addProperty("audioUri", entry.audioUri)
                    addProperty("lrcPath", entry.lrcPath)
                    addProperty("quality", entry.quality)
                    addProperty("downloadedAt", entry.downloadedAt)
                })
            }
        }
        root.add("downloads", downloads)

        val playback = runCatching { settingsStore.loadPlaybackState() }.getOrNull()
        root.add("playback", playback?.let { gson.toJsonTree(it) } ?: JsonNull.INSTANCE)

        val pluginState = runCatching {
            withTimeoutOrNull(3_000) { PluginStore.awaitReady() }
            PluginStore.state.value
        }.getOrNull()
        root.add("plugins", JsonObject().apply {
            addProperty("selectedSource", pluginState?.selectedSource ?: "netease")
            add("subscriptions", gson.toJsonTree(pluginState?.subscriptions?.map { subscription ->
                mapOf(
                    "id" to subscription.id,
                    "name" to subscription.name,
                    "location" to subscription.location,
                    "builtIn" to subscription.builtIn,
                    "enabled" to subscription.enabled,
                    "updatedAt" to subscription.updatedAt
                )
            } ?: emptyList<Any>()))
            add("plugins", gson.toJsonTree(pluginState?.plugins?.map { plugin ->
                mapOf(
                    "id" to plugin.id,
                    "subscriptionId" to plugin.subscriptionId,
                    "name" to plugin.name,
                    "format" to plugin.format,
                    "enabled" to plugin.enabled,
                    "version" to plugin.version
                )
            } ?: emptyList<Any>()))
        })

        gson.toJson(root)
    }

    private fun parse(value: kotlinx.serialization.json.JsonElement) =
        JsonParser.parseString(value.toString())

    private fun timestamp(): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssZ", Locale.US).format(Date())
}
