import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../appearance_controller.dart';
import '../domain/online_music.dart';
import 'neko_theme.dart';
import 'widgets/page_layout.dart';
import 'widgets/settings_list.dart';

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key, required this.controller});
  final AppearanceController controller;

  Future<void> pickWallpaper(BuildContext context) async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: '图片',
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
          ),
        ],
      );
      if (file != null) await controller.localWallpaper(file.path);
    } catch (failure) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failure is MusicSearchException
                  ? failure.message
                  : '无法选择图片，请检查文件权限。',
            ),
          ),
        );
      }
    }
  }

  static String percent(double value) => '${(value * 100).round()}%';

  static String whole(double value) => value.round().toString();

  Widget slider(
    String title,
    double value,
    double min,
    double max,
    ValueChanged<double>? change, {
    String Function(double) format = percent,
  }) => SettingsControlTile(
    title: title,
    value: format(value),
    child: Slider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      divisions: 20,
      onChanged: change,
    ),
  );

  Widget choices<T>(
    List<(T, String)> options,
    T selected,
    ValueChanged<T> onSelected,
  ) => Wrap(
    spacing: NekoSpace.sm,
    runSpacing: NekoSpace.sm,
    children: [
      for (final (value, label) in options)
        ChoiceChip(
          label: Text(label),
          selected: value == selected,
          onSelected: (_) => onSelected(value),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final hasWallpaper = controller.wallpaper != null;
      final wallpaperOn = controller.wallpaperEnabled;
      return DetailPage(
        title: '主题与背景',
        children: [
          SettingsSection(
            title: '主题',
            children: [
              SettingsControlTile(
                title: '颜色模式',
                child: choices(
                  const [
                    (ThemeMode.system, '跟随系统'),
                    (ThemeMode.light, '浅色'),
                    (ThemeMode.dark, '深色'),
                  ],
                  controller.theme,
                  (value) => controller.update(themeMode: value),
                ),
              ),
              slider(
                '界面文字缩放',
                controller.scale,
                .85,
                1.4,
                (value) => controller.update(textScale: value),
              ),
            ],
          ),
          SettingsSection(
            title: '窗口背景',
            description:
                '随机壁纸只在点击时请求本站；本地图片路径不会上传。'
                '模糊上限为 20，避免占用过多 GPU。',
            children: [
              SettingsSwitchTile(
                icon: Icons.wallpaper_rounded,
                title: '壁纸背景',
                subtitle: hasWallpaper ? null : '先选择一张图片或加载随机壁纸',
                value: wallpaperOn,
                onChanged: hasWallpaper
                    ? (value) => controller.update(showWallpaper: value)
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.all(NekoSpace.lg),
                child: Wrap(
                  spacing: NekoSpace.sm,
                  runSpacing: NekoSpace.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => pickWallpaper(context),
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text('选择本地图片'),
                    ),
                    OutlinedButton.icon(
                      onPressed: controller.busy
                          ? null
                          : controller.randomWallpaper,
                      icon: const Icon(Icons.shuffle_rounded, size: 18),
                      label: const Text('随机横屏壁纸'),
                    ),
                    if (hasWallpaper)
                      TextButton(
                        onPressed: () =>
                            controller.update(clearWallpaper: true),
                        child: const Text('恢复纯色背景'),
                      ),
                  ],
                ),
              ),
              if (controller.busy) const LinearProgressIndicator(),
              slider(
                '背景遮罩',
                controller.mask,
                .35,
                .95,
                wallpaperOn
                    ? (value) => controller.update(darkness: value)
                    : null,
              ),
              slider(
                '背景模糊',
                controller.blur,
                0,
                20,
                wallpaperOn
                    ? (value) => controller.update(blurRadius: value)
                    : null,
                format: whole,
              ),
              slider(
                '面板不透明度',
                controller.controls,
                .55,
                1,
                wallpaperOn
                    ? (value) => controller.update(controlAlpha: value)
                    : null,
              ),
            ],
          ),
          SettingsSection(
            title: '播放页背景',
            description: '与窗口背景相互独立；没有封面或壁纸时使用纯色，不会自动请求随机壁纸。',
            children: [
              SettingsControlTile(
                title: '背景来源',
                child: choices(
                  const [
                    (PlayerBackground.solid, '纯色'),
                    (PlayerBackground.cover, '歌曲封面'),
                    (PlayerBackground.wallpaper, '当前壁纸'),
                  ],
                  controller.playerBackground,
                  (value) => controller.update(playerMode: value),
                ),
              ),
              slider(
                '遮罩',
                controller.playerMask,
                .35,
                .95,
                controller.playerBackground == PlayerBackground.solid
                    ? null
                    : (value) => controller.update(playerDarkness: value),
              ),
              slider(
                '模糊',
                controller.playerBlur,
                0,
                20,
                controller.playerBackground == PlayerBackground.solid
                    ? null
                    : (value) => controller.update(playerBlurRadius: value),
                format: whole,
              ),
            ],
          ),
          if (controller.error case final error?)
            InlineNotice(error, error: true),
        ],
      );
    },
  );
}
