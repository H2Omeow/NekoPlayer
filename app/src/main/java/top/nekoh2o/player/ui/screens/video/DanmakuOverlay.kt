package top.nekoh2o.player.ui.screens.video

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.sp
import top.nekoh2o.player.data.bilibili.DanmakuItem
import top.nekoh2o.player.data.store.DanmakuSettings

/** 弹幕基础字号（标准档），字号档位在此基础上缩放。 */
private const val BASE_SP = 15f

/** 单条滚动弹幕的基准飞行时间（速度 1.0）。 */
private const val SCROLL_MS = 9000L

/** 顶部/底部弹幕停留时间。 */
private const val STATIC_MS = 4200L

/**
 * 弹幕层：Canvas 直接绘制，按播放进度驱动，不参与重组循环。
 * 只依赖当前播放位置（positionProvider），暂停/拖动/倍速都自然同步。
 */
@Composable
fun DanmakuOverlay(
    items: List<DanmakuItem>,
    settings: DanmakuSettings,
    positionProvider: () -> Long,
    modifier: Modifier = Modifier
) {
    if (!settings.enabled || items.isEmpty()) return
    val measurer = rememberTextMeasurer(cacheSize = 512)
    val density = LocalDensity.current
    var size by remember { mutableStateOf(IntSize.Zero) }
    val position = remember { mutableLongStateOf(0L) }

    val laneHeightPx = with(density) { (BASE_SP.sp.toPx() * 1.62f) * settings.fontScale.coerceIn(0.6f, 2f) }
    val laneCount = ((size.height * settings.area.coerceIn(0.25f, 1f)) / laneHeightPx)
        .toInt().coerceIn(1, 24)

    val prepared = remember(items, settings, size) {
        prepareDanmaku(items, settings, laneCount)
    }

    LaunchedEffect(Unit) {
        while (true) {
            withFrameNanos { position.longValue = positionProvider() }
        }
    }

    Canvas(modifier.fillMaxSize().onSizeChanged { size = it }) {
        if (prepared.isEmpty()) return@Canvas
        drawDanmaku(this, measurer, prepared, settings, position.longValue, size.width.toFloat(), size.height.toFloat(), laneHeightPx, laneCount)
    }
}

/** 预处理：过滤 + 度量估算 + 轨道分配，帧循环里只做位置计算。 */
private class PreparedDanmaku(
    val text: AnnotatedString,
    val color: Color,
    val fontSizeSp: Float,
    val mode: Int,
    val progressMs: Long,
    val weight: Int,
    var lane: Int = 0,
    var durationMs: Long = 0L
)

private fun prepareDanmaku(
    items: List<DanmakuItem>,
    settings: DanmakuSettings,
    laneCount: Int
): List<PreparedDanmaku> {
    val alpha = settings.opacity.coerceIn(0.1f, 1f)
    val speed = settings.speed.coerceIn(0.4f, 2.5f)
    val scrollMs = (SCROLL_MS / speed).toLong()
    val cap = settings.density.coerceIn(20, 400)
    val out = ArrayList<PreparedDanmaku>(items.size)

    for (d in items) {
        if (d.mode in 7..9) continue // 高级弹幕本期不渲染
        val scroll = d.mode in 1..3 || d.mode == 6
        if (scroll && !settings.showScroll) continue
        if (d.mode == 5 && !settings.showTop) continue
        if (d.mode == 4 && !settings.showBottom) continue
        if (!settings.keepColor && d.color != 0xFFFFFF) continue
        if (settings.blockWords.any { it.isNotEmpty() && d.content.contains(it, ignoreCase = true) }) continue
        if (d.content.isBlank()) continue
        val sp = when (d.fontSize) {
            18 -> BASE_SP * 0.8f
            36 -> BASE_SP * 1.35f
            else -> BASE_SP
        } * settings.fontScale.coerceIn(0.6f, 2f)
        out += PreparedDanmaku(
            text = AnnotatedString(d.content),
            color = Color(0xFF000000.toInt() or (d.color and 0xFFFFFF)).copy(alpha = alpha),
            fontSizeSp = sp,
            mode = d.mode,
            progressMs = d.progressMs,
            weight = d.weight
        )
    }
    out.sortBy { it.progressMs }

    // 轨道分配：同一轨道上一条飞完才允许下一条进入
    val lanesFree = LongArray(laneCount) { Long.MIN_VALUE }
    var scrollSeen = 0
    var staticSlot = 0
    for (p in out) {
        if (p.mode == 4 || p.mode == 5) {
            p.lane = staticSlot++ % laneCount
            p.durationMs = STATIC_MS
            continue
        }
        if (scrollSeen >= cap) continue
        scrollSeen++
        val idx = lanesFree.indexOfFirst { it <= p.progressMs }
        if (idx < 0) continue // 没有空轨：丢弃，避免叠字
        p.lane = idx
        p.durationMs = scrollMs
        lanesFree[idx] = p.progressMs + scrollMs
    }
    return out
}

