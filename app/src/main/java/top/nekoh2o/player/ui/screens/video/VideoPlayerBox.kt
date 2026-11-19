package top.nekoh2o.player.ui.screens.video

import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.media.AudioManager
import android.view.ViewGroup
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.annotation.OptIn
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.isActive
import top.nekoh2o.player.data.bilibili.DanmakuItem
import top.nekoh2o.player.data.bilibili.BiliSession
import top.nekoh2o.player.data.bilibili.PlaySource
import top.nekoh2o.player.data.store.DanmakuSettings
import top.nekoh2o.player.data.store.PlayerSettings

private const val UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

/** B 站视频源需要的请求头；缺失会被 403。 */
private fun biliHeaders(): Map<String, String> {
    val headers = mutableMapOf(
        "Referer" to "https://www.bilibili.com/",
        "Origin" to "https://www.bilibili.com",
        "User-Agent" to UA,
        "Accept" to "*/*",
        // B 站 CDN 对没有 Range 的请求会直接返回 567/403，必须带上初始 Range
        "Range" to "bytes=0-"
    )
    val cookie = runCatching { BiliSession.cookieHeader() }.getOrDefault("")
    if (cookie.isNotBlank()) headers["Cookie"] = cookie
    return headers
}

@OptIn(UnstableApi::class)
@Composable
fun VideoPlayerBox(
    source: PlaySource?,
    title: String,
    danmaku: List<DanmakuItem>,
    danmakuSettings: DanmakuSettings,
    playerSettings: PlayerSettings,
    startPositionMs: Long,
    fullscreen: Boolean,
    onToggleFullscreen: () -> Unit,
    onBack: () -> Unit,
    onEnded: () -> Unit,
    onProgress: (positionMs: Long, durationMs: Long) -> Unit,
    onOpenDanmakuSettings: () -> Unit,
    onOpenPlayerSettings: () -> Unit,
    onFatalError: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val activity = remember(context) { context.findActivity() }

    val exo = remember {
        val http = DefaultHttpDataSource.Factory()
            .setDefaultRequestProperties(biliHeaders())
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(20_000)
            .setReadTimeoutMs(20_000)
        val ds = DefaultDataSource.Factory(context, http)
        ExoPlayer.Builder(context)
            .setMediaSourceFactory(DefaultMediaSourceFactory(ds))
            .build()
            .apply {
                repeatMode = Player.REPEAT_MODE_OFF
                playWhenReady = true
                setHandleAudioBecomingNoisy(true)
            }
    }
    DisposableEffect(exo) {
        onDispose { exo.release() }
    }

    var isPlaying by remember { mutableStateOf(false) }
    var durationMs by remember { mutableLongStateOf(0L) }
    var positionMs by remember { mutableLongStateOf(startPositionMs) }
    var bufferedMs by remember { mutableLongStateOf(0L) }
    var buffering by remember { mutableStateOf(true) }
    var errorText by remember { mutableStateOf<String?>(null) }
    var ended by remember { mutableStateOf(false) }
    var speed by remember { mutableFloatStateOf(playerSettings.defaultSpeed) }

    // 播放器事件
    DisposableEffect(exo) {
        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                buffering = state == Player.STATE_BUFFERING
                if (state == Player.STATE_ENDED) {
                    ended = true
                    onEnded()
                }
                if (state == Player.STATE_READY) {
                    errorText = null
                    durationMs = exo.duration.coerceAtLeast(0L)
                }
            }

            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying = playing
            }

            override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                errorText = error.errorCodeName + "：" + (error.message ?: "播放失败")
                buffering = false
                if (error.errorCode == androidx.media3.common.PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS ||
                    error.errorCode == androidx.media3.common.PlaybackException.ERROR_CODE_IO_UNSPECIFIED ||
                    error.errorCode == androidx.media3.common.PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED
                ) {
                    onFatalError()
                }
            }
        }
        exo.addListener(listener)
        onDispose { exo.removeListener(listener) }
    }

    // 媒体源切换：只在首次使用导航带入的进度，之后换源/重试都从当前位置继续
    var startConsumed by remember { mutableStateOf(false) }
    LaunchedEffect(source?.url) {
        val url = source?.url ?: return@LaunchedEffect
        val resumeAt = when {
            !startConsumed && startPositionMs > 0 -> startPositionMs
            else -> exo.currentPosition.coerceAtLeast(0L)
        }
        startConsumed = true
        ended = false
        errorText = null
        exo.setMediaItem(MediaItem.fromUri(url))
        exo.prepare()
        if (resumeAt > 0) exo.seekTo(resumeAt)
        exo.playWhenReady = true
        exo.setPlaybackSpeed(speed)
    }

    // 播放进度轮询（驱动控制条与弹幕层）
    LaunchedEffect(exo) {
        while (isActive) {
            positionMs = exo.currentPosition.coerceAtLeast(0L)
            bufferedMs = exo.bufferedPosition.coerceAtLeast(0L)
            if (exo.duration > 0) durationMs = exo.duration
            delay(120)
        }
    }

    // 进度回传（每 2 秒一次，供历史记录落盘）
    LaunchedEffect(exo) {
        while (isActive) {
            delay(2000)
            if (durationMs > 0) onProgress(positionMs, durationMs)
        }
    }

    // 播放中常亮，离开页面时恢复
    DisposableEffect(isPlaying) {
        activity?.window?.let { w ->
            if (isPlaying) w.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            else w.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        onDispose {
            activity?.window?.let { w ->
                w.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                w.attributes = w.attributes.apply { screenBrightness = -1f }
            }
        }
    }

    var controlsVisible by remember { mutableStateOf(true) }
    var seekPreviewMs by remember { mutableLongStateOf(-1L) }
    var gestureHint by remember { mutableStateOf<String?>(null) }
    var hintValue by remember { mutableFloatStateOf(0f) }

    LaunchedEffect(controlsVisible, isPlaying) {
        if (controlsVisible && isPlaying) {
            delay((playerSettings.autoHideControlsSec.coerceIn(1, 12) * 1000).toLong())
            controlsVisible = false
        }
    }

    val audioManager = remember { context.getSystemService(Context.AUDIO_SERVICE) as AudioManager }

    Box(
        modifier
            .background(Color.Black)
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = {
                        if (errorText != null) {
                            errorText = null
                            source?.url?.let {
                                exo.setMediaItem(MediaItem.fromUri(it))
                                exo.prepare()
                                exo.playWhenReady = true
                            }
                        } else {
                            controlsVisible = !controlsVisible
                        }
                    },
                    onDoubleTap = { offset ->
                        val half = size.width / 2f
                        val step = playerSettings.doubleTapSeekSec.coerceIn(3, 60) * 1000L
                        if (offset.x < half * 0.72f) {
                            exo.seekTo((exo.currentPosition - step).coerceAtLeast(0))
                            gestureHint = "◀◀ 后退 ${step / 1000} 秒"
                        } else if (offset.x > size.width - half * 0.72f) {
                            exo.seekTo((exo.currentPosition + step).coerceAtMost(durationMs.coerceAtLeast(0)))
                            gestureHint = "快进 ${step / 1000} 秒 ▶▶"
                        } else {
                            if (exo.isPlaying) exo.pause() else exo.play()
                        }
                    },
                    onPress = {
                        coroutineScope {
                            val base = speed
                            var boosted = false
                            val job = if (playerSettings.longPressSpeed > 1f) launch {
                                delay(420)
                                boosted = true
                                speed = playerSettings.longPressSpeed
                                exo.setPlaybackSpeed(speed)
                                gestureHint = "${playerSettings.longPressSpeed}× 倍速播放中"
                            } else null
                            tryAwaitRelease()
                            job?.cancel()
                            if (boosted) {
                                speed = base
                                exo.setPlaybackSpeed(base)
                                gestureHint = null
                            }
                        }
                    }
                )
            }
            .pointerInput(Unit) {
                detectVerticalDragGestures(
                    onDragStart = { offset ->
                        hintValue = if (offset.x < size.width / 2f) {
                            -1f
                        } else {
                            audioManager.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat() /
                                audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
                        }
                    },
                    onDragEnd = { gestureHint = null },
                    onDragCancel = { gestureHint = null },
                    onVerticalDrag = { change, dragAmount ->
                        change.consume()
                        val delta = -dragAmount / size.height
                        if (hintValue < 0f) {
                            // 左半屏：亮度（这里用系统窗口亮度近似，-1 表示跟随系统）
                            val w = activity?.window ?: return@detectVerticalDragGestures
                            val current = w.attributes.screenBrightness.takeIf { it > 0f } ?: 0.5f
                            val next = (current + delta * 1.6f).coerceIn(0.02f, 1f)
                            w.attributes = w.attributes.apply { screenBrightness = next }
                            hintValue = next
                            gestureHint = "亮度 ${(next * 100).toInt()}%"
                        } else {
                            val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            val cur = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                            val next = (cur + (delta * max * 1.8f).toInt()).coerceIn(0, max)
                            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, next, 0)
                            hintValue = next.toFloat() / max
                            gestureHint = "音量 ${(hintValue * 100).toInt()}%"
                        }
                    }
                )
            }
    ) {
        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply {
                    player = exo
                    useController = false
                    resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                    setShowBuffering(PlayerView.SHOW_BUFFERING_NEVER)
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )
                    setBackgroundColor(android.graphics.Color.BLACK)
                }
            },
            modifier = Modifier.fillMaxSize(),
            onRelease = { it.player = null }
        )

        // 弹幕层（在画面之上、控制条之下）
        DanmakuOverlay(
            items = danmaku,
            settings = danmakuSettings,
            positionProvider = { positionMs },
            modifier = Modifier.fillMaxSize().padding(horizontal = 6.dp, vertical = 2.dp)
        )

        // 顶部/底部渐隐遮罩 + 控制条
        AnimatedVisibility(visible = controlsVisible, enter = fadeIn(), exit = fadeOut()) {
            Box(Modifier.fillMaxSize()) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(
                            Brush.verticalGradient(
                                0f to Color.Black.copy(alpha = 0.55f),
                                0.28f to Color.Transparent,
                                0.62f to Color.Transparent,
                                1f to Color.Black.copy(alpha = 0.78f)
                            )
                        )
                )
                PlayerChrome(
                    title = title,
                    isPlaying = isPlaying,
                    positionMs = if (seekPreviewMs >= 0) seekPreviewMs else positionMs,
                    durationMs = durationMs,
                    bufferedMs = bufferedMs,
                    speed = speed,
                    qualityLabel = source?.qualityLabel ?: "自动",
                    danmakuOn = danmakuSettings.enabled,
                    fullscreen = fullscreen,
                    onBack = onBack,
                    onTogglePlay = { if (exo.isPlaying) exo.pause() else exo.play() },
                    onSeek = { ms ->
                        seekPreviewMs = ms
                        exo.seekTo(ms)
                    },
                    onSeekFinished = { seekPreviewMs = -1L },
                    onToggleDanmaku = onOpenDanmakuSettings,
                    onSpeed = {
                        val next = nextSpeed(speed)
                        speed = next
                        exo.setPlaybackSpeed(next)
                    },
                    onToggleFullscreen = onToggleFullscreen,
                    onOpenPlayerSettings = onOpenPlayerSettings
                )
            }
        }

        if (buffering && errorText == null) {
            CircularProgressIndicator(
                color = MaterialTheme.colorScheme.primary,
                strokeWidth = 3.dp,
                modifier = Modifier.align(Alignment.Center).size(36.dp)
            )
        }

        if (errorText != null) {
            Column(
                Modifier
                    .align(Alignment.Center)
                    .clip(RoundedCornerShape(12.dp))
                    .background(Color.Black.copy(alpha = 0.72f))
                    .padding(20.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Icon(Icons.Filled.CloudOff, null, tint = Color.White.copy(alpha = 0.8f), modifier = Modifier.size(30.dp))
                Spacer(Modifier.height(8.dp))
                Text(errorText!!, color = Color.White, style = MaterialTheme.typography.bodySmall)
                Spacer(Modifier.height(12.dp))
                Text(
                    "点击重试",
                    color = MaterialTheme.colorScheme.primary,
                    style = MaterialTheme.typography.labelLarge,
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(Color.White.copy(alpha = 0.12f))
                        .padding(horizontal = 16.dp, vertical = 6.dp)
                )
            }
        }

        gestureHint?.let { hint ->
            Box(
                Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 16.dp)
                    .clip(RoundedCornerShape(50))
                    .background(Color.Black.copy(alpha = 0.6f))
                    .padding(horizontal = 14.dp, vertical = 6.dp)
            ) {
                Text(hint, color = Color.White, style = MaterialTheme.typography.labelMedium)
            }
        }

        if (ended) {
            Box(
                Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.45f)),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("已播放完毕", color = Color.White, style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(10.dp))
                    Text(
                        "重新播放",
                        color = MaterialTheme.colorScheme.onPrimary,
                        style = MaterialTheme.typography.labelLarge,
                        modifier = Modifier
                            .clip(RoundedCornerShape(50))
                            .background(MaterialTheme.colorScheme.primary)
                            .clickableNoRipple {
                                ended = false
                                exo.seekTo(0)
                                exo.play()
                            }
                            .padding(horizontal = 20.dp, vertical = 8.dp)
                    )
                }
            }
        }
    }
}

