package top.nekoh2o.player.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * 全屏播放等需要独占窗口的场景，置 true 时主框架隐藏侧边导航、底部导航与迷你播放器。
 */
object Immersive {
    var active by mutableStateOf(false)
}
