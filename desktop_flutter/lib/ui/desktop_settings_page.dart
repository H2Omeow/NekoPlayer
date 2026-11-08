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
        title: '桌面歌词与系统控制',
        children: [
          SettingsSection(
            title: '桌面歌词',
            description: integration.positioningAvailable
                ? '未锁定时拖动歌词窗口即可移动，双击切换播放 / 暂停。开关、锁定、字号和透明度在重启后保留。'
                : '当前窗口系统不开放自由定位，置顶、位置与鼠标穿透效果受桌面合成器限制。',
            children: [
              SettingsSwitchTile(
                icon: Icons.subtitles_outlined,
                title: '显示桌面歌词',
                subtitle: lyrics ? null : '当前环境无法创建歌词窗口',
                value: integration.overlay,
                onChanged: lyrics
                    ? (value) => integration.configureOverlay(enabled: value)
                    : null,
              ),
              SettingsSwitchTile(
                icon: Icons.lock_outline_rounded,
                title: '锁定并允许鼠标穿透',
                subtitle: '锁定后需要回到这里解锁或关闭歌词',
                value: integration.locked,
                onChanged: lyrics
                    ? (value) => integration.configureOverlay(lock: value)
                    : null,
              ),
              SettingsSwitchTile(
                icon: Icons.view_agenda_outlined,
                title: '双行显示',
                value: integration.player.doubleLyrics,
                onChanged: (value) {
                  integration.player.setLyricPreferences(twoLines: value);
                  integration.configureOverlay();
                },
              ),
              SettingsSwitchTile(
                icon: Icons.translate_rounded,
                title: '显示翻译',
                subtitle: '有翻译时第二行显示翻译，否则显示下一句',
                value: integration.player.showTranslation,
                onChanged: (value) {
                  integration.player.setLyricPreferences(translation: value);
                  integration.configureOverlay();
                },
              ),
              SettingsSwitchTile(
                icon: Icons.title_rounded,
                title: '显示歌名',
                subtitle: '在歌词上方显示当前歌曲名称',
                value: integration.overlayTitle,
                onChanged: lyrics
                    ? (value) => integration.configureOverlay(showTitle: value)
                    : null,
              ),
              SettingsSwitchTile(
                icon: Icons.linear_scale_rounded,
                title: '显示进度条',
                value: integration.overlayProgress,
                onChanged: lyrics
                    ? (value) =>
                          integration.configureOverlay(showProgress: value)
                    : null,
              ),
              SettingsSwitchTile(
                icon: Icons.play_circle_outline_rounded,
                title: '显示播放控制',
                subtitle: '上一首、播放 / 暂停、下一首；锁定时不可点击',
                value: integration.overlayControls,
                onChanged: lyrics
                    ? (value) =>
                          integration.configureOverlay(showControls: value)
                    : null,
              ),
              SettingsControlTile(
                title: '字号',
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
                title: '不透明度',
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
            title: '系统',
            children: [
              SettingsTile(
                icon: Icons.speaker_group_outlined,
                title: '系统媒体控制',
                subtitle: integration.mediaAvailable
                    ? '可以用系统媒体面板和键盘媒体键控制播放'
                    : '当前环境没有可用的系统媒体会话，应用内快捷键仍然可用',
                value: integration.mediaAvailable ? '已连接' : '不可用',
              ),
              SettingsSwitchTile(
                icon: Icons.minimize_rounded,
                title: '关闭窗口时最小化到托盘',
                subtitle: integration.trayAvailable
                    ? '仅本次启动有效；从托盘菜单显示窗口、控制播放或退出'
                    : '当前桌面没有可用托盘，关闭窗口会直接退出',
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
