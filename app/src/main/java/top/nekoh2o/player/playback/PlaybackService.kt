package top.nekoh2o.player.playback

import top.nekoh2o.player.i18n.NekoI18n.tr

import top.nekoh2o.player.data.net.CookieStore

import android.content.Intent
import android.net.Uri
import androidx.media3.common.AudioAttributes
import androidx.media3.common.AuxEffectInfo
import androidx.media3.common.C
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.Player
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.RenderersFactory
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.audio.MediaCodecAudioRenderer
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.video.MediaCodecVideoRenderer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import kotlinx.coroutines.runBlocking
import top.nekoh2o.player.audio.NativeAudioProcessor
import top.nekoh2o.player.audio.SystemAudioEffectsManager
import top.nekoh2o.player.data.cache.MusicCache
import top.nekoh2o.player.data.model.AudioEffectEngine
import top.nekoh2o.player.data.model.AudioEffectSettings
import top.nekoh2o.player.data.repo.DownloadIndex
import top.nekoh2o.player.data.repo.MusicRepository
import top.nekoh2o.player.data.store.SettingsStore
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.File
import kotlin.math.max

@UnstableApi
class PlaybackService : MediaSessionService() {

    private var mediaSession: MediaSession? = null
    private var exoPlayer: ExoPlayer? = null
    private val fadeHandler = Handler(Looper.getMainLooper())
    private var fadeRunnable: Runnable? = null
    private var fadeToken = 0
    private var fadeMode = FadeMode.NONE
    private var pendingFadeIn = false
    private var userVolume = 1f
    private val repo = MusicRepository()
    private var audioEffectsManager: SystemAudioEffectsManager? = null
    private var nativeAudioProcessor: NativeAudioProcessor? = null
    private var effectsSessionId = C.AUDIO_SESSION_ID_UNSET

    override fun onCreate() {
        super.onCreate()

        // 缓存数据库损坏时必须继续提供播放能力，否则 MediaController 连接失败会导致应用启动闪退
        runCatching { MusicCache.init(this) }
            .onFailure { Log.e(TAG, "音乐缓存初始化失败，本次启动不启用缓存", it) }

        val httpFactory = DefaultHttpDataSource.Factory()
            .setUserAgent("NekoPlayer/1.0")
            .setAllowCrossProtocolRedirects(true)

        // 上游使用 DefaultDataSource，同时支持网络、file:// 与 content:// URI。
        val localAndHttpFactory = DefaultDataSource.Factory(this, httpFactory)
        val cacheFactory = MusicCache.dataSourceFactory(localAndHttpFactory)
        val settingsStore = SettingsStore(this)

        val playbackFactory = androidx.media3.datasource.DataSource.Factory {
            if (settingsStore.load().cacheEnabled) {
                runCatching { cacheFactory.createDataSource() }
                    .getOrElse { localAndHttpFactory.createDataSource() }
            } else {
                localAndHttpFactory.createDataSource()
            }
        }
        val resolvingFactory = ResolvingDataSource.Factory(playbackFactory) { dataSpec ->
            val raw = dataSpec.uri.toString()

            if (!raw.startsWith("neko:")) return@Factory dataSpec

            val song = SongPlaybackUri.decode(dataSpec.uri) ?: return@Factory dataSpec
            val key = MusicCache.cacheKeyForSong(song)

            // 已下载文件优先直读。兼容旧版本保存的裸绝对路径。
            DownloadIndex.get(song)?.let { downloaded ->
                normalizeReadableUri(downloaded.audioUri)?.let { localUri ->
                    return@Factory dataSpec.buildUpon()
                        .setUri(localUri)
                        .setKey("download:" + key)
                        .build()
                }
            }

            val audio = try { runBlocking {
                top.nekoh2o.player.data.repo.SongQualityRepository().resolvePlayback(song, CookieStore.level)
            } } catch (e: Exception) {
                if (settingsStore.load().cacheEnabled) {
                    MusicCache.offlineKey(song, CookieStore.level)?.let { cached ->
                        return@Factory dataSpec.buildUpon().setKey(cached).build()
                    }
                }
                throw java.io.IOException(e.message ?: tr("歌曲音质查询失败"), e)
            }
            if (audio == null) throw java.io.IOException(tr("当前账号没有该歌曲的可播放音质"))
            val qualityKey = key + ":quality:" + audio.quality.id
            dataSpec.buildUpon().setUri(Uri.parse(audio.url)).setKey(qualityKey)
                .setHttpRequestHeaders(dataSpec.httpRequestHeaders + audio.headers).build()
        }

        val player = ExoPlayer.Builder(this)
            .setRenderersFactory(createRenderersFactory())
            .setMediaSourceFactory(
                DefaultMediaSourceFactory(resolvingFactory)
            )
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .build(),
                true
            )
            .setHandleAudioBecomingNoisy(true)
            // 网络播放时持有 WifiLock + WakeLock，避免 CPU/WiFi 休眠导致后台断流
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .build()
        exoPlayer = player
        userVolume = player.volume

