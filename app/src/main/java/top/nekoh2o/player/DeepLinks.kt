package top.nekoh2o.player

import android.content.Intent
import android.net.Uri
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

sealed class SocialDeepLink {
    data class Share(val token: String) : SocialDeepLink()
    data class Chat(val peerId: String) : SocialDeepLink()
    data class User(val userId: String) : SocialDeepLink()
}

fun interface DeepLinkStateListener {
    fun onChanged(link: SocialDeepLink?)
}

/** 深链在 Activity 中解析，由 Compose 界面消费；导航状态不依赖任何单例 ViewModel。 */
object SocialDeepLinks {
    private val _pending = MutableStateFlow<SocialDeepLink?>(null)
    val pending: StateFlow<SocialDeepLink?> = _pending.asStateFlow()

    const val SCHEME = "nekoplayer"

    /** 返回 true 表示该 Intent 已被社交深链处理（auth 深链仍由 MainActivity 单独处理）。 */
    fun handle(intent: Intent?): Boolean {
        val data = intent?.data ?: return false
        val link = parse(data) ?: return false
        _pending.value = link
        return true
    }

    fun parse(uri: Uri): SocialDeepLink? {
        if (uri.scheme == "https" || uri.scheme == "http") {
            if (uri.host != "player.nekoh2o.top") return null
            val segments = uri.pathSegments
            if (segments.size >= 2 && segments[0] == "s") {
                val token = segments[1].takeIf { it.matches(Regex("[A-Za-z0-9_-]{16,64}")) }
                return token?.let { SocialDeepLink.Share(it) }
            }
            return null
        }
        if (uri.scheme != SCHEME) return null
        return when (uri.host) {
            "share" -> uri.getQueryParameter("token")
                ?.takeIf { it.matches(Regex("[A-Za-z0-9_-]{16,64}")) }
                ?.let { SocialDeepLink.Share(it) }
            "chat" -> {
                val peer = uri.getQueryParameter("peer").orEmpty().ifBlank {
                    uri.getQueryParameter("id").orEmpty()
                }
                peer.takeIf { it.isNotBlank() }?.let { SocialDeepLink.Chat(it) }
            }
            "user" -> uri.getQueryParameter("id")
                ?.takeIf { it.isNotBlank() }
                ?.let { SocialDeepLink.User(it) }
            else -> null
        }
    }

    fun consume() {
        _pending.value = null
    }
}

/** Activity 是否处于可见状态；后台推送服务据此抑制重复通知。 */
object AppVisibility {
    @Volatile var foreground: Boolean = false
        private set

    fun onStart() { foreground = true }
    fun onStop() { foreground = false }
}
