package top.nekoh2o.player.ui.screens

import top.nekoh2o.player.i18n.NekoI18n.tr

import android.content.res.Configuration
import android.provider.Settings
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.automirrored.outlined.Comment
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.RepeatOne
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Speed
import androidx.compose.material.icons.outlined.Subtitles
import androidx.compose.material.icons.outlined.SubtitlesOff
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import sh.calvin.reorderable.ReorderableItem
import sh.calvin.reorderable.rememberReorderableLazyListState
import top.nekoh2o.player.data.model.BgSource
import top.nekoh2o.player.data.model.LyricLine
import top.nekoh2o.player.data.model.LyricWord
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.ui.PlayMode
import top.nekoh2o.player.ui.PlayerViewModel
import top.nekoh2o.player.ui.UiState
import top.nekoh2o.player.ui.a11y.clickableRow
import top.nekoh2o.player.ui.a11y.toggleSemantics
import top.nekoh2o.player.ui.components.Artwork
import top.nekoh2o.player.ui.components.FavoriteButton
import top.nekoh2o.player.ui.components.songSourceLabel
import top.nekoh2o.player.ui.theme.NekoDefaults
import top.nekoh2o.player.ui.theme.NekoRadius
import top.nekoh2o.player.ui.theme.NekoSpace

// 播放器铺在封面 / 壁纸上，文字固定用白色系，不跟随主题
private val TextMain = Color.White
private val TextSub = Color.White.copy(alpha = 0.7f)
private val LyricIdle = Color.White.copy(alpha = 0.45f)

/** 全屏播放器的操作回调。 */
class PlayerControls(
    val onClose: () -> Unit,
    val onTogglePlay: () -> Unit,
    val onPrev: () -> Unit,
    val onNext: () -> Unit,
    val onCycleMode: () -> Unit,
    val onSeek: (Long) -> Unit,
    val onToggleFav: () -> Unit,
    val onQueue: () -> Unit,
    val onSpeed: () -> Unit,
    val onTimer: () -> Unit,
    val onDownload: () -> Unit,
    val onComments: () -> Unit,
    val onFloating: () -> Unit,
    val onDynamicLyrics: () -> Unit,
    val onShare: () -> Unit
)

