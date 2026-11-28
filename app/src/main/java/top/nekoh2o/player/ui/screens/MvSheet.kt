package top.nekoh2o.player.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.OndemandVideo
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
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
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import top.nekoh2o.player.data.repo.MusicVideo
import top.nekoh2o.player.data.repo.MvRepository
import top.nekoh2o.player.i18n.NekoI18n.tr
import top.nekoh2o.player.ui.components.Artwork
import top.nekoh2o.player.ui.components.EmptyState
import top.nekoh2o.player.ui.components.InlineNotice
import top.nekoh2o.player.ui.components.NekoBottomSheet
import top.nekoh2o.player.ui.theme.NekoDefaults
import top.nekoh2o.player.ui.theme.NekoRadius
import top.nekoh2o.player.ui.theme.NekoSpace

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MvSheet(
    source: String,
    initialQuery: String,
    onPauseMusic: () -> Unit,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val repo = remember { MvRepository() }
    var query by remember { mutableStateOf(initialQuery) }
    var videos by remember { mutableStateOf<List<MusicVideo>>(emptyList()) }
    var url by remember { mutableStateOf<String?>(null) }
    var selected by remember { mutableStateOf<MusicVideo?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }
    var searched by remember { mutableStateOf(false) }
    var page by remember { mutableIntStateOf(1) }
    var more by remember { mutableStateOf(false) }

    val player = remember { ExoPlayer.Builder(context).build() }
    DisposableEffect(player) { onDispose { player.release() } }
    LaunchedEffect(url) {
        url?.let {
            onPauseMusic()
            player.setMediaItem(MediaItem.fromUri(it))
            player.prepare()
            player.playWhenReady = true
        }
    }

    fun search(next: Boolean = false) {
        if (query.isBlank() || loading) return
        scope.launch {
            loading = true; error = null
            try {
                val currentPage = if (next) page + 1 else 1
                val found = withContext(Dispatchers.IO) { repo.search(source, query.trim(), currentPage) }
                videos = (if (next) videos + found else found).distinctBy { "${it.source}:${it.id}" }
                page = currentPage
                more = found.size >= 30
                searched = true
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                error = tr("内置插件 MV 搜索失败，请稍后重试")
            } finally {
                loading = false
            }
        }
    }

    LaunchedEffect(Unit) {
        if (initialQuery.isNotBlank()) search()
    }

    NekoBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.9f)
                .padding(horizontal = NekoSpace.lg)
        ) {
            Text("MV", style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.height(NekoSpace.sm))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(NekoSpace.sm)
            ) {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    modifier = Modifier.weight(1f),
                    singleLine = true,
                    placeholder = { Text(tr("搜索 MV")) },
                    leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                    trailingIcon = {
                        if (query.isNotEmpty()) {
                            IconButton(onClick = { query = "" }) {
                                Icon(Icons.Filled.Close, contentDescription = tr("清空"))
                            }
                        }
                    },
                    shape = RoundedCornerShape(50),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { search() }),
                    colors = NekoDefaults.textFieldColors()
                )
                Button(onClick = { search() }, enabled = !loading && query.isNotBlank()) {
                    Text(tr("搜索"))
                }
            }
            if (loading) LinearProgressIndicator(Modifier.fillMaxWidth().padding(top = NekoSpace.sm))
            error?.let {
                Spacer(Modifier.height(NekoSpace.sm))
                InlineNotice(it, error = true)
            }
            if (url != null) {
                Spacer(Modifier.height(NekoSpace.md))
                Box(
                    Modifier
                        .fillMaxWidth()
                        .aspectRatio(16f / 9f)
                        .clip(RoundedCornerShape(NekoRadius.card))
                        .background(Color.Black)
                ) {
                    AndroidView(
                        factory = { PlayerView(it).apply { this.player = player; useController = true } },
                        modifier = Modifier.fillMaxSize(),
                        onRelease = { it.player = null }
                    )
                }
                selected?.let { cur ->
                    Text(
                        cur.title,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(top = NekoSpace.sm)
                    )
                    if (cur.artist.isNotBlank()) {
                        Text(
                            cur.artist,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
            Spacer(Modifier.height(NekoSpace.md))
            if (videos.isEmpty() && !loading) {
                EmptyState(
                    icon = Icons.Filled.OndemandVideo,
                    title = if (searched) tr("没有找到相关 MV") else tr("搜索 MV"),
                    description = if (searched) tr("换个关键词试试") else tr("输入歌名或歌手查找音乐视频")
                )
            } else {
                LazyColumn(
                    Modifier.fillMaxWidth().weight(1f),
                    verticalArrangement = Arrangement.spacedBy(NekoSpace.sm),
                    contentPadding = PaddingValues(bottom = NekoSpace.xl)
                ) {
                    items(videos, key = { "${it.source}:${it.id}" }) { video ->
                        val active = selected?.id == video.id && selected?.source == video.source
                        Surface(
                            shape = RoundedCornerShape(NekoRadius.card),
                            color = if (active) MaterialTheme.colorScheme.surfaceContainerHigh
                            else MaterialTheme.colorScheme.surfaceContainerLow,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(NekoRadius.card))
                                .clickable(enabled = !loading) {
                                    scope.launch {
                                        loading = true; error = null
                                        try {
                                            url = withContext(Dispatchers.IO) { repo.url(video) }
                                                ?: throw IllegalStateException()
                                            selected = video
                                        } catch (e: CancellationException) {
                                            throw e
                                        } catch (_: Exception) {
                                            error = tr("暂无可播放 MV 链接")
                                        } finally {
                                            loading = false
                                        }
                                    }
                                }
                        ) {
                            Row(
                                Modifier.padding(NekoSpace.sm),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(NekoSpace.md)
                            ) {
                                Artwork(
                                    url = video.artwork,
                                    modifier = Modifier.width(104.dp).aspectRatio(16f / 9f),
                                    size = null,
                                    shape = RoundedCornerShape(NekoRadius.cover),
                                    thumbnail = null,
                                    placeholder = Icons.Filled.OndemandVideo
                                )
                                Column(Modifier.weight(1f)) {
                                    Text(
                                        video.title,
                                        style = MaterialTheme.typography.bodyMedium,
                                        fontWeight = if (active) FontWeight.SemiBold else FontWeight.Normal,
                                        color = if (active) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                                        maxLines = 2,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                    if (video.artist.isNotBlank()) {
                                        Text(
                                            video.artist,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                            modifier = Modifier.padding(top = 2.dp)
                                        )
                                    }
                                }
                                if (active) {
                                    Icon(
                                        Icons.Filled.PlayArrow,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.primary
                                    )
                                }
                            }
                        }
                    }
                    if (more) {
                        item {
                            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                                TextButton(
                                    onClick = { search(true) },
                                    enabled = !loading,
                                    colors = NekoDefaults.textButtonColors()
                                ) { Text(tr("加载更多")) }
                            }
                        }
                    }
                }
            }
        }
    }
}
