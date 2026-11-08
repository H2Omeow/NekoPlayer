package top.nekoh2o.player.ui.screens

import top.nekoh2o.player.i18n.NekoI18n.tr

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.RemoveCircleOutline
import androidx.compose.material.icons.outlined.Audiotrack
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.MusicNote
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import top.nekoh2o.player.data.model.Playlist
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.ui.PlayerViewModel
import top.nekoh2o.player.ui.UiState
import top.nekoh2o.player.ui.a11y.clickableRow
import top.nekoh2o.player.ui.components.Artwork
import top.nekoh2o.player.ui.components.ChipRow
import top.nekoh2o.player.ui.components.DetailTopBar
import top.nekoh2o.player.ui.components.EmptyState
import top.nekoh2o.player.ui.components.ScreenHeader
import top.nekoh2o.player.ui.components.SettingsSection
import top.nekoh2o.player.ui.components.SettingsTile
import top.nekoh2o.player.ui.components.SongActions
import top.nekoh2o.player.ui.components.SongRow
import top.nekoh2o.player.ui.components.songKey
import top.nekoh2o.player.ui.theme.NekoDefaults
import top.nekoh2o.player.ui.theme.NekoRadius
import top.nekoh2o.player.ui.theme.NekoSpace

enum class LibraryTab(private val rawLabel: String) {
    HISTORY("播放记录"),
    FAVORITES("我的收藏"),
    PLAYLISTS("歌单");

    val label: String get() = tr(rawLabel)
}

/** 「我的」页的回调。 */
class MineCallbacks(
    val onLogin: () -> Unit,
    val onLogout: () -> Unit,
    val onSettings: () -> Unit,
    val onNetease: () -> Unit,
    val onKugou: () -> Unit,
    val onCloudSync: () -> Unit,
    val onOpenPlaylist: (Int) -> Unit,
    val onCreatePlaylist: () -> Unit,
    val onDeletePlaylist: (Int) -> Unit
)

private enum class MinePage { HOME, SETTINGS, NETEASE, KUGOU, KUGOU_LOGIN, CLOUD_SYNC }

@Composable
fun MineScreen(
    vm: PlayerViewModel,
    libraryTab: LibraryTab,
    onLibraryTab: (LibraryTab) -> Unit,
    onStartSsoLogin: () -> Unit
) {
    val state by vm.ui.collectAsState()
    val sync by vm.cloudSync.state.collectAsState()
    var page by remember { mutableStateOf(MinePage.HOME) }
    var openedPlaylist by remember { mutableIntStateOf(-1) }
    var addTarget by remember { mutableStateOf<Song?>(null) }
    var creating by remember { mutableStateOf(false) }
    val actions = remember(vm) { vm.songActions { addTarget = it } }

    when {
        page == MinePage.SETTINGS -> SettingsScreen(vm) { page = MinePage.HOME }
        page == MinePage.NETEASE -> NeteaseScreen(vm) { page = MinePage.HOME }
        page == MinePage.KUGOU_LOGIN -> KugouLoginScreen(vm) { page = MinePage.HOME }
        page == MinePage.KUGOU -> KugouAccountScreen(
            vm = vm,
            onBack = { page = MinePage.HOME },
            onLogin = { page = MinePage.KUGOU_LOGIN }
        )
        page == MinePage.CLOUD_SYNC -> CloudSyncScreen(vm) { page = MinePage.HOME }
        openedPlaylist in state.playlists.indices -> PlaylistDetail(
            playlist = state.playlists[openedPlaylist],
            actions = actions,
            onRemove = { vm.removeFromPlaylist(openedPlaylist, it) },
            onBack = { openedPlaylist = -1 }
        )
        else -> MineContent(
            state = state,
            syncSummary = when {
                !state.loggedIn -> tr("登录后可用")
                sync.conflictCount > 0 -> tr("{count} 项需要处理", "count" to sync.conflictCount)
                else -> null
            },
            libraryTab = libraryTab,
            onLibraryTab = onLibraryTab,
            actions = actions,
            callbacks = remember(vm) {
                MineCallbacks(
                    onLogin = onStartSsoLogin,
                    onLogout = {
                        android.webkit.CookieManager.getInstance().removeAllCookies(null)
                        android.webkit.CookieManager.getInstance().flush()
                        vm.logout()
                    },
                    onSettings = { page = MinePage.SETTINGS },
                    onNetease = { page = MinePage.NETEASE },
                    onKugou = { page = MinePage.KUGOU },
                    onCloudSync = { page = MinePage.CLOUD_SYNC },
                    onOpenPlaylist = { openedPlaylist = it },
                    onCreatePlaylist = { creating = true },
                    onDeletePlaylist = vm::deletePlaylist
                )
            }
        )
    }

    addTarget?.let { song -> AddToPlaylistDialog(vm, song) { addTarget = null } }
    if (creating) CreatePlaylistDialog(
        onCreate = { vm.createPlaylist(it) },
        onDismiss = { creating = false }
    )
}

