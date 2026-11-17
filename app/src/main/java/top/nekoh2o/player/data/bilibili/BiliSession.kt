package top.nekoh2o.player.data.bilibili

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * B 站登录态。
 *
 * Cookie 只保存在应用私有目录（`getSharedPreferences`，其它应用读不到）；
 * 这里刻意不写网络请求：宿主只负责存/取，Cookie 由 [BiliClient] 显式塞进请求头，
 * 与桌面端"插件不带 Cookie 罐"的约束保持一致。
 */
object BiliSession {

    private const val PREFS = "bilibili_session"
    private const val KEY_COOKIE = "cookie"
    private const val KEY_MID = "mid"
    private const val KEY_NAME = "name"
    private const val KEY_FACE = "face"

    private var prefs: SharedPreferences? = null

    private val _account = MutableStateFlow(BiliAccount())
    val account: StateFlow<BiliAccount> = _account.asStateFlow()

    fun init(context: Context) {
        if (prefs != null) return
        val p = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs = p
        _account.value = BiliAccount(
            mid = p.getLong(KEY_MID, 0),
            name = p.getString(KEY_NAME, "").orEmpty(),
            face = p.getString(KEY_FACE, "").orEmpty(),
            isLogin = !p.getString(KEY_COOKIE, "").isNullOrEmpty()
        )
    }

    fun isLogin(): Boolean = _account.value.isLogin

    fun cookieHeader(): String = prefs?.getString(KEY_COOKIE, "").orEmpty()

    /** 发弹幕/点赞需要的 csrf，就是 bili_jct。 */
    fun csrf(): String = cookieValue("bili_jct")

    fun cookieValue(key: String): String {
        val raw = cookieHeader()
        if (raw.isEmpty()) return ""
        return raw.split(';').map { it.trim() }.firstOrNull { it.startsWith("$key=") }
            ?.substringAfter('=').orEmpty()
    }

    /** 把 Set-Cookie 里需要的字段并进现有 Cookie（保留 buvid3 之类的设备标识）。 */
    fun mergeCookies(incoming: Map<String, String>) {
        val merged = linkedMapOf<String, String>()
        cookieHeader().split(';').map { it.trim() }.filter { it.contains('=') }.forEach {
            merged[it.substringBefore('=')] = it.substringAfter('=')
        }
        incoming.forEach { (k, v) -> if (v.isNotEmpty()) merged[k] = v }
        val cookie = merged.entries.joinToString("; ") { "${it.key}=${it.value}" }
        saveCookie(cookie)
    }

    fun importCookie(raw: String) {
        val cookie = raw.trim().removePrefix("Cookie:").trim()
        saveCookie(cookie)
        val mid = cookieValue("DedeUserID").toLongOrNull() ?: 0
        val updated = _account.value.copy(mid = mid, isLogin = cookie.isNotEmpty())
        _account.value = updated
        prefs?.edit()?.putLong(KEY_MID, mid)?.apply()
    }

    fun updateProfile(mid: Long, name: String, face: String) {
        val updated = _account.value.copy(mid = mid, name = name, face = face)
        _account.value = updated
        prefs?.edit()?.putLong(KEY_MID, mid)?.putString(KEY_NAME, name)?.putString(KEY_FACE, face)?.apply()
    }

    private fun saveCookie(cookie: String) {
        prefs?.edit()?.putString(KEY_COOKIE, cookie)?.apply()
        if (_account.value.isLogin != cookie.isNotEmpty()) {
            _account.value = _account.value.copy(isLogin = cookie.isNotEmpty())
        }
    }

    fun logout() {
        prefs?.edit()?.clear()?.apply()
        _account.value = BiliAccount()
    }

    /** 供测试/调试：当前 Cookie 的键名集合。 */
    fun cookieKeys(): Set<String> =
        cookieHeader().split(';').map { it.trim().substringBefore('=') }.filter { it.isNotEmpty() }.toSet()
}
