package top.nekoh2o.player.data.plugins

import top.nekoh2o.player.i18n.NekoI18n.tr

import android.content.Context
import android.net.Uri
import android.util.AtomicFile
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import java.io.File
import java.io.IOException
import java.net.URI

object PluginStore {
    const val BUILTIN_URL = "https://animemusic.bzxhkj.com/animemusic/subscription.json"
    private const val BUILTIN_ID = "builtin-animemusic"
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val mutex = Mutex()
    private val ready = CompletableDeferred<Unit>()
    private val mutableState = MutableStateFlow(PluginState())
    val state: StateFlow<PluginState> = mutableState
    private lateinit var context: Context
    private lateinit var file: AtomicFile

    suspend fun initialize(appContext: Context) = withContext(Dispatchers.IO) {
        mutex.withLock {
            if (ready.isCompleted) return@withLock
            context = appContext.applicationContext
            file = AtomicFile(File(context.filesDir, "music-plugins.json"))
            try {
                val bundled = context.assets.open("music_plugins/animemusic.json").bufferedReader().use {
                    Json.parseToJsonElement(it.readText()).jsonObject
                }
                val builtins = bundled["plugins"]!!.jsonArray.map { element ->
                    val descriptor = element.jsonObject
                    MusicPlugin("animemusic-${descriptor.string("platform")}", BUILTIN_ID,
                        descriptor.string("name"), descriptor.string("update"), "animemusic/1", descriptor)
                }
                val loaded = if (file.baseFile.exists() || File(file.baseFile.path + ".bak").exists()) {
                    file.openRead().bufferedReader().use { json.decodeFromString<PluginState>(it.readText()) }
                } else PluginState()
                val subscriptions = loaded.subscriptions.toMutableList()
                if (subscriptions.none { it.id == BUILTIN_ID }) subscriptions.add(0,
                    PluginSubscription(BUILTIN_ID, tr("Animemusic 内置订阅"), BUILTIN_URL, builtIn = true))
                val plugins = loaded.plugins.toMutableList()
                builtins.forEach { builtin -> if (plugins.none { it.id == builtin.id }) plugins.add(builtin) }
                persist(loaded.copy(subscriptions = subscriptions, plugins = plugins))
                ready.complete(Unit)
            } catch (failure: Exception) {
                ready.completeExceptionally(IOException(tr("音源数据读取失败，已保留原文件"), failure))
                throw failure
            }
        }
    }

    suspend fun awaitReady() = ready.await()

    fun sources(snapshot: PluginState = state.value): List<PluginSource> {
        val active = snapshot.subscriptions.filter { it.enabled }.map { it.id }.toSet()
        return snapshot.plugins.filter { it.enabled && it.subscriptionId in active }.flatMap { plugin ->
            when {
                plugin.format == "lx" -> (plugin.descriptor["sources"] as? JsonObject).orEmpty().map { (platform, descriptor) ->
                    PluginSource("${plugin.id}:$platform", "${plugin.name} · ${(descriptor as? JsonObject)?.string("name") ?: platform}", plugin, platform)
                }
                plugin.platform == "all" -> plugin.descriptor.strings("platforms").map { platform ->
                    PluginSource("${plugin.id}:$platform", "${plugin.name} · $platform", plugin, platform)
                }
                else -> listOf(PluginSource(plugin.id, plugin.name, plugin, plugin.platform))
            }
        }
    }

    fun source(id: String): PluginSource? = sources().firstOrNull { it.id == id }
    fun isPluginSource(id: String): Boolean = id != "netease" && id != "kugou"
    fun sourceName(id: String): String = source(id)?.name ?: state.value.plugins.firstOrNull { it.id == id }?.name ?: id