@Composable
fun MineContent(
    state: UiState,
    syncSummary: String?,
    libraryTab: LibraryTab,
    onLibraryTab: (LibraryTab) -> Unit,
    actions: SongActions,
    callbacks: MineCallbacks
) {
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = NekoSpace.xl)) {
        item {
            ScreenHeader(tr("我的")) {
                IconButton(onClick = callbacks.onSettings) {
                    Icon(Icons.Outlined.Settings, contentDescription = tr("设置"))
                }
            }
        }
        item {
            ProfileCard(
                state = state,
                onLogin = callbacks.onLogin,
                onLogout = callbacks.onLogout,
                modifier = Modifier.padding(horizontal = NekoSpace.lg, vertical = NekoSpace.sm)
            )
        }
        item {
            SettingsSection(
                modifier = Modifier.padding(horizontal = NekoSpace.lg, vertical = NekoSpace.sm)
            ) {
                SettingsTile(
                    title = tr("网易云音乐"),
                    icon = Icons.Outlined.MusicNote,
                    value = state.ncAccount.takeIf { it.isValid }?.nickname?.ifBlank { tr("已登录") } ?: tr("未登录"),
                    onClick = callbacks.onNetease
                )
                SettingsTile(
                    title = tr("酷狗音乐"),
                    icon = Icons.Outlined.Audiotrack,
                    value = state.kgAccount.takeIf { it.isValid }?.let { account ->
                        account.nickname.ifBlank { tr("已登录") } + if (account.platform == 1) " · " + tr("概念版") else ""
                    } ?: tr("未登录"),
                    onClick = callbacks.onKugou
                )
                SettingsTile(
                    title = tr("云端同步"),
                    icon = Icons.Outlined.Cloud,
                    value = syncSummary,
                    onClick = callbacks.onCloudSync
                )
            }
        }
        item {
            ChipRow(
                items = LibraryTab.entries,
                selected = libraryTab,
                label = { it.label },
                onSelect = onLibraryTab,
                modifier = Modifier.padding(top = NekoSpace.lg, bottom = NekoSpace.sm)
            )
        }
        when (libraryTab) {
            LibraryTab.HISTORY -> songList(
                state.history, state, actions,
                empty = { EmptyState(Icons.Filled.History, tr("还没有播放记录"), description = tr("播放过的歌曲会出现在这里。")) }
            )
            LibraryTab.FAVORITES -> songList(
                state.favorites, state, actions,
                empty = { EmptyState(Icons.Filled.FavoriteBorder, tr("还没有收藏"), description = tr("点歌曲旁的心形即可收藏。")) }
            )
            LibraryTab.PLAYLISTS -> playlistList(state.playlists, callbacks)
        }
    }
}

