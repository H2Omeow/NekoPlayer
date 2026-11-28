package top.nekoh2o.player.ui.screens.video

import top.nekoh2o.player.ui.components.NekoAlertDialog
import top.nekoh2o.player.ui.components.NekoBottomSheet

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import top.nekoh2o.player.data.store.DanmakuSettings
import top.nekoh2o.player.data.store.PlayerSettings
import top.nekoh2o.player.data.store.VideoSettings
import top.nekoh2o.player.ui.theme.NekoSolid
import top.nekoh2o.player.ui.theme.NekoSpace
import top.nekoh2o.player.i18n.NekoI18n.tr

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DanmakuSettingsSheet(
    settings: VideoSettings,
    onChange: (VideoSettings) -> Unit,
    onReset: () -> Unit,
    onDismiss: () -> Unit
) {
    val d = settings.danmaku
    fun set(block: (DanmakuSettings) -> DanmakuSettings) {
        onChange(settings.copy(danmaku = block(d).normalized()))
    }
    NekoBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = NekoSolid.sheet,
        dragHandle = { BottomSheetDefaults.DragHandle() }
    ) {
        LazyColumn(
            Modifier.fillMaxWidth().navigationBarsPadding(),
            contentPadding = PaddingValues(bottom = NekoSpace.xl)
        ) {
            item {
                SheetTitle(tr("弹幕设置"), action = tr("恢复默认"), onAction = onReset)
                SwitchRow(tr("显示弹幕"), d.enabled) { v -> set { it.copy(enabled = v) } }
                SliderRow(tr("不透明度"), d.opacity, 0.15f..1f, "${(d.opacity * 100).toInt()}%") { v ->
                    set { it.copy(opacity = v) }
                }
                ChoiceRow(tr("字号"), listOf(tr("小") to 0.8f, tr("标准") to 1f, tr("大") to 1.25f, tr("超大") to 1.5f), d.fontScale) { v ->
                    set { it.copy(fontScale = v) }
                }
                ChoiceRow(tr("速度"), listOf(tr("慢") to 0.6f, tr("标准") to 1f, tr("快") to 1.5f, tr("极快") to 2f), d.speed) { v ->
                    set { it.copy(speed = v) }
                }
                ChoiceRow(
                    tr("显示区域"),
                    listOf("1/4" to 0.25f, "1/2" to 0.5f, "3/4" to 0.75f, tr("全屏") to 1f),
                    d.area
                ) { v -> set { it.copy(area = v) } }
                RowTitle(tr("弹幕类型"))
                Row(Modifier.fillMaxWidth().padding(horizontal = NekoSpace.lg), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ToggleChip(tr("滚动"), d.showScroll) { v -> set { it.copy(showScroll = v) } }
                    ToggleChip(tr("顶部"), d.showTop) { v -> set { it.copy(showTop = v) } }
                    ToggleChip(tr("底部"), d.showBottom) { v -> set { it.copy(showBottom = v) } }
                }
                SwitchRow(tr("保留彩色弹幕"), d.keepColor) { v -> set { it.copy(keepColor = v) } }
                SwitchRow(tr("加粗"), d.bold) { v -> set { it.copy(bold = v) } }
                SwitchRow(tr("描边阴影"), d.shadow) { v -> set { it.copy(shadow = v) } }
                SliderRow(tr("描边粗细"), d.strokeWidth, 0f..3f, "%.1f".format(d.strokeWidth)) { v ->
                    set { it.copy(strokeWidth = v) }
                }
                ChoiceRow(
                    tr("字体"),
                    listOf(tr("系统") to "system", tr("衬线") to "serif", tr("等宽") to "mono"),
                    d.fontFamily
                ) { v -> set { it.copy(fontFamily = v) } }
                SliderRow(tr("同屏上限"), d.density.toFloat(), 30f..300f, tr("{count} 条", "count" to d.density)) { v ->
                    set { it.copy(density = v.toInt()) }
                }
                SwitchRow(tr("合并重复弹幕"), d.mergeDuplicate) { v -> set { it.copy(mergeDuplicate = v) } }
                BlockWordsRow(d.blockWords) { list -> set { it.copy(blockWords = list) } }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlayerSettingsSheet(
    settings: VideoSettings,
    onChange: (VideoSettings) -> Unit,
    onReset: () -> Unit,
    onDismiss: () -> Unit
) {
    val p = settings.player
    fun set(block: (PlayerSettings) -> PlayerSettings) {
        onChange(settings.copy(player = block(p).normalized()))
    }
    NekoBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = NekoSolid.sheet,
        dragHandle = { BottomSheetDefaults.DragHandle() }
    ) {
        LazyColumn(
            Modifier.fillMaxWidth().navigationBarsPadding(),
            contentPadding = PaddingValues(bottom = NekoSpace.xl)
        ) {
            item {
                SheetTitle(tr("播放设置"), action = tr("恢复默认"), onAction = onReset)
                ChoiceRow(
                    tr("默认清晰度"),
                    listOf("1080P" to 80f, "720P" to 64f, "480P" to 32f, "360P" to 16f),
                    p.defaultQuality.toFloat()
                ) { v -> set { it.copy(defaultQuality = v.toInt()) } }
                ChoiceRow(
                    tr("默认倍速"),
                    listOf("0.75×" to 0.75f, "1.0×" to 1f, "1.25×" to 1.25f, "1.5×" to 1.5f),
                    p.defaultSpeed
                ) { v -> set { it.copy(defaultSpeed = v) } }
                ChoiceRow(
                    tr("双击跳转"),
                    listOf(tr("5 秒") to 5f, tr("10 秒") to 10f, tr("15 秒") to 15f, tr("30 秒") to 30f),
                    p.doubleTapSeekSec.toFloat()
                ) { v -> set { it.copy(doubleTapSeekSec = v.toInt()) } }
                ChoiceRow(
                    tr("长按倍速"),
                    listOf("1.5×" to 1.5f, "2.0×" to 2f, "3.0×" to 3f, tr("关闭") to 1f),
                    p.longPressSpeed
                ) { v -> set { it.copy(longPressSpeed = v) } }
                SliderRow(tr("控制条自动隐藏"), p.autoHideControlsSec.toFloat(), 1f..10f, tr("{seconds} 秒", "seconds" to p.autoHideControlsSec)) { v ->
                    set { it.copy(autoHideControlsSec = v.toInt()) }
                }
                SwitchRow(tr("横屏自动全屏"), p.autoFullscreen) { v -> set { it.copy(autoFullscreen = v) } }
                SwitchRow(tr("播完自动下一个"), p.autoPlayNext) { v -> set { it.copy(autoPlayNext = v) } }
                SwitchRow(tr("记住播放进度"), p.rememberProgress) { v -> set { it.copy(rememberProgress = v) } }
            }
        }
    }
}

@Composable
private fun SheetTitle(title: String, action: String, onAction: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = NekoSpace.lg, vertical = NekoSpace.sm),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.weight(1f))
        Text(
            action,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable(onClick = onAction).padding(8.dp)
        )
    }
}

