package top.nekoh2o.player.data.plugins

import top.nekoh2o.player.i18n.NekoI18n.tr

import android.content.Context
import android.util.Base64
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.io.InputStream
import java.security.SecureRandom
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

internal object PluginHttp {
    const val MAX_BYTES = 5 * 1024 * 1024
    val client = OkHttpClient.Builder().cookieJar(CookieJar.NO_COOKIES)
        .connectTimeout(8, TimeUnit.SECONDS).readTimeout(12, TimeUnit.SECONDS)
        .callTimeout(15, TimeUnit.SECONDS).followRedirects(false).followSslRedirects(false).build()

    suspend fun get(url: String): String {
        require(validPluginUrl(url)) { tr("请输入有效的 HTTP(S) 地址") }
        return execute(Request.Builder().url(url).build()).use { response ->
            if (!response.isSuccessful) throw IOException(tr("音源服务器返回 HTTP {code}", "code" to response.code))
            val body = response.body ?: throw IOException(tr("音源服务器返回空内容"))
            withContext(Dispatchers.IO) { body.byteStream().use { it.readPluginBytes() }.toString(Charsets.UTF_8) }
        }
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    suspend fun execute(request: Request): Response {
        var current = request
        repeat(5) {
            val response = executeOnce(current)
            if (response.code !in listOf(301, 302, 303, 307, 308)) return response
            val next = response.header("Location")?.let { current.url.resolve(it) }
            val code = response.code
            response.close()
            require(next != null && next.username.isEmpty() && next.password.isEmpty()) { tr("音源重定向地址无效") }
            require(!current.url.isHttps || next.isHttps) { tr("音源请求拒绝降级为 HTTP") }
            val builder = current.newBuilder().url(next)
            if (current.url.scheme != next.scheme || current.url.host != next.host || current.url.port != next.port) {
                builder.removeHeader("Authorization").removeHeader("Cookie").removeHeader("Proxy-Authorization")
            }
            if (code == 303 || code in listOf(301, 302) && current.method == "POST") {
                builder.method("GET", null).removeHeader("Content-Type").removeHeader("Content-Length")
            }
            current = builder.build()
        }
        throw IOException(tr("音源重定向次数过多"))
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    private suspend fun executeOnce(request: Request): Response = suspendCancellableCoroutine { continuation ->
        val call = client.newCall(request)
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, exception: IOException) {
                if (!continuation.isCancelled) continuation.resumeWithException(IOException(tr("音源网络请求失败")))
            }
            override fun onResponse(call: Call, response: Response) {
                continuation.resume(response) { response.close() }
            }
        })
    }
}

internal fun InputStream.readPluginBytes(): ByteArray {
    val output = java.io.ByteArrayOutputStream()
    val buffer = ByteArray(8192)
    while (true) {
        val count = read(buffer)
        if (count < 0) break
        require(output.size() + count <= PluginHttp.MAX_BYTES) { tr("音源内容超过 5 MiB 限制") }
        output.write(buffer, 0, count)
    }
    return output.toByteArray()
}

data class PluginInvocation(val value: JsonElement, val storage: JsonObject)

class PluginRuntime(private val context: Context) {
    private val bootstrap by lazy { context.assets.open("music_plugins/runtime.js").bufferedReader().use { it.readText() } }

    suspend fun run(plugin: MusicPlugin, method: String? = null, args: JsonArray = JsonArray(emptyList())): PluginInvocation {
        return try {
            withTimeout(20_000) {
                val native = withContext(nativeDispatcher) { NativePluginVm() }
                val handle = withContext(nativeDispatcher) { native.create() }
                check(handle != 0L) { tr("无法创建脚本环境") }
                try {
                    evaluate(native, handle, bootstrap)
                    val options = buildJsonObject {
                        if (plugin.format != "auto") put("format", plugin.format)
                        put("name", plugin.name); put("os", "android")
                        put("variables", plugin.variables); put("storage", plugin.storage)
                    }
                    evaluate(native, handle, "NekoPlugin.load(${JsonPrimitive(plugin.script)},$options);''")
                    val loaded = settle(native, handle, plugin.storage)
                    if (method == null) loaded else {
                        evaluate(native, handle, "NekoPlugin.invoke(${JsonPrimitive(method)},$args);''")
                        settle(native, handle, loaded.storage)
                    }
                } finally {
                    withContext(NonCancellable + nativeDispatcher) { native.close(handle) }
                }
            }
        } catch (failure: TimeoutCancellationException) {
            currentCoroutineContext().ensureActive()
            throw IOException(tr("音源脚本执行超过 20 秒"))
        } catch (failure: LinkageError) {
            throw IOException(tr("当前安装包缺少音源脚本运行库"))
        }
    }

