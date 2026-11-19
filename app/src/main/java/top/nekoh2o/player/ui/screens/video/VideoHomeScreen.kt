package top.nekoh2o.player.ui.screens.video

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.material3.Surface
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import top.nekoh2o.player.data.bilibili.BiliAccount
import top.nekoh2o.player.data.bilibili.BiliSession
import top.nekoh2o.player.data.bilibili.VideoItem
import top.nekoh2o.player.data.repo.VideoCategory
import top.nekoh2o.player.data.repo.VideoRepository
import top.nekoh2o.player.data.store.VideoHistoryStore
import top.nekoh2o.player.data.store.VideoSettings
import top.nekoh2o.player.data.store.VideoSettingsStore
import top.nekoh2o.player.ui.screens.cloud.CloudFilesScreen
import top.nekoh2o.player.ui.theme.NekoSpace

sealed interface VideoRoute {
    data object Home : VideoRoute
    data class Search(val query: String) : VideoRoute
    data class Detail(val bvid: String, val startMs: Long) : VideoRoute
    data object Profile : VideoRoute
}

@Composable
fun VideoScreen() {
    val context = LocalContext.current
    val repo = remember { VideoRepository() }
    val settingsStore = remember { VideoSettingsStore(context) }
    val history = remember { VideoHistoryStore(context) }
    val settings by settingsStore.state.collectAsState()
    val account by BiliSession.account.collectAsState()

    val routeStack = remember { mutableStateListOf<VideoRoute>(VideoRoute.Home) }
    val route: VideoRoute = routeStack.last()
    fun push(next: VideoRoute) {
        routeStack.add(next)
    }
    fun pop() {
        if (routeStack.size > 1) routeStack.removeAt(routeStack.lastIndex)
    }
    var showLogin by remember { mutableStateOf(false) }
    var showCloud by remember { mutableStateOf(false) }
    var showDanmakuSheet by remember { mutableStateOf(false) }
    var showPlayerSheet by remember { mutableStateOf(false) }
    var historyVersion by remember { mutableIntStateOf(0) }

    BackHandler(enabled = routeStack.size > 1) { pop() }

    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        when (val r = route) {
            VideoRoute.Home -> VideoHomeContent(
                repo = repo,
                account = account,
                settings = settings,
                history = history,
                historyVersion = historyVersion,
                onOpenVideo = { bvid, start -> push(VideoRoute.Detail(bvid, start)) },
                onOpenSearch = { q -> push(VideoRoute.Search(q)) },
                onLogin = {
                    if (account.isLogin) {
                        push(VideoRoute.Profile)
                    } else {
                        showLogin = true
                    }
                }
            )
            VideoRoute.Profile -> VideoProfileScreen(
                account = account,
                history = history,
                historyVersion = historyVersion,
                onBack = { pop(); historyVersion++ },
                onLogin = { showLogin = true },
                onOpenVideo = { bvid -> push(VideoRoute.Detail(bvid, 0L)) },
                onOpenCloudFiles = { showCloud = true },
                onOpenPlayerSettings = { showPlayerSheet = true },
                onOpenDanmakuSettings = { showDanmakuSheet = true },
                onChanged = { historyVersion++ }
            )
            is VideoRoute.Search -> VideoSearchScreen(
                initialQuery = r.query,
                repo = repo,
                onBack = { pop() },
                onOpenVideo = { bvid -> push(VideoRoute.Detail(bvid, 0L)) }
            )
            is VideoRoute.Detail -> VideoDetailScreen(
                bvid = r.bvid,
                startMs = r.startMs,
                settings = settings,
                repo = repo,
                history = history,
                account = account,
                onBack = { pop(); historyVersion++ },
                onOpenVideo = { bvid -> push(VideoRoute.Detail(bvid, 0L)) },
                onLogin = { showLogin = true },
                onOpenDanmakuSettings = { showDanmakuSheet = true },
                onOpenPlayerSettings = { showPlayerSheet = true },
                onProgress = { _, _ -> },
                onSendDanmakuClick = {}
            )
        }
    }

    if (showCloud) {
        Dialog(
            onDismissRequest = { showCloud = false },
            properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)
        ) {
            Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                CloudFilesScreen(onBack = { showCloud = false })
            }
        }
    }

    if (showDanmakuSheet) {
        DanmakuSettingsSheet(
            settings = settings,
            onChange = { settingsStore.save(it) },
            onReset = { settingsStore.resetDanmaku() },
            onDismiss = { showDanmakuSheet = false }
        )
    }
    if (showPlayerSheet) {
        PlayerSettingsSheet(
            settings = settings,
            onChange = { settingsStore.save(it) },
            onReset = { settingsStore.resetPlayer() },
            onDismiss = { showPlayerSheet = false }
        )
    }
    if (showLogin) {
        VideoLoginScreen(
            repo = repo,
            onClose = { showLogin = false },
            onLoggedIn = {
                showLogin = false
                historyVersion++
            }
        )
    }
}

