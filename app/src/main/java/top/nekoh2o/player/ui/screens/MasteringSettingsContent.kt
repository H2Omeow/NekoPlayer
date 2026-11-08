package top.nekoh2o.player.ui.screens

import top.nekoh2o.player.i18n.NekoI18n.tr

import androidx.compose.foundation.layout.Box
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.*
import androidx.compose.runtime.*
import top.nekoh2o.player.data.model.AudioEffectSettings
import top.nekoh2o.player.data.model.MasteringPresets
import top.nekoh2o.player.ui.components.SettingsSection
import top.nekoh2o.player.ui.components.SettingsTile

@Composable
internal fun MasteringSettingsContent(
    settings: AudioEffectSettings,
    onPreset: (Int) -> Unit,
    onMix: (Int) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val selected = MasteringPresets.available.firstOrNull { it.id == settings.masteringPresetId }
    val missing = selected == null && settings.masteringPresetId != 0
    SettingsSection(
        title = tr("母带处理"),
        description = if (missing) tr("已保存的母带预设暂不可用。") else null
    ) {
        Box {
            SettingsTile(
                title = tr("预设"),
                value = selected?.let { tr(it.name) } ?: tr("关闭"),
                onClick = { expanded = true },
                trailing = {
                    Text(selected?.let { tr(it.name) } ?: tr("关闭"), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Icon(Icons.Default.ArrowDropDown, contentDescription = tr("选择母带预设"))
                }
            )
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                DropdownMenuItem(text = { Text(tr("关闭母带处理")) }, onClick = { onPreset(0); expanded = false })
                MasteringPresets.available.forEach { preset ->
                    DropdownMenuItem(
                        text = { Text(tr(preset.name)) },
                        onClick = { onPreset(preset.id); expanded = false }
                    )
                }
            }
        }
        if (selected != null) EffectSlider(tr("母带混合"), "", settings.masteringMix, onMix)
    }
}
