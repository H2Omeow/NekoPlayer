package top.nekoh2o.player.ui.components

import top.nekoh2o.player.i18n.NekoI18n.tr

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.PlaylistAdd
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.data.repo.AnimemusicRepository
import top.nekoh2o.player.ui.a11y.clickableRow
import top.nekoh2o.player.ui.a11y.toggleSemantics
import top.nekoh2o.player.ui.theme.NekoSpace

/**
 * 歌曲行：封面、标题、歌手 · 来源；右侧收藏和「更多」菜单（加入队列 / 加入歌单）。
 * 封面和标题合并成一个「播放」按钮节点，收藏与菜单各自独立可聚焦。
 */
@Composable
fun SongRow(
    song: Song,
    onPlay: () -> Unit,
    modifier: Modifier = Modifier,
    isFav: Boolean = false,
    playing: Boolean = false,
    subtitle: String = "${song.ar} · ${songSourceLabel(song)}",
    onFav: (() -> Unit)? = null,
    onAdd: (() -> Unit)? = null,
    onAddToPlaylist: (() -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null
) {
    val share = LocalSongShareHandler.current
    Row(
        modifier
            .fillMaxWidth()
            .padding(start = NekoSpace.lg, end = NekoSpace.xs),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            Modifier
                .weight(1f)
                .clickableRow(rowLabel = "${song.nm}，${song.ar}", actionLabel = tr("播放"), onClick = onPlay)
                .padding(vertical = NekoSpace.sm),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Artwork(song.pc, size = 48.dp)
            Spacer(Modifier.width(NekoSpace.md))
            Column(Modifier.weight(1f)) {
                Text(
                    song.nm,
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (playing) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
        if (onFav != null) FavoriteButton(isFav, onFav)
        trailing?.invoke()
        if (onAdd != null || onAddToPlaylist != null || share != null) {
            SongMenu(onAdd, onAddToPlaylist, share?.let { handler -> { handler(song) } })
        }
    }
}

/** 带弹跳动画的收藏按钮。 */
@Composable
fun FavoriteButton(
    isFav: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    idleTint: Color = MaterialTheme.colorScheme.onSurfaceVariant
) {
    var scale by remember { mutableFloatStateOf(1f) }
    val animated by animateFloatAsState(
        targetValue = scale,
        animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessLow),
        label = "favorite_scale"
    )
    LaunchedEffect(isFav) {
        if (isFav) {
            scale = 1.3f
            delay(150)
            scale = 1f
        }
    }
    IconButton(
        onClick = onClick,
        modifier = modifier.toggleSemantics(tr("收藏"), if (isFav) tr("已收藏") else tr("未收藏"))
    ) {
        Icon(
            if (isFav) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
            contentDescription = null,
            tint = if (isFav) MaterialTheme.colorScheme.primary else idleTint,
            modifier = Modifier.graphicsLayer {
                scaleX = animated
                scaleY = animated
            }
        )
    }
}

@Composable
private fun SongMenu(onAdd: (() -> Unit)?, onAddToPlaylist: (() -> Unit)?, onShare: (() -> Unit)?) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }) {
            Icon(
                Icons.Filled.MoreVert,
                contentDescription = tr("歌曲操作"),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            if (onAdd != null) {
                DropdownMenuItem(
                    text = { Text(tr("加入播放队列")) },
                    leadingIcon = { Icon(Icons.AutoMirrored.Filled.QueueMusic, null) },
                    onClick = { open = false; onAdd() }
                )
            }
            if (onAddToPlaylist != null) {
                DropdownMenuItem(
                    text = { Text(tr("加入歌单…")) },
                    leadingIcon = { Icon(Icons.AutoMirrored.Filled.PlaylistAdd, null) },
                    onClick = { open = false; onAddToPlaylist() }
                )
            }
            if (onShare != null) {
                DropdownMenuItem(
                    text = { Text(tr("分享…")) },
                    leadingIcon = { Icon(Icons.Filled.Share, null) },
                    onClick = { open = false; onShare() }
                )
            }
        }
    }
}

fun songKey(song: Song): String = song.source + ":" + song.hash.ifBlank { song.id.toString() }

fun songSourceLabel(song: Song): String = when {
    song.source == "netease" -> tr("网易云")
    song.source == "kugou" -> tr("酷狗")
    song.source.startsWith("animemusic-") -> tr("内置插件·{source}", "source" to AnimemusicRepository.label(song.providerSource))
    else -> song.source
}
