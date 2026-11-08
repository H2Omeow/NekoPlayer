package top.nekoh2o.player.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import top.nekoh2o.player.data.model.DownloadStatus
import top.nekoh2o.player.data.model.DownloadTask
import top.nekoh2o.player.data.model.DownloadedSong
import top.nekoh2o.player.ui.PlayerViewModel
import top.nekoh2o.player.ui.a11y.clickableRow
import top.nekoh2o.player.ui.components.Artwork
import top.nekoh2o.player.ui.components.DetailTopBar
import top.nekoh2o.player.ui.components.EmptyState
import top.nekoh2o.player.ui.components.SectionHeader
import top.nekoh2o.player.ui.theme.NekoDefaults
import top.nekoh2o.player.ui.theme.NekoSpace

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DownloadManagerScreen(vm: PlayerViewModel, onBack: () -> Unit) {
    val state by vm.ui.collectAsState()
    // 正在进行的任务（未完成）
    val active = state.downloadTasks.filter { it.status != DownloadStatus.DONE }
    val done = state.downloadedSongs

    var showDeleteConfirm by remember { mutableStateOf<top.nekoh2o.player.data.model.Song?>(null) }

    // 删除确认对话框
    if (showDeleteConfirm != null) {
        val song = showDeleteConfirm
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = null },
            title = { Text("删除下载的文件？") },
            text = { Text("确定要删除「${song?.nm ?: "该歌曲"}」及其文件吗？此操作不可撤销。") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDeleteConfirm?.let { vm.removeDownloaded(it) }
                        showDeleteConfirm = null
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)
                ) { Text("删除") }
            },
            dismissButton = {
                TextButton(
                    onClick = { showDeleteConfirm = null },
                    colors = NekoDefaults.textButtonColors()
                ) { Text("取消") }
            }
        )
    }

    Column(Modifier.fillMaxSize()) {
        DetailTopBar("下载管理", onBack)

        if (active.isEmpty() && done.isEmpty()) {
            EmptyState(Icons.Outlined.Download, "还没有下载", description = "在全屏播放器中点「下载」，选择音质后开始下载。")
            return@Column
        }

        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = NekoSpace.xl)) {
            if (active.isNotEmpty()) {
                item {
                    SectionHeader("正在下载 · ${active.size}", Modifier.padding(start = NekoSpace.lg, top = NekoSpace.sm, bottom = NekoSpace.xs))
                }
                items(active, key = { it.song.source + ":" + it.song.id }) { task ->
                    ActiveTaskRow(
                        task = task,
                        onRetry = { vm.retryDownload(task.song, task.quality) },
                        modifier = Modifier.animateItem(
                            fadeInSpec = androidx.compose.animation.core.spring(
                                dampingRatio = androidx.compose.animation.core.Spring.DampingRatioMediumBouncy,
                                stiffness = androidx.compose.animation.core.Spring.StiffnessMediumLow
                            ),
                            placementSpec = androidx.compose.animation.core.spring(
                                dampingRatio = androidx.compose.animation.core.Spring.DampingRatioMediumBouncy,
                                stiffness = androidx.compose.animation.core.Spring.StiffnessMediumLow
                            ),
                            fadeOutSpec = androidx.compose.animation.core.spring(
                                dampingRatio = androidx.compose.animation.core.Spring.DampingRatioMediumBouncy,
                                stiffness = androidx.compose.animation.core.Spring.StiffnessMediumLow
                            )
                        )
                    )
                }
            }

            if (done.isNotEmpty()) {
                item {
                    SectionHeader("已下载 · ${done.size}", Modifier.padding(start = NekoSpace.lg, top = NekoSpace.lg, bottom = NekoSpace.xs))
                }
                items(done, key = { it.song.source + ":" + it.songId }) { d ->
                    DownloadedRow(
                        item = d,
                        onPlay = { vm.playNow(d.song) },
                        onRemove = { showDeleteConfirm = d.song },
                        modifier = Modifier.animateItem(
                            fadeInSpec = androidx.compose.animation.core.spring(
                                dampingRatio = androidx.compose.animation.core.Spring.DampingRatioMediumBouncy,
                                stiffness = androidx.compose.animation.core.Spring.StiffnessMediumLow
                            ),
                            placementSpec = androidx.compose.animation.core.spring(
                                dampingRatio = androidx.compose.animation.core.Spring.DampingRatioMediumBouncy,
                                stiffness = androidx.compose.animation.core.Spring.StiffnessMediumLow
                            ),
                            fadeOutSpec = androidx.compose.animation.core.spring(
                                dampingRatio = androidx.compose.animation.core.Spring.DampingRatioMediumBouncy,
                                stiffness = androidx.compose.animation.core.Spring.StiffnessMediumLow
                            )
                        )
                    )
                }
            }
        }
    }
}

