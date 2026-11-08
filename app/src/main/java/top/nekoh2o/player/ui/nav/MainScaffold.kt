package top.nekoh2o.player.ui.nav

import top.nekoh2o.player.i18n.NekoI18n.tr

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.LibraryMusic
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.SocialDeepLink
import top.nekoh2o.player.SocialDeepLinks
import top.nekoh2o.player.ui.PlayerViewModel
import top.nekoh2o.player.ui.a11y.clickableRow
import top.nekoh2o.player.ui.components.Artwork
import top.nekoh2o.player.ui.components.LocalSongShareHandler
import top.nekoh2o.player.ui.screens.HomeScreen
import top.nekoh2o.player.ui.screens.LibraryTab
import top.nekoh2o.player.ui.screens.MineScreen
import top.nekoh2o.player.ui.screens.MusicScreen
import top.nekoh2o.player.ui.social.SocialScreen
import top.nekoh2o.player.ui.theme.NekoRadius
import top.nekoh2o.player.ui.theme.NekoSpace

enum class Tab(private val rawLabel: String, val icon: ImageVector, val selectedIcon: ImageVector) {
    HOME("主页", Icons.Outlined.Home, Icons.Filled.Home),
    MUSIC("音乐", Icons.Outlined.LibraryMusic, Icons.Filled.LibraryMusic),
    SOCIAL("社区", Icons.Outlined.ChatBubbleOutline, Icons.Filled.ChatBubble),
    MINE("我的", Icons.Outlined.Person, Icons.Filled.Person);

    val label: String get() = tr(rawLabel)
}

@Composable
fun MainScaffold(
    vm: PlayerViewModel,
    onOpenFullPlayer: () -> Unit,
    onStartSsoLogin: () -> Unit
) {
    val state by vm.ui.collectAsState()
    val socialState by vm.socialVm.state.collectAsState()
    val pendingDeepLink by SocialDeepLinks.pending.collectAsState()
    var tab by rememberSaveable { mutableStateOf(Tab.HOME) }
    var libraryTab by rememberSaveable { mutableStateOf(LibraryTab.HISTORY) }
    val snackbar = remember { SnackbarHostState() }

    LaunchedEffect(state.toast) {
        state.toast?.let {
            snackbar.showSnackbar(it)
            vm.clearToast()
        }
    }

    LaunchedEffect(socialState.toast) {
        socialState.toast?.let {
            snackbar.showSnackbar(it)
            vm.socialVm.clearToast()
        }
    }

    LaunchedEffect(state.loggedIn) {
        if (state.loggedIn) vm.socialVm.start() else vm.socialVm.stop()
    }

    LaunchedEffect(pendingDeepLink, state.loggedIn) {
        val link = pendingDeepLink ?: return@LaunchedEffect
        when (link) {
            is SocialDeepLink.Share -> {
                tab = Tab.SOCIAL
                vm.socialVm.openShareToken(link.token)
                SocialDeepLinks.consume()
            }
            is SocialDeepLink.Chat -> {
                tab = Tab.SOCIAL
                if (state.loggedIn) {
                    vm.socialVm.openChat(link.peerId)
                    SocialDeepLinks.consume()
                }
            }
            is SocialDeepLink.User -> {
                tab = Tab.SOCIAL
                if (state.loggedIn) {
                    vm.socialVm.loadProfile(link.userId)
                    SocialDeepLinks.consume()
                }
            }
        }
    }

    fun select(target: Tab) {
        tab = target
        if (target == Tab.MUSIC && state.recSongs.isEmpty()) vm.loadRecommend()
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val useRail = maxWidth >= 600.dp
        // 开了全局背景时铺壁纸并让 Scaffold 透明；控件透明度由 NekoTheme 统一处理
        val wallpaper = state.wallpaperUrl.takeIf { state.settings.globalBgEnabled }
        if (wallpaper != null) {
            AsyncImage(
                model = wallpaper,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().blur(state.settings.globalBlurRadius.dp)
            )
            Box(
                Modifier.fillMaxSize()
                    .background(Color.Black.copy(alpha = state.settings.globalMaskAlpha))
            )
        }

        CompositionLocalProvider(
            LocalSongShareHandler provides { song -> vm.socialVm.openShareComposer(song) }
        ) {
        MainLayout(
            tab = tab,
            useRail = useRail,
            transparent = wallpaper != null,
            snackbar = snackbar,
            socialUnread = socialState.unread,
            onSelect = ::select,
            miniPlayer = {
                state.current?.let { song ->
                    MiniPlayer(
                        song = song,
                        isPlaying = state.isPlaying,
                        progress = if (state.durationMs > 0)
                            (state.positionMs.toFloat() / state.durationMs).coerceIn(0f, 1f) else 0f,
                        onOpen = onOpenFullPlayer,
                        onToggle = vm::togglePlay,
                        onNext = vm::next
                    )
                }
            }
        ) {
            when (tab) {
                Tab.HOME -> HomeScreen(
                    vm = vm,
                    onOpenFullPlayer = onOpenFullPlayer,
                    onBrowse = { select(Tab.MUSIC) },
                    onOpenLibrary = { libraryTab = it; select(Tab.MINE) }
                )
                Tab.MUSIC -> MusicScreen(vm)
                Tab.SOCIAL -> SocialScreen(vm, onStartSsoLogin)
                Tab.MINE -> MineScreen(
                    vm = vm,
                    libraryTab = libraryTab,
                    onLibraryTab = { libraryTab = it },
                    onStartSsoLogin = onStartSsoLogin
                )
            }
        }
        }
    }
}