@Composable
private fun ProfileCard(
    state: UiState,
    onLogin: () -> Unit,
    onLogout: () -> Unit,
    modifier: Modifier = Modifier
) {
    val user = state.user
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(NekoRadius.artwork),
        color = MaterialTheme.colorScheme.surfaceContainer
    ) {
        Row(
            Modifier.padding(NekoSpace.lg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(NekoSpace.md)
        ) {
            Artwork(user?.avatar, size = 56.dp, shape = CircleShape, thumbnail = null, placeholder = Icons.Filled.Person)
            Column(Modifier.weight(1f)) {
                Text(
                    user?.nickname ?: user?.username ?: tr("未登录"),
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 1, overflow = TextOverflow.Ellipsis
                )
                Text(
                    if (state.loggedIn) tr("NekoPlayer 账号") else tr("登录后可在设备间同步收藏、歌单和播放记录"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2, overflow = TextOverflow.Ellipsis
                )
            }
            if (state.loggedIn) {
                OutlinedButton(onClick = onLogout, colors = NekoDefaults.outlinedButtonColors()) { Text(tr("退出")) }
            } else {
                Button(onClick = onLogin) { Text(tr("登录")) }
            }
        }
    }
}

private fun LazyListScope.songList(
    songs: List<Song>,
    state: UiState,
    actions: SongActions,
    empty: @Composable () -> Unit
) {
    if (songs.isEmpty()) {
        item { empty() }
        return
    }
    item { PlayAllRow(songs.size) { actions.playAll(songs) } }
    items(songs, key = { songKey(it) }) { song ->
        SongRow(
            song = song,
            isFav = actions.isFav(song),
            playing = state.current?.let { songKey(it) == songKey(song) } == true,
            onPlay = { actions.play(song) },
            onFav = { actions.toggleFav(song) },
            onAdd = { actions.queue(song) },
            onAddToPlaylist = { actions.addToPlaylist(song) },
            modifier = Modifier.animateItem()
        )
    }
}

@Composable
private fun PlayAllRow(count: Int, onPlayAll: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = NekoSpace.lg, vertical = NekoSpace.xs),
        verticalAlignment = Alignment.CenterVertically
    ) {
        FilledTonalButton(onClick = onPlayAll, contentPadding = PaddingValues(horizontal = NekoSpace.lg)) {
            Icon(Icons.Filled.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(NekoSpace.xs))
            Text(tr("播放全部"))
        }
        Spacer(Modifier.width(NekoSpace.md))
        Text(tr("{count} 首", "count" to count), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private fun LazyListScope.playlistList(playlists: List<Playlist>, callbacks: MineCallbacks) {
    item {
        Row(
            Modifier
                .fillMaxWidth()
                .clickableRow(rowLabel = tr("新建歌单"), actionLabel = tr("新建"), onClick = callbacks.onCreatePlaylist)
                .padding(horizontal = NekoSpace.lg, vertical = NekoSpace.sm),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(NekoSpace.md)
        ) {
            Surface(Modifier.size(52.dp), shape = RoundedCornerShape(NekoRadius.cover), color = MaterialTheme.colorScheme.surfaceContainerHigh) {
                Box(contentAlignment = Alignment.Center) { Icon(Icons.Filled.Add, contentDescription = null) }
            }
            Text(tr("新建歌单"), style = MaterialTheme.typography.bodyLarge)
        }
    }
    if (playlists.isEmpty()) item {
        EmptyState(Icons.AutoMirrored.Filled.QueueMusic, tr("还没有自己的歌单"), description = tr("新建歌单后，可以在歌曲菜单中把歌加进来。"))
    }
    itemsIndexed(playlists) { index, playlist ->
        Row(
            Modifier.fillMaxWidth().padding(start = NekoSpace.lg, end = NekoSpace.xs),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                Modifier
                    .weight(1f)
                    .clickableRow(rowLabel = tr("{name}，{count} 首", "name" to playlist.name, "count" to playlist.songs.size), actionLabel = tr("打开歌单")) {
                        callbacks.onOpenPlaylist(index)
                    }
                    .padding(vertical = NekoSpace.sm),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(NekoSpace.md)
            ) {
                Artwork(playlist.songs.firstOrNull()?.pc, size = 52.dp, placeholder = Icons.AutoMirrored.Filled.QueueMusic)
                Column(Modifier.weight(1f)) {
                    Text(playlist.name, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(
                        tr("{count} 首", "count" to playlist.songs.size), style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            IconButton(onClick = { callbacks.onDeletePlaylist(index) }) {
                Icon(Icons.Filled.Delete, contentDescription = tr("删除歌单"), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun PlaylistDetail(
    playlist: Playlist,
    actions: SongActions,
    onRemove: (Int) -> Unit,
    onBack: () -> Unit
) {
    Column(Modifier.fillMaxSize()) {
        DetailTopBar(playlist.name, onBack)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = NekoSpace.xl)) {
            if (playlist.songs.isEmpty()) {
                item { EmptyState(Icons.AutoMirrored.Filled.QueueMusic, tr("歌单是空的"), description = tr("在歌曲菜单中选择「加入歌单」。")) }
            } else {
                item { PlayAllRow(playlist.songs.size) { actions.playAll(playlist.songs) } }
                itemsIndexed(playlist.songs) { index, song ->
                    SongRow(
                        song = song,
                        isFav = actions.isFav(song),
                        onPlay = { actions.play(song) },
                        onFav = { actions.toggleFav(song) },
                        trailing = {
                            IconButton(onClick = { onRemove(index) }) {
                                Icon(
                                    Icons.Filled.RemoveCircleOutline, contentDescription = tr("从歌单移除"),
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    )
                }
            }
        }
    }
}

@Composable
fun CreatePlaylistDialog(onCreate: (String) -> Unit, onDismiss: () -> Unit) {
    var name by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(tr("新建歌单")) },
        text = {
            OutlinedTextField(
                value = name, onValueChange = { name = it },
                singleLine = true, label = { Text(tr("歌单名称")) },
                colors = NekoDefaults.textFieldColors()
            )
        },
        confirmButton = {
            TextButton(
                onClick = { if (name.isNotBlank()) onCreate(name.trim()); onDismiss() },
                enabled = name.isNotBlank()
            ) { Text(tr("创建")) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, colors = NekoDefaults.textButtonColors()) { Text(tr("取消")) }
        }
    )
}