private fun nextSpeed(current: Float): Float {
    val steps = listOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, 1.75f, 2f, 3f)
    val idx = steps.indexOfFirst { it > current + 0.01f }
    return if (idx < 0) 0.5f else steps[idx]
}

private fun Modifier.clickableNoRipple(onClick: () -> Unit): Modifier =
    this.then(Modifier.pointerInput(Unit) { detectTapGestures { onClick() } })

@Composable
private fun PlayerChrome(
    title: String,
    isPlaying: Boolean,
    positionMs: Long,
    durationMs: Long,
    bufferedMs: Long,
    speed: Float,
    qualityLabel: String,
    danmakuOn: Boolean,
    fullscreen: Boolean,
    onBack: () -> Unit,
    onTogglePlay: () -> Unit,
    onSeek: (Long) -> Unit,
    onSeekFinished: () -> Unit,
    onToggleDanmaku: () -> Unit,
    onSpeed: () -> Unit,
    onToggleFullscreen: () -> Unit,
    onOpenPlayerSettings: () -> Unit
) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val compact = maxWidth < 560.dp
        Column(Modifier.fillMaxSize()) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onBack) {
                    Icon(Icons.Filled.ArrowBackIosNew, "返回", tint = Color.White, modifier = Modifier.size(18.dp))
                }
                Text(
                    title,
                    color = Color.White,
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 1,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                IconButton(onClick = onOpenPlayerSettings) {
                    Icon(Icons.Outlined.MoreVert, "更多", tint = Color.White)
                }
            }
            Spacer(Modifier.weight(1f))
            if (compact) {
                Column(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 4.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        PlayPauseButton(isPlaying, onTogglePlay, 36.dp)
                        Text(
                            "${formatPosition(positionMs)} / ${formatPosition(durationMs)}",
                            color = Color.White.copy(alpha = 0.92f),
                            style = MaterialTheme.typography.labelMedium
                        )
                        Spacer(Modifier.width(8.dp))
                        SeekBar(
                            positionMs = positionMs,
                            bufferedMs = bufferedMs,
                            durationMs = durationMs,
                            onSeek = onSeek,
                            onSeekFinished = onSeekFinished,
                            modifier = Modifier.weight(1f)
                        )
                    }
                    Row(
                        Modifier.fillMaxWidth().padding(top = 2.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        DanmakuButton(danmakuOn, onToggleDanmaku, 34.dp)
                        Spacer(Modifier.weight(1f))
                        QualityChip(qualityLabel)
                        Spacer(Modifier.width(6.dp))
                        SpeedChip(speed, onSpeed)
                        Spacer(Modifier.width(2.dp))
                        IconButton(onClick = onToggleFullscreen, modifier = Modifier.size(34.dp)) {
                            Icon(
                                if (fullscreen) Icons.Filled.FullscreenExit else Icons.Filled.Fullscreen,
                                "全屏",
                                tint = Color.White,
                                modifier = Modifier.size(20.dp)
                            )
                        }
                    }
                }
            } else {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    PlayPauseButton(isPlaying, onTogglePlay, 40.dp)
                    Text(
                        "${formatPosition(positionMs)} / ${formatPosition(durationMs)}",
                        color = Color.White.copy(alpha = 0.92f),
                        style = MaterialTheme.typography.labelMedium
                    )
                    Spacer(Modifier.width(12.dp))
                    SeekBar(
                        positionMs = positionMs,
                        bufferedMs = bufferedMs,
                        durationMs = durationMs,
                        onSeek = onSeek,
                        onSeekFinished = onSeekFinished,
                        modifier = Modifier.weight(1f)
                    )
                    Spacer(Modifier.width(12.dp))
                    DanmakuButton(danmakuOn, onToggleDanmaku, 36.dp)
                    QualityChip(qualityLabel)
                    Spacer(Modifier.width(8.dp))
                    SpeedChip(speed, onSpeed)
                    IconButton(onClick = onToggleFullscreen, modifier = Modifier.size(36.dp)) {
                        Icon(
                            if (fullscreen) Icons.Filled.FullscreenExit else Icons.Filled.Fullscreen,
                            "全屏",
                            tint = Color.White
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun PlayPauseButton(isPlaying: Boolean, onTogglePlay: () -> Unit, size: Dp) {
    IconButton(onClick = onTogglePlay, modifier = Modifier.size(size)) {
        Icon(
            if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
            if (isPlaying) "暂停" else "播放",
            tint = Color.White
        )
    }
}

@Composable
private fun DanmakuButton(danmakuOn: Boolean, onToggleDanmaku: () -> Unit, size: Dp) {
    IconButton(onClick = onToggleDanmaku, modifier = Modifier.size(size)) {
        Icon(
            if (danmakuOn) Icons.Filled.Subtitles else Icons.Outlined.SubtitlesOff,
            "弹幕",
            tint = if (danmakuOn) MaterialTheme.colorScheme.primary else Color.White.copy(alpha = 0.7f)
        )
    }
}

@Composable
private fun QualityChip(label: String) {
    Text(
        label.ifBlank { "自动" },
        color = Color.White.copy(alpha = 0.85f),
        style = MaterialTheme.typography.labelMedium,
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(Color.White.copy(alpha = 0.14f))
            .padding(horizontal = 8.dp, vertical = 3.dp)
    )
}

@Composable
private fun SpeedChip(speed: Float, onSpeed: () -> Unit) {
    Text(
        if (speed == speed.toInt().toFloat()) "${speed.toInt()}×" else "${speed}×",
        color = Color.White.copy(alpha = 0.85f),
        style = MaterialTheme.typography.labelMedium,
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(Color.White.copy(alpha = 0.14f))
            .clickableNoRipple { onSpeed() }
            .padding(horizontal = 8.dp, vertical = 3.dp)
    )
}

@Composable
private fun SeekBar(
    positionMs: Long,
    bufferedMs: Long,
    durationMs: Long,
    onSeek: (Long) -> Unit,
    onSeekFinished: () -> Unit,
    modifier: Modifier = Modifier
) {
    if (durationMs <= 0L) {
        Box(modifier.height(24.dp))
        return
    }
    Slider(
        value = positionMs.coerceIn(0L, durationMs).toFloat(),
        valueRange = 0f..durationMs.toFloat(),
        onValueChange = { onSeek(it.toLong()) },
        onValueChangeFinished = onSeekFinished,
        colors = SliderDefaults.colors(
            thumbColor = Color.White,
            activeTrackColor = MaterialTheme.colorScheme.primary,
            inactiveTrackColor = Color.White.copy(alpha = 0.24f)
        ),
        modifier = modifier.height(24.dp)
    )
}

private fun Context.findActivity(): ComponentActivity? {
    var ctx: Context? = this
    while (ctx is ContextWrapper) {
        if (ctx is ComponentActivity) return ctx
        ctx = ctx.baseContext
    }
    return null
}
