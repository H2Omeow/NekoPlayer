import '../i18n/tr.dart';
import 'package:flutter/material.dart';

import '../desktop_integration.dart';
import 'widgets/page_layout.dart';
import 'widgets/settings_list.dart';

class DesktopSettingsPage extends StatelessWidget {
  const DesktopSettingsPage({super.key, required this.integration});
  final DesktopIntegration integration;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([integration, integration.player]),
    builder: (context, _) {
      final lyrics = integration.lyricsAvailable;
      return DetailPage(
        title: tr('桌面歌词与系统控制'),
        children: [
          SettingsSection(
            title: tr('桌面歌词'),
            description: integration.positioningAvailable
                ? tr('未锁定时拖动歌词窗口即可移动，双击切换播放 / 暂停。开关、锁定、字号和透明度在重启后保留。')
                : tr('当前窗口系统不开放自由定位，置顶、位置与鼠标穿透效果受桌面合成器限制。'),
            children: [
              SettingsSwitchTile(
                icon: Icons.subtitles_outlined,
                title: tr('显示桌面歌词'),
                subtitle: lyrics ? null : tr('当前环境无法创建歌词窗口'),
                value: integration.overlay,
                onChanged: lyrics
                    ? (value) => integration.configureOverlay(enabled: value)
                    : null,
              ),
              SettingsSwitchTile(
                icon: Icons.lock_outline_rounded,
                title: tr('锁定并允许鼠标穿透'),
                subtitle: tr('锁定后需要回到这里解锁或关闭歌词'),
                value: integration.locked,
                onChanged: lyrics
                    ? (value) => integration.configureOverlay(lock: value)
                    : null,
              ),
              SettingsSwitchTile(
                icon: Icons.view_agenda_outlined,
                title: tr('双行显示'),
                value: integration.player.doubleLyrics,
                onChanged: (value) {
                  integration.player.setLyricPreferences(twoLines: value);
                  integration.configureOverlay();
                },
              ),
              SettingsSwitchTile(
                icon: Icons.translate_rounded,
                title: tr('显示翻译'),
                subtitle: tr('有翻译时第二行显示翻译，否则显示下一句'),
                value: integration.player.showTranslation,
                onChanged: (value) {
                  integration.player.setLyricPreferences(translation: value);
                  integration.configureOverlay();
                },
              ),
              SettingsSwitchTile(
                icon: Icons.title_rounded,
                title: tr('显示歌名'),
                subtitle: tr('在歌词上方显示当前歌曲名称'),
                value: integration.overlayTitle,
                onChanged: lyrics
                    ? (value) => integration.configureOverlay(showTitle: value)
                    : null,
              ),
              SettingsSwitchTile(
                icon: Icons.linear_scale_rounded,
                title: tr('显示进度条'),
                value: integration.overlayProgress,
                onChanged: lyrics
                    ? (value) =>
                          integration.configureOverlay(showProgress: value)
                    : null,
              ),
              SettingsSwitchTile(
                icon: Icons.play_circle_outline_rounded,
                title: tr('显示播放控制'),
                subtitle: tr('上一首、播放 / 暂停、下一首；锁定时不可点击'),
                value: integration.overlayControls,
                onChanged: lyrics
                    ? (value) =>
                          integration.configureOverlay(showControls: value)
                    : null,
              ),
              SettingsControlTile(
                title: tr('字号'),
                value: '${integration.fontSize.round()}',
                child: Slider(
                  min: 18,
                  max: 64,
                  divisions: 46,
                  value: integration.fontSize,
                  onChanged: lyrics
                      ? (value) => integration.configureOverlay(size: value)
                      : null,
                ),
              ),
              SettingsControlTile(
                title: tr('不透明度'),
                value: '${(integration.opacity * 100).round()}%',
                child: Slider(
                  min: .25,
                  max: 1,
                  divisions: 15,
                  value: integration.opacity,
                  onChanged: lyrics
                      ? (value) => integration.configureOverlay(alpha: value)
                      : null,
                ),
              ),
            ],
          ),
          SettingsSection(
            title: tr('系统'),
            children: [
              SettingsTile(
                icon: Icons.speaker_group_outlined,
                title: tr('系统媒体控制'),
                subtitle: integration.mediaAvailable
                    ? tr('可以用系统媒体面板和键盘媒体键控制播放')
                    : tr('当前环境没有可用的系统媒体会话，应用内快捷键仍然可用'),
                value: integration.mediaAvailable ? tr('已连接') : tr('不可用'),
              ),
              SettingsSwitchTile(
                icon: Icons.minimize_rounded,
                title: tr('关闭窗口时最小化到托盘'),
                subtitle: integration.trayAvailable
                    ? tr('仅本次启动有效；从托盘菜单显示窗口、控制播放或退出')
                    : tr('当前桌面没有可用托盘，关闭窗口会直接退出'),
                value: integration.closeToTray,
                onChanged: integration.trayAvailable
                    ? integration.configureTray
                    : null,
              ),
            ],
          ),
          if (integration.error case final error?)
            InlineNotice(error, error: true),
        ],
      );
    },
  );
}
