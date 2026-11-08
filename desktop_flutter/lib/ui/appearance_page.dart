import '../i18n/tr.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as paths;

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
                XTypeGroup(
            label: tr('图片'),
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
                  : tr('无法选择图片，请检查文件权限。'),
            ),
          ),
        );
      }
    }
  }

  Future<void> pickFont(BuildContext context) async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
                XTypeGroup(label: tr('字体'), extensions: ['ttf', 'otf']),
        ],
      );
      if (file != null) await controller.setCustomFont(file.path);
    } catch (failure) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failure is MusicSearchException
                  ? failure.message
                  : tr('无法读取字体文件，请检查文件权限。'),
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
    int divisions = 20,
  }) => SettingsControlTile(
    title: title,
    value: format(value),
    child: Slider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      divisions: divisions,
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
        title: tr('主题与背景'),
        children: [
          SettingsSection(
            title: tr('主题'),
            children: [
              SettingsControlTile(
                title: tr('颜色模式'),
                child: choices(
                        [
                    (ThemeMode.system, tr('跟随系统')),
                    (ThemeMode.light, tr('浅色')),
                    (ThemeMode.dark, tr('深色')),
                  ],
                  controller.theme,
                  (value) => controller.update(themeMode: value),
                ),
              ),
              slider(
                tr('界面文字缩放'),
                controller.scale,
                .85,
                1.4,
                (value) => controller.update(textScale: value),
              ),
            ],
          ),
          SettingsSection(
            title: tr('字体'),
            description: tr('选择本地 TTF / OTF 字体应用到整个界面。字体缺少的中文会回退到内置字体。'),
            children: [
              SettingsTile(
                icon: Icons.text_fields_rounded,
                title: tr('界面字体'),
                subtitle: controller.fontPath == null
                    ? tr('使用内置字体')
                    : paths.basename(controller.fontPath!),
                onTap: () => pickFont(context),
              ),
              Padding(
                padding: const EdgeInsets.all(NekoSpace.lg),
                child: Wrap(
                  spacing: NekoSpace.sm,
                  runSpacing: NekoSpace.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => pickFont(context),
                      icon: const Icon(Icons.font_download_outlined, size: 18),
                      label:       Text(tr('选择本地字体')),
                    ),
                    if (controller.fontPath != null)
                      TextButton(
                        onPressed: controller.clearCustomFont,
                        child:       Text(tr('恢复默认字体')),
                      ),
                  ],
                ),
              ),
              if (controller.fontError case final message?)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: NekoSpace.lg),
                  child: InlineNotice(message, error: true),
                ),
            ],
          ),
          SettingsSection(
            title: tr('窗口背景'),
            description:
                tr('随机壁纸只在点击时请求本站；本地图片路径不会上传。') + tr('模糊上限为 20，避免占用过多 GPU。'),
            children: [
              SettingsSwitchTile(
                icon: Icons.wallpaper_rounded,
                title: tr('壁纸背景'),
                subtitle: hasWallpaper ? null : tr('先选择一张图片或加载随机壁纸'),
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
                      label:       Text(tr('选择本地图片')),
                    ),
                    OutlinedButton.icon(
                      onPressed: controller.busy
                          ? null
                          : controller.randomWallpaper,
                      icon: const Icon(Icons.shuffle_rounded, size: 18),
                      label:       Text(tr('随机横屏壁纸')),
                    ),
                    if (hasWallpaper)
                      TextButton(
                        onPressed: () =>
                            controller.update(clearWallpaper: true),
                        child:       Text(tr('恢复纯色背景')),
                      ),
                  ],
                ),
              ),
              if (controller.busy) const LinearProgressIndicator(),
              slider(
                tr('背景遮罩'),
                controller.mask,
                .35,
                .95,
                wallpaperOn
                    ? (value) => controller.update(darkness: value)
                    : null,
              ),
              slider(
                tr('背景模糊'),
                controller.blur,
                0,
                20,
                wallpaperOn
                    ? (value) => controller.update(blurRadius: value)
                    : null,
                format: whole,
              ),
              slider(
                tr('面板不透明度'),
                controller.controls,
                .2,
                1,
                wallpaperOn
                    ? (value) => controller.update(controlAlpha: value)
                    : null,
                divisions: 80,
              ),
            ],
          ),
          SettingsSection(
            title: tr('播放页背景'),
            description: tr('与窗口背景相互独立；没有封面或壁纸时使用纯色，不会自动请求随机壁纸。'),
            children: [
              SettingsControlTile(
                title: tr('背景来源'),
                child: choices(
                        [
                    (PlayerBackground.solid, tr('纯色')),
                    (PlayerBackground.cover, tr('歌曲封面')),
                    (PlayerBackground.wallpaper, tr('当前壁纸')),
                  ],
                  controller.playerBackground,
                  (value) => controller.update(playerMode: value),
                ),
              ),
              slider(
                tr('遮罩'),
                controller.playerMask,
                .35,
                .95,
                controller.playerBackground == PlayerBackground.solid
                    ? null
                    : (value) => controller.update(playerDarkness: value),
              ),
              slider(
                tr('模糊'),
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