    private suspend fun evaluate(native: NativePluginVm, handle: Long, script: String): String {
        val result = withContext(nativeDispatcher) { Json.parseToJsonElement(native.eval(handle, script)).jsonObject }
        if (result["ok"] != JsonPrimitive(true)) throw IOException(tr("音源脚本执行失败，请检查脚本兼容性"))
        return result.string("value")
    }

    private data class HostReply(val id: JsonElement, val success: Boolean, val value: JsonElement)

    private suspend fun settle(native: NativePluginVm, handle: Long, initialStorage: JsonObject): PluginInvocation = coroutineScope {
        var storage = initialStorage
        var requestCount = 0
        var pendingCount = 0
        val replies = Channel<HostReply>(Channel.UNLIMITED)
        val jobs = mutableListOf<Job>()
        try { while (true) {
            currentCoroutineContext().ensureActive()
            val state = Json.parseToJsonElement(evaluate(native, handle, "NekoPlugin.take()")).jsonObject
            storage = state["storage"] as? JsonObject ?: storage
            val requests = (state["requests"] as? JsonArray).orEmpty().filterIsInstance<JsonObject>()
            requestCount += requests.size
            pendingCount += requests.size
            require(requestCount <= 64) { tr("音源脚本请求次数过多") }
            requests.forEach { request ->
                jobs.add(launch {
                    val reply = try {
                        true to hostRequest(request)
                    } catch (failure: CancellationException) {
                        throw failure
                    } catch (_: Exception) {
                        false to JsonPrimitive("Host request failed")
                    }
                    val id = request["id"] ?: throw IOException(tr("音源宿主请求缺少标识"))
                    replies.send(HostReply(id, reply.first, reply.second))
                })
            }
            when (state.string("state")) {
                "done" -> return@coroutineScope PluginInvocation(state["value"] ?: JsonNull, storage)
                "error" -> throw IOException(tr("音源脚本调用失败，请检查配置或更新音源"))
                "pending" -> {
                    require(pendingCount > 0) { tr("音源脚本没有可处理的请求") }
                    val reply = replies.receive()
                    pendingCount--
                    evaluate(native, handle, "NekoPlugin.deliver(${reply.id},${reply.success},${reply.value});''")
                }
                else -> throw IOException(tr("音源运行库返回未知状态"))
            }
        } } finally {
            jobs.forEach { it.cancel() }
            replies.close()
        }
        @Suppress("UNREACHABLE_CODE")
        error(tr("音源脚本未完成"))
    }

    private suspend fun hostRequest(request: JsonObject): JsonElement = withContext(Dispatchers.IO) {
        val payload = request["payload"] as? JsonObject ?: JsonObject(emptyMap())
        when (request.string("kind")) {
            "random" -> {
                val length = (payload["length"] as? JsonPrimitive)?.intOrNull ?: 0
                require(length in 0..65536)
                val bytes = ByteArray(length).also { random.nextBytes(it) }
                JsonPrimitive(Base64.encodeToString(bytes, Base64.NO_WRAP))
            }
            "delay" -> {
                val milliseconds = (payload["milliseconds"] as? JsonPrimitive)?.longOrNull ?: 0L
                require(milliseconds in 0..20_000)
                delay(milliseconds)
                JsonNull
            }
            "http" -> {
                val url = payload.string("url")
                require(validPluginUrl(url))
                val headers = payload["headers"] as? JsonObject ?: JsonObject(emptyMap())
                val builder = Request.Builder().url(url)
                headers.forEach { (name, value) -> builder.header(name, (value as? JsonPrimitive)?.contentOrNull.orEmpty()) }
                val method = payload.string("method").ifBlank { "GET" }.uppercase()
                val content = payload["body"]?.takeIf { it != JsonNull }
                val body = if (method in listOf("GET", "HEAD")) null else {
                    val text = (content as? JsonPrimitive)?.contentOrNull ?: content?.toString().orEmpty()
                    text.toRequestBody(headers.string("content-type", "Content-Type").toMediaTypeOrNull())
                }
                PluginHttp.execute(builder.method(method, body).build()).use { response ->
                    val bytes = response.body?.byteStream()?.use { it.readPluginBytes() } ?: byteArrayOf()
                    buildJsonObject {
                        put("status", response.code); put("url", response.request.url.toString())
                        put("headers", buildJsonObject { response.headers.names().forEach { name -> put(name, response.header(name).orEmpty()) } })
                        put("body", Base64.encodeToString(bytes, Base64.NO_WRAP))
                    }
                }
            }
            else -> throw IOException(tr("不支持的音源宿主请求"))
        }
    }

    companion object {
        private val nativeDispatcher = Executors.newSingleThreadExecutor { task ->
            Thread(task, "music-plugin-vm").apply { isDaemon = true }
        }.asCoroutineDispatcher()
        private val random = SecureRandom()
    }
}