@Composable
fun FullPlayerScreen(vm: PlayerViewModel, onClose: () -> Unit) {
    val state by vm.ui.collectAsState()
    val cur = state.current
    var showQueue by remember { mutableStateOf(false) }
    var showSpeedDialog by remember { mutableStateOf(false) }
    var showTimerDialog by remember { mutableStateOf(false) }
    var showFloatingPermDialog by remember { mutableStateOf(false) }
    var showQualityDialog by remember { mutableStateOf(false) }
    var showComments by remember { mutableStateOf(false) }
    var showLyrics by remember { mutableStateOf(false) }
    var showDynamicLyrics by remember { mutableStateOf(false) }
    val context = LocalContext.current
    // 设置中强制横屏时始终用横屏布局，否则跟随设备方向
    val landscape = state.settings.landscapeMode ||
        LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE

    val controls = remember(vm) {
        PlayerControls(
            onClose = onClose,
            onTogglePlay = vm::togglePlay,
            onPrev = vm::prev,
            onNext = vm::next,
            onCycleMode = vm::cyclePlayMode,
            onSeek = vm::seekTo,
            onToggleFav = { vm.ui.value.current?.let(vm::toggleFav) },
            onQueue = { showQueue = true },
            onSpeed = { showSpeedDialog = true },
            onTimer = { showTimerDialog = true },
            onDownload = { if (vm.ui.value.current != null) showQualityDialog = true },
            onComments = { if (vm.ui.value.current != null) showComments = true },
            onFloating = {
                if (!Settings.canDrawOverlays(context)) showFloatingPermDialog = true
                else vm.toggleFloatingLyric(context)
            },
            onDynamicLyrics = { showDynamicLyrics = true },
            onShare = { vm.socialVm.openShareComposer(vm.ui.value.current) }
        )
    }

    FullPlayerContent(
        state = state,
        isFav = cur != null && vm.isFav(cur),
        landscape = landscape,
        showLyrics = showLyrics,
        onToggleLyrics = { showLyrics = !showLyrics },
        controls = controls
    )

    if (showDynamicLyrics) DynamicLyricsScreen(
        state = state,
        onClose = { showDynamicLyrics = false },
        onToggle = vm::togglePlay,
        onPrevious = vm::prev,
        onNext = vm::next,
        onSeek = vm::seekTo
    )
    if (showComments && cur != null) SongCommentsSheet(cur) { showComments = false }
    if (showQueue) QueueSheet(vm, onDismiss = { showQueue = false })
    if (showFloatingPermDialog) {
        AlertDialog(
            onDismissRequest = { showFloatingPermDialog = false },
            title = { Text(tr("需要悬浮窗权限")) },
            text = { Text(tr("悬浮歌词需要「显示在其他应用上层」权限，才能在其他应用和锁屏界面上显示当前歌词。")) },
            confirmButton = {
                TextButton(onClick = { showFloatingPermDialog = false; vm.toggleFloatingLyric(context) }) { Text(tr("去授权")) }
            },
            dismissButton = {
                TextButton(onClick = { showFloatingPermDialog = false }, colors = NekoDefaults.textButtonColors()) { Text(tr("取消")) }
            }
        )
    }
    if (showSpeedDialog) {
        OptionDialog(
            title = tr("播放速度"),
            options = listOf(0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f).map { it to "${it}x" },
            current = state.settings.playbackSpeed,
            onSelect = { vm.setPlaybackSpeed(it); showSpeedDialog = false },
            onDismiss = { showSpeedDialog = false }
        )
    }
    if (showTimerDialog) {
        OptionDialog(
            title = tr("定时关闭"),
            options = listOf(0 to tr("关闭"), 15 to tr("{minutes} 分钟", "minutes" to 15), 30 to tr("{minutes} 分钟", "minutes" to 30), 45 to tr("{minutes} 分钟", "minutes" to 45), 60 to tr("{minutes} 分钟", "minutes" to 60)),
            current = state.sleepMinutes,
            onSelect = { vm.setSleepTimer(it); showTimerDialog = false },
            onDismiss = { showTimerDialog = false }
        )
    }
    if (showQualityDialog) {
        QualityDialog(
            song = cur,
            current = state.quality,
            onSelect = { q ->
                showQualityDialog = false
                cur?.let { vm.downloadSong(it, q) }
            },
            onDismiss = { showQualityDialog = false }
        )
    }
}

@Composable
fun FullPlayerContent(
    state: UiState,
    isFav: Boolean,
    landscape: Boolean,
    showLyrics: Boolean,
    onToggleLyrics: () -> Unit,
    controls: PlayerControls
) {
    val cur = state.current
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        val background = when (state.settings.fpBgSource) {
            BgSource.WALLPAPER -> state.wallpaperUrl
            BgSource.COVER -> cur?.pc?.let { "$it?param=800y800" }
        }
        AsyncImage(
            model = background,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize().blur(state.settings.fpBlurRadius.dp)
        )
        // 遮罩 + 底部加深，保证控件区域的白字在亮色封面上也清晰
        Box(
            Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = state.settings.fpMaskAlpha))
                .background(Brush.verticalGradient(0.5f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.45f)))
        )
        if (landscape) LandscapeLayout(state, isFav, controls)
        else PortraitLayout(state, isFav, showLyrics, onToggleLyrics, controls)
    }
}

@Composable
private fun PortraitLayout(
    state: UiState,
    isFav: Boolean,
    showLyrics: Boolean,
    onToggleLyrics: () -> Unit,
    controls: PlayerControls
) {
    val cur = state.current
    Column(
        Modifier
            .fillMaxSize()
            .windowInsetsPadding(WindowInsets.systemBars)
    ) {
        PlayerTopBar(cur, controls, Modifier.padding(horizontal = NekoSpace.sm))
        Column(Modifier.weight(1f).padding(horizontal = NekoSpace.xl)) {
            Box(
                Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .clickable(onClickLabel = if (showLyrics) tr("显示封面") else tr("显示歌词"), role = Role.Button) { onToggleLyrics() },
                contentAlignment = Alignment.Center
            ) {
                Crossfade(targetState = showLyrics, animationSpec = tween(300), label = "lyrics_cover_toggle") { show ->
                    if (show) {
                        LyricView(state, Modifier.fillMaxSize())
                    } else {
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            PlayerArtwork(cur?.pc, state.isPlaying, Modifier.fillMaxWidth().widthIn(max = 360.dp))
                        }
                    }
                }
            }
            Spacer(Modifier.height(NekoSpace.lg))
            TrackHeader(cur, isFav, controls.onToggleFav)
            Spacer(Modifier.height(NekoSpace.sm))
            ProgressBar(state.positionMs, state.durationMs, controls.onSeek)
            Transport(state, controls, Modifier.padding(vertical = NekoSpace.sm))
            ActionRow(state, controls, Modifier.padding(bottom = NekoSpace.lg))
        }
    }
}

