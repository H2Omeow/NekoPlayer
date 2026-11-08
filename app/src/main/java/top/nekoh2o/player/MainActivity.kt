package top.nekoh2o.player

import android.Manifest
import android.content.Intent
import android.content.pm.ActivityInfo
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import top.nekoh2o.player.ui.PlayerViewModel
import top.nekoh2o.player.ui.nav.MainScaffold
import top.nekoh2o.player.ui.social.ShareSongSheet
import top.nekoh2o.player.ui.theme.CustomFont
import top.nekoh2o.player.ui.theme.NekoTheme
import top.nekoh2o.player.social.SocialPushService

class MainActivity : ComponentActivity() {

    private val vm: PlayerViewModel by viewModels()

    private val notifPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        // 冷启动时若由深链拉起（浏览器登录完成回跳），处理携带的 token
        handleAuthDeepLink(intent)
        SocialDeepLinks.handle(intent)
        setContent {
            val state by vm.ui.collectAsState()

            LaunchedEffect(state.loggedIn, state.settings.socialPushEnabled) {
                if (state.loggedIn && state.settings.socialPushEnabled) {
                    SocialPushService.start(applicationContext)
                } else {
                    SocialPushService.stop(applicationContext)
                }
            }

            // 根据横屏模式设置锁定屏幕方向
            LaunchedEffect(state.settings.landscapeMode) {
                requestedOrientation = if (state.settings.landscapeMode) {
                    ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                } else {
                    ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                }
            }

            // 壁纸开启且已拿到图时才让控件透明，否则白字会落到纯色底上
            val translucent = state.settings.globalBgEnabled && state.wallpaperUrl != null
            val customFont = remember(state.settings.customFontPath) {
                CustomFont.load(state.settings.customFontPath)
            }

            NekoTheme(
                controlAlpha = state.settings.controlAlpha,
                translucent = translucent,
                uiScale = state.settings.uiScale,
                customFont = customFont
            ) {
                var fullPlayer by remember { mutableStateOf(false) }

                // 全屏播放器打开时，把主界面整棵子树从无障碍树中移除，
                // 否则 TalkBack 仍会朗读被遮住的主界面内容，需多次切换才能到达全屏播放器。
                Box(
                    Modifier.then(
                        if (fullPlayer) Modifier.clearAndSetSemantics { } else Modifier
                    )
                ) {
                    MainScaffold(
                        vm = vm,
                        onOpenFullPlayer = { fullPlayer = true },
                        onStartSsoLogin = { startSsoLogin() }
                    )
                }

                AnimatedVisibility(
                    visible = fullPlayer,
                    enter = slideInVertically { it },
                    exit = slideOutVertically { it }
                ) {
                    top.nekoh2o.player.ui.screens.FullPlayerScreen(
                        vm = vm,
                        onClose = { fullPlayer = false }
                    )
                }
                if (fullPlayer) BackHandler { fullPlayer = false }

                // 分享弹窗放在最上层，歌曲列表、聊天和全屏播放器共用
                ShareSongSheet(vm)
            }
        }
    }

    // 回到前台时检查云同步（同步层自带 60 秒节流，未登录则忽略）
    override fun onStart() {
        super.onStart()
        AppVisibility.onStart()
        vm.onAppForeground()
        val state = vm.ui.value
        if (state.loggedIn && state.settings.socialPushEnabled) {
            SocialPushService.start(applicationContext)
        }
    }

    override fun onStop() {
        AppVisibility.onStop()
        super.onStop()
    }

    // 已在栈顶（singleTop）时，回跳深链通过 onNewIntent 送达
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAuthDeepLink(intent)
        SocialDeepLinks.handle(intent)
    }

    // 跳转系统浏览器打开账户中心登录，登录完成后账户中心 302 回跳 nekoplayer://auth?token=<JWT>
    private fun startSsoLogin() {
        val redirect = Uri.encode("$AUTH_SCHEME://$AUTH_HOST")
        val loginUrl = "$ACCOUNT_CENTER/login?redirect=$redirect"
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(loginUrl)))
        } catch (e: Exception) {
            Toast.makeText(this, "无法打开浏览器", Toast.LENGTH_SHORT).show()
        }
    }

    // 解析回跳深链，取出 JWT 交给 ViewModel 完成登录
    private fun handleAuthDeepLink(intent: Intent?) {
        val data = intent?.data ?: return
        if (data.scheme != AUTH_SCHEME || data.host != AUTH_HOST) return
        val token = data.getQueryParameter("token")
        if (!token.isNullOrEmpty()) {
            vm.onSsoTokenReceived(token)
            Toast.makeText(this, "登录成功", Toast.LENGTH_SHORT).show()
        }
    }

    companion object {
        private const val ACCOUNT_CENTER = "https://account.nekoh2o.top"
        private const val AUTH_SCHEME = "nekoplayer"
        private const val AUTH_HOST = "auth"
    }
}
