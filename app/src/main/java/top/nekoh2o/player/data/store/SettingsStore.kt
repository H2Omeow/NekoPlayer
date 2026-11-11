package top.nekoh2o.player.data.store

import android.content.Context
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import top.nekoh2o.player.data.model.AppSettings
import top.nekoh2o.player.data.model.AudioEffectEngine
import top.nekoh2o.player.data.model.AudioEffectSettings
import top.nekoh2o.player.data.model.BgSource
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.i18n.NekoI18n

class SettingsStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences("settings", Context.MODE_PRIVATE)

    private val gson = Gson()

    fun load(): AppSettings = AppSettings(
        globalBgEnabled = prefs.getBoolean(KEY_G_ENABLED, true),
        globalMaskAlpha = prefs.getFloat(KEY_G_MASK, 0.6f),
        globalBlurRadius = prefs.getInt(KEY_G_BLUR, 15),
        fpBgSource = runCatching {
            BgSource.valueOf(prefs.getString(KEY_FP_BG, BgSource.COVER.name)!!)
        }.getOrDefault(BgSource.COVER),
        fpMaskAlpha = prefs.getFloat(KEY_FP_MASK, 0.4f),
        fpBlurRadius = prefs.getInt(KEY_FP_BLUR, 20),
        cacheEnabled = prefs.getBoolean(KEY_CACHE_ENABLED, true),
        controlAlpha = prefs.getFloat(KEY_CTRL_ALPHA, 0.3f),
        playbackSpeed = prefs.getFloat(KEY_SPEED, 1.0f),
        fadePlayback = prefs.getBoolean(KEY_FADE_PLAYBACK, true),
        fadeMilliseconds = prefs.getInt(KEY_FADE_MS, 300).coerceIn(50, 2000),
        floatingLyricEnabled = prefs.getBoolean(KEY_FLOAT_LYRIC, false),
        floatingLyricDoubleRow = prefs.getBoolean(KEY_FLOAT_DOUBLE_ROW, false),
        floatingLyricShowTranslation = prefs.getBoolean(KEY_FLOAT_TRANSLATION, true),
        downloadDirUri = prefs.getString(KEY_DOWNLOAD_DIR, "") ?: "",
        audioQuality = prefs.getString(KEY_AUDIO_QUALITY, "exhigh") ?: "exhigh",
        landscapeMode = prefs.getBoolean(KEY_LANDSCAPE_MODE, false),
        uiScale = prefs.getFloat(KEY_UI_SCALE, 1.0f),
        audioEffects = AudioEffectSettings(
            engine = AudioEffectEngine.entries.getOrNull(prefs.getInt(KEY_AUDIO_ENGINE, 0))
                ?: AudioEffectEngine.NONE,
            eqBands = prefs.getString(KEY_EQ_BANDS, null)?.split(",")
                ?.map { it.toFloatOrNull() ?: 0f } ?: List(10) { 0f },
            eqPresetName = prefs.getString(KEY_EQ_PRESET, "") ?: "",
            bassBoost = prefs.getInt(KEY_BASS_BOOST, 0),
            virtualizer = prefs.getInt(KEY_VIRTUALIZER, 0),
            reverbWet = prefs.getInt(KEY_REVERB_WET, 0),
            reverbRoomSize = prefs.getInt(KEY_REVERB_ROOM, 50),
            reverbDamping = prefs.getInt(KEY_REVERB_DAMP, 30),
            loudnessGain = prefs.getInt(KEY_LOUDNESS, 0),
            masteringPresetId = prefs.getInt(KEY_MASTERING_PRESET, 0),
            masteringMix = prefs.getInt(KEY_MASTERING_MIX, 100)
        ).normalized(),
        customFontPath = prefs.getString(KEY_CUSTOM_FONT, "") ?: "",
        customFontName = prefs.getString(KEY_CUSTOM_FONT_NAME, "") ?: "",
        socialPushEnabled = prefs.getBoolean(KEY_SOCIAL_PUSH, true),
        language = prefs.getString(KEY_LANGUAGE, NekoI18n.SYSTEM) ?: NekoI18n.SYSTEM
    )

    fun save(s: AppSettings) {
        prefs.edit()
            .putBoolean(KEY_G_ENABLED, s.globalBgEnabled)
            .putFloat(KEY_G_MASK, s.globalMaskAlpha)
            .putInt(KEY_G_BLUR, s.globalBlurRadius)
            .putString(KEY_FP_BG, s.fpBgSource.name)
            .putFloat(KEY_FP_MASK, s.fpMaskAlpha)
            .putInt(KEY_FP_BLUR, s.fpBlurRadius)
            .putBoolean(KEY_CACHE_ENABLED, s.cacheEnabled)
            .putFloat(KEY_CTRL_ALPHA, s.controlAlpha)
            .putFloat(KEY_SPEED, s.playbackSpeed)
            .putBoolean(KEY_FADE_PLAYBACK, s.fadePlayback)
            .putInt(KEY_FADE_MS, s.fadeMilliseconds.coerceIn(50, 2000))
            .putBoolean(KEY_FLOAT_LYRIC, s.floatingLyricEnabled)
            .putBoolean(KEY_FLOAT_DOUBLE_ROW, s.floatingLyricDoubleRow)
            .putBoolean(KEY_FLOAT_TRANSLATION, s.floatingLyricShowTranslation)
            .putString(KEY_DOWNLOAD_DIR, s.downloadDirUri)
            .putString(KEY_AUDIO_QUALITY, s.audioQuality)
            .putBoolean(KEY_LANDSCAPE_MODE, s.landscapeMode)
            .putFloat(KEY_UI_SCALE, s.uiScale)
            .putInt(KEY_AUDIO_ENGINE, s.audioEffects.engine.value)
            .putString(KEY_EQ_BANDS, s.audioEffects.eqBands.joinToString(","))
            .putString(KEY_EQ_PRESET, s.audioEffects.eqPresetName)
            .putInt(KEY_BASS_BOOST, s.audioEffects.bassBoost)
            .putInt(KEY_VIRTUALIZER, s.audioEffects.virtualizer)
            .putInt(KEY_REVERB_WET, s.audioEffects.reverbWet)
            .putInt(KEY_REVERB_ROOM, s.audioEffects.reverbRoomSize)
            .putInt(KEY_REVERB_DAMP, s.audioEffects.reverbDamping)
            .putInt(KEY_LOUDNESS, s.audioEffects.loudnessGain)
            .putInt(KEY_MASTERING_PRESET, s.audioEffects.masteringPresetId)
            .putInt(KEY_MASTERING_MIX, s.audioEffects.masteringMix)
            .putString(KEY_CUSTOM_FONT, s.customFontPath)
            .putString(KEY_CUSTOM_FONT_NAME, s.customFontName)
            .putBoolean(KEY_SOCIAL_PUSH, s.socialPushEnabled)
            .putString(KEY_LANGUAGE, s.language)
            .apply()
    }

    companion object {
        private const val KEY_G_ENABLED = "g_bg_enabled"
        private const val KEY_G_MASK = "g_mask"
        private const val KEY_G_BLUR = "g_blur"
        private const val KEY_FP_BG = "fp_bg"
        private const val KEY_FP_MASK = "fp_mask"
        private const val KEY_FP_BLUR = "fp_blur"
        private const val KEY_CACHE_ENABLED = "cache_enabled"
        private const val KEY_CTRL_ALPHA = "ctrl_alpha"
        private const val KEY_SPEED = "playback_speed"
        private const val KEY_FADE_PLAYBACK = "fade_playback"
        private const val KEY_FADE_MS = "fade_milliseconds"
        private const val KEY_FLOAT_LYRIC = "floating_lyric"
        private const val KEY_FLOAT_DOUBLE_ROW = "floating_double_row"
        private const val KEY_FLOAT_TRANSLATION = "floating_translation"
        private const val KEY_DOWNLOAD_DIR = "download_dir_uri"
        private const val KEY_AUDIO_QUALITY = "audio_quality"
        private const val KEY_LANDSCAPE_MODE = "landscape_mode"
        private const val KEY_UI_SCALE = "ui_scale"
        private const val KEY_AUDIO_ENGINE = "audio_engine"
        private const val KEY_EQ_BANDS = "eq_bands"
        private const val KEY_EQ_PRESET = "eq_preset"
        private const val KEY_BASS_BOOST = "bass_boost"
        private const val KEY_VIRTUALIZER = "virtualizer"
        private const val KEY_REVERB_WET = "reverb_wet"
        private const val KEY_REVERB_ROOM = "reverb_room_size"
        private const val KEY_REVERB_DAMP = "reverb_damping"
        private const val KEY_LOUDNESS = "loudness_gain"
        private const val KEY_MASTERING_PRESET = "mastering_preset_id"
        private const val KEY_MASTERING_MIX = "mastering_mix"
        private const val KEY_CUSTOM_FONT = "custom_font_path"
        private const val KEY_CUSTOM_FONT_NAME = "custom_font_name"
        private const val KEY_SOCIAL_PUSH = "social_push_enabled"
        private const val KEY_LANGUAGE = "language_tag"

        // 播放状态保存
        private const val KEY_PLAY_QUEUE = "play_queue"
        private const val KEY_PLAY_INDEX = "play_index"
        private const val KEY_PLAY_POSITION = "play_position"
    }

    // ==================== 播放状态保存/恢复 ====================

    data class PlaybackState(
        val queue: List<Song>,
        val currentIndex: Int,
        val position: Long
    )

    fun savePlaybackState(queue: List<Song>, currentIndex: Int, position: Long) {
        val json = gson.toJson(queue)
        android.util.Log.d("SettingsStore", "保存播放状态到 SharedPreferences：队列 ${queue.size} 首，JSON 长度 ${json.length}")
        prefs.edit()
            .putString(KEY_PLAY_QUEUE, json)
            .putInt(KEY_PLAY_INDEX, currentIndex)
            .putLong(KEY_PLAY_POSITION, position)
            .apply()
        android.util.Log.d("SettingsStore", "播放状态已写入 SharedPreferences")
    }

    fun loadPlaybackState(): PlaybackState? {
        val json = prefs.getString(KEY_PLAY_QUEUE, null)
        if (json == null) {
            android.util.Log.d("SettingsStore", "SharedPreferences 中没有保存的队列")
            return null
        }
        val index = prefs.getInt(KEY_PLAY_INDEX, 0)
        val position = prefs.getLong(KEY_PLAY_POSITION, 0)

        android.util.Log.d("SettingsStore", "从 SharedPreferences 读取播放状态：JSON 长度 ${json.length}，索引 $index，进度 $position")
        return try {
            val type = object : TypeToken<List<Song>>() {}.type
            val queue: List<Song> = gson.fromJson(json, type)
            if (queue.isEmpty()) {
                android.util.Log.w("SettingsStore", "解析后的队列为空")
                null
            } else {
                android.util.Log.d("SettingsStore", "成功解析播放状态：队列 ${queue.size} 首")
                PlaybackState(queue, index, position)
            }
        } catch (e: Exception) {
            android.util.Log.e("SettingsStore", "解析播放状态失败", e)
            null
        }
    }

    fun clearPlaybackState() {
        prefs.edit()
            .remove(KEY_PLAY_QUEUE)
            .remove(KEY_PLAY_INDEX)
            .remove(KEY_PLAY_POSITION)
            .apply()
    }
}