@Composable
private fun LandscapeLayout(state: UiState, isFav: Boolean, controls: PlayerControls) {
    val cur = state.current
    Row(
        Modifier
            .fillMaxSize()
            .windowInsetsPadding(WindowInsets.systemBars)
            .padding(start = NekoSpace.sm, end = NekoSpace.xl)
    ) {
        Column(Modifier.weight(0.42f).fillMaxHeight()) {
            PlayerTopBar(cur, controls)
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                PlayerArtwork(cur?.pc, state.isPlaying, Modifier.fillMaxHeight(0.9f))
            }
            TrackHeader(cur, isFav, controls.onToggleFav, Modifier.padding(start = NekoSpace.lg, bottom = NekoSpace.lg))
        }
        Spacer(Modifier.width(NekoSpace.xxl))
        Column(Modifier.weight(0.58f).fillMaxHeight()) {
            LyricView(state, Modifier.weight(1f).fillMaxWidth())
            ProgressBar(state.positionMs, state.durationMs, controls.onSeek)
            Transport(state, controls)
            ActionRow(state, controls, Modifier.padding(bottom = NekoSpace.md))
        }
    }
}

@Composable
private fun PlayerTopBar(song: Song?, controls: PlayerControls, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = controls.onClose) {
            Icon(Icons.Filled.KeyboardArrowDown, contentDescription = tr("收起"), tint = TextMain)
        }
        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(tr("正在播放"), style = MaterialTheme.typography.labelMedium, color = TextSub)
            if (song != null) {
                Text(songSourceLabel(song), style = MaterialTheme.typography.labelSmall, color = TextSub.copy(alpha = 0.5f))
            }
        }
        IconButton(onClick = controls.onShare) {
            Icon(Icons.Filled.Share, contentDescription = tr("分享歌曲"), tint = TextMain)
        }
        IconButton(onClick = controls.onDynamicLyrics) {
            Icon(Icons.Filled.AutoAwesome, contentDescription = tr("动态歌词"), tint = TextMain)
        }
    }
}

/** 圆角方形封面；暂停时略微缩小，播放时弹回。 */
@Composable
private fun PlayerArtwork(url: String?, playing: Boolean, modifier: Modifier = Modifier) {
    val scale by animateFloatAsState(
        targetValue = if (playing) 1f else 0.86f,
        animationSpec = spring(dampingRatio = Spring.DampingRatioLowBouncy, stiffness = Spring.StiffnessLow),
        label = "artwork_scale"
    )
    val shape = RoundedCornerShape(NekoRadius.artwork)
    Box(
        modifier
            .aspectRatio(1f)
            .scale(scale)
            .shadow(24.dp, shape, ambientColor = Color.Black, spotColor = Color.Black)
    ) {
        Artwork(url, Modifier.fillMaxSize(), size = null, shape = shape, thumbnail = 600)
    }
}

@Composable
private fun TrackHeader(song: Song?, isFav: Boolean, onToggleFav: () -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(
                song?.nm ?: tr("未在播放"),
                style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
                color = TextMain,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
            Text(
                song?.ar ?: tr("从音乐页选一首歌"),
                style = MaterialTheme.typography.bodyMedium,
                color = TextSub,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
        }
        if (song != null) {
            FavoriteButton(isFav, onToggleFav, idleTint = TextSub)
        }
    }
}

