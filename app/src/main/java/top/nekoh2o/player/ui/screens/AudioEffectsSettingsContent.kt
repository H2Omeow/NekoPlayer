package top.nekoh2o.player.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import top.nekoh2o.player.audio.AudioEffectStatus
import top.nekoh2o.player.data.model.AudioEffectEngine
import top.nekoh2o.player.data.model.EQPresets
import top.nekoh2o.player.ui.PlayerViewModel
import top.nekoh2o.player.ui.components.InlineNotice
import top.nekoh2o.player.ui.components.NekoChip
import top.nekoh2o.player.ui.components.SettingsControlTile
import top.nekoh2o.player.ui.components.SettingsSection
import top.nekoh2o.player.ui.components.SettingsSliderTile
import top.nekoh2o.player.ui.components.SettingsTile
import top.nekoh2o.player.ui.theme.NekoSpace

private fun AudioEffectEngine.description(): String? = when (this) {
    AudioEffectEngine.NONE -> null
    AudioEffectEngine.SYSTEM -> "系统处理，功耗较低；可用效果与听感取决于设备"
    AudioEffectEngine.NATIVE_CPP -> "本地 DSP，参数更丰富；CPU 占用较高"
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AudioEffectsSettingsContent(vm: PlayerViewModel) {
    val state by vm.ui.collectAsState()
    val settings = state.settings.audioEffects
    val status by AudioEffectStatus.state.collectAsState()
    val native = settings.engine == AudioEffectEngine.NATIVE_CPP
    val capabilities = status.system

    SettingsSection(title = "音效引擎") {
        AudioEffectEngine.entries.forEach { engine ->
            SettingsTile(
                title = engine.label,
                subtitle = engine.description(),
                modifier = Modifier.selectable(
                    selected = settings.engine == engine,
                    role = Role.RadioButton,
                    onClick = { vm.setAudioEffectEngine(engine) }
                ),
                trailing = { RadioButton(selected = settings.engine == engine, onClick = null) }
            )
        }
    }
    if (settings.engine == AudioEffectEngine.NONE) return

    when {
        native -> status.nativeError?.let { InlineNotice(it, error = true) }
        !status.systemInitialized -> InlineNotice("等待音频会话，设备能力尚未确认。")
        !capabilities.any -> InlineNotice("当前音频会话没有可用的系统音效。", error = true)
    }
    if (native) MasteringSettingsContent(settings, vm::setMasteringPreset, vm::setMasteringMix)

    if (native || capabilities.equalizer) {
        SettingsSection(title = "均衡器") {
            SettingsControlTile(title = "预设") {
                FlowRow(
                    modifier = Modifier.fillMaxWidth().padding(top = NekoSpace.xs),
                    horizontalArrangement = Arrangement.spacedBy(NekoSpace.sm),
                    verticalArrangement = Arrangement.spacedBy(NekoSpace.sm)
                ) {
                    EQPresets.presets.keys.forEach { name ->
                        NekoChip(name, settings.eqPresetName == name, { vm.setEqPreset(name) })
                    }
                }
            }
            SettingsControlTile(title = "自定义", value = "±15 dB") {
                EqualizerVisualizer(
                    bands = settings.eqBands,
                    frequencies = EQPresets.frequencies,
                    onBandsChange = vm::setEqBands
                )
            }
        }
    }

    SettingsSection(title = "效果") {
        if (native || capabilities.bassBoost) EffectSlider("低音增强", "增强 80Hz 以下频段", settings.bassBoost, vm::setBassBoost)
        if (native || capabilities.virtualizer) EffectSlider("3D 环绕", "拓宽立体声场", settings.virtualizer, vm::setVirtualizer)
        if (native || capabilities.reverb) EffectSlider("空间混响", "模拟厅堂混响", settings.reverbWet, vm::setReverbWet)
        if (native) {
            EffectSlider("混响空间", "", settings.reverbRoomSize, vm::setReverbRoomSize)
            EffectSlider("混响阻尼", "", settings.reverbDamping, vm::setReverbDamping)
        }
        if (native || capabilities.loudness) EffectSlider("响度增益", "整体音量提升", settings.loudnessGain, vm::setLoudnessGain)
    }

    SettingsSection {
        SettingsTile(title = "重置所有音效参数", destructive = true, onClick = vm::resetAudioEffects, trailing = {})
    }
}

@Composable
internal fun EffectSlider(
    label: String,
    description: String,
    value: Int,
    onValueChange: (Int) -> Unit
) {
    SettingsSliderTile(
        title = label,
        subtitle = description.ifEmpty { null },
        value = value.toFloat(),
        valueLabel = "$value%",
        onValueChange = { onValueChange(it.toInt()) },
        valueRange = 0f..100f,
        steps = 99
    )
}

@Composable
private fun EqualizerVisualizer(
    bands: List<Float>,
    frequencies: List<Int>,
    onBandsChange: (List<Float>) -> Unit
) {
    Row(
        Modifier
            .fillMaxWidth()
            .height(220.dp),
        horizontalArrangement = Arrangement.SpaceEvenly
    ) {
        bands.forEachIndexed { index, gain ->
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.weight(1f)
            ) {
                Text(
                    "${if (gain >= 0) "+" else ""}${gain.toInt()}",
                    style = MaterialTheme.typography.labelSmall,
                    color = if (gain == 0f) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.primary
                )
                // 横向滑条旋转 270° 作为竖向推子
                Slider(
                    value = gain,
                    onValueChange = { newGain ->
                        onBandsChange(bands.toMutableList().also { it[index] = newGain })
                    },
                    valueRange = -15f..15f,
                    modifier = Modifier
                        .weight(1f)
                        .graphicsLayer { rotationZ = 270f }
                        .width(180.dp)
                )
                Text(
                    if (frequencies[index] >= 1000) "${frequencies[index] / 1000}k" else "${frequencies[index]}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
