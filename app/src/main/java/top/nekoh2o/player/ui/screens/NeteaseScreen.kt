package top.nekoh2o.player.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Person
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import top.nekoh2o.player.data.model.NcAccountResp
import top.nekoh2o.player.data.model.NcPlaylistItem
import top.nekoh2o.player.data.model.NcRecordItem
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.data.net.CookieStore
import top.nekoh2o.player.ui.PlayerViewModel
import top.nekoh2o.player.ui.components.Artwork
import top.nekoh2o.player.ui.components.ChipRow
import top.nekoh2o.player.ui.components.DetailTopBar
import top.nekoh2o.player.ui.components.EmptyState
import top.nekoh2o.player.ui.components.SongRow
import top.nekoh2o.player.ui.components.StatusBadge
import top.nekoh2o.player.ui.theme.NekoDefaults
import top.nekoh2o.player.ui.theme.NekoRadius
import top.nekoh2o.player.ui.theme.NekoSpace

/**
 * 网易云音乐界面
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NeteaseScreen(vm: PlayerViewModel, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    val hasNcCookie = remember { CookieStore.hasNcUserCookie() }
    var showQrLogin by remember { mutableStateOf(!hasNcCookie) }
    var ncAccount by remember { mutableStateOf<NcAccountResp?>(null) }
    var loading by remember { mutableStateOf(false) }
    var currentTab by remember { mutableIntStateOf(0) }

    // 歌单、红心、播放记录
    var playlists by remember { mutableStateOf<List<NcPlaylistItem>>(emptyList()) }
    var likeSongs by remember { mutableStateOf<List<Song>>(emptyList()) }
    var playRecords by remember { mutableStateOf<List<NcRecordItem>>(emptyList()) }

    // 加载网易云账号信息
    LaunchedEffect(hasNcCookie) {
        if (hasNcCookie && !showQrLogin) {
            loading = true
            ncAccount = vm.fetchNcAccount()
            loading = false
        }
    }

    if (showQrLogin) {
        QrLoginDialog(vm) {
            showQrLogin = false
            // 登录成功后刷新
            scope.launch {
                loading = true
                ncAccount = vm.fetchNcAccount()
                loading = false
            }
        }
        return
    }

    Column(Modifier.fillMaxSize()) {
        DetailTopBar("网易云音乐", onBack)
        Column(Modifier.fillMaxSize()) {
            NcAccountCard(ncAccount, loading) {
                showQrLogin = true
            }

            if (ncAccount != null) {
                ChipRow(
                    items = listOf(0, 1, 2),
                    selected = currentTab,
                    label = { listOf("歌单", "红心", "播放记录")[it] },
                    onSelect = { currentTab = it },
                    modifier = Modifier.padding(vertical = NekoSpace.sm)
                )

                // 内容区域
                when (currentTab) {
                    0 -> NcPlaylistTab(vm, ncAccount, playlists, loading) { list ->
                        playlists = list
                    }
                    1 -> NcLikeSongsTab(vm, ncAccount, likeSongs, loading) { songs ->
                        likeSongs = songs
                    }
                    2 -> NcPlayRecordTab(vm, ncAccount, playRecords, loading) { records ->
                        playRecords = records
                    }
                }
            }
        }
    }
}

@Composable
private fun NcAccountCard(
    account: NcAccountResp?,
    loading: Boolean,
    onRelogin: () -> Unit
) {
    Surface(
        Modifier.fillMaxWidth().padding(horizontal = NekoSpace.lg, vertical = NekoSpace.sm),
        shape = RoundedCornerShape(NekoRadius.artwork),
        color = MaterialTheme.colorScheme.surfaceContainer
    ) {
        Row(
            Modifier.fillMaxWidth().padding(NekoSpace.lg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(NekoSpace.md)
        ) {
            when {
                loading -> {
                    CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                    Text("正在读取账号…", style = MaterialTheme.typography.bodyMedium)
                }
                account == null -> {
                    Artwork(null, size = 56.dp, shape = CircleShape, placeholder = Icons.Filled.Person)
                    Column(Modifier.weight(1f)) {
                        Text("未登录", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "Cookie 缺失或已失效",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Button(onClick = onRelogin) { Text("扫码登录") }
                }
                else -> {
                    val vip = account.account?.vipType ?: 0
                    Artwork(account.profile?.avatarUrl, size = 56.dp, shape = CircleShape, thumbnail = null, placeholder = Icons.Filled.Person)
                    Column(Modifier.weight(1f)) {
                        Text(
                            account.profile?.nickname ?: "网易云用户",
                            style = MaterialTheme.typography.titleMedium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Spacer(Modifier.height(NekoSpace.xs))
                        StatusBadge(
                            vipTypeName(vip),
                            if (vip > 0) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
                        )
                    }
                    TextButton(onClick = onRelogin, colors = NekoDefaults.textButtonColors()) { Text("重新登录") }
                }
            }
        }
    }
}

/**
 * 歌单列表 Tab
 */
