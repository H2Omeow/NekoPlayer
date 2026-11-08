package top.nekoh2o.player.ui.screens

import top.nekoh2o.player.i18n.NekoI18n.tr

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import top.nekoh2o.player.ui.PlayerViewModel
import top.nekoh2o.player.ui.UiState
import top.nekoh2o.player.ui.components.Artwork
import top.nekoh2o.player.ui.components.ScreenHeader
import top.nekoh2o.player.ui.components.SectionHeader
import top.nekoh2o.player.ui.components.SongActions
import top.nekoh2o.player.ui.components.SongRow
import top.nekoh2o.player.ui.theme.NekoRadius
import top.nekoh2o.player.ui.theme.NekoSpace
import java.util.Calendar

@Composable
fun HomeScreen(
    vm: PlayerViewModel,
    onOpenFullPlayer: () -> Unit,
    onBrowse: () -> Unit,
    onOpenLibrary: (LibraryTab) -> Unit
) {
    val state by vm.ui.collectAsState()
    var addTarget by remember { mutableStateOf<top.nekoh2o.player.data.model.Song?>(null) }
    val actions = remember(vm) { vm.songActions { addTarget = it } }
    HomeContent(
        state = state,
        greeting = greeting(Calendar.getInstance().get(Calendar.HOUR_OF_DAY)),
        actions = actions,
        onOpenFullPlayer = onOpenFullPlayer,
        onTogglePlay = vm::togglePlay,
        onBrowse = onBrowse,
        onOpenLibrary = onOpenLibrary
    )
    addTarget?.let { song -> AddToPlaylistDialog(vm, song) { addTarget = null } }
}

fun greeting(hour: Int): String = when (hour) {
    in 5..10 -> tr("早上好")
    in 11..13 -> tr("中午好")
    in 14..17 -> tr("下午好")
    else -> tr("晚上好")
}

@Composable
fun HomeContent(
    state: UiState,
    greeting: String,
    actions: SongActions,
    onOpenFullPlayer: () -> Unit,
    onTogglePlay: () -> Unit,
    onBrowse: () -> Unit,
    onOpenLibrary: (LibraryTab) -> Unit
) {
    val recent = state.history.take(12)
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = NekoSpace.xl)
    ) {
        item { ScreenHeader(greeting, subtitle = tr("让喜欢的音乐，陪你一会儿")) }
        item {
            NowPlayingCard(
                state = state,
                onOpenFullPlayer = onOpenFullPlayer,
                onTogglePlay = onTogglePlay,
                onBrowse = onBrowse,
                modifier = Modifier.padding(horizontal = NekoSpace.lg, vertical = NekoSpace.sm)
            )
        }
        item {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = NekoSpace.lg, vertical = NekoSpace.sm),
                horizontalArrangement = Arrangement.spacedBy(NekoSpace.sm)
            ) {
                LibraryShortcut(Icons.Filled.Favorite, tr("我的收藏"), state.favorites.size, Modifier.weight(1f)) {
                    onOpenLibrary(LibraryTab.FAVORITES)
                }
                LibraryShortcut(Icons.Filled.History, tr("最近播放"), state.history.size, Modifier.weight(1f)) {
                    onOpenLibrary(LibraryTab.HISTORY)
                }
                LibraryShortcut(Icons.AutoMirrored.Filled.QueueMusic, tr("我的歌单"), state.playlists.size, Modifier.weight(1f)) {
                    onOpenLibrary(LibraryTab.PLAYLISTS)
                }
            }
        }
        item {
            SectionHeader(
                tr("最近听过"),
                Modifier.padding(start = NekoSpace.lg, end = NekoSpace.sm, top = NekoSpace.lg, bottom = NekoSpace.xs),
                actionLabel = if (recent.isNotEmpty()) tr("全部") else null,
                onAction = { onOpenLibrary(LibraryTab.HISTORY) }
            )
        }
        if (recent.isEmpty()) item {
            Text(
                tr("播放记录会出现在这里。收藏的歌曲和创建的歌单都在「我的」中。"),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = NekoSpace.lg)
            )
        }
        itemsIndexed(recent, key = { index, song -> "${song.source}:${song.id}:$index" }) { index, song ->
            SongRow(
                song = song,
                isFav = actions.isFav(song),
                playing = state.current?.let { it.id == song.id && it.source == song.source } == true,
                onPlay = { actions.playAll(recent.drop(index) + recent.take(index)) },
                onFav = { actions.toggleFav(song) },
                onAdd = { actions.queue(song) },
                onAddToPlaylist = { actions.addToPlaylist(song) }
            )
        }
    }
}

@Composable
private fun NowPlayingCard(
    state: UiState,
    onOpenFullPlayer: () -> Unit,
    onTogglePlay: () -> Unit,
    onBrowse: () -> Unit,
    modifier: Modifier = Modifier
) {
    val colors = MaterialTheme.colorScheme
    val current = state.current
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(NekoRadius.artwork),
        color = colors.surfaceContainer,
        onClick = { if (current != null) onOpenFullPlayer() else onBrowse() }
    ) {
        Row(
            Modifier.padding(NekoSpace.lg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(NekoSpace.lg)
        ) {
            Artwork(
                current?.pc,
                size = 88.dp,
                shape = RoundedCornerShape(NekoRadius.card),
                thumbnail = 300,
                placeholder = Icons.Filled.Headphones
            )
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    if (current == null) tr("开始收听") else if (state.isPlaying) tr("正在播放") else tr("继续收听"),
                    style = MaterialTheme.typography.labelMedium,
                    color = colors.primary
                )
                Text(
                    current?.nm ?: tr("还没有正在播放的歌曲"),
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 2, overflow = TextOverflow.Ellipsis
                )
                Text(
                    current?.ar ?: tr("搜索一首歌，或从推荐开始"),
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.onSurfaceVariant,
                    maxLines = 1, overflow = TextOverflow.Ellipsis
                )
            }
            if (current != null) {
                FilledIconButton(onClick = onTogglePlay, modifier = Modifier.size(48.dp)) {
                    Icon(
                        if (state.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                        contentDescription = if (state.isPlaying) tr("暂停") else tr("播放")
                    )
                }
            } else {
                FilledTonalIconButton(onClick = onBrowse, modifier = Modifier.size(48.dp)) {
                    Icon(Icons.Filled.Search, contentDescription = tr("去音乐页搜索"))
                }
            }
        }
    }
}

@Composable
private fun LibraryShortcut(
    icon: ImageVector,
    label: String,
    count: Int,
    modifier: Modifier,
    onClick: () -> Unit
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(NekoRadius.card),
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        onClick = onClick
    ) {
        Column(Modifier.padding(NekoSpace.md), verticalArrangement = Arrangement.spacedBy(NekoSpace.xs)) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
            Text(count.toString(), style = MaterialTheme.typography.titleLarge)
            Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