@Composable
private fun ActiveTaskRow(task: DownloadTask, onRetry: () -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier.fillMaxWidth().padding(start = NekoSpace.lg, end = NekoSpace.xs, top = NekoSpace.sm, bottom = NekoSpace.sm),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Artwork(task.song.pc, size = 44.dp, thumbnail = 100)
        Spacer(Modifier.width(NekoSpace.md))
        Column(Modifier.weight(1f)) {
            Text(task.song.nm, maxLines = 1, overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.bodyMedium)
            when (task.status) {
                DownloadStatus.FAILED -> Text(
                    "下载失败：${task.errorMsg ?: "未知错误"}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
                else -> {
                    Spacer(Modifier.height(4.dp))
                    val animatedProgress by androidx.compose.animation.core.animateFloatAsState(
                        targetValue = task.progress,
                        animationSpec = androidx.compose.animation.core.tween(
                            durationMillis = 300,
                            easing = androidx.compose.animation.core.FastOutSlowInEasing
                        ),
                        label = "download_progress"
                    )
                    LinearProgressIndicator(
                        progress = { animatedProgress },
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }
        }
        Spacer(Modifier.width(8.dp))
        if (task.status == DownloadStatus.FAILED) {
            TextButton(
                onClick = onRetry,
                colors = NekoDefaults.textButtonColors()
            ) {
                Text("重试")
            }
        } else {
            Text("${(task.progress * 100).toInt()}%",
                style = MaterialTheme.typography.labelMedium)
        }
    }
}

@Composable
private fun DownloadedRow(
    item: DownloadedSong,
    onPlay: () -> Unit,
    onRemove: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier.fillMaxWidth().padding(start = NekoSpace.lg, end = NekoSpace.xs, top = NekoSpace.sm, bottom = NekoSpace.sm),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            Modifier.weight(1f).clickableRow(
                rowLabel = "${item.song.nm}，${item.song.ar}，${qualityLabel(item.quality)}",
                actionLabel = "播放"
            ) { onPlay() },
            verticalAlignment = Alignment.CenterVertically
        ) {
            Artwork(item.song.pc, size = 44.dp, thumbnail = 100)
            Spacer(Modifier.width(NekoSpace.md))
            Column(Modifier.weight(1f)) {
                Text(item.song.nm, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodyMedium)
                Text(
                    "${item.song.ar} · ${qualityLabel(item.quality)}",
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        IconButton(onClick = onRemove) {
            Icon(Icons.Filled.Delete, contentDescription = "删除文件", tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

private fun qualityLabel(q: String): String = when (q) {
    "standard" -> "标准"
    "higher" -> "较高"
    "exhigh" -> "极高"
    "lossless" -> "无损 SQ"
    "hires" -> "Hi-Res 无损"
    "jyeffect" -> "高清臻音"
    "sky" -> "沉浸环绕声"
    "jymaster" -> "超清母带"
    "dolby" -> "臻音全景声"
    else -> q
}
