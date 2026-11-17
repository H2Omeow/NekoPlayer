package top.nekoh2o.player.ui.screens.video

import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import top.nekoh2o.player.data.bilibili.BiliAccount
import top.nekoh2o.player.data.bilibili.CommentItem
import top.nekoh2o.player.data.bilibili.DanmakuItem
import top.nekoh2o.player.data.bilibili.PlaySource
import top.nekoh2o.player.data.bilibili.VideoDetail
import top.nekoh2o.player.data.bilibili.VideoItem
import top.nekoh2o.player.data.repo.VideoRepository
import top.nekoh2o.player.data.store.VideoHistoryStore
import top.nekoh2o.player.data.store.WatchEntry
import top.nekoh2o.player.data.store.VideoSettings
import top.nekoh2o.player.ui.theme.NekoRadius
import top.nekoh2o.player.ui.theme.NekoSpace

@Composable
fun VideoDetailScreen(
    bvid: String,
    startMs: Long,
    settings: VideoSettings,
    repo: VideoRepository,
    history: VideoHistoryStore,
    account: BiliAccount,
    onBack: () -> Unit,
    onOpenVideo: (String) -> Unit,
    onLogin: () -> Unit,
    onOpenDanmakuSettings: () -> Unit,
    onOpenPlayerSettings: () -> Unit,
    onProgress: (Long, Long) -> Unit,
    onSendDanmakuClick: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var detail by remember { mutableStateOf<VideoDetail?>(null) }
    var source by remember { mutableStateOf<PlaySource?>(null) }
    var danmaku by remember { mutableStateOf<List<DanmakuItem>>(emptyList()) }
    var related by remember { mutableStateOf<List<VideoItem>>(emptyList()) }
    var comments by remember { mutableStateOf<List<CommentItem>>(emptyList()) }
    var commentCount by remember { mutableIntStateOf(0) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var fullscreen by remember { mutableStateOf(false) }
    var positionMs by remember { mutableLongStateOf(startMs) }
    var tab by remember { mutableIntStateOf(0) }

    LaunchedEffect(bvid) {
        loading = true
        error = null
        runCatching { repo.detail(bvid) }
            .onSuccess { d ->
                detail = d
                runCatching { repo.related(bvid) }.onSuccess { related = it }
                runCatching { repo.play(bvid, d.cid, settings.player.defaultQuality) }
                    .onSuccess { source = it }
                    .onFailure { error = "无法获取播放地址：${it.message}" }
                runCatching { repo.danmaku(d.cid, d.item.aid, d.item.durationSec) }
                    .onSuccess { danmaku = it }
                runCatching { repo.comments(d.item.aid) }
                    .onSuccess { r -> comments = r.first; commentCount = r.second }
            }
            .onFailure { error = it.message ?: "加载失败" }
        loading = false
    }

    // 播放进度落盘
    LaunchedEffect(bvid, detail) {
        val d = detail ?: return@LaunchedEffect
        while (true) {
            kotlinx.coroutines.delay(3000)
            if (positionMs > 3000 && d.item.durationSec > 0) {
                history.upsert(
                    WatchEntry(
                        bvid = d.item.bvid,
                        aid = d.item.aid,
                        cid = d.cid,
                        title = d.item.title,
                        cover = d.item.cover,
                        upName = d.item.upName,
                        durationSec = d.item.durationSec,
                        positionMs = positionMs
                    )
                )
            }
        }
    }

    val activity = remember(context) { context.activity() }
    DisposableEffect(fullscreen) {
        val window = activity?.window
        val controller = window?.let { WindowCompat.getInsetsController(it, it.decorView) }
        if (fullscreen) {
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            controller?.hide(WindowInsetsCompat.Type.systemBars())
            controller?.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        } else {
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            controller?.show(WindowInsetsCompat.Type.systemBars())
        }
        onDispose {
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            controller?.show(WindowInsetsCompat.Type.systemBars())
        }
    }

    BackHandler(enabled = fullscreen) { fullscreen = false }

    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        if (loading) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
            }
        } else if (detail == null) {
            VideoEmptyState(
                icon = Icons.Outlined.ErrorOutline,
                title = "视频加载失败",
                message = error,
                action = "返回",
                onAction = onBack,
                modifier = Modifier.align(Alignment.Center)
            )
        } else {
            val d = detail!!
            val listState = rememberLazyListState()
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .then(if (fullscreen) Modifier else Modifier.imePadding()),
                contentPadding = if (fullscreen) PaddingValues(0.dp)
                else PaddingValues(bottom = 72.dp)
            ) {
                item {
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .then(if (fullscreen) Modifier.fillMaxHeight() else Modifier.aspectRatio(16f / 9f))
                    ) {
                        VideoPlayerBox(
                            source = source,
                            title = d.item.title,
                            danmaku = danmaku,
                            danmakuSettings = settings.danmaku,
                            playerSettings = settings.player,
                            startPositionMs = startMs,
                            fullscreen = fullscreen,
                            onToggleFullscreen = { fullscreen = !fullscreen },
                            onBack = { if (fullscreen) fullscreen = false else onBack() },
                            onEnded = {},
                            onProgress = { pos, _ -> positionMs = pos; onProgress(pos, d.item.durationSec * 1000L) },
                            onOpenDanmakuSettings = onOpenDanmakuSettings,
                            onOpenPlayerSettings = onOpenPlayerSettings,
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                }
                if (!fullscreen) {
                    item { DetailHeader(d, account, scope, repo, onLogin) }
                    item {
                        DetailActions(
                            d = d,
                            loggedIn = account.isLogin,
                            onLike = { scope.launch { toast(context, runCatching { repo.like(d.item.aid) }.getOrDefault(false), "点赞") } },
                            onCoin = { scope.launch { toast(context, runCatching { repo.coin(d.item.aid) }.getOrDefault(false), "投币") } },
                            onFavorite = { scope.launch { toast(context, runCatching { repo.favorite(d.item.aid) }.getOrDefault(false), "收藏") } },
                            onShare = { toast(context, true, "已复制链接") },
                            onWatchLater = { toast(context, true, "已加入稍后再看") },
                            onDanmakuSettings = onOpenDanmakuSettings
                        )
                    }
                    item { UpRow(d, account, onLogin, onOpenVideo) }
                    item {
                        DetailTabs(tab, commentCount) { tab = it }
                    }
                    when (tab) {
                        0 -> item { DescriptionBlock(d) }
                        1 -> {
                            if (comments.isEmpty()) {
                                item {
                                    Text(
                                        "还没有评论，或评论加载失败",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.padding(NekoSpace.lg)
                                    )
                                }
                            } else {
                                items(comments, key = { it.rpid }) { CommentRow(it) }
                            }
                        }
                        else -> items(related, key = { it.bvid }) { item ->
                            VideoListRow(
                                item,
                                onClick = { onOpenVideo(item.bvid) },
                                modifier = Modifier.padding(horizontal = NekoSpace.lg)
                            )
                        }
                    }
                }
            }

            if (!fullscreen) {
                DanmakuInputBar(
                    onSend = { text ->
                        val cid = d.cid
                        scope.launch {
                            val ok = runCatching {
                                repo.postDanmaku(
                                    cid = cid,
                                    aid = d.item.aid,
                                    content = text,
                                    progressMs = positionMs,
                                    mode = if (settings.danmaku.showScroll) 1 else 5,
                                    fontSize = 25,
                                    color = 0xFFFFFF
                                )
                            }.getOrDefault(false)
                            if (ok) {
                                danmaku = danmaku + DanmakuItem(
                                    id = System.currentTimeMillis(),
                                    progressMs = positionMs,
                                    mode = 1,
                                    fontSize = 25,
                                    color = 0xFFFFFF,
                                    content = text,
                                    weight = 10
                                )
                            }
                            toast(context, ok, if (ok) "弹幕已发送" else "发送失败（需登录）")
                        }
                    },
                    onOpenSettings = onOpenDanmakuSettings,
                    modifier = Modifier.align(Alignment.BottomCenter)
                )
            }
        }
    }
}