/** 主界面框架：窄屏底部导航，宽屏左侧导航栏；迷你播放器贴在导航上方。 */
@Composable
fun MainLayout(
    tab: Tab,
    useRail: Boolean,
    transparent: Boolean,
    snackbar: SnackbarHostState,
    socialUnread: Int,
    onSelect: (Tab) -> Unit,
    miniPlayer: @Composable () -> Unit,
    content: @Composable () -> Unit
) {
    val colors = MaterialTheme.colorScheme
    val itemColors = NavigationBarItemDefaults.colors(
        selectedIconColor = colors.primary,
        selectedTextColor = colors.onSurface,
        indicatorColor = colors.primary.copy(alpha = 0.16f),
        unselectedIconColor = colors.onSurfaceVariant,
        unselectedTextColor = colors.onSurfaceVariant
    )
    val railColors = NavigationRailItemDefaults.colors(
        selectedIconColor = colors.primary,
        selectedTextColor = colors.onSurface,
        indicatorColor = colors.primary.copy(alpha = 0.16f),
        unselectedIconColor = colors.onSurfaceVariant,
        unselectedTextColor = colors.onSurfaceVariant
    )
    Scaffold(
        containerColor = if (transparent) Color.Transparent else colors.background,
        snackbarHost = { SnackbarHost(snackbar) },
        bottomBar = {
            Column {
                miniPlayer()
                if (!useRail) NavigationBar(
                    containerColor = colors.surfaceContainerLow,
                    tonalElevation = 0.dp
                ) {
                    Tab.entries.forEach { t ->
                        NavigationBarItem(
                            selected = tab == t,
                            onClick = { onSelect(t) },
                            icon = {
                                TabIcon(
                                    tab = t,
                                    selected = tab == t,
                                    unread = if (t == Tab.SOCIAL) socialUnread else 0
                                )
                            },
                            label = { Text(t.label) },
                            colors = itemColors
                        )
                    }
                }
            }
        }
    ) { pad ->
        Row(Modifier.padding(pad)) {
            if (useRail) NavigationRail(
                Modifier.fillMaxHeight(),
                containerColor = colors.surfaceContainerLow,
                header = {
                    Text(
                        "Neko",
                        Modifier.padding(vertical = NekoSpace.xl),
                        style = MaterialTheme.typography.titleMedium,
                        color = colors.primary
                    )
                }
            ) {
                Tab.entries.forEach { t ->
                    NavigationRailItem(
                        selected = tab == t,
                        onClick = { onSelect(t) },
                        icon = {
                            TabIcon(
                                tab = t,
                                selected = tab == t,
                                unread = if (t == Tab.SOCIAL) socialUnread else 0
                            )
                        },
                        label = { Text(t.label) },
                        colors = railColors,
                        modifier = Modifier.padding(vertical = NekoSpace.sm)
                    )
                }
            }
            Box(Modifier.weight(1f)) { content() }
        }
    }
}

