package top.nekoh2o.player

import android.app.Application
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
import top.nekoh2o.player.i18n.NekoI18n

class PlayerApp : Application() {

    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    lateinit var localStore: LocalStore
        private set

    override fun onCreate() {
        super.onCreate()

        // 界面语言必须在 ViewModel 和任何界面文案之前初始化
        NekoI18n.initialize(this)
        MusicCache.init(this)
        DownloadIndex.init(this)
        localStore = LocalStore(this)
        appScope.launch {
            runCatching { top.nekoh2o.player.data.plugins.PluginStore.initialize(this@PlayerApp) }
        }

        // CookieStore 必须先初始化完成，ApiFactory 的拦截器才能读到正确的 token
        appScope.launch {
            CookieStore.init(this@PlayerApp)

            // CookieStore 加载完成后再初始化 ApiFactory，确保拦截器能读到已保存的 token
            ApiFactory.init(this@PlayerApp)

            // 确保网易云有游客 Cookie
            if (!CookieStore.hasAnyCookie()) {
                MusicRepository().ensureGuestCookie()
            }

            // 确保酷狗有 dfid
            if (CookieStore.kgDfidValue().isEmpty()) {
                val dfid = KugouRepository().getDfid()
                if (dfid != null) {
                    CookieStore.setKgDfid(dfid)
                }
            }
        }
    }

    companion object {
        lateinit var instance: PlayerApp
            private set
    }

    init {
        @Suppress("LeakingThis")
        instance = this
    }
}