private fun Context.activity(): ComponentActivity? {
    var ctx: android.content.Context? = this
    while (ctx is ContextWrapper) {
        if (ctx is ComponentActivity) return ctx
        ctx = ctx.baseContext
    }
    return null
}

private fun toast(context: android.content.Context, ok: Boolean, action: String) {
    val msg = if (ok) "$action 成功" else "$action 失败，请先登录 B 站账号"
    Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
}

@Composable
private fun DetailHeader(
    d: VideoDetail,
    account: BiliAccount,
    scope: kotlinx.coroutines.CoroutineScope,
    repo: VideoRepository,
    onLogin: () -> Unit
) {
    Column(Modifier.padding(horizontal = NekoSpace.lg)) {
        Spacer(Modifier.height(NekoSpace.md))
        Text(
            d.item.title,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface
        )
        Spacer(Modifier.height(6.dp))
        Text(
            buildString {
                if (d.item.views > 0) append("${formatCount(d.item.views)}播放 · ")
                append("${formatCount(d.item.danmakuCount)}弹幕")
                if (d.item.pubdate > 0) append(" · ${formatDate(d.item.pubdate)}")
                append(" · bilibili")
            },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun DetailActions(
    d: VideoDetail,
    loggedIn: Boolean,
    onLike: () -> Unit,
    onCoin: () -> Unit,
    onFavorite: () -> Unit,
    onShare: () -> Unit,
    onWatchLater: () -> Unit,
    onDanmakuSettings: () -> Unit
) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = NekoSpace.lg, vertical = NekoSpace.md),
        horizontalArrangement = Arrangement.SpaceEvenly
    ) {
        ActionItem(Icons.Outlined.FavoriteBorder, formatCount(d.stat.like), onLike)
        ActionItem(Icons.Outlined.MonetizationOn, formatCount(d.stat.coin), onCoin)
        ActionItem(Icons.Outlined.StarBorder, formatCount(d.stat.favorite), onFavorite)
        ActionItem(Icons.Outlined.Share, "分享", onShare)
        ActionItem(Icons.Outlined.Subtitles, "弹幕设置", onDanmakuSettings)
    }
    if (!loggedIn) {
        Text(
            "登录后即可点赞、投币、收藏与发送弹幕",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = NekoSpace.lg)
        )
    }
}

