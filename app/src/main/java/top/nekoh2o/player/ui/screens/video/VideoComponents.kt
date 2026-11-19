package top.nekoh2o.player.ui.screens.video

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import top.nekoh2o.player.data.bilibili.VideoItem
import top.nekoh2o.player.ui.theme.NekoRadius
import top.nekoh2o.player.ui.theme.NekoSpace
import top.nekoh2o.player.i18n.NekoI18n
import top.nekoh2o.player.i18n.NekoI18n.tr

/** 图片请求带上 B 站 Referer，否则部分封面会 403。 */
@Composable
fun biliImage(url: String, modifier: Modifier = Modifier, contentScale: ContentScale = ContentScale.Crop) {
    val ctx = LocalContext.current
    AsyncImage(
        model = ImageRequest.Builder(ctx)
            .data(url)
            .addHeader("Referer", "https://www.bilibili.com/")
            .addHeader("User-Agent", "Mozilla/5.0")
            .crossfade(180)
            .build(),
        contentDescription = null,
        contentScale = contentScale,
        modifier = modifier
    )
}

fun formatCount(n: Long): String {
    // 英文环境用 K/M/B，中日环境用万/億
    val english = NekoI18n.activeLanguageTag().startsWith("en")
    return when {
        n >= 1_000_000_000 -> if (english) "%.1fB".format(n / 1_000_000_000.0) else tr("%.1f亿").format(n / 100_000_000.0)
        n >= 1_000_000 -> if (english) "%.1fM".format(n / 1_000_000.0) else tr("%.1f万").format(n / 10_000.0)
        n >= 10_000 -> if (english) "%.1fK".format(n / 1_000.0) else tr("%.1f万").format(n / 10_000.0)
        else -> n.toString()
    }
}

fun formatDuration(seconds: Int): String {
    if (seconds <= 0) return "--:--"
    val h = seconds / 3600
    val m = (seconds % 3600) / 60
    val s = seconds % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}

fun formatPosition(ms: Long): String = formatDuration((ms / 1000).toInt())

fun formatDate(epochSec: Long): String {
    if (epochSec <= 0) return ""
    val f = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault())
    return f.format(java.util.Date(epochSec * 1000))
}

@Composable
fun DurationBadge(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelSmall,
        color = Color.White,
        modifier = modifier
            .clip(RoundedCornerShape(6.dp))
            .background(Color.Black.copy(alpha = 0.62f))
            .padding(horizontal = 6.dp, vertical = 2.dp)
    )
}

/** 16:9 封面：时长角标 + 顶部标签 + 播放中遮罩。 */
@Composable
fun VideoCover(item: VideoItem, modifier: Modifier = Modifier, showProgress: Float? = null) {
    Box(
        modifier
            .aspectRatio(16f / 9f)
            .clip(RoundedCornerShape(NekoRadius.cover))
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
    ) {
        biliImage(item.cover, Modifier.fillMaxSize())
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        0.55f to Color.Transparent,
                        1f to Color.Black.copy(alpha = 0.55f)
                    )
                )
        )
        if (item.badges.isNotEmpty()) {
            Row(
                Modifier.align(Alignment.TopStart).padding(6.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                item.badges.take(2).forEach { badge ->
                    Text(
                        text = badge,
                        style = MaterialTheme.typography.labelSmall,
                        color = Color.White,
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(Color.Black.copy(alpha = 0.55f))
                            .padding(horizontal = 6.dp, vertical = 2.dp)
                    )
                }
            }
        }
        DurationBadge(
            formatDuration(item.durationSec),
            Modifier.align(Alignment.BottomEnd).padding(6.dp)
        )
        if (showProgress != null && showProgress > 0f) {
            Box(
                Modifier
                    .align(Alignment.BottomStart)
                    .fillMaxWidth()
                    .height(2.dp)
                    .background(Color.White.copy(alpha = 0.22f))
            ) {
                Box(
                    Modifier
                        .fillMaxWidth(showProgress.coerceIn(0f, 1f))
                        .height(2.dp)
                        .background(MaterialTheme.colorScheme.primary)
                )
            }
        }
    }
}