@Composable
private fun Transport(state: UiState, controls: PlayerControls, modifier: Modifier = Modifier) {
    Row(
        modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        val modeLabel = when (state.playMode) {
            PlayMode.LOOP -> tr("列表循环")
            PlayMode.SINGLE -> tr("单曲循环")
            PlayMode.RANDOM -> tr("随机播放")
        }
        IconButton(onClick = controls.onCycleMode, modifier = Modifier.toggleSemantics(tr("播放模式"), modeLabel)) {
            AnimatedContent(
                targetState = state.playMode,
                transitionSpec = {
                    (fadeIn(tween(200)) + scaleIn(tween(200), initialScale = 0.8f))
                        .togetherWith(fadeOut(tween(200)) + scaleOut(tween(200), targetScale = 0.8f))
                },
                label = "play_mode"
            ) { mode ->
                Icon(
                    when (mode) {
                        PlayMode.LOOP -> Icons.Filled.Repeat
                        PlayMode.SINGLE -> Icons.Filled.RepeatOne
                        PlayMode.RANDOM -> Icons.Filled.Shuffle
                    },
                    contentDescription = null, tint = TextSub
                )
            }
        }
        IconButton(onClick = controls.onPrev, modifier = Modifier.size(56.dp)) {
            Icon(Icons.Filled.SkipPrevious, contentDescription = tr("上一首"), tint = TextMain, modifier = Modifier.size(36.dp))
        }
        FilledIconButton(
            onClick = controls.onTogglePlay,
            modifier = Modifier.size(72.dp),
            colors = IconButtonDefaults.filledIconButtonColors(containerColor = TextMain, contentColor = Color.Black)
        ) {
            AnimatedContent(
                targetState = state.isPlaying,
                transitionSpec = {
                    (fadeIn(tween(150)) + scaleIn(tween(150), initialScale = 0.8f))
                        .togetherWith(fadeOut(tween(150)) + scaleOut(tween(150), targetScale = 0.8f))
                },
                label = "play_pause"
            ) { playing ->
                Icon(
                    if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                    contentDescription = if (playing) tr("暂停") else tr("播放"),
                    modifier = Modifier.size(36.dp)
                )
            }
        }
        IconButton(onClick = controls.onNext, modifier = Modifier.size(56.dp)) {
            Icon(Icons.Filled.SkipNext, contentDescription = tr("下一首"), tint = TextMain, modifier = Modifier.size(36.dp))
        }
        IconButton(onClick = controls.onQueue) {
            Icon(Icons.AutoMirrored.Filled.QueueMusic, contentDescription = tr("播放列表"), tint = TextSub)
        }
    }
}

@Composable
private fun ActionRow(state: UiState, controls: PlayerControls, modifier: Modifier = Modifier) {
    val sleep = state.sleepMinutes
    val floating = state.settings.floatingLyricEnabled
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
        ActionItem(Icons.Outlined.Speed, "${state.settings.playbackSpeed}x", tr("倍速"), onClick = controls.onSpeed)
        ActionItem(
            Icons.Outlined.Timer, if (sleep > 0) tr("{minutes} 分钟", "minutes" to sleep) else tr("定时"), tr("定时关闭"),
            active = sleep > 0, state = if (sleep > 0) tr("已设定 {minutes} 分钟", "minutes" to sleep) else tr("未开启"), onClick = controls.onTimer
        )
        ActionItem(Icons.AutoMirrored.Outlined.Comment,tr("评论"), tr("查看歌曲评论"), onClick = controls.onComments)
        ActionItem(Icons.Outlined.Download, tr("下载"), tr("下载当前歌曲"), onClick = controls.onDownload)
        ActionItem(
            if (floating) Icons.Outlined.Subtitles else Icons.Outlined.SubtitlesOff, tr("悬浮词"), tr("悬浮歌词"),
            active = floating, state = if (floating) tr("已开启") else tr("已关闭"), onClick = controls.onFloating
        )
    }
}