@Composable
private fun RowTitle(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.onSurface,
        modifier = Modifier.padding(horizontal = NekoSpace.lg, vertical = NekoSpace.sm)
    )
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable { onChange(!checked) }.padding(horizontal = NekoSpace.lg, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Switch(
            checked = checked,
            onCheckedChange = onChange,
            colors = SwitchDefaults.colors(checkedTrackColor = MaterialTheme.colorScheme.primary)
        )
    }
}

@Composable
private fun SliderRow(
    label: String,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    valueText: String,
    onChange: (Float) -> Unit
) {
    Column(Modifier.fillMaxWidth().padding(horizontal = NekoSpace.lg, vertical = 4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
            Text(valueText, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Slider(
            value = value.coerceIn(range.start, range.endInclusive),
            valueRange = range,
            onValueChange = onChange,
            colors = SliderDefaults.colors(
                thumbColor = MaterialTheme.colorScheme.primary,
                activeTrackColor = MaterialTheme.colorScheme.primary
            )
        )
    }
}

@Composable
private fun <T> ChoiceRow(label: String, options: List<Pair<String, T>>, value: T, onChange: (T) -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = NekoSpace.lg, vertical = 6.dp)) {
        Text(label, style = MaterialTheme.typography.bodyLarge)
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            options.forEach { (text, v) ->
                val selected = v == value
                Text(
                    text,
                    style = MaterialTheme.typography.labelLarge,
                    color = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(
                            if (selected) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.surfaceContainerHigh
                        )
                        .clickable { onChange(v) }
                        .padding(horizontal = 14.dp, vertical = 7.dp)
                )
            }
        }
    }
}

@Composable
private fun ToggleChip(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Text(
        label,
        style = MaterialTheme.typography.labelLarge,
        color = if (checked) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(if (checked) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainerHigh)
            .clickable { onChange(!checked) }
            .padding(horizontal = 14.dp, vertical = 7.dp)
    )
}

@Composable
private fun BlockWordsRow(words: List<String>, onChange: (List<String>) -> Unit) {
    var showDialog by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().clickable { showDialog = true }
            .padding(horizontal = NekoSpace.lg, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(tr("屏蔽关键词"), style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Text(
            tr("已屏蔽 {count} 个", "count" to words.size),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
    if (showDialog) {
        var draft by remember { mutableStateOf(words.joinToString("\n")) }
        NekoAlertDialog(
            onDismissRequest = { showDialog = false },
            title = { Text(tr("屏蔽关键词")) },
            text = {
                Column {
                    Text(
                        tr("每行一个关键词，命中即不显示"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(
                        value = draft,
                        onValueChange = { draft = it },
                        minLines = 5,
                        maxLines = 8,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    onChange(draft.split("\n", "，", ",").map { it.trim() }.filter { it.isNotEmpty() })
                    showDialog = false
                }) { Text(tr("保存")) }
            },
            dismissButton = {
                TextButton(onClick = { showDialog = false }) { Text(tr("取消")) }
            }
        )
    }
}
