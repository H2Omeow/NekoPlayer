import 'package:flutter/material.dart';

import '../appearance_controller.dart';
import '../i18n/tr.dart';
import '../performance_profile.dart';
import 'widgets/page_layout.dart';
import 'widgets/settings_list.dart';

class PerformanceSettingsPage extends StatelessWidget {
  const PerformanceSettingsPage({super.key});

  static const _fpsOptions = [30, 45, 60, 75, 90, 120, 144, 0];

  static String tierLabel(LyricsQualityTier tier) => switch (tier) {
    LyricsQualityTier.high => tr('高清'),
    LyricsQualityTier.balanced => tr('均衡'),
    LyricsQualityTier.power => tr('省电'),
    LyricsQualityTier.extreme => tr('极简'),
  };

  static String modeLabel(
    LyricsQualityMode mode,
    AppearanceController appearance,
  ) => switch (mode) {
    LyricsQualityMode.auto =>
      tr('自动（推荐：{tier}）', {
        'tier': tierLabel(appearance.device.recommendedLyricsTier),
      }),
    LyricsQualityMode.high => tr('高清'),
    LyricsQualityMode.balanced => tr('均衡'),
    LyricsQualityMode.power => tr('省电'),
    LyricsQualityMode.extreme => tr('极简'),
    LyricsQualityMode.custom => tr('自定义'),
  };

  static String fpsLabel(int fps) =>
      fps == 0 ? tr('无上限') : '$fps fps';

  static String profileLabel(LyricsQualityProfile profile) => [
    '${(profile.scale * 100).round()}%',
    fpsLabel(profile.fps),
    if (!profile.effects) tr('减少滤镜和背景动效'),
  ].join(' · ');

  Future<T?> choose<T>(
    BuildContext context,
    String title,
    List<(T, String)> options,
    T current,
  ) => showDialog<T>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        RadioGroup<T>(
          groupValue: current,
          onChanged: (value) => Navigator.pop(context, value),
          child: Column(
            children: [
              for (final option in options)
                RadioListTile<T>(value: option.$1, title: Text(option.$2)),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final appearance = AppearanceScope.maybeOf(context);
    if (appearance == null) {
      return const DetailPage(title: '', children: []);
    }
    final device = appearance.device;
    final profile = appearance.lyricsProfile;
    final performanceLabel = switch (appearance.performanceMode) {
      PerformanceMode.auto => tr('自动'),
      PerformanceMode.on => tr('开启'),
      PerformanceMode.off => tr('关闭'),
    };
    return PanelPage(
      maxWidth: 760,
      children: [
        PageHeader(title: tr('性能与动态歌词')),
        SettingsSection(
          title: tr('设备检测'),
          description: tr(
            '自动档会根据物理分辨率、显示缩放、屏幕刷新率和显卡选择；手动档可随时覆盖。',
          ),
          children: [
            SettingsTile(
              icon: Icons.monitor_rounded,
              title: tr('物理分辨率'),
              value: device.resolutionLabel,
            ),
            SettingsTile(
              icon: Icons.aspect_ratio_rounded,
              title: tr('显示缩放'),
              value: '${(device.devicePixelRatio * 100).round()}%',
            ),
            SettingsTile(
              icon: Icons.speed_rounded,
              title: tr('屏幕刷新率'),
              value: '${device.refreshRate.round()} Hz',
            ),
            if (device.gpu.isNotEmpty)
              SettingsTile(
                icon: Icons.memory_rounded,
                title: tr('显卡'),
                value: device.gpu,
              ),
            SettingsTile(
              icon: Icons.auto_awesome_rounded,
              title: tr('自动建议'),
              value: tierLabel(device.recommendedLyricsTier),
            ),
          ],
        ),
        SettingsSection(
          title: tr('界面性能模式'),
          description: tr(
            '自动模式会在 4K 或高显示缩放下限制模糊半径并关闭页面转场，降低 GPU 峰值占用；1080p 普通显示器保持原有效果。',
          ),
          children: [
            SettingsTile(
              icon: Icons.tune_rounded,
              title: tr('界面性能模式'),
              value: performanceLabel,
              subtitle: appearance.performanceUiEnabled
                  ? tr('当前已降低模糊和转场开销')
                  : tr('当前使用完整界面效果'),
              onTap: () async {
                final value = await choose<PerformanceMode>(
                  context,
                  tr('界面性能模式'),
                  [
                    (PerformanceMode.auto, tr('自动')),
                    (PerformanceMode.on, tr('开启')),
                    (PerformanceMode.off, tr('关闭')),
                  ],
                  appearance.performanceMode,
                );
                if (value != null) appearance.updatePerformance(mode: value);
              },
            ),
          ],
        ),
        SettingsSection(
          title: tr('动态歌词画质'),
          description: tr(
            '渲染比例相对当前物理分辨率计算，100% 为原生。帧率是上限，实际帧率仍受显卡和屏幕刷新率限制。',
          ),
          children: [
            SettingsTile(
              icon: Icons.auto_fix_high_rounded,
              title: tr('动态歌词画质'),
              value: modeLabel(appearance.lyricsQualityMode, appearance),
              subtitle: profileLabel(profile),
              onTap: () async {
                final value = await choose<LyricsQualityMode>(
                  context,
                  tr('动态歌词画质'),
                  [
                    (
                      LyricsQualityMode.auto,
                      tr('自动（推荐：{tier}）', {
                        'tier': tierLabel(
                          device.recommendedLyricsTier,
                        ),
                      }),
                    ),
                    (LyricsQualityMode.high, tr('高清')),
                    (LyricsQualityMode.balanced, tr('均衡')),
                    (LyricsQualityMode.power, tr('省电')),
                    (LyricsQualityMode.extreme, tr('极简')),
                    (LyricsQualityMode.custom, tr('自定义')),
                  ],
                  appearance.lyricsQualityMode,
                );
                if (value != null) {
                  appearance.updateLyricsQuality(mode: value);
                }
              },
            ),
            if (appearance.lyricsQualityMode == LyricsQualityMode.custom) ...[
              SettingsControlTile(
                title: tr('渲染比例'),
                value: '${(appearance.lyricsScale * 100).round()}%',
                child: Slider(
                  min: .25,
                  max: 1.5,
                  divisions: 25,
                  value: appearance.lyricsScale,
                  onChanged: (value) =>
                      appearance.updateLyricsQuality(renderScale: value),
                ),
              ),
              SettingsTile(
                icon: Icons.speed_rounded,
                title: tr('帧率上限'),
                value: fpsLabel(appearance.lyricsFps),
                onTap: () async {
                  final value = await choose<int>(
                    context,
                    tr('帧率上限'),
                    [
                      for (final fps in _fpsOptions) (fps, fpsLabel(fps)),
                    ],
                    appearance.lyricsFps,
                  );
                  if (value != null) {
                    appearance.updateLyricsQuality(fps: value);
                  }
                },
              ),
              SettingsSwitchTile(
                icon: Icons.blur_off_rounded,
                title: tr('减少滤镜和背景动效'),
                subtitle: tr('关闭高成本模糊、阴影和装饰动画，适合低性能显卡'),
                value: !appearance.lyricsEffects,
                onChanged: (value) =>
                    appearance.updateLyricsQuality(effects: !value),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