@Composable
private fun ActionItem(
    icon: ImageVector,
    label: String,
    description: String,
    active: Boolean = false,
    state: String? = null,
    onClick: () -> Unit
) {
    val tint = if (active) MaterialTheme.colorScheme.primary else TextSub
    // 图标与文字合并为一个按钮节点，TalkBack 朗读「名称，状态，按钮」
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .clickable(onClick = onClick, role = Role.Button)
            .semantics(mergeDescendants = true) {
                contentDescription = description
                role = Role.Button
                state?.let { stateDescription = it }
            }
            .padding(horizontal = NekoSpace.sm, vertical = NekoSpace.xs)
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(22.dp))
        Spacer(Modifier.height(2.dp))
        Text(label, style = MaterialTheme.typography.labelSmall, color = tint)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProgressBar(positionMs: Long, durationMs: Long, onSeek: (Long) -> Unit) {
    var dragging by remember { mutableStateOf(false) }
    var dragValue by remember { mutableFloatStateOf(0f) }
    val fraction = if (durationMs > 0) positionMs.toFloat() / durationMs else 0f
    Column(Modifier.fillMaxWidth()) {
        Slider(
            value = (if (dragging) dragValue else fraction).coerceIn(0f, 1f),
            onValueChange = { dragging = true; dragValue = it },
            onValueChangeFinished = {
                dragging = false
                if (durationMs > 0) onSeek((dragValue * durationMs).toLong())
            },
            // 细轨道 + 小圆点，拖动时圆点放大
            thumb = {
                val size by animateFloatAsState(if (dragging) 18f else 12f, label = "thumb")
                Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) {
                    Box(Modifier.size(size.dp).background(TextMain, CircleShape))
                }
            },
            track = { sliderState ->
                val value = sliderState.value
                Canvas(Modifier.fillMaxWidth().height(4.dp)) {
                    val y = size.height / 2
                    val stroke = size.height
                    drawLine(
                        TextMain.copy(alpha = 0.2f),
                        Offset(0f, y),
                        Offset(size.width, y),
                        stroke, StrokeCap.Round
                    )
                    drawLine(
                        TextMain,
                        Offset(0f, y),
                        Offset(size.width * value, y),
                        stroke, StrokeCap.Round
                    )
                }
            }
        )
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(
                fmtTime(if (dragging) (dragValue * durationMs).toLong() else positionMs),
                style = MaterialTheme.typography.labelSmall, color = TextSub
            )
            Text(fmtTime(durationMs), style = MaterialTheme.typography.labelSmall, color = TextSub)
        }
    }
}

private fun fmtTime(ms: Long): String {
    if (ms <= 0) return "00:00"
    val total = ms / 1000
    return "%02d:%02d".format(total / 60, total % 60)
}

@Composable
private fun LyricView(state: UiState, modifier: Modifier = Modifier) {
    val lyrics = state.lyrics
    if (lyrics.isEmpty()) {
        Box(modifier, Alignment.Center) { Text(tr("暂无歌词"), color = LyricIdle) }
        return
    }
    val activeIndex = state.lyricIndex
    val activeColor = TextMain
    val listState = rememberLazyListState()
    val density = LocalDensity.current

    LaunchedEffect(activeIndex) {
        if (activeIndex < 0) return@LaunchedEffect
        val viewport = listState.layoutInfo.viewportEndOffset - listState.layoutInfo.viewportStartOffset
        val itemPx = with(density) { (20 * 1.6f + 16).dp.toPx() }.toInt()
        listState.animateScrollToItem(activeIndex, -(viewport / 2 - itemPx / 2))
    }

    LazyColumn(
        modifier = modifier,
        state = listState,
        horizontalAlignment = Alignment.CenterHorizontally,
        contentPadding = PaddingValues(vertical = 48.dp),
        verticalArrangement = Arrangement.spacedBy(NekoSpace.lg)
    ) {
        items(lyrics.size) { i ->
            LyricRow(lyrics[i], i == activeIndex, state.positionMs / 1000.0, state.isPlaying, activeColor)
        }
    }
}

@Composable
private fun LyricRow(
    line: LyricLine,
    isActive: Boolean,
    positionSec: Double,
    isPlaying: Boolean,
    activeColor: Color
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        if (isActive && line.words != null) {
            KaraokeLine(line.words, positionSec, isPlaying, activeColor, LyricIdle)
        } else {
            Text(
                line.text,
                color = if (isActive) activeColor else LyricIdle,
                fontSize = if (isActive) 20.sp else 16.sp,
                fontWeight = if (isActive) FontWeight.Bold else FontWeight.Medium,
                textAlign = TextAlign.Center
            )
        }
        line.translation?.let {
            Text(
                it,
                color = if (isActive) activeColor.copy(alpha = 0.8f) else LyricIdle,
                fontSize = 13.sp, textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 2.dp)
            )
        }
    }
}