    suspend fun importLocation(location: String, name: String = "", format: String = "auto") = withContext(Dispatchers.IO) {
        awaitReady()
        mutex.withLock {
            val normalized = location.trim()
            require(state.value.subscriptions.size < 64 || state.value.subscriptions.any { it.location == normalized }) { tr("最多支持 64 个订阅") }
            val existing = state.value.subscriptions.firstOrNull { it.location == normalized }
            val subscription = existing ?: PluginSubscription("sub-${pluginDigest(normalized).take(24)}",
                name.trim().ifBlank { tr("外部音源") }, normalized)
            install(subscription, format)
        }
    }

    suspend fun update(id: String) = withContext(Dispatchers.IO) {
        awaitReady()
        mutex.withLock {
            val subscription = state.value.subscriptions.firstOrNull { it.id == id } ?: error(tr("订阅不存在"))
            install(subscription, "auto")
        }
    }

    suspend fun setSubscriptionEnabled(id: String, enabled: Boolean) = mutate { current ->
        current.copy(subscriptions = current.subscriptions.map { if (it.id == id) it.copy(enabled = enabled) else it })
    }

    suspend fun setPluginEnabled(id: String, enabled: Boolean) = mutate { current ->
        current.copy(plugins = current.plugins.map { if (it.id == id) it.copy(enabled = enabled) else it })
    }

    suspend fun delete(id: String) = mutate { current ->
        require(current.subscriptions.none { it.id == id && it.builtIn }) { tr("内置订阅可以关闭，不能删除") }
        current.copy(subscriptions = current.subscriptions.filterNot { it.id == id }, plugins = current.plugins.filterNot { it.subscriptionId == id })
    }

    suspend fun selectSource(id: String) = mutate { it.copy(selectedSource = id) }

    suspend fun configure(id: String, variables: JsonObject) = mutate { current ->
        current.copy(plugins = current.plugins.map { if (it.id == id) it.copy(variables = variables) else it })
    }

    suspend fun saveStorage(plugin: MusicPlugin, storage: JsonObject) = mutate { current ->
        current.copy(plugins = current.plugins.map {
            if (it.id == plugin.id && it.script == plugin.script && it.variables == plugin.variables) it.copy(storage = storage) else it
        })
    }

    private suspend fun mutate(transform: (PluginState) -> PluginState) = withContext(Dispatchers.IO) {
        awaitReady()
        mutex.withLock { persist(transform(state.value)) }
    }

    private fun persist(next: PluginState) {
        val available = sources(next).map { it.id }.toSet() + setOf("netease", "kugou")
        val normalized = if (next.selectedSource in available) next else next.copy(selectedSource = "netease")
        if (normalized == state.value && file.baseFile.exists()) return
        val output = file.startWrite()
        try {
            output.write(json.encodeToString(normalized).toByteArray())
            file.finishWrite(output)
        } catch (failure: Exception) {
            file.failWrite(output)
            throw failure
        }
        mutableState.value = normalized
    }

    private suspend fun install(subscription: PluginSubscription, format: String) {
        withTimeout(120_000) {
            val text = readLocation(subscription.location)
            val document = runCatching { Json.parseToJsonElement(text) }.getOrNull()
            val entries = when (document) {
                is JsonArray -> document
                is JsonObject -> document["plugins"] as? JsonArray
                else -> null
            }
            val plugins = if (entries != null) {
                require(entries.size in 1..64) { tr("订阅必须包含 1–64 个音源") }
                entries.map { element ->
                    val entry = if (element is JsonPrimitive && element.isString) buildJsonObject { put("url", element.content) } else element.jsonObject
                    val location = resolveLocation(subscription.location, entry.string("url", "srcUrl", "update"))
                    if (entry.string("format") == "animemusic/1" && entry.string("api").isNotBlank()) {
                        descriptorPlugin(subscription, location, entry)
                    } else {
                        val script = readLocation(location)
                        val expected = entry["sha256"]?.let { (it as? JsonPrimitive)?.contentOrNull ?: error(tr("音源 SHA256 格式无效")) }
                        verifyPluginChecksum(script, expected)
                        parsePlugin(subscription, location, script, entry.string("name"), entry.string("format").ifBlank { format })
                    }
                }
            } else {
                require(document == null) { tr("JSON 文件缺少 plugins 数组") }
                listOf(parsePlugin(subscription, subscription.location, text, subscription.name, format))
            }
            require(plugins.distinctBy { it.id }.size == plugins.size) { tr("订阅包含重复音源") }
            require(plugins.sumOf { it.script.toByteArray().size.toLong() } <= 16L * 1024 * 1024) { tr("订阅脚本总大小超过限制") }
            val current = state.value
            val retained = plugins.map { plugin ->
                current.plugins.firstOrNull { it.id == plugin.id }?.let { old ->
                    plugin.copy(enabled = old.enabled, variables = old.variables, storage = old.storage)
                } ?: plugin
            }
            val updated = subscription.copy(updatedAt = System.currentTimeMillis())
            persist(current.copy(subscriptions = current.subscriptions.filterNot { it.id == subscription.id } + updated,
                plugins = current.plugins.filterNot { it.subscriptionId == subscription.id } + retained))
        }
    }

