package top.nekoh2o.player.ui.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import top.nekoh2o.player.data.model.AppSettings
import top.nekoh2o.player.data.model.BgSource
import top.nekoh2o.player.data.store.SettingsStore

/**
 * 设置管理 ViewModel
 * 负责：个性化设置（背景、模糊、透明度、横屏、UI缩放）、悬浮窗歌词设置、倍速控制
 */
class SettingsViewModel(app: Application) : AndroidViewModel(app) {

    private val settingsStore = SettingsStore(app)

    /**
     * 加载当前设置
     */
    fun loadSettings(): AppSettings {
        return settingsStore.load()
    }

    /**
     * 保存设置
     */
    fun saveSettings(settings: AppSettings) {
        settingsStore.save(settings)
    }

    // ==================== 全局背景设置 ====================

    fun setGlobalBgEnabled(enabled: Boolean, current: AppSettings): AppSettings {
        val updated = current.copy(globalBgEnabled = enabled)
        settingsStore.save(updated)
        return updated
    }

    fun setGlobalMaskAlpha(alpha: Float, current: AppSettings): AppSettings {
        val updated = current.copy(globalMaskAlpha = alpha)
        settingsStore.save(updated)
        return updated
    }

    fun setGlobalBlurRadius(radius: Int, current: AppSettings): AppSettings {
        val updated = current.copy(globalBlurRadius = radius)
        settingsStore.save(updated)
        return updated
    }

    // ==================== 全屏播放器背景设置 ====================

    fun setFpBgSource(source: BgSource, current: AppSettings): AppSettings {
        val updated = current.copy(fpBgSource = source)
        settingsStore.save(updated)
        return updated
    }

    fun setFpMaskAlpha(alpha: Float, current: AppSettings): AppSettings {
        val updated = current.copy(fpMaskAlpha = alpha)
        settingsStore.save(updated)
        return updated
    }

    fun setFpBlurRadius(radius: Int, current: AppSettings): AppSettings {
        val updated = current.copy(fpBlurRadius = radius)
        settingsStore.save(updated)
        return updated
    }

    // ==================== 缓存设置 ====================

    fun setCacheEnabled(enabled: Boolean, current: AppSettings): AppSettings {
        val updated = current.copy(cacheEnabled = enabled)
        settingsStore.save(updated)
        return updated
    }

    fun setSocialPushEnabled(enabled: Boolean, current: AppSettings): AppSettings {
        val updated = current.copy(socialPushEnabled = enabled)
        settingsStore.save(updated)
        return updated
    }

    // ==================== 控件透明度 ====================

    fun setControlAlpha(alpha: Float, current: AppSettings): AppSettings {
        val updated = current.copy(controlAlpha = alpha)
        settingsStore.save(updated)
        return updated
    }

    // ==================== 播放倍速 ====================

    fun setPlaybackSpeed(speed: Float, current: AppSettings): AppSettings {
        val updated = current.copy(playbackSpeed = speed)
        settingsStore.save(updated)
        return updated
    }

    // ==================== 悬浮窗歌词设置 ====================

    fun setFloatingLyricEnabled(enabled: Boolean, current: AppSettings): AppSettings {
        val updated = current.copy(floatingLyricEnabled = enabled)
        settingsStore.save(updated)
        return updated
    }

    fun setFloatingLyricDoubleRow(enabled: Boolean, current: AppSettings): AppSettings {
        val updated = current.copy(floatingLyricDoubleRow = enabled)
        settingsStore.save(updated)
        return updated
    }

    fun setFloatingLyricShowTranslation(enabled: Boolean, current: AppSettings): AppSettings {
        val updated = current.copy(floatingLyricShowTranslation = enabled)
        settingsStore.save(updated)
        return updated
    }

    // ==================== 下载目录 ====================

    fun setDownloadDir(uri: String, current: AppSettings): AppSettings {
        val updated = current.copy(downloadDirUri = uri)
        settingsStore.save(updated)
        return updated
    }

    // ==================== 音质设置 ====================

    fun setAudioQuality(quality: String, current: AppSettings): AppSettings {
        val updated = current.copy(audioQuality = quality)
        settingsStore.save(updated)
        return updated
    }

    // ==================== 横屏模式 ====================

    fun setLandscapeMode(enabled: Boolean, current: AppSettings): AppSettings {
        val updated = current.copy(landscapeMode = enabled)
        settingsStore.save(updated)
        return updated
    }

    // ==================== UI 缩放 ====================

    fun setUiScale(scale: Float, current: AppSettings): AppSettings {
        val clamped = scale.coerceIn(0.8f, 1.3f)
        val updated = current.copy(uiScale = clamped)
        settingsStore.save(updated)
        return updated
    }

    // ==================== 自定义字体 ====================

    fun setCustomFontPath(
        path: String,
        name: String,
        current: AppSettings
    ): AppSettings {
        val updated = current.copy(customFontPath = path, customFontName = name)
        settingsStore.save(updated)
        return updated
    }
}