@OptIn(ExperimentalTextApi::class)
@Composable
private fun KaraokeLine(
    words: List<LyricWord>,
    positionSec: Double,
    isPlaying: Boolean,
    activeColor: Color,
    idleColor: Color
) {
    val measurer = rememberTextMeasurer()
    val style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold, fontSize = 20.sp)
    val fullText = remember(words) { words.joinToString("") { it.text } }

    var anchorSec by remember { mutableDoubleStateOf(positionSec) }
    var anchorNanos by remember { mutableLongStateOf(0L) }
    var frameSec by remember { mutableDoubleStateOf(positionSec) }

    LaunchedEffect(positionSec) {
        anchorSec = positionSec; anchorNanos = 0L; frameSec = positionSec
    }
    LaunchedEffect(isPlaying, words) {
        if (!isPlaying) { frameSec = positionSec; return@LaunchedEffect }
        while (true) {
            withFrameNanos { now ->
                if (anchorNanos == 0L) anchorNanos = now
                frameSec = anchorSec + (now - anchorNanos) / 1_000_000_000.0
            }
        }
    }
    val drivePos = if (isPlaying) frameSec else positionSec

    Canvas(
        modifier = Modifier.fillMaxWidth()
            .height(with(LocalDensity.current) { (style.fontSize.value * 1.7f).sp.toDp() })
    ) {
        val layout = measurer.measure(text = fullText, style = style)
        val startX = (size.width - layout.size.width) / 2f
        val topY = (size.height - layout.size.height) / 2f

        var filledPx = 0f
        var charIndex = 0
        run {
            words.forEach { w ->
                val start = charIndex
                val end = charIndex + w.text.length
                if (start >= layout.layoutInput.text.length || end == 0) {
                    charIndex = end; return@forEach
                }
                val wLeft = layout.getBoundingBox(start).left
                val wRight = layout.getBoundingBox(end - 1).right
                val p = ((drivePos - w.start) / w.dur).coerceIn(0.0, 1.0).toFloat()
                if (p >= 1f) filledPx = wRight
                else if (p > 0f) { filledPx = wLeft + (wRight - wLeft) * p; charIndex = end; return@run }
                else { charIndex = end; return@run }
                charIndex = end
            }
        }

        drawText(layout, color = idleColor, topLeft = Offset(startX, topY))
        if (filledPx > 0f) {
            clipRect(left = startX, top = 0f, right = startX + filledPx, bottom = size.height) {
                drawText(layout, color = activeColor, topLeft = Offset(startX, topY))
            }
        }
    }
}

