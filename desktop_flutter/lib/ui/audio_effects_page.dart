import 'package:flutter/material.dart';

import '../domain/audio_effects.dart';
import '../domain/mastering_presets.dart';
import '../playback/effects_playback_engine.dart';
import 'neko_theme.dart';
import 'widgets/page_layout.dart';
import 'widgets/settings_list.dart';

class AudioEffectsPage extends StatelessWidget {
  const AudioEffectsPage({super.key, required this.engine});
  final EffectsPlaybackEngine engine;

  Widget slider(
    String label,
    double value,
    ValueChanged<double> change, {
    double minimum = 0,
    double maximum = 100,
  }) => SettingsControlTile(
    title: label,
    value: '${value.round()}${minimum < 0 ? ' dB' : '%'}',
    child: Slider(
      value: value.clamp(minimum, maximum),
      min: minimum,
      max: maximum,
      divisions: (maximum - minimum).round(),
      onChanged: engine.changing ? null : change,
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: engine,
    builder: (context, _) {
      final settings = engine.effects;
      final mastering = MasteringPreset.find(settings.mastering);
      final text = Theme.of(context).textTheme;
      void configure(AudioEffects value) => engine.configure(value);
      return DetailPage(
        title: '音效',
        maxWidth: 820,
        actions: [
          TextButton(
            onPressed: engine.changing
                ? null
                : () => configure(AudioEffects(enabled: settings.enabled)),
            child: const Text('全部重置'),
          ),
        ],
        children: [
          SettingsSection(
            description:
                '参数实时生效；变速和跳转会重新启动解码。'
                '母带只开放原版实际实现的 15–34 号处理链。重启应用后专业模式默认关闭。',
            children: [
              SettingsSwitchTile(
                icon: Icons.graphic_eq_rounded,
                title: '专业音效',
                subtitle:
                    '使用原版 C++ DSP，以 48kHz 双声道输出到系统音频设备。'
                    '切换时会重新解析当前音源。',
                value: settings.enabled,
                onChanged: engine.changing
                    ? null
                    : (value) => configure(settings.copyWith(enabled: value)),
              ),
            ],
          ),
          if (engine.effectsError case final error?) ...[
            InlineNotice(error, error: true),
            const SizedBox(height: NekoSpace.lg),
          ],
          if (engine.changing) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: NekoSpace.lg),
          ],
          SettingsSection(
            title: '均衡器',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  NekoSpace.lg,
                  NekoSpace.lg,
                  NekoSpace.lg,
                  0,
                ),
                child: Wrap(
                  spacing: NekoSpace.sm,
                  runSpacing: NekoSpace.sm,
                  children: [
                    for (final preset in AudioEffects.presets.entries)
                      ActionChip(
                        label: Text(preset.key),
                        onPressed: engine.changing
                            ? null
                            : () => configure(
                                settings.copyWith(eq: preset.value),
                              ),
                      ),
                  ],
                ),
              ),
              _Equalizer(
                values: settings.values.take(10).toList(),
                enabled: !engine.changing,
                onChanged: (index, value) {
                  final bands = List<double>.of(settings.values.take(10));
                  bands[index] = value;
                  configure(settings.copyWith(eq: bands));
                },
              ),
            ],
          ),
          SettingsSection(
            title: '空间与动态',
            children: [
              slider(
                '低音增强',
                settings.bass,
                (value) => configure(settings.copyWith(bass: value)),
              ),
              slider(
                '立体声宽度',
                settings.width,
                (value) => configure(settings.copyWith(width: value)),
              ),
              slider(
                '混响湿声',
                settings.wet,
                (value) => configure(settings.copyWith(wet: value)),
              ),
              slider(
                '混响空间',
                settings.room,
                (value) => configure(settings.copyWith(room: value)),
              ),
              slider(
                '混响阻尼',
                settings.damping,
                (value) => configure(settings.copyWith(damping: value)),
              ),
              slider(
                '响度增益',
                settings.loudness,
                (value) => configure(settings.copyWith(loudness: value)),
              ),
            ],
          ),
          SettingsSection(
            title: '母带处理',
            children: [
              Padding(
                padding: const EdgeInsets.all(NekoSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<int>(
                      key: ValueKey(settings.mastering),
                      initialValue: settings.values[16].toInt(),
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '处理链'),
                      items: [
                        const DropdownMenuItem(value: 0, child: Text('关闭')),
                        for (final preset in MasteringPreset.available)
                          DropdownMenuItem(
                            value: preset.id,
                            child: Text(
                              preset.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: engine.changing
                          ? null
                          : (value) {
                              if (value != null) {
                                configure(settings.copyWith(mastering: value));
                              }
                            },
                    ),
                    if (mastering != null) ...[
                      const SizedBox(height: NekoSpace.sm),
                      Text(
                        '${mastering.group} · ${mastering.description}',
                        style: text.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              slider(
                '母带混合',
                settings.mix,
                (value) => configure(settings.copyWith(mix: value)),
              ),
            ],
          ),
        ],
      );
    },
  );
}

/// Ten vertical faders, like a hardware graphic EQ.
class _Equalizer extends StatelessWidget {
  const _Equalizer({
    required this.values,
    required this.enabled,
    required this.onChanged,
  });

  final List<double> values;
  final bool enabled;
  final void Function(int index, double value) onChanged;

  static String frequency(int hz) => hz >= 1000 ? '${hz ~/ 1000}k' : '$hz';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(NekoSpace.lg),
      child: Row(
        children: [
          for (var index = 0; index < values.length; index++)
            SizedBox(
              width: 64,
              child: Column(
                children: [
                  Text(
                    '${values[index] > 0 ? '+' : ''}${values[index].round()}',
                    style: text.labelMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  SizedBox(
                    height: 180,
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Slider(
                        value: values[index].clamp(-15, 15),
                        min: -15,
                        max: 15,
                        divisions: 30,
                        semanticFormatterCallback: (value) =>
                            '${AudioEffects.frequencies[index]} Hz ${value.round()} dB',
                        onChanged: enabled
                            ? (value) => onChanged(index, value)
                            : null,
                      ),
                    ),
                  ),
                  Text(
                    frequency(AudioEffects.frequencies[index]),
                    style: text.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