/** 双列/多列网格卡片。 */
@Composable
fun VideoGridCard(
    item: VideoItem,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    progress: Float? = null,
    subtitle: String? = null
) {
    Column(
        modifier
            .clip(RoundedCornerShape(NekoRadius.card))
            .clickable(onClick = onClick)
            .padding(bottom = 2.dp)
    ) {
        VideoCover(item, Modifier.fillMaxWidth(), progress)
        Spacer(Modifier.height(NekoSpace.sm))
        Text(
            text = item.title,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
        Spacer(Modifier.height(2.dp))
        Text(
            text = subtitle ?: buildString {
                append(item.upName.ifBlank { "bilibili" })
                if (item.views > 0) append(" · ${formatCount(item.views)}播放")
            },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

/** 列表行卡片，搜索结果/相关推荐用。 */
@Composable
fun VideoListRow(
    item: VideoItem,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    trailing: @Composable (() -> Unit)? = null
) {
    Row(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(NekoRadius.card))
            .clickable(onClick = onClick)
            .padding(vertical = NekoSpace.sm)
    ) {
        Box(Modifier.width(142.dp)) {
            VideoCover(item, Modifier.fillMaxWidth())
        }
        Spacer(Modifier.width(NekoSpace.md))
        Column(Modifier.weight(1f)) {
            Text(
                text = item.title,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(Modifier.height(6.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Avatar(item.upFace, 20.dp)
                Spacer(Modifier.width(6.dp))
                Text(
                    text = item.upName.ifBlank { "bilibili" },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false)
                )
            }
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Filled.PlayArrow,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(14.dp)
                )
                Text(
                    text = "${formatCount(item.views)} · 弹幕 ${formatCount(item.danmakuCount)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        if (trailing != null) trailing()
    }
}

@Composable
fun Avatar(url: String?, size: androidx.compose.ui.unit.Dp) {
    Box(
        Modifier
            .size(size)
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.surfaceContainerHighest),
        contentAlignment = Alignment.Center
    ) {
        if (!url.isNullOrBlank()) {
            biliImage(url, Modifier.fillMaxSize(), ContentScale.Crop)
        } else {
            Text("B", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
fun VideoChip(text: String, selected: Boolean, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    Text(
        text = text,
        style = MaterialTheme.typography.labelLarge,
        color = if (selected) cs.onPrimary else cs.onSurfaceVariant,
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(if (selected) cs.primary else cs.surfaceContainerHigh)
            .clickable(onClick = onClick)
            .padding(horizontal = NekoSpace.lg, vertical = NekoSpace.sm)
    )
}

@Composable
fun SectionHeader(title: String, action: String? = null, onAction: (() -> Unit)? = null) {
    Row(
        Modifier.fillMaxWidth().padding(top = NekoSpace.lg, bottom = NekoSpace.sm),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.weight(1f)
        )
        if (action != null) {
            Text(
                text = action,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .clip(RoundedCornerShape(6.dp))
                    .clickable(enabled = onAction != null) { onAction?.invoke() }
                    .padding(horizontal = 6.dp, vertical = 4.dp)
            )
        }
    }
}

/** 空态 / 提示占位。 */
@Composable
fun VideoEmptyState(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    message: String? = null,
    action: String? = null,
    onAction: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    Column(
        modifier.fillMaxWidth().padding(vertical = 56.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            icon, contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
            modifier = Modifier.size(40.dp)
        )
        Spacer(Modifier.height(NekoSpace.md))
        Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurface)
        if (message != null) {
            Spacer(Modifier.height(NekoSpace.xs))
            Text(
                message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 32.dp),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )
        }
        if (action != null && onAction != null) {
            Spacer(Modifier.height(NekoSpace.lg))
            Text(
                text = action,
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onPrimary,
                modifier = Modifier
                    .clip(RoundedCornerShape(50))
                    .background(MaterialTheme.colorScheme.primary)
                    .clickable(onClick = onAction)
                    .padding(horizontal = NekoSpace.xl, vertical = NekoSpace.sm)
            )
        }
    }
}
