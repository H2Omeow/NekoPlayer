package top.nekoh2o.player.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import top.nekoh2o.player.ui.theme.NekoRadius
import top.nekoh2o.player.ui.theme.NekoSpace

/** 一组设置项：小标题 + 圆角面板，面板内各行之间自动加分隔线。 */
@Composable
fun SettingsSection(
    modifier: Modifier = Modifier,
    title: String? = null,
    description: String? = null,
    content: @Composable () -> Unit
) {
    Column(modifier.fillMaxWidth()) {
        if (title != null) {
            Text(
                title,
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = NekoSpace.xs, end = NekoSpace.xs, bottom = NekoSpace.sm)
            )
        }
        Surface(
            shape = RoundedCornerShape(NekoRadius.card),
            color = MaterialTheme.colorScheme.surfaceContainerLow,
            modifier = Modifier.fillMaxWidth()
        ) {
            DividedColumn(inset = NekoSpace.lg, content = content)
        }
        if (description != null) {
            Text(
                description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = NekoSpace.xs, end = NekoSpace.xs, top = NekoSpace.sm)
            )
        }
    }
}

/** 纵向排列子项，并在相邻子项之间画一条缩进的细线。条件不满足而未输出的子项不占分隔线。 */
@Composable
private fun DividedColumn(inset: Dp, content: @Composable () -> Unit) {
    val color = MaterialTheme.colorScheme.outlineVariant
    var lines by remember { mutableStateOf(IntArray(0)) }
    Layout(
        content = content,
        modifier = Modifier.drawWithContent {
            drawContent()
            val start = inset.toPx()
            lines.forEach { y ->
                drawLine(color, Offset(start, y.toFloat()), Offset(size.width - start, y.toFloat()), 1.dp.toPx())
            }
        }
    ) { measurables, constraints ->
        val placeables = measurables.map { it.measure(constraints.copy(minHeight = 0)) }
        val width = if (constraints.hasBoundedWidth) constraints.maxWidth
        else placeables.maxOfOrNull { it.width } ?: 0
        val height = placeables.sumOf { it.height }
        layout(width, height) {
            val ys = ArrayList<Int>(placeables.size)
            var y = 0
            placeables.forEachIndexed { index, placeable ->
                if (index > 0 && placeable.height > 0) ys += y
                placeable.place(0, y)
                y += placeable.height
            }
            val array = ys.toIntArray()
            if (!array.contentEquals(lines)) lines = array
        }
    }
}

/** 普通设置行：可带图标、副标题、右侧当前值；可点击时显示右箭头。 */
@Composable
fun SettingsTile(
    title: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    subtitle: String? = null,
    value: String? = null,
    destructive: Boolean = false,
    enabled: Boolean = true,
    onClick: (() -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null
) {
    val colors = MaterialTheme.colorScheme
    val foreground = when {
        !enabled -> colors.onSurface.copy(alpha = 0.38f)
        destructive -> colors.error
        else -> colors.onSurface
    }
    TileRow(
        modifier = modifier.then(
            if (onClick != null) Modifier.clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            else Modifier
        ),
        icon = icon,
        iconTint = if (destructive) colors.error else colors.onSurfaceVariant,
        title = title,
        titleColor = foreground,
        subtitle = subtitle
    ) {
        if (trailing != null) trailing()
        else {
            if (value != null) {
                Text(
                    value,
                    style = MaterialTheme.typography.bodyMedium,
                    color = colors.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.widthIn(max = 160.dp)
                )
            }
            if (onClick != null) {
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = colors.onSurfaceVariant
                )
            }
        }
    }
}

/** 开关设置行，整行可点。 */
@Composable
fun SettingsSwitchTile(
    title: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    subtitle: String? = null,
    enabled: Boolean = true
) {
    TileRow(
        modifier = modifier.toggleable(
            value = checked,
            enabled = enabled,
            role = Role.Switch,
            onValueChange = onCheckedChange
        ),
        icon = icon,
        iconTint = MaterialTheme.colorScheme.onSurfaceVariant,
        title = title,
        titleColor = MaterialTheme.colorScheme.onSurface,
        subtitle = subtitle
    ) {
        Switch(checked = checked, onCheckedChange = null, enabled = enabled)
    }
}

/** 标题下方放自定义控件（滑块、选项组等）的设置行。 */
@Composable
fun SettingsControlTile(
    title: String,
    modifier: Modifier = Modifier,
    value: String? = null,
    subtitle: String? = null,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier
            .fillMaxWidth()
            .padding(horizontal = NekoSpace.lg, vertical = NekoSpace.md)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
            if (value != null) {
                Text(
                    value,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        if (subtitle != null) {
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 2.dp)
            )
        }
        Spacer(Modifier.size(NekoSpace.xs))
        content()
    }
}

/** 滑块设置行。 */
@Composable
fun SettingsSliderTile(
    title: String,
    value: Float,
    onValueChange: (Float) -> Unit,
    valueLabel: String,
    modifier: Modifier = Modifier,
    valueRange: ClosedFloatingPointRange<Float> = 0f..1f,
    steps: Int = 0,
    subtitle: String? = null
) {
    SettingsControlTile(title = title, modifier = modifier, value = valueLabel, subtitle = subtitle) {
        Slider(value = value, onValueChange = onValueChange, valueRange = valueRange, steps = steps)
    }
}

@Composable
private fun TileRow(
    modifier: Modifier,
    icon: ImageVector?,
    iconTint: androidx.compose.ui.graphics.Color,
    title: String,
    titleColor: androidx.compose.ui.graphics.Color,
    subtitle: String?,
    trailing: @Composable () -> Unit
) {
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .padding(horizontal = NekoSpace.lg, vertical = NekoSpace.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(NekoSpace.md)
    ) {
        if (icon != null) Icon(icon, contentDescription = null, tint = iconTint)
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = titleColor)
            if (subtitle != null) {
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 2.dp)
                )
            }
        }
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(NekoSpace.xs)
        ) { trailing() }
    }
}

/** 行内提示：普通信息或错误。 */
@Composable
fun InlineNotice(
    message: String,
    modifier: Modifier = Modifier,
    error: Boolean = false,
    action: (@Composable () -> Unit)? = null
) {
    val colors = MaterialTheme.colorScheme
    Surface(
        shape = RoundedCornerShape(NekoRadius.card),
        color = if (error) colors.errorContainer else colors.surfaceContainerHigh,
        contentColor = if (error) colors.onErrorContainer else colors.onSurface,
        modifier = modifier.fillMaxWidth()
    ) {
        Row(
            Modifier.padding(horizontal = NekoSpace.lg, vertical = NekoSpace.md),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(NekoSpace.md)
        ) {
            Icon(
                if (error) Icons.Outlined.ErrorOutline else Icons.Outlined.Info,
                contentDescription = null,
                modifier = Modifier.size(20.dp),
                tint = if (error) colors.onErrorContainer else colors.onSurfaceVariant
            )
            Text(message, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
            action?.invoke()
        }
    }
}
