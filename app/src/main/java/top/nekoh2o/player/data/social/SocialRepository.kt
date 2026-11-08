package top.nekoh2o.player.data.social

import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Request
import okhttp3.Response
import retrofit2.HttpException
import top.nekoh2o.player.data.net.ApiFactory
import top.nekoh2o.player.data.net.CookieStore
import java.io.Closeable
import java.io.IOException
import java.util.concurrent.TimeUnit

class SocialRepository {

    private val api = ApiFactory.social
    private val json = Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true }

    suspend fun conversations(): List<SocialConversation> = call { api.conversations().also { check(it.code) }.conversations }

    suspend fun conversationWith(peerId: String): SocialConversation? =
        call { api.conversationWith(peerId).also { check(it.code) }.conversation }

    suspend fun createConversation(peerId: String): SocialConversation =
        call {
            val resp = api.createConversation(CreateConversationRequest(peerId))
            check(resp.code)
            resp.conversation ?: throw SocialException("无法创建会话")
        }

    suspend fun messages(conversationId: String, afterSeq: Long? = null): SocialMessagesResp =
        call { api.messages(conversationId, 100, afterSeq?.takeIf { it > 0 }).also { check(it.code) } }

    suspend fun markRead(conversationId: String, seq: Long): SocialReadResp =
        call { api.markRead(conversationId, ReadRequest(seq)).also { check(it.code) } }

    suspend fun sendMessage(request: SendMessageRequest): SocialSendResp =
        call { api.sendMessage(request).also { check(it.code) } }

    suspend fun deleteMessage(id: String): SocialSendResp =
        call { api.deleteMessage(id).also { check(it.code) } }

    suspend fun searchUsers(query: String): List<SocialProfile> =
        call { api.searchUsers(query).also { check(it.code) }.users }

    suspend fun profile(id: String): SocialProfile =
        call { api.profile(id).also { check(it.code) }.profile ?: throw SocialException("用户不存在") }

    suspend fun userShares(id: String): List<SocialShare> =
        call { api.userShares(id).also { check(it.code) }.shares }

    suspend fun followers(id: String): List<SocialProfile> =
        call { api.followers(id).also { check(it.code) }.users }

    suspend fun following(id: String): List<SocialProfile> =
        call { api.following(id).also { check(it.code) }.users }

    suspend fun follow(id: String, following: Boolean): SocialFollowResp =
        call { (if (following) api.follow(id, FollowRequest(true)) else api.unfollow(id)).also { check(it.code) } }

    suspend fun block(id: String, blocked: Boolean): SocialBlockResp =
        call { (if (blocked) api.block(id) else api.unblock(id)).also { check(it.code) } }

    suspend fun feed(): List<SocialShare> = call { api.feed().also { check(it.code) }.shares }

    suspend fun createShare(request: ShareRequest): SocialShare =
        call { api.createShare(request).also { check(it.code) }.share ?: throw SocialException("分享创建失败") }

    suspend fun share(token: String): SocialShare =
        call { api.share(token).also { check(it.code) }.share ?: throw SocialException("分享不存在") }

    suspend fun revokeShare(token: String): SocialShare =
        call { api.revokeShare(token).also { check(it.code) }.share ?: throw SocialException("分享不存在") }

    suspend fun preferences(): SocialPreferences =
        call { api.preferences().also { check(it.code) }.preferences }

    suspend fun savePreferences(policy: String): SocialPreferences =
        call { api.savePreferences(PreferencesRequest(policy)).also { check(it.code) }.preferences }

    suspend fun unread(): Int = call { api.unread().also { check(it.code) }.unread }

    private fun check(code: Int) {
        if (code != 0) throw SocialException("请求失败（$code）", code)
    }

    private suspend fun <T> call(block: suspend () -> T): T {
        try {
            return block()
        } catch (e: CancellationException) {
            throw e
        } catch (e: HttpException) {
            val text = runCatching { e.response()?.errorBody()?.string() }.getOrNull()
            val body = text?.let { runCatching { json.decodeFromString<SocialErrorMessage>(it) }.getOrNull() }
            val message = when {
                body?.msg?.isNotBlank() == true -> body.msg
                e.code() == 401 -> "登录已失效，请重新登录"
                e.code() == 403 -> "没有权限执行该操作"
                e.code() == 404 -> "内容不存在"
                e.code() == 410 -> "分享已失效"
                e.code() == 429 -> "操作过于频繁，请稍后再试"
                else -> "请求失败（HTTP ${e.code()}）"
            }
            throw SocialException(message, e.code())
        } catch (e: IOException) {
            throw SocialException("网络连接失败，请检查网络")
        }
    }
}

/** 带 Authorization 头的 SSE 连接；在 IO 线程调用 [read]，[close] 可随时中断。 */
class SocialSseConnection internal constructor(private val call: okhttp3.Call) : Closeable {

    fun read(onEvent: (event: String, data: String) -> Unit) {
        call.execute().use { response: Response ->
            if (!response.isSuccessful) {
                throw SocialException(
                    if (response.code == 401) "登录已失效" else "实时连接失败（${response.code}）",
                    response.code
                )
            }
            val source = response.body?.source() ?: throw SocialException("实时连接无响应")
            var event = "message"
            val data = StringBuilder()
            while (!call.isCanceled()) {
                val line = source.readUtf8Line() ?: throw IOException("实时连接已断开")
                if (line.isEmpty()) {
                    if (data.isNotEmpty()) {
                        onEvent(event, data.toString())
                        event = "message"
                        data.clear()
                    }
                    continue
                }
                if (line.startsWith(":")) continue
                val colon = line.indexOf(':')
                val field = if (colon < 0) line else line.substring(0, colon)
                val value = if (colon < 0) "" else line.substring(colon + 1).removePrefix(" ")
                when (field) {
                    "event" -> event = value
                    "data" -> {
                        if (data.isNotEmpty()) data.append('\n')
                        data.append(value)
                    }
                }
            }
        }
    }

    override fun close() {
        runCatching { call.cancel() }
    }

    companion object {
        fun open(): SocialSseConnection {
            val token = CookieStore.appTokenValue()
            if (token.isEmpty()) throw SocialException("请先登录", 401)
            val url = (ApiFactory.BASE + "social/events").toHttpUrl()
            val client = ApiFactory.client().newBuilder()
                .readTimeout(0, TimeUnit.MILLISECONDS)
                .callTimeout(0, TimeUnit.MILLISECONDS)
                .build()
            val request = Request.Builder()
                .url(url)
                .header("Authorization", "Bearer $token")
                .header("Accept", "text/event-stream")
                .build()
            return SocialSseConnection(client.newCall(request))
        }
    }
}