    private fun descriptorPlugin(subscription: PluginSubscription, location: String, descriptor: JsonObject): MusicPlugin {
        require(validPluginUrl(descriptor.string("api"))) { tr("Animemusic 音源缺少有效 api 地址") }
        val platform = descriptor.string("platform")
        require(platform.isNotBlank()) { tr("Animemusic 音源缺少 platform") }
        val id = if (subscription.builtIn) "animemusic-$platform" else "plugin-${pluginDigest(subscription.id + location).take(24)}"
        return MusicPlugin(id, subscription.id, descriptor.string("name").ifBlank { platform }, location, "animemusic/1", descriptor)
    }

    private suspend fun parsePlugin(subscription: PluginSubscription, location: String, script: String, name: String, format: String): MusicPlugin {
        val meta = parsePluginMetadata(script)
        if (meta?.string("format") == "animemusic/1") return descriptorPlugin(subscription, location, meta)
        val detected = if (format != "auto") format else if (Regex("""(?:globalThis\.|global\.|window\.)?lx\s*[.\[]""").containsMatchIn(script)) "lx" else "auto"
        require(detected in listOf("auto", "musicfree", "baka", "lx")) { tr("不支持的脚本格式") }
        val plugin = MusicPlugin("plugin-${pluginDigest(subscription.id + location).take(24)}", subscription.id,
            name.ifBlank { tr("外部音源") }, location, detected, JsonObject(emptyMap()), script)
        val result = PluginRuntime(context).run(plugin)
        val descriptor = result.value as? JsonObject ?: throw IOException(tr("脚本未返回音源元数据"))
        if (detected == "lx") require((descriptor["sources"] as? JsonObject)?.isNotEmpty() == true) { tr("LX 脚本没有注册来源") }
        return plugin.copy(format = descriptor.string("format"), name = descriptor.string("name", "platform").ifBlank { plugin.name }, descriptor = descriptor, storage = result.storage)
    }

    private suspend fun readLocation(location: String): String = when {
        validPluginUrl(location) -> PluginHttp.get(location)
        location.startsWith("content://") -> context.contentResolver.openInputStream(Uri.parse(location))?.use {
            it.readPluginBytes().toString(Charsets.UTF_8)
        } ?: throw IOException(tr("无法读取本地音源文件"))
        else -> throw IOException(tr("仅支持 HTTP(S) 地址或选择的本地文件"))
    }

    private fun resolveLocation(base: String, value: String): String {
        require(value.isNotBlank()) { tr("订阅条目缺少 url") }
        val resolved = if (validPluginUrl(value)) value else if (validPluginUrl(base)) URI(base).resolve(value).toString() else value
        require(validPluginUrl(resolved)) { tr("订阅条目必须提供有效 HTTP(S) 地址") }
        return resolved
    }
}