/** 底部/侧边导航图标；社区未读用 Badge 叠在图标右上角。 */
@Composable
private fun TabIcon(tab: Tab, selected: Boolean, unread: Int) {
    val icon = if (selected) tab.selectedIcon else tab.icon
    if (unread > 0) {
        BadgedBox(badge = {
            Badge { Text(if (unread > 99) "99+" else unread.toString()) }
        }) {
            Icon(icon, contentDescription = null)
        }
    } else {
        Icon(icon, contentDescription = null)
    }
}

/** 底部迷你播放器：点封面或标题打开全屏播放器。 */
@Composable
fun MiniPlayer(
    song: Song,
    isPlaying: Boolean,
    progress: Float,
    onOpen: () -> Unit,
    onToggle: () -> Unit,
    onNext: () -> Unit
) {
    val colors = MaterialTheme.colorScheme
    Surface(
        modifier = Modifier.padding(horizontal = NekoSpace.sm, vertical = NekoSpace.xs),
        shape = RoundedCornerShape(NekoRadius.card),
        color = colors.surfaceContainerHigh
    ) {
        Column {
            Row(
                Modifier.fillMaxWidth().padding(start = NekoSpace.sm, end = NekoSpace.xs, top = NekoSpace.sm, bottom = 6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    Modifier.weight(1f).clickableRow(rowLabel = "${song.nm}，${song.ar}", actionLabel = tr("打开播放器"), onClick = onOpen),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Artwork(song.pc, size = 44.dp, thumbnail = 100)
                    Spacer(Modifier.width(NekoSpace.md))
                    Column(Modifier.weight(1f)) {
                        Text(song.nm, maxLines = 1, overflow = TextOverflow.Ellipsis,
                            style = MaterialTheme.typography.titleSmall)
                        Text(song.ar, maxLines = 1, overflow = TextOverflow.Ellipsis,
                            style = MaterialTheme.typography.bodySmall, color = colors.onSurfaceVariant)
                    }
                }
                IconButton(onClick = onToggle) {
                    AnimatedContent(
                        targetState = isPlaying,
                        transitionSpec = {
                            (fadeIn(tween(150)) + scaleIn(tween(150), initialScale = 0.8f))
                                .togetherWith(fadeOut(tween(150)) + scaleOut(tween(150), targetScale = 0.8f))
                        },
                        label = "play_pause_mini"
                    ) { playing ->
                        Icon(
                            if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                            contentDescription = if (playing) tr("暂停") else tr("播放"),
                            modifier = Modifier.size(30.dp)
                        )
                    }
                }
                IconButton(onClick = onNext) {
                    Icon(Icons.Filled.SkipNext, contentDescription = tr("下一首"))
                }
            }
            // 进度条贴在卡片底边，圆角裁切
            Box(
                Modifier
                    .padding(horizontal = NekoSpace.md)
                    .padding(bottom = 6.dp)
                    .fillMaxWidth()
                    .height(2.dp)
                    .clip(RoundedCornerShape(1.dp))
                    .background(colors.onSurface.copy(alpha = 0.12f))
            ) {
                Box(
                    Modifier
                        .fillMaxWidth(progress)
                        .fillMaxHeight()
                        .background(colors.primary)
                )
            }
        }
    }
}
