package top.nekoh2o.player

import android.app.Application
import android.util.Log
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import top.nekoh2o.player.data.cache.MusicCache
import top.nekoh2o.player.data.net.ApiFactory
import top.nekoh2o.player.data.net.CookieStore
import top.nekoh2o.player.data.repo.DownloadIndex
import top.nekoh2o.player.data.repo.KugouRepository
import top.nekoh2o.player.data.repo.LocalStore
import top.nekoh2o.player.data.repo.MusicRepository
import top.nekoh2o.player.diagnostics.CrashLog
import top.nekoh2o.player.i18n.NekoI18n

class PlayerApp : Application() {

    private val scopeHandler = CoroutineExceptionHandler { _, error ->
        Log.e(TAG, "后台初始化任务失败", error)
    }
    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO + scopeHandler)

    lateinit var localStore: LocalStore
        private set

    override fun onCreate() {
        super.onCreate()
        CrashLog.install(this)

        // 界面语言必须在 ViewModel 和任何界面文案之前初始化
        runCatching { NekoI18n.initialize(this) }
            .onFailure { Log.e(TAG, "语言初始化失败，使用默认语言", it) }
        // 缓存 / 下载索引损坏时不能阻止冷启动
        runCatching { MusicCache.init(this) }
            .onFailure { Log.e(TAG, "音乐缓存初始化失败，将直接读取网络或本地文件", it) }
        runCatching { DownloadIndex.init(this) }
            .onFailure { Log.e(TAG, "下载索引读取失败", it) }
        localStore = LocalStore(this)

        // 必须同步完成：PlayerViewModel 在构造时就会创建 Repository，
        // 直接访问 ApiFactory 的 lateinit 客户端。若放到后台协程里，
        // 冷启动时可能与界面初始化竞争并抛 UninitializedPropertyAccessException。
        runCatching { ApiFactory.init(this) }
            .onFailure { Log.e(TAG, "网络层初始化失败", it) }

        appScope.launch {
            runCatching { top.nekoh2o.player.data.plugins.PluginStore.initialize(this@PlayerApp) }
                .onFailure { Log.e(TAG, "音源插件初始化失败", it) }
        }

        // CookieStore 异步加载，拦截器在每次请求时读取 token
        appScope.launch {
            runCatching { CookieStore.init(this@PlayerApp) }
                .onFailure { Log.e(TAG, "登录凭据初始化失败", it) }

            // 确保网易云有游客 Cookie
            if (!CookieStore.hasAnyCookie()) {
                runCatching { MusicRepository().ensureGuestCookie() }
                    .onFailure { Log.w(TAG, "获取游客 Cookie 失败", it) }
            }

            // 确保酷狗有 dfid
            if (CookieStore.kgDfidValue().isEmpty()) {
                runCatching {
                    val dfid = KugouRepository().getDfid()
                    if (dfid != null) {
                        CookieStore.setKgDfid(dfid)
                    }
                }.onFailure { Log.w(TAG, "获取酷狗设备标识失败", it) }
            }
        }
    }

    companion object {
        private const val TAG = "PlayerApp"

        lateinit var instance: PlayerApp
            private set
    }

    init {
        @Suppress("LeakingThis")
        instance = this
    }
}
