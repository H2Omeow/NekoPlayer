package top.nekoh2o.player.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import top.nekoh2o.player.ui.theme.NekoRadius

/**
 * 封面图。图片未加载或缺失时显示带图标的占位底色，不会出现空白方块。
 *
 * @param thumbnail 网易云图片按需裁剪尺寸（`?param=NyN`），传 null 使用原图
 */
@Composable
fun Artwork(
    url: String?,
    modifier: Modifier = Modifier,
    size: Dp? = 48.dp,
    shape: Shape = RoundedCornerShape(NekoRadius.cover),
    thumbnail: Int? = 200,
    placeholder: ImageVector = Icons.Filled.MusicNote
) {
    Box(
        (if (size != null) modifier.size(size) else modifier)
            .clip(shape)
            .background(MaterialTheme.colorScheme.surfaceContainerHighest),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            placeholder,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
            modifier = Modifier.size(if (size != null && size < 56.dp) 20.dp else 32.dp)
        )
        if (!url.isNullOrBlank()) {
            AsyncImage(
                model = artworkUrl(url, thumbnail),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        }
    }
}

/** 网易云图片带上尺寸参数以减少流量；其他来源原样返回。 */
fun artworkUrl(url: String, thumbnail: Int?): String =
    if (thumbnail == null || '?' in url || !url.contains("music.126.net")) url
    else "$url?param=${thumbnail}y$thumbnail"
