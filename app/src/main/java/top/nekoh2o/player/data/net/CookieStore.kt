package top.nekoh2o.player.data.net

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

private val Context.dataStore by preferencesDataStore("player_prefs")

/**
 * 网易云 cookie 管理 + 酷狗 token + SSO app_token：
 * - userCookie：网易云QR/手动登录得到，优先使用（对应 web napcat_nc_cookie）
 * - guestCookie：网易云首启拉 /register/anonimous 兜底（对应 nc_guest_cookie）
 * - kgToken：酷狗音乐登录token
 * - kgPlatform：酷狗音乐平台类型（0=原版，1=概念版）
 * - level：音质档位
 * - appToken：SSO 登录后服务端下发的 Bearer token，App 用它鉴权 player 域名接口
 * 除 DataStore 落地外，额外用内存缓存，供拦截器/播放线程同步读取。
 */
object CookieStore {

    private val KEY_USER = stringPreferencesKey("nc_cookie")
    private val KEY_GUEST = stringPreferencesKey("nc_guest_cookie")
    private val KEY_LEVEL = stringPreferencesKey("quality_level")
    private val KEY_APP_TOKEN = stringPreferencesKey("app_token")
    private val KEY_KG_TOKEN = stringPreferencesKey("kg_token")
    private val KEY_KG_PLATFORM = stringPreferencesKey("kg_platform")
    private val KEY_KG_USERID = stringPreferencesKey("kg_userid")
    private val KEY_KG_DFID = stringPreferencesKey("kg_dfid")

    lateinit var kgSessions: KugouSessionStore
        private set

    private lateinit var appContext: Context
    @Volatile private var userCookie: String = ""
    @Volatile private var guestCookie: String = ""
    @Volatile private var appToken: String = ""
    @Volatile private var kgPlatform: String = "0"  // 0=原版，1=概念版
    @Volatile var level: String = "exhigh"
        private set
    private val ready = CompletableDeferred<Unit>()
    private val initMutex = Mutex()

    suspend fun init(context: Context) {
        initMutex.withLock {
            if (ready.isCompleted) return

            appContext = context.applicationContext
            var user = ""
            var guest = ""
            var token = ""
            var platform = "0"
            var quality = "exhigh"
            var kgToken = ""
            var kgUser = ""
            var kgDfid = ""
            try {
                val prefs = appContext.dataStore.data.first()
                user = prefs[KEY_USER] ?: ""
                guest = prefs[KEY_GUEST] ?: ""
                token = prefs[KEY_APP_TOKEN] ?: ""
                platform = prefs[KEY_KG_PLATFORM] ?: "0"
                quality = prefs[KEY_LEVEL] ?: "exhigh"
                kgToken = prefs[KEY_KG_TOKEN].orEmpty()
                kgUser = prefs[KEY_KG_USERID].orEmpty()
                kgDfid = prefs[KEY_KG_DFID].orEmpty()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // 数据文件损坏 / 磁盘暂时不可读时用空凭据继续启动，避免每次冷启动都闪退
                android.util.Log.e("CookieStore", "读取本地凭据失败，以空凭据继续启动", e)
            }

            userCookie = user
            guestCookie = guest
            appToken = token
            kgPlatform = platform
            level = quality
            runCatching {
                kgSessions = KugouSessionStore(
                    AndroidProviderPreferences(
                        appContext.getSharedPreferences("kugou_sessions", Context.MODE_PRIVATE)
                    )
                )
                kgSessions.migrate(kgPlatformValue(), kgToken, kgUser, kgDfid)
            }.onFailure { error ->
                android.util.Log.e("CookieStore", "酷狗登录状态初始化失败", error)
                if (!this::kgSessions.isInitialized) {
                    runCatching {
                        kgSessions = KugouSessionStore(
                            AndroidProviderPreferences(
                                appContext.getSharedPreferences("kugou_sessions", Context.MODE_PRIVATE)
                            )
                        )
                    }
                }
            }
            ready.complete(Unit)
        }
    }

    suspend fun awaitReady() {
        ready.await()
    }

    // 播放线程同步读取：用户 cookie 优先，否则游客 cookie
    fun activeCookie(): String = userCookie.ifEmpty { guestCookie }

    // 仅用户 cookie（用于云端同步，不含游客）
    fun userCookieValue(): String = userCookie

    suspend fun setUserCookie(cookie: String) {
        userCookie = cookie
        appContext.dataStore.edit { it[KEY_USER] = cookie }
    }

    suspend fun setGuestCookie(cookie: String) {
        guestCookie = cookie
        appContext.dataStore.edit { it[KEY_GUEST] = cookie }
    }

    suspend fun setLevel(value: String) {
        level = value
        appContext.dataStore.edit { it[KEY_LEVEL] = value }
    }

    fun hasAnyCookie(): Boolean = activeCookie().isNotEmpty()

    fun hasNcUserCookie(): Boolean = userCookie.isNotEmpty()

    // ==================== SSO app_token ====================
    fun appTokenValue(): String {
        return appToken
    }

    suspend fun setAppToken(token: String) {
        appToken = token
        appContext.dataStore.edit { it[KEY_APP_TOKEN] = token }
    }

    suspend fun clearAppToken() {
        appToken = ""
        appContext.dataStore.edit { it.remove(KEY_APP_TOKEN) }
    }

    // KuGou credentials are scoped to a backend platform. Device cookies survive logout.
    fun kgTokenValue(platform: Int = kgPlatformValue()): String = kgSessions.value(platform, "token")
    suspend fun setKgToken(token: String) = kgSessions.merge(kgPlatformValue(), mapOf("token" to token))
    suspend fun clearKgToken() = kgSessions.clearLogin(kgPlatformValue())
    fun hasKgToken(): Boolean = kgTokenValue().isNotEmpty()
    fun kgPlatformValue(): Int = kgPlatform.toIntOrNull()?.takeIf { it in 0..1 } ?: 0

    suspend fun setKgPlatform(platform: Int) {
        require(platform in 0..1)
        kgPlatform = platform.toString()
        appContext.dataStore.edit { it[KEY_KG_PLATFORM] = kgPlatform }
    }

    fun kgUseridValue(platform: Int = kgPlatformValue()): String = kgSessions.value(platform, "userid")
    suspend fun setKgUserid(userid: String) = kgSessions.merge(kgPlatformValue(), mapOf("userid" to userid))
    fun kgDfidValue(platform: Int = kgPlatformValue()): String = kgSessions.value(platform, "dfid")
    suspend fun setKgDfid(dfid: String) {
        if (dfid.isNotBlank()) kgSessions.merge(kgPlatformValue(), mapOf("dfid" to dfid))
    }
    fun kgCookieValue(platform: Int = kgPlatformValue()): String = kgSessions.cookie(platform)
}