private fun drawDanmaku(
    scope: androidx.compose.ui.graphics.drawscope.DrawScope,
    measurer: androidx.compose.ui.text.TextMeasurer,
    prepared: List<PreparedDanmaku>,
    settings: DanmakuSettings,
    posMs: Long,
    width: Float,
    height: Float,
    laneHeightPx: Float,
    laneCount: Int
) {
    val strokeWidth = settings.strokeWidth.coerceIn(0f, 6f)
    val shadow = if (settings.shadow) Shadow(Color.Black.copy(alpha = 0.9f), Offset(0f, 1.5f), 3f) else null
    val family = when (settings.fontFamily) {
        "serif" -> FontFamily.Serif
        "mono" -> FontFamily.Monospace
        else -> FontFamily.Default
    }

    for (p in prepared) {
        val t = posMs - p.progressMs
        if (t < 0) continue
        if (p.mode == 4 || p.mode == 5) {
            if (t > STATIC_MS) continue
            val style = baseStyle(p, settings.bold, family, shadow)
            val layout = measurer.measure(p.text, style)
            val x = (width - layout.size.width) / 2f
            val y = if (p.mode == 5) {
                p.lane * laneHeightPx + 6f
            } else {
                height - (p.lane + 1) * laneHeightPx - 6f
            }
            drawStyled(scope, measurer, p, style, strokeWidth, Offset(x, y))
            continue
        }
        if (p.durationMs <= 0L || t > p.durationMs) continue
        val progress = t.toFloat() / p.durationMs
        val style = baseStyle(p, settings.bold, family, shadow)
        val layout = measurer.measure(p.text, style)
        val textW = layout.size.width.toFloat()
        val x = width - progress * (width + textW)
        if (x + textW < 0f || x > width) continue
        val lane = p.lane % laneCount
        drawStyled(scope, measurer, p, style, strokeWidth, Offset(x, lane * laneHeightPx + 4f))
    }
}

private fun baseStyle(
    p: PreparedDanmaku,
    bold: Boolean,
    family: FontFamily,
    shadow: Shadow?
): TextStyle = TextStyle(
    color = p.color,
    fontSize = p.fontSizeSp.sp,
    fontWeight = if (bold) FontWeight.Bold else FontWeight.Medium,
    fontFamily = family,
    shadow = shadow
)

private fun drawStyled(
    scope: androidx.compose.ui.graphics.drawscope.DrawScope,
    measurer: androidx.compose.ui.text.TextMeasurer,
    p: PreparedDanmaku,
    style: TextStyle,
    strokeWidth: Float,
    offset: Offset
) {
    if (strokeWidth > 0.1f) {
        val strokeStyle = style.copy(
            drawStyle = Stroke(width = strokeWidth),
            color = Color.Black.copy(alpha = 0.62f),
            shadow = null
        )
        scope.drawText(measurer.measure(p.text, strokeStyle), topLeft = offset)
    }
    scope.drawText(measurer.measure(p.text, style), topLeft = offset)
}

/** 进度条上的弹幕热力条：按 1% 分桶统计，返回 0..1 的归一化数组。 */
fun danmakuHeat(items: List<DanmakuItem>, durationMs: Long, buckets: Int = 100): FloatArray {
    val out = FloatArray(buckets)
    if (durationMs <= 0L || items.isEmpty()) return out
    for (d in items) {
        val i = ((d.progressMs.toDouble() / durationMs) * buckets).toInt().coerceIn(0, buckets - 1)
        out[i] += 1f
    }
    val max = out.maxOrNull() ?: 0f
    if (max <= 0f) return out
    for (i in out.indices) out[i] = (out[i] / max).coerceIn(0f, 1f)
    return out
}
