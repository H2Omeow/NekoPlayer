package top.nekoh2o.player.data.cloud

import android.content.Context
import android.net.Uri
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import top.nekoh2o.player.data.net.CookieStore
import java.io.InputStream
import java.util.concurrent.TimeUnit

/**
 * 云存储 / 赞赏 / 森空岛绑定接口。
 *
 * 所有请求都打到 player.nekoh2o.top，由 ApiFactory 同源的 Bearer token 鉴权；
 * 对象直传地址是雨云 ROS 域名，不带 token。
 */
object CloudApi {
    private const val BASE = "https://player.nekoh2o.top"
    private const val ACCOUNT = "https://account.nekoh2o.top"
    private const val PLAYER_HOST = "player.nekoh2o.top"

    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .addInterceptor { chain ->
                val req = chain.request()
                val token = CookieStore.appTokenValue()
                val authorized = req.url.host == PLAYER_HOST || req.url.host == "account.nekoh2o.top"
                if (authorized && token.isNotEmpty()) {
                    chain.proceed(req.newBuilder().header("Authorization", "Bearer $token").build())
                } else {
                    chain.proceed(req)
                }
            }
            .build()
    }

    class CloudException(val code: Int, override val message: String, val needSkland: Boolean = false) : Exception(message)

    private suspend fun execute(request: Request): JsonObject = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        client.newCall(request).execute().use { res ->
            val text = res.body?.string().orEmpty()
            if (text.isBlank()) {
                if (!res.isSuccessful) throw CloudException(res.code, "HTTP ${res.code}")
                return@use JsonObject(emptyMap())
            }
            val root = runCatching { json.parseToJsonElement(text).jsonObject }.getOrNull()
                ?: throw CloudException(res.code, text.take(160))
            val code = root["code"]?.jsonPrimitive?.content?.toIntOrNull() ?: 0
            if (!res.isSuccessful || code != 0) {
                val need = root["needSkland"]?.jsonPrimitive?.content?.toBoolean() ?: false
                throw CloudException(if (code != 0) code else res.code, root["msg"]?.jsonPrimitive?.content ?: "请求失败", need)
            }
            root["data"]?.let { if (it is JsonObject) return@use it }
            root
        }
    }

    private fun get(path: String): Request =
        Request.Builder().url(BASE + path).get().build()

    private fun postJson(path: String, body: JsonObject): Request =
        Request.Builder().url(BASE + path)
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .build()

    suspend fun files(): JsonObject = execute(get("/files"))
    suspend fun pricing(): JsonObject = execute(get("/pricing"))
    suspend fun myOrders(): JsonObject = execute(get("/orders/mine"))
    suspend fun notifications(): JsonObject = execute(get("/notifications"))

    suspend fun markNotificationsRead(): JsonObject = execute(postJson("/notifications/read", JsonObject(emptyMap())))

    suspend fun uploadUrl(name: String, size: Long, category: String): JsonObject = execute(
        postJson("/files/upload-url", buildJsonObject {
            put("name", name); put("size", size); put("category", category)
        })
    )

    suspend fun complete(fileId: String): JsonObject = execute(
        postJson("/files/complete", buildJsonObject { put("fileId", fileId) })
    )

    suspend fun createMultipart(name: String, size: Long, category: String): JsonObject = execute(
        postJson("/files/multipart", buildJsonObject {
            put("name", name); put("size", size); put("category", category)
        })
    )

    suspend fun partUrl(fileId: String, index: Int): String =
        execute(get("/files/multipart/$fileId/part/$index"))["url"]!!.jsonPrimitive.content

    suspend fun completeMultipart(fileId: String, parts: List<Pair<Int, String>>): JsonObject = execute(
        postJson("/files/multipart/$fileId/complete", buildJsonObject {
            put("parts", buildJsonArray {
                parts.forEach { (n, etag) ->
                    add(buildJsonObject { put("partNumber", n); put("etag", etag) })
                }
            })
        })
    )

    suspend fun abortMultipart(fileId: String) {
        runCatching { execute(postJson("/files/multipart/$fileId/abort", buildJsonObject {})) }
    }

    suspend fun delete(fileId: String): JsonObject = execute(
        Request.Builder().url(BASE + "/files/" + fileId).delete().build()
    )

    suspend fun share(fileId: String, mode: String, days: Int): JsonObject = execute(
        postJson("/files/$fileId/share", buildJsonObject {
            put("mode", mode); put("expiresDays", days)
        })
    )

    suspend fun createOrder(tier: String, months: Int): JsonObject = execute(
        postJson("/orders", buildJsonObject { put("tier", tier); put("months", months) })
    )

    suspend fun uploadReceipt(orderId: String, bytes: ByteArray, mime: String): JsonObject = execute(
        Request.Builder().url(BASE + "/orders/$orderId/receipt")
            .post(bytes.toRequestBody(mime.toMediaType()))
            .build()
    )

    // ---------- 森空岛扫码绑定 ----------
    suspend fun sklandStart(): JsonObject = execute(
        Request.Builder().url("$ACCOUNT/auth/skland/start")
            .post("{}".toRequestBody("application/json".toMediaType())).build()
    )

    suspend fun sklandPoll(sid: String): JsonObject =
        execute(Request.Builder().url("$ACCOUNT/auth/skland/poll?sid=$sid").get().build())

    suspend fun sklandSmsSend(phone: String): JsonObject = execute(
        Request.Builder().url("$ACCOUNT/auth/skland/sms/send")
            .post(JsonObject(mapOf("phone" to JsonPrimitive(phone))).toString().toRequestBody("application/json".toMediaType()))
            .build()
    )

    suspend fun sklandSmsVerify(phone: String, code: String): JsonObject = execute(
        Request.Builder().url("$ACCOUNT/auth/skland/sms/verify")
            .post(
                JsonObject(
                    mapOf("phone" to JsonPrimitive(phone), "code" to JsonPrimitive(code))
                ).toString().toRequestBody("application/json".toMediaType())
            )
            .build()
    )

    suspend fun sklandWebToken(token: String): JsonObject = execute(
        Request.Builder().url("$ACCOUNT/auth/skland/token")
            .post(
                JsonObject(mapOf("token" to JsonPrimitive(token)))
                    .toString().toRequestBody("application/json".toMediaType())
            )
            .build()
    )

    suspend fun sklandPasswordVerify(phone: String, password: String): JsonObject = execute(
        Request.Builder().url("$ACCOUNT/auth/skland/password/verify")
            .post(
                JsonObject(
                    mapOf("phone" to JsonPrimitive(phone), "password" to JsonPrimitive(password))
                ).toString().toRequestBody("application/json".toMediaType())
            )
            .build()
    )

    // ---------- 上传实现 ----------
    private const val PART_SIZE = 5 * 1024 * 1024

    /**
     * 直传文件到对象存储。
     * @param onProgress 已上传字节 / 总字节
     */
    suspend fun upload(
        context: Context,
        uri: Uri,
        name: String,
        size: Long,
        category: String,
        onProgress: (Float) -> Unit = {}
    ): JsonObject = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        val resolver = context.contentResolver
        val mime = resolver.getType(uri) ?: "application/octet-stream"
        if (size <= PART_SIZE) {
            val meta = uploadUrl(name, size, category)
            val url = meta["uploadUrl"]!!.jsonPrimitive.content
            val fileId = meta["fileId"]!!.jsonPrimitive.content
            resolver.openInputStream(uri)?.use { input ->
                val bytes = input.readBytes()
                putBytes(url, bytes, mime)
            } ?: throw CloudException(0, "无法读取文件")
            onProgress(1f)
            return@withContext complete(fileId)
        }

        val meta = createMultipart(name, size, category)
        val fileId = meta["fileId"]!!.jsonPrimitive.content
        val partCount = meta["partCount"]!!.jsonPrimitive.content.toInt()
        resolver.openInputStream(uri) ?: throw CloudException(0, "无法读取文件")
        val parts = mutableListOf<Pair<Int, String>>()
        try {
            for (index in 1..partCount) {
                val url = partUrl(fileId, index)
                val bytes = readChunk(resolver.openInputStream(uri)!!, index, PART_SIZE, size)
                val etag = putBytes(url, bytes, "application/octet-stream")
                parts.add(index to etag)
                onProgress((index.toFloat() / partCount).coerceIn(0f, 1f))
            }
            return@withContext completeMultipart(fileId, parts)
        } catch (error: Throwable) {
            abortMultipart(fileId)
            throw error
        }
    }

    private fun readChunk(input: InputStream, index: Int, partSize: Int, total: Long): ByteArray {
        input.use { stream ->
            val skip = (index - 1).toLong() * partSize
            if (skip > 0) {
                var remaining = skip
                while (remaining > 0) {
                    val skipped = stream.skip(remaining)
                    if (skipped <= 0) break
                    remaining -= skipped
                }
            }
            val length = minOf(partSize.toLong(), total - skip).toInt().coerceAtLeast(0)
            val buffer = ByteArray(length)
            var read = 0
            while (read < length) {
                val n = stream.read(buffer, read, length - read)
                if (n <= 0) break
                read += n
            }
            return if (read == length) buffer else buffer.copyOf(read)
        }
    }

    private fun putBytes(url: String, bytes: ByteArray, mime: String): String {
        val request = Request.Builder().url(url)
            .put(bytes.toRequestBody(mime.toMediaType()))
            .build()
        client.newCall(request).execute().use { res ->
            if (!res.isSuccessful) throw CloudException(res.code, "上传失败 HTTP ${res.code}")
            return res.header("ETag")?.trim() ?: throw CloudException(0, "分片缺少 ETag")
        }
    }

    fun filesOf(root: JsonObject): JsonArray = root["data"] as? JsonArray ?: root["data"]?.jsonArray ?: JsonArray(emptyList())
}