@Composable
private fun VideoHomeContent(
    repo: VideoRepository,
    account: BiliAccount,
    settings: VideoSettings,
    history: VideoHistoryStore,
    historyVersion: Int,
    onOpenVideo: (String, Long) -> Unit,
    onOpenSearch: (String) -> Unit,
    onLogin: () -> Unit
) {
    var category by remember { mutableStateOf(VideoCategory.RECOMMEND) }
    var items by remember { mutableStateOf<List<VideoItem>>(emptyList()) }
    var page by remember { mutableIntStateOf(1) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var resume by remember { mutableStateOf(history.resumeCandidates(8)) }
    val scope = rememberCoroutineScope()
    val gridState = rememberLazyGridState()

    suspend fun load(reset: Boolean) {
        loading = true
        error = null
        val target = if (reset) 1 else page + 1
        runCatching { repo.feed(category, target) }
            .onSuccess { pageData ->
                items = if (reset) pageData.items else (items + pageData.items).distinctBy { it.bvid }
                page = target
            }
            .onFailure { error = it.message ?: "加载失败" }
        loading = false
    }

    LaunchedEffect(category) {
        items = emptyList()
        load(true)
    }
    LaunchedEffect(historyVersion) { resume = history.resumeCandidates(8) }

    LazyVerticalGrid(
        state = gridState,
        columns = GridCells.Fixed(2),
        contentPadding = PaddingValues(bottom = 24.dp),
        horizontalArrangement = Arrangement.spacedBy(NekoSpace.md),
        verticalArrangement = Arrangement.spacedBy(NekoSpace.lg),
        modifier = Modifier.fillMaxSize().statusBarsPadding()
    ) {
        item(span = { GridItemSpan(maxLineSpan) }) {
            HomeHeader(account, onSearch = { onOpenSearch("") }, onLogin = onLogin)
        }
        item(span = { GridItemSpan(maxLineSpan) }) {
            LazyRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                contentPadding = PaddingValues(horizontal = NekoSpace.lg)
            ) {
                items(VideoCategory.entries) { c ->
                    VideoChip(c.label, c == category) { category = c }
                }
            }
        }
        if (resume.isNotEmpty()) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                Column {
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = NekoSpace.lg, vertical = NekoSpace.sm),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            "继续观看",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.weight(1f)
                        )
                        Text(
                            "全部",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.clickable { }
                        )
                    }
                    LazyRow(
                        horizontalArrangement = Arrangement.spacedBy(NekoSpace.md),
                        contentPadding = PaddingValues(horizontal = NekoSpace.lg)
                    ) {
                        items(resume, key = { it.bvid }) { entry ->
                            Column(
                                Modifier.width(200.dp).clip(RoundedCornerShape(16.dp)).clickable {
                                    onOpenVideo(entry.bvid, entry.positionMs)
                                }
                            ) {
                                val item = VideoItem(
                                    bvid = entry.bvid,
                                    aid = entry.aid,
                                    title = entry.title,
                                    cover = entry.cover,
                                    upName = entry.upName,
                                    durationSec = entry.durationSec
                                )
                                VideoCover(item, Modifier.fillMaxWidth(), entry.progress)
                                Spacer(Modifier.height(6.dp))
                                Text(
                                    entry.title,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurface,
                                    maxLines = 1,
                                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
                                )
                            }
                        }
                    }
                }
            }
        }
        item(span = { GridItemSpan(maxLineSpan) }) {
            SectionHeader(
                title = when (category) {
                    VideoCategory.RECOMMEND -> "为你推荐"
                    VideoCategory.FOLLOW -> "关注动态"
                    VideoCategory.HOT -> "热门"
                    else -> category.label
                },
                action = if (loading) "加载中…" else null
            )
        }

        if (error != null && items.isEmpty()) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                VideoEmptyState(
                    icon = Icons.Outlined.ErrorOutline,
                    title = "加载失败",
                    message = error,
                    action = "重试",
                    onAction = { scope.launch { load(true) } }
                )
            }
        } else if (items.isEmpty() && !loading) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                VideoEmptyState(
                    icon = Icons.Outlined.Movie,
                    title = if (category == VideoCategory.FOLLOW) "登录后查看关注动态" else "这里还没有内容",
                    message = if (category == VideoCategory.FOLLOW) "关注喜欢的 UP 主，新投稿会出现在这里" else null,
                    action = if (category == VideoCategory.FOLLOW) "去登录" else null,
                    onAction = onLogin
                )
            }
        }

        items(items, key = { it.bvid }) { video ->
            VideoGridCard(
                item = video,
                onClick = { onOpenVideo(video.bvid, 0L) },
                modifier = Modifier.padding(
                    start = if (gridState.layoutInfo.visibleItemsInfo.isEmpty()) NekoSpace.lg else 0.dp
                ).padding(
                    end = NekoSpace.md
                )
            )
        }

        if (items.isNotEmpty()) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                Box(Modifier.fillMaxWidth().padding(NekoSpace.lg), contentAlignment = Alignment.Center) {
                    if (loading) {
                        CircularProgressIndicator(
                            color = MaterialTheme.colorScheme.primary,
                            strokeWidth = 2.dp,
                            modifier = Modifier.size(22.dp)
                        )
                    } else if (error != null) {
                        TextButton(onClick = { scope.launch { load(false) } }) { Text("加载失败，点击重试") }
                    } else {
                        TextButton(onClick = { scope.launch { load(false) } }) { Text("加载更多") }
                    }
                }
            }
        }
    }
}

@Composable
private fun HomeHeader(account: BiliAccount, onSearch: () -> Unit, onLogin: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = NekoSpace.lg, vertical = NekoSpace.sm),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            "视频",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurface
        )
        Spacer(Modifier.weight(1f))
        IconButton(onClick = onSearch) {
            Icon(Icons.Filled.Search, "搜索", tint = MaterialTheme.colorScheme.onSurface)
        }
        Spacer(Modifier.width(4.dp))
        Box(Modifier.clickable(onClick = onLogin)) {
            Avatar(account.face, 34.dp)
        }
    }
}