@Composable
private fun NcPlaylistTab(
    vm: PlayerViewModel,
    account: NcAccountResp?,
    playlists: List<NcPlaylistItem>,
    loading: Boolean,
    onLoaded: (List<NcPlaylistItem>) -> Unit
) {
    val scope = rememberCoroutineScope()
    val uid = account?.profile?.userId ?: return

    LaunchedEffect(uid) {
        if (playlists.isEmpty() && !loading) {
            val list = vm.fetchNcPlaylists(uid)
            onLoaded(list)
        }
    }

    if (loading || playlists.isEmpty()) {
        Box(Modifier.fillMaxSize(), Alignment.Center) {
            if (loading) CircularProgressIndicator()
            else EmptyState(Icons.AutoMirrored.Filled.QueueMusic, "没有歌单")
        }
        return
    }

    LazyColumn(Modifier.fillMaxSize()) {
        items(playlists, key = { it.id }) { playlist ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(start = NekoSpace.lg, end = NekoSpace.xs, top = NekoSpace.sm, bottom = NekoSpace.sm),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Artwork(playlist.coverImgUrl, size = 52.dp)
                Spacer(Modifier.width(NekoSpace.md))
                Column(Modifier.weight(1f)) {
                    Text(
                        playlist.name,
                        style = MaterialTheme.typography.bodyLarge,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        "${playlist.trackCount} 首",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                IconButton(
                    onClick = {
                        scope.launch {
                            vm.importNcPlaylistToLocal(playlist)
                        }
                    }
                ) {
                    Icon(Icons.Filled.CloudDownload, "导入到本地", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

/**
 * 红心歌曲 Tab
 */
@Composable
private fun NcLikeSongsTab(
    vm: PlayerViewModel,
    account: NcAccountResp?,
    songs: List<Song>,
    loading: Boolean,
    onLoaded: (List<Song>) -> Unit
) {
    val scope = rememberCoroutineScope()
    val uid = account?.profile?.userId ?: return

    LaunchedEffect(uid) {
        if (songs.isEmpty() && !loading) {
            val list = vm.fetchNcLikeSongs(uid)
            onLoaded(list)
        }
    }

    Column(Modifier.fillMaxSize()) {
        if (songs.isEmpty()) {
            Box(Modifier.fillMaxSize(), Alignment.Center) {
                if (loading) CircularProgressIndicator()
                else EmptyState(Icons.Filled.FavoriteBorder, "没有红心歌曲")
            }
        } else {
            Row(
                Modifier.fillMaxWidth().padding(start = NekoSpace.lg, end = NekoSpace.sm),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("共 ${songs.size} 首", style = MaterialTheme.typography.bodyMedium)
                TextButton(
                    onClick = {
                        scope.launch {
                            vm.importNcLikeSongsToLocal(songs)
                        }
                    },
                    colors = NekoDefaults.textButtonColors()
                ) {
                    Icon(Icons.Filled.CloudDownload, null)
                    Spacer(Modifier.width(4.dp))
                    Text("全部导入到收藏")
                }
            }
            LazyColumn(Modifier.fillMaxSize()) {
                items(songs, key = { it.source + ":" + it.hash.ifBlank { it.id.toString() } }) { song ->
                    SongRow(song, onPlay = { vm.playNow(song) }, subtitle = song.ar)
                }
            }
        }
    }
}

/**
 * 播放记录 Tab
 */
@Composable
private fun NcPlayRecordTab(
    vm: PlayerViewModel,
    account: NcAccountResp?,
    records: List<NcRecordItem>,
    loading: Boolean,
    onLoaded: (List<NcRecordItem>) -> Unit
) {
    val scope = rememberCoroutineScope()
    val uid = account?.profile?.userId ?: return

    LaunchedEffect(uid) {
        if (records.isEmpty() && !loading) {
            val list = vm.fetchNcPlayRecord(uid)
            onLoaded(list)
        }
    }

    val songs = remember(records) { records.map { it.song.toSong() } }

    Column(Modifier.fillMaxSize()) {
        if (records.isEmpty()) {
            Box(Modifier.fillMaxSize(), Alignment.Center) {
                if (loading) CircularProgressIndicator()
                else EmptyState(Icons.Filled.History, "最近一周没有播放记录")
            }
        } else {
            Row(
                Modifier.fillMaxWidth().padding(start = NekoSpace.lg, end = NekoSpace.sm),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("最近一周 ${records.size} 首", style = MaterialTheme.typography.bodyMedium)
                TextButton(
                    onClick = {
                        scope.launch {
                            vm.importNcRecordToLocal(songs)
                        }
                    },
                    colors = NekoDefaults.textButtonColors()
                ) {
                    Icon(Icons.Filled.CloudDownload, null)
                    Spacer(Modifier.width(4.dp))
                    Text("全部导入到历史")
                }
            }
            LazyColumn(Modifier.fillMaxSize()) {
                items(records, key = { it.song.id }) { record ->
                    val song = record.song.toSong()
                    SongRow(song, onPlay = { vm.playNow(song) }, subtitle = "${song.ar} · 播放 ${record.playCount} 次")
                }
            }
        }
    }
}

// 辅助函数
private fun vipTypeName(vipType: Int): String = when (vipType) {
    0 -> "普通用户"
    1 -> "黑胶 VIP"
    11 -> "超级 VIP"
    else -> "VIP"
}

private fun formatVipExpire(timestamp: Long): String {
    val date = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.CHINA)
        .format(java.util.Date(timestamp))
    return date
}

// NcSongDetail 转 Song 扩展
private fun top.nekoh2o.player.data.model.NcSongDetail.toSong() = Song(
    id = this.id,
    nm = this.name,
    ar = this.ar.joinToString("/") { it.name },
    pc = this.al?.picUrl
)
