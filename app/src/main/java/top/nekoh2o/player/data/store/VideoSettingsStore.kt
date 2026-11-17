package top.nekoh2o.player.data.store

import android.content.Context
import com.google.gson.Gson
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** 弹幕可自定义项。默认值按 B 站网页端手感给。 */
data class DanmakuSettings(
    val enabled: Boolean = true,
    val opacity: Float = 1f,
    val fontScale: Float = 1f,
    val speed: Float = 1f,
    val area: Float = 0.75f,
    val density: Int = 120,
    val bold: Boolean = false,
    val strokeWidth: Float = 0.6f,
    val shadow: Boolean = true,
    val showScroll: Boolean = true,
    val showTop: Boolean = true,
    val showBottom: Boolean = true,
    val keepColor: Boolean = true,
    val smartOcclusion: Boolean = false,
    val mergeDuplicate: Boolean = true,
    val fontFamily: String = "system",
    val blockWords: List<String> = emptyList()
) {
    fun normalized(): DanmakuSettings = copy(
        opacity = opacity.coerceIn(0.15f, 1f),
        fontScale = fontScale.coerceIn(0.6f, 2f),
        speed = speed.coerceIn(0.4f, 2.2f),
        area = area.coerceIn(0.25f, 1f),
        density = density.coerceIn(20, 400),
        strokeWidth = strokeWidth.coerceIn(0f, 3f),
        blockWords = blockWords.map { it.trim() }.filter { it.isNotEmpty() }.distinct().take(100)
    )
}

/** 播放器可自定义项。 */
data class PlayerSettings(
    val defaultQuality: Int = 80,
    val defaultSpeed: Float = 1f,
    val doubleTapSeekSec: Int = 10,
    val longPressSpeed: Float = 2f,
    val autoFullscreen: Boolean = true,
    val autoPlayNext: Boolean = true,
    val rememberProgress: Boolean = true,
    val gestureSensitivity: Float = 1f,
    val autoHideControlsSec: Int = 3,
    val seekBarStyle: Int = 0
) {
    fun normalized(): PlayerSettings = copy(
        defaultSpeed = defaultSpeed.coerceIn(0.5f, 2f),
        doubleTapSeekSec = doubleTapSeekSec.coerceIn(5, 30),
        longPressSpeed = longPressSpeed.coerceIn(1.5f, 4f),
        gestureSensitivity = gestureSensitivity.coerceIn(0.5f, 2f),
        autoHideControlsSec = autoHideControlsSec.coerceIn(1, 10),
        seekBarStyle = seekBarStyle.coerceIn(0, 1)
    )
}

data class VideoSettings(
    val danmaku: DanmakuSettings = DanmakuSettings(),
    val player: PlayerSettings = PlayerSettings()
)

/**
 * 视频模块的本地偏好。与 `SettingsStore` 一样用 SharedPreferences + Gson 落地，
 * 但单独一个文件，避免和音乐设置互相影响。
 */
class VideoSettingsStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences("video_settings", Context.MODE_PRIVATE)
    private val gson = Gson()

    private val _state = MutableStateFlow(load())
    val state: StateFlow<VideoSettings> = _state.asStateFlow()

    fun load(): VideoSettings {
        val raw = prefs.getString(KEY, null) ?: return VideoSettings()
        return runCatching { gson.fromJson(raw, VideoSettings::class.java) }
            .getOrNull()
            ?.let { VideoSettings(it.danmaku.normalized(), it.player.normalized()) }
            ?: VideoSettings()
    }

    fun save(settings: VideoSettings) {
        val normalized = VideoSettings(settings.danmaku.normalized(), settings.player.normalized())
        prefs.edit().putString(KEY, gson.toJson(normalized)).apply()
        _state.value = normalized
    }

    fun update(block: (VideoSettings) -> VideoSettings) {
        save(block(_state.value))
    }

    fun resetDanmaku() {
        save(_state.value.copy(danmaku = DanmakuSettings()))
    }

    fun resetPlayer() {
        save(_state.value.copy(player = PlayerSettings()))
    }

    fun resetAll() {
        save(VideoSettings())
    }

    private companion object {
        const val KEY = "settings_json"
    }
}