        player.addListener(object : Player.Listener {
            override fun onAudioSessionIdChanged(audioSessionId: Int) {
                runCatching { initAudioEffects(audioSessionId) }
                    .onFailure { Log.e(TAG, "初始化系统音效失败", it) }
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_READY && audioEffectsManager == null) {
                    runCatching { initAudioEffects(player.audioSessionId) }
                        .onFailure { Log.e(TAG, "初始化系统音效失败", it) }
                }
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (isPlaying && pendingFadeIn) {
                    startFadeIn(fadeDuration())
                } else if (!isPlaying && pendingFadeIn) {
                    // 还没真正开始出声就结束（例如加载失败），恢复用户音量。
                    pendingFadeIn = false
                    cancelFade(resetVolume = true)
                }
            }

            override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                pendingFadeIn = false
                cancelFade(resetVolume = true)
            }
        })

        // MediaSession 使用包装后的播放器，使通知栏、耳机按键和蓝牙控制
        // 与界面按钮走同一套淡入淡出逻辑。
        val fadingPlayer = object : ForwardingPlayer(player) {
            override fun play() = requestPlay()

            override fun pause() = requestPause()

            override fun setPlayWhenReady(playWhenReady: Boolean) {
                if (playWhenReady) requestPlay() else requestPause()
            }

            override fun setVolume(volume: Float) {
                userVolume = volume.coerceIn(0f, 1f)
                cancelFade(resetVolume = true)
                player.volume = userVolume
            }

            override fun getVolume(): Float = userVolume
        }

        val session = runCatching { MediaSession.Builder(this, fadingPlayer).build() }
            .onFailure { error ->
                Log.e(TAG, "创建媒体会话失败", error)
                runCatching { player.release() }
                exoPlayer = null
            }
            .getOrNull()
        mediaSession = session
        if (session == null) {
            // 连接方会收到失败并自行重试，不能在这里抛异常导致整个进程崩溃
            stopSelf()
        }
    }

    // ==================== 播放 / 暂停淡入淡出 ====================

    private enum class FadeMode { NONE, IN, OUT }

    private fun fadeDuration(): Int =
        SettingsStore(this).load().fadeMilliseconds.coerceIn(0, 2000)

    private fun fadeEnabled(): Boolean = SettingsStore(this).load().fadePlayback

    private fun requestPlay() {
        val player = exoPlayer ?: return
        if (player.playWhenReady) {
            // 播放中再次收到 play（例如淡出尚未结束），取消淡出并恢复音量。
            if (fadeMode == FadeMode.OUT) cancelFade(resetVolume = true)
            player.play()
            return
        }
        val duration = fadeDuration()
        if (!fadeEnabled() || duration <= 0 || userVolume <= 0f) {
            cancelFade(resetVolume = true)
            player.play()
            return
        }
        cancelFade(resetVolume = false)
        pendingFadeIn = true
        player.volume = 0f
        player.play()
    }

    private fun requestPause() {
        val player = exoPlayer ?: return
        pendingFadeIn = false
        if (!player.playWhenReady || !player.isPlaying) {
            cancelFade(resetVolume = true)
            player.pause()
            return
        }
        val duration = fadeDuration()
        if (!fadeEnabled() || duration <= 0 || userVolume <= 0f) {
            cancelFade(resetVolume = true)
            player.pause()
            return
        }
        if (fadeMode == FadeMode.OUT) return
        startFadeOut(duration)
    }

    private fun startFadeIn(duration: Int) {
        val player = exoPlayer ?: return
        pendingFadeIn = false
        if (!fadeEnabled() || duration <= 0 || userVolume <= 0f) {
            player.volume = userVolume
            return
        }
        cancelFade(resetVolume = false)
        fadeMode = FadeMode.IN
        val token = ++fadeToken
        val steps = max(1, duration / FADE_STEP_MS)
        val interval = max(1L, duration.toLong() / steps)
        var step = 0
        val runnable = object : Runnable {
            override fun run() {
                if (token != fadeToken) return
                step++
                val progress = step.toFloat() / steps
                player.volume = userVolume * progress
                if (step >= steps) {
                    fadeMode = FadeMode.NONE
                    fadeRunnable = null
                    player.volume = userVolume
                } else {
                    fadeHandler.postDelayed(this, interval)
                }
            }
        }
        fadeRunnable = runnable
        fadeHandler.postDelayed(runnable, interval)
    }

    private fun startFadeOut(duration: Int) {
        val player = exoPlayer ?: return
        val startVolume = player.volume.coerceIn(0f, userVolume)
        cancelFade(resetVolume = false)
        if (startVolume <= 0f) {
            // Keep the output muted while paused so buffered frames cannot
            // leak through at full volume; the next play restores it.
            player.pause()
            return
        }
        fadeMode = FadeMode.OUT
        val token = ++fadeToken
        val steps = max(1, duration / FADE_STEP_MS)
        val interval = max(1L, duration.toLong() / steps)
        var step = 0
        val runnable = object : Runnable {
            override fun run() {
                if (token != fadeToken) return
                step++
                val progress = step.toFloat() / steps
                player.volume = startVolume * (1f - progress)
                if (step >= steps) {
                    fadeMode = FadeMode.NONE
                    fadeRunnable = null
                    // Stay at zero until the next play. Restoring the user
                    // volume right after pause() can briefly unmute buffered
                    // audio frames.
                    player.pause()
                } else {
                    fadeHandler.postDelayed(this, interval)
                }
            }
        }
        fadeRunnable = runnable
        fadeHandler.postDelayed(runnable, interval)
    }

    private fun cancelFade(resetVolume: Boolean) {
        fadeToken++
        fadeRunnable?.let(fadeHandler::removeCallbacks)
        fadeRunnable = null
        fadeMode = FadeMode.NONE
        pendingFadeIn = false
        if (resetVolume) exoPlayer?.volume = userVolume
    }

    private fun createRenderersFactory(): RenderersFactory {
        return RenderersFactory { eventHandler, videoRendererEventListener, audioRendererEventListener, textRendererOutput, metadataRendererOutput ->
            val settings = SettingsStore(this).load()

            // Native processor 常驻为透明旁路，运行时切换引擎无需销毁播放器。
            // 某些 ABI/ROM 上 JNI 库可能不可用；此时退化为无音效播放而不是让服务崩溃。
            val processor = runCatching { NativeAudioProcessor() }
                .onFailure { Log.e(TAG, "专业音效处理器不可用，已回退到普通播放", it) }
                .getOrNull()
            if (processor != null) {
                nativeAudioProcessor = processor
                processor.applySettings(settings.audioEffects)
            }
            val audioProcessors = listOfNotNull(processor).toTypedArray<AudioProcessor>()

            // 创建带自定义 AudioProcessor 的 AudioSink
            val audioSink = DefaultAudioSink.Builder(this)
                .setAudioProcessors(audioProcessors)
                .build()

            arrayOf(
                MediaCodecVideoRenderer(
                    this,
                    MediaCodecSelector.DEFAULT,
                    50000L,
                    eventHandler,
                    videoRendererEventListener,
                    50
                ),
                MediaCodecAudioRenderer(
                    this,
                    MediaCodecSelector.DEFAULT,
                    eventHandler,
                    audioRendererEventListener,
                    audioSink
                )
            )
        }
    }

    private fun normalizeReadableUri(raw: String): Uri? {
        val uri = runCatching {
            val parsed = Uri.parse(raw)
            if (parsed.scheme.isNullOrBlank()) Uri.fromFile(File(raw)) else parsed
        }.getOrNull() ?: return null

        return runCatching {
            when (uri.scheme) {
                "content" -> {
                    contentResolver.openFileDescriptor(uri, "r")?.use { } ?: return null
                    uri
                }
                "file" -> {
                    val file = File(uri.path ?: return null)
                    uri.takeIf { file.isFile && file.canRead() }
                }
                else -> null
            }
        }.getOrNull()
    }

    private fun initAudioEffects(audioSessionId: Int) {
        if (effectsSessionId != audioSessionId) {
            audioEffectsManager?.release()
            audioEffectsManager = null
            effectsSessionId = audioSessionId
        }
        updateAudioEffects(SettingsStore(this).load().audioEffects)
    }

    private fun updateAudioEffects(settings: AudioEffectSettings) {
        val safe = settings.normalized()
        val player = exoPlayer ?: return
        if (safe.engine != AudioEffectEngine.SYSTEM) {
            player.setAuxEffectInfo(AuxEffectInfo(0, 0f))
            audioEffectsManager?.release()
            audioEffectsManager = null
        }
        nativeAudioProcessor?.applySettings(safe)
        if (safe.engine == AudioEffectEngine.SYSTEM) {
            val sessionId = player.audioSessionId
            if (sessionId <= 0) return
            if (audioEffectsManager == null || effectsSessionId != sessionId) {
                audioEffectsManager?.release()
                effectsSessionId = sessionId
                audioEffectsManager = SystemAudioEffectsManager(sessionId).apply { initialize() }
            }
            audioEffectsManager?.let { manager ->
                manager.applySettings(safe)
                try {
                    player.setAuxEffectInfo(AuxEffectInfo(manager.auxEffectId, manager.reverbSendLevel))
                } catch (_: Exception) {
                    manager.disableReverb()
                    player.setAuxEffectInfo(AuxEffectInfo(0, 0f))
                }
            }
        }
    }


    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "top.nekoh2o.player.ACTION_UPDATE_AUDIO_EFFECTS") {
            runCatching { handleAudioEffectsUpdate(intent) }
                .onFailure { Log.e(TAG, "更新音效设置失败", it) }
        }
        return super.onStartCommand(intent, flags, startId)
    }

    private fun handleAudioEffectsUpdate(intent: Intent) {
        val engineValue = intent.getIntExtra("engine", 0)
        val engine = AudioEffectEngine.entries.getOrNull(engineValue) ?: return

        val settings = AudioEffectSettings(
            engine = engine,
            eqBands = intent.getFloatArrayExtra("eq_bands")?.toList() ?: List(10) { 0f },
            bassBoost = intent.getIntExtra("bass_boost", 0),
            virtualizer = intent.getIntExtra("virtualizer", 0),
            reverbWet = intent.getIntExtra("reverb_wet", 0),
            reverbRoomSize = intent.getIntExtra("reverb_room_size", 50),
            reverbDamping = intent.getIntExtra("reverb_damping", 30),
            loudnessGain = intent.getIntExtra("loudness_gain", 0),
            masteringPresetId = intent.getIntExtra("mastering_preset", 0),
            masteringMix = intent.getIntExtra("mastering_mix", 100)
        )

        updateAudioEffects(settings)
    }

    override fun onGetSession(
        controllerInfo: MediaSession.ControllerInfo
    ): MediaSession? = mediaSession

    override fun onDestroy() {
        cancelFade(resetVolume = false)
        fadeHandler.removeCallbacksAndMessages(null)
        runCatching { audioEffectsManager?.release() }
        audioEffectsManager = null
        nativeAudioProcessor = null
        runCatching {
            mediaSession?.release()
            exoPlayer?.release()
        }.onFailure { Log.e(TAG, "释放媒体会话失败", it) }
        mediaSession = null
        exoPlayer = null
        super.onDestroy()
    }

    companion object {
        private const val TAG = "PlaybackService"
        private const val FADE_STEP_MS = 16
    }
}
