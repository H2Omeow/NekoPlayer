package top.nekoh2o.player.ui.screens.video

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
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = NekoSolid.sheet,
        dragHandle = { BottomSheetDefaults.DragHandle() }
    ) {
        LazyColumn(
            Modifier.fillMaxWidth().navigationBarsPadding(),
            contentPadding = PaddingValues(bottom = NekoSpace.xl)
        ) {
            item {
                SheetTitle("弹幕设置", action = "恢复默认", onAction = onReset)
                SwitchRow("显示弹幕", d.enabled) { v -> set { it.copy(enabled = v) } }
                SliderRow("不透明度", d.opacity, 0.15f..1f, "${(d.opacity * 100).toInt()}%") { v ->
                    set { it.copy(opacity = v) }
                }
                ChoiceRow("字号", listOf("小" to 0.8f, "标准" to 1f, "大" to 1.25f, "超大" to 1.5f), d.fontScale) { v ->
                    set { it.copy(fontScale = v) }
                }
                ChoiceRow("速度", listOf("慢" to 0.6f, "标准" to 1f, "快" to 1.5f, "极快" to 2f), d.speed) { v ->
                    set { it.copy(speed = v) }
                }
                ChoiceRow(
                    "显示区域",
                    listOf("1/4" to 0.25f, "1/2" to 0.5f, "3/4" to 0.75f, "全屏" to 1f),
                    d.area
                ) { v -> set { it.copy(area = v) } }
                RowTitle("弹幕类型")
                Row(Modifier.fillMaxWidth().padding(horizontal = NekoSpace.lg), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ToggleChip("滚动", d.showScroll) { v -> set { it.copy(showScroll = v) } }
                    ToggleChip("顶部", d.showTop) { v -> set { it.copy(showTop = v) } }
                    ToggleChip("底部", d.showBottom) { v -> set { it.copy(showBottom = v) } }
                }
                SwitchRow("保留彩色弹幕", d.keepColor) { v -> set { it.copy(keepColor = v) } }
                SwitchRow("加粗", d.bold) { v -> set { it.copy(bold = v) } }
                SwitchRow("描边阴影", d.shadow) { v -> set { it.copy(shadow = v) } }
                SliderRow("描边粗细", d.strokeWidth, 0f..3f, "%.1f".format(d.strokeWidth)) { v ->
                    set { it.copy(strokeWidth = v) }
                }
                ChoiceRow(
                    "字体",
                    listOf("系统" to "system", "衬线" to "serif", "等宽" to "mono"),
                    d.fontFamily
                ) { v -> set { it.copy(fontFamily = v) } }
                SliderRow("同屏上限", d.density.toFloat(), 30f..300f, "${d.density} 条") { v ->
                    set { it.copy(density = v.toInt()) }
                }
                SwitchRow("合并重复弹幕", d.mergeDuplicate) { v -> set { it.copy(mergeDuplicate = v) } }
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
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = NekoSolid.sheet,
        dragHandle = { BottomSheetDefaults.DragHandle() }
    ) {
        LazyColumn(
            Modifier.fillMaxWidth().navigationBarsPadding(),
            contentPadding = PaddingValues(bottom = NekoSpace.xl)
        ) {
            item {
                SheetTitle("播放设置", action = "恢复默认", onAction = onReset)
                ChoiceRow(
                    "默认清晰度",
                    listOf("1080P" to 80f, "720P" to 64f, "480P" to 32f, "360P" to 16f),
                    p.defaultQuality.toFloat()
                ) { v -> set { it.copy(defaultQuality = v.toInt()) } }
                ChoiceRow(
                    "默认倍速",
                    listOf("0.75×" to 0.75f, "1.0×" to 1f, "1.25×" to 1.25f, "1.5×" to 1.5f),
                    p.defaultSpeed
                ) { v -> set { it.copy(defaultSpeed = v) } }
                ChoiceRow(
                    "双击跳转",
                    listOf("5 秒" to 5f, "10 秒" to 10f, "15 秒" to 15f, "30 秒" to 30f),
                    p.doubleTapSeekSec.toFloat()
                ) { v -> set { it.copy(doubleTapSeekSec = v.toInt()) } }
                ChoiceRow(
                    "长按倍速",
                    listOf("1.5×" to 1.5f, "2.0×" to 2f, "3.0×" to 3f, "关闭" to 1f),
                    p.longPressSpeed
                ) { v -> set { it.copy(longPressSpeed = v) } }
                SliderRow("控制条自动隐藏", p.autoHideControlsSec.toFloat(), 1f..10f, "${p.autoHideControlsSec} 秒") { v ->
                    set { it.copy(autoHideControlsSec = v.toInt()) }
                }
                SwitchRow("横屏自动全屏", p.autoFullscreen) { v -> set { it.copy(autoFullscreen = v) } }
                SwitchRow("播完自动下一个", p.autoPlayNext) { v -> set { it.copy(autoPlayNext = v) } }
                SwitchRow("记住播放进度", p.rememberProgress) { v -> set { it.copy(rememberProgress = v) } }
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
        Text("屏蔽关键词", style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Text(
            "已屏蔽 ${words.size} 个",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
    if (showDialog) {
        var draft by remember { mutableStateOf(words.joinToString("\n")) }
        AlertDialog(
            onDismissRequest = { showDialog = false },
            title = { Text("屏蔽关键词") },
            text = {
                Column {
                    Text(
                        "每行一个关键词，命中即不显示",
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
                }) { Text("保存") }
            },
            dismissButton = {
                TextButton(onClick = { showDialog = false }) { Text("取消") }
            }
        )
    }
}