@Composable
private fun <T> OptionDialog(
    title: String,
    options: List<Pair<T, String>>,
    current: T,
    onSelect: (T) -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column {
                options.forEach { (value, label) ->
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .clickable(role = Role.RadioButton) { onSelect(value) }
                            .padding(vertical = NekoSpace.sm),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        RadioButton(selected = value == current, onClick = null)
                        Spacer(Modifier.width(NekoSpace.md))
                        Text(label, style = MaterialTheme.typography.bodyLarge)
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = {
            TextButton(onClick = onDismiss, colors = NekoDefaults.textButtonColors()) { Text(tr("取消")) }
        }
    )
}

@Composable
private fun QualityDialog(song: Song?, current: String, onSelect: (String) -> Unit, onDismiss: () -> Unit) {
    var options by remember(song) { mutableStateOf<List<top.nekoh2o.player.data.repo.AudioQuality>>(emptyList()) }
    var loading by remember(song) { mutableStateOf(true) }
    var error by remember(song) { mutableStateOf<String?>(null) }
    var retry by remember { mutableIntStateOf(0) }
    LaunchedEffect(song, retry) {
        loading = true; error = null
        try { options = song?.let { top.nekoh2o.player.data.repo.SongQualityRepository().downloadable(it) }.orEmpty() }
        catch (e: kotlinx.coroutines.CancellationException) { throw e }
        catch (e: Exception) { error = e.message ?: tr("音质查询失败") }
        finally { loading = false }
    }
    val preferred = top.nekoh2o.player.data.repo.SongQualityRepository.preferredFor(song?.source.orEmpty(), current)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(tr("下载音质")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(NekoSpace.sm)) {
                when {
                    loading -> Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(NekoSpace.md))
                        Text(tr("正在查询音质和下载权限…"))
                    }
                    error != null -> {
                        Text(error!!, color = MaterialTheme.colorScheme.error)
                        TextButton(onClick = { retry++ }) { Text(tr("重试")) }
                    }
                    options.isEmpty() -> Text(tr("当前账号没有可下载的音质，请登录对应音乐平台或检查歌曲版权。"))
                    else -> LazyColumn {
                        items(options, key = { it.id }) { option ->
                            Row(
                                Modifier
                                    .fillMaxWidth()
                                    .clickable { onSelect(option.id) }
                                    .padding(vertical = NekoSpace.md),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    option.label,
                                    style = MaterialTheme.typography.bodyLarge,
                                    fontWeight = if (option.id == preferred) FontWeight.Bold else FontWeight.Normal,
                                    modifier = Modifier.weight(1f)
                                )
                                if (option.size > 0) {
                                    Text(
                                        "%.1f MB".format(option.size / 1048576.0),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss, colors = NekoDefaults.textButtonColors()) { Text(tr("取消")) } }
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun QueueSheet(vm: PlayerViewModel, onDismiss: () -> Unit) {
    val state by vm.ui.collectAsState()
    val listState = rememberLazyListState()
    val reorderState = rememberReorderableLazyListState(listState) { from, to ->
        vm.moveInQueue(from.index, to.index)
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = NekoSpace.xl, vertical = NekoSpace.sm),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(tr("播放队列"), style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
            Text(tr("{count} 首", "count" to state.queue.size), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (state.queue.isEmpty()) {
            Box(Modifier.fillMaxWidth().padding(NekoSpace.xxl), Alignment.Center) {
                Text(tr("播放队列是空的"), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxWidth().heightIn(max = 480.dp),
                contentPadding = PaddingValues(bottom = NekoSpace.lg)
            ) {
                items(state.queue, key = { it.id }) { song ->
                    val index = state.queue.indexOf(song)
                    val playing = index == state.currentIndex
                    ReorderableItem(reorderState, key = song.id) { dragging ->
                        Surface(
                            color = if (dragging) MaterialTheme.colorScheme.surfaceContainerHighest else Color.Transparent,
                            modifier = Modifier.animateItem()
                        ) {
                            Row(
                                Modifier.fillMaxWidth().padding(start = NekoSpace.lg, end = NekoSpace.xs),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Row(
                                    Modifier
                                        .weight(1f)
                                        .clickableRow(
                                            rowLabel = "${song.nm}，${song.ar}" + if (playing) tr("，正在播放") else "",
                                            actionLabel = tr("播放")
                                        ) { vm.playAt(index); onDismiss() }
                                        .padding(vertical = NekoSpace.sm),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(NekoSpace.md)
                                ) {
                                    Box(contentAlignment = Alignment.Center) {
                                        Artwork(song.pc, size = 40.dp, thumbnail = 100)
                                        if (playing) Box(
                                            Modifier.size(40.dp).background(Color.Black.copy(alpha = 0.5f), RoundedCornerShape(NekoRadius.cover)),
                                            contentAlignment = Alignment.Center
                                        ) {
                                            Icon(Icons.Filled.GraphicEq, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
                                        }
                                    }
                                    Column(Modifier.weight(1f)) {
                                        Text(
                                            song.nm, maxLines = 1, overflow = TextOverflow.Ellipsis,
                                            style = MaterialTheme.typography.bodyLarge,
                                            color = if (playing) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
                                        )
                                        Text(
                                            song.ar, style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            maxLines = 1, overflow = TextOverflow.Ellipsis
                                        )
                                    }
                                }
                                IconButton(onClick = { vm.removeFromQueue(index) }) {
                                    Icon(Icons.Filled.Close, contentDescription = tr("移除"), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                Icon(
                                    Icons.Filled.DragHandle,
                                    contentDescription = tr("拖动排序"),
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.draggableHandle().padding(NekoSpace.md)
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