@Composable
private fun ActionItem(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 6.dp)
    ) {
        Icon(icon, contentDescription = label, tint = MaterialTheme.colorScheme.onSurface, modifier = Modifier.size(22.dp))
        Spacer(Modifier.height(4.dp))
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun UpRow(d: VideoDetail, account: BiliAccount, onLogin: () -> Unit, onOpenVideo: (String) -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = NekoSpace.lg, vertical = NekoSpace.sm)
            .clip(RoundedCornerShape(NekoRadius.card))
            .background(MaterialTheme.colorScheme.surfaceContainerLow)
            .padding(NekoSpace.md),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Avatar(d.owner.face, 40.dp)
        Spacer(Modifier.width(NekoSpace.md))
        Column(Modifier.weight(1f)) {
            Text(
                d.owner.name,
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurface
            )
            Text(
                "UP 主 · 关注收取更新",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Text(
            if (account.isLogin) "已登录" else "登录",
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onPrimary,
            modifier = Modifier
                .clip(RoundedCornerShape(50))
                .background(MaterialTheme.colorScheme.primary)
                .clickable { if (!account.isLogin) onLogin() }
                .padding(horizontal = 16.dp, vertical = 6.dp)
        )
    }
}

@Composable
private fun DetailTabs(tab: Int, commentCount: Int, onSelect: (Int) -> Unit) {
    val labels = listOf("简介", "评论 ${formatCount(commentCount.toLong())}", "相关推荐")
    Row(Modifier.fillMaxWidth().padding(horizontal = NekoSpace.lg, vertical = NekoSpace.sm)) {
        labels.forEachIndexed { i, label ->
            Column(
                Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .clickable { onSelect(i) }
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    label,
                    style = MaterialTheme.typography.titleSmall,
                    color = if (tab == i) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
                    fontWeight = if (tab == i) FontWeight.SemiBold else FontWeight.Normal
                )
                Spacer(Modifier.height(4.dp))
                Box(
                    Modifier
                        .width(18.dp)
                        .height(2.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(if (tab == i) MaterialTheme.colorScheme.primary else Color.Transparent)
                )
            }
        }
    }
}

@Composable
private fun DescriptionBlock(d: VideoDetail) {
    var expanded by remember { mutableStateOf(false) }
    Column(Modifier.padding(horizontal = NekoSpace.lg, vertical = NekoSpace.sm)) {
        Text(
            d.desc.ifBlank { "暂无简介" },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = if (expanded) Int.MAX_VALUE else 3,
            overflow = TextOverflow.Ellipsis
        )
        if (d.desc.length > 80) {
            Text(
                if (expanded) "收起" else "展开全部简介",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier
                    .clickable { expanded = !expanded }
                    .padding(top = 6.dp)
            )
        }
        Spacer(Modifier.height(NekoSpace.sm))
        Text(
            "分区：${d.tname.ifBlank { "视频" }}" + if (d.copyright == 2) " · 转载" else "",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun CommentRow(c: CommentItem) {
    Row(Modifier.fillMaxWidth().padding(horizontal = NekoSpace.lg, vertical = NekoSpace.sm)) {
        Avatar(c.face, 32.dp)
        Spacer(Modifier.width(NekoSpace.md))
        Column(Modifier.weight(1f)) {
            Text(c.uname, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(2.dp))
            Text(c.content, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface)
            Spacer(Modifier.height(4.dp))
            Text(
                "${formatCount(c.like)} 赞" + if (c.ctime > 0) " · ${formatDate(c.ctime)}" else "",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun DanmakuInputBar(onSend: (String) -> Unit, onOpenSettings: () -> Unit, modifier: Modifier = Modifier) {
    var text by remember { mutableStateOf("") }
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainer,
        tonalElevation = 0.dp,
        modifier = modifier.fillMaxWidth()
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = NekoSpace.md, vertical = NekoSpace.sm),
            verticalAlignment = Alignment.CenterVertically
        ) {
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                placeholder = { Text("发个友善的弹幕见证当下", style = MaterialTheme.typography.bodySmall) },
                textStyle = MaterialTheme.typography.bodySmall,
                singleLine = true,
                shape = RoundedCornerShape(50),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                keyboardActions = KeyboardActions(onSend = {
                    if (text.isNotBlank()) {
                        onSend(text.trim())
                        text = ""
                    }
                }),
                modifier = Modifier.weight(1f).height(44.dp)
            )
            IconButton(onClick = onOpenSettings) {
                Icon(Icons.Outlined.Settings, "弹幕设置", tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            TextButton(onClick = {
                if (text.isNotBlank()) {
                    onSend(text.trim())
                    text = ""
                }
            }) { Text("发送") }
        }
    }
}
