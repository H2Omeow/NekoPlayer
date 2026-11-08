package top.nekoh2o.player.playback

import top.nekoh2o.player.i18n.NekoI18n.tr

import top.nekoh2o.player.data.net.CookieStore

import android.content.Intent
import android.net.Uri
import androidx.media3.common.AudioAttributes
import androidx.media3.common.AuxEffectInfo
import androidx.media3.common.C
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
import java.io.File

@UnstableApi
class PlaybackService : MediaSessionService() {

    private var mediaSession: MediaSession? = null
    private val repo = MusicRepository()
    private var audioEffectsManager: SystemAudioEffectsManager? = null
    private var nativeAudioProcessor: NativeAudioProcessor? = null
    private var effectsSessionId = C.AUDIO_SESSION_ID_UNSET

    override fun onCreate() {
        super.onCreate()

        MusicCache.init(this)

        val httpFactory = DefaultHttpDataSource.Factory()
            .setUserAgent("NekoPlayer/1.0")
            .setAllowCrossProtocolRedirects(true)

        // 上游使用 DefaultDataSource，同时支持网络、file:// 与 content:// URI。
        val localAndHttpFactory = DefaultDataSource.Factory(this, httpFactory)
        val cacheFactory = MusicCache.dataSourceFactory(localAndHttpFactory)
        val settingsStore = SettingsStore(this)

        val playbackFactory = androidx.media3.datasource.DataSource.Factory {
            if (settingsStore.load().cacheEnabled) cacheFactory.createDataSource() else localAndHttpFactory.createDataSource()
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

        player.addListener(object : Player.Listener {
            override fun onAudioSessionIdChanged(audioSessionId: Int) {
                initAudioEffects(audioSessionId)
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_READY && audioEffectsManager == null) {
                    initAudioEffects(player.audioSessionId)
                }
            }
        })

        mediaSession = MediaSession.Builder(this, player).build()
    }

    private fun createRenderersFactory(): RenderersFactory {
        return RenderersFactory { eventHandler, videoRendererEventListener, audioRendererEventListener, textRendererOutput, metadataRendererOutput ->
            val settings = SettingsStore(this).load()

            // Native processor 常驻为透明旁路，运行时切换引擎无需销毁播放器。
            val processor = NativeAudioProcessor()
            nativeAudioProcessor = processor
            processor.applySettings(settings.audioEffects)
            val audioProcessors = arrayOf<AudioProcessor>(processor)

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
        val player = mediaSession?.player as? ExoPlayer ?: return
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
            handleAudioEffectsUpdate(intent)
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
        audioEffectsManager?.release()
        audioEffectsManager = null
        nativeAudioProcessor = null
        mediaSession?.run {
            player.release()
            release()
        }
        mediaSession = null
        super.onDestroy()
    }
}
