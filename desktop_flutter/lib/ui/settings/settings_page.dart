import '../../i18n/tr.dart';
import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../appearance_controller.dart';
import '../../data/native_music_catalog.dart';
import '../../desktop_integration.dart';
import '../../diagnostics/app_info.dart';
import '../../i18n/app_language.dart';

import '../../playback/effects_playback_engine.dart';
import '../../player_controller.dart';
import '../../site_controller.dart';
import '../../sync/cloud_sync_controller.dart';
import '../../sync/sync_section.dart';
import '../accounts_panel.dart';
import '../appearance_page.dart';
import '../audio_cache_page.dart';
import '../audio_effects_page.dart';
import '../cloud_sync_page.dart';
import '../desktop_settings_page.dart';
import '../diagnostics_page.dart';
import '../downloads_page.dart';
import '../legacy_import_page.dart';
import '../neko_theme.dart';
import '../plugin_subscriptions_page.dart';
import '../widgets/page_layout.dart';
import '../widgets/settings_list.dart';

final qualities = [
  ('standard', tr('标准')),
  ('exhigh', tr('极高')),
  ('lossless', tr('无损')),
  ('hires', 'Hi-Res'),
  ('jymaster', tr('超清母带')),
];

const rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

String rateLabel(double rate) =>
    rate == 1 ? tr('正常') : '${rate.toString().replaceAll(RegExp(r'\.0$'), '')}×';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.player,
    required this.catalog,
    required this.site,
    required this.cloudSync,
    required this.integration,
    required this.language,
  });

  final PlayerController player;
  final NativeMusicCatalog catalog;
  final SiteController site;
  final CloudSyncController cloudSync;
  final DesktopIntegration integration;
  final AppLanguage language;

  void push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

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

  String accountSummary() {
    final user = site.user;
    if (catalog.accounts.siteToken.isEmpty) return tr('未登录');
    final name = user?['nickname'] ?? user?['username'];
    return name?.toString() ?? tr('已登录');
  }

  String syncSummary() {
    if (!cloudSync.signedIn) return tr('登录后可用');
    if (cloudSync.busy) return tr('正在同步…');
    if (cloudSync.conflicts.isNotEmpty) return tr('有冲突需要处理');
    if (cloudSync.error != null) return tr('上次同步失败');
    final last = cloudSync.lastCheckedAt;
    return last == 0
        ? tr('尚未同步')
        : tr('上次检查 {time}', {
            'time': describeTime(last, DateTime.now()).split(' · ').first,
          });
  }

  String platformSummary() {
    final accounts = catalog.accounts;
    final parts = [
      if (accounts.neteaseLoggedIn) tr('网易云'),
      if (accounts.kugouLoggedIn() || accounts.kugouTokenOnly()) tr('酷狗'),
    ];
    return parts.isEmpty ? tr('未登录') : '已登录 ${parts.join('、')}';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      player,
      site,
      cloudSync,
      catalog.accounts,
      integration,
      language,
    ]),
    builder: (context, _) {
      final appearance = AppearanceScope.maybeOf(context);
      final quality = qualities
          .where((item) => item.$1 == player.preferredQuality)
          .firstOrNull;
      final sleep = player.sleepDeadline;
      String two(int value) => value.toString().padLeft(2, '0');
      return PanelPage(
        maxWidth: 760,
        children: [
                PageHeader(title: tr('设置')),
          SettingsSection(
            title: tr('界面语言'),
            children: [
              SettingsTile(
                icon: Icons.translate_rounded,
                title: tr('界面语言'),
                subtitle: tr('默认跟随系统；切换后立即生效'),
                value: switch (language.tag) {
                  'zh-CN' => tr('简体中文'),
                  'zh-TW' => tr('繁體中文'),
                  'en' => 'English',
                  'ja' => tr('日本語'),
                  _ => tr('跟随系统'),
                },
                onTap: () async {
                  final next = await choose<String>(
                    context,
                    tr('界面语言'),
                    [
                      ('system', tr('跟随系统')),
                      ('zh-CN', tr('简体中文')),
                      ('zh-TW', tr('繁體中文')),
                      ('en', 'English'),
                      ('ja', tr('日本語')),
                    ],
                    language.tag,
                  );
                  if (next != null) await language.setTag(next);
                },
              ),
            ],
          ),
          SettingsSection(
            title: tr('账号与同步'),
            children: [
              SettingsTile(
                icon: Icons.cloud_sync_outlined,
                title: tr('NekoPlayer 账号与云端同步'),
                subtitle: cloudSync.signedIn
                    ? tr('{account} · 收藏、歌单、播放记录与平台登录', {
                        'account': accountSummary(),
                      })
                    : tr('登录后在设备间同步收藏、歌单、播放记录与平台登录'),
                value: cloudSync.signedIn ? syncSummary() : tr('未登录'),
                onTap: () => push(
                  context,
                  CloudSyncPage(controller: cloudSync, site: site),
                ),
              ),
              SettingsTile(
                icon: Icons.person_outline_rounded,
                title: tr('音乐平台账号'),
                subtitle: tr('网易云音乐、酷狗音乐'),
                value: platformSummary(),
                onTap: () => push(
                  context,
                  DetailPage(
                    title: tr('音乐平台账号'),
                    children: [AccountsPanel(catalog: catalog)],
                  ),
                ),
              ),
            ],
          ),
          SettingsSection(
            title: tr('播放'),
            children: [
              SettingsTile(
                icon: Icons.high_quality_outlined,
                title: tr('在线播放音质'),
                subtitle: tr('从下一首开始生效，实际音质取决于账号权益'),
                value: quality?.$2 ?? player.preferredQuality,
                onTap: () async {
                  final value = await choose(
                    context,
                    tr('在线播放音质'),
                    qualities,
                    player.preferredQuality,
                  );
                  if (value != null) player.setPreferredQuality(value);
                },
              ),
              SettingsTile(
                icon: Icons.speed_rounded,
                title: tr('播放速度'),
                value: rateLabel(player.rate),
                onTap: () async {
                  final value = await choose(context, tr('播放速度'), [
                    for (final rate in rates) (rate, rateLabel(rate)),
                  ], player.rate);
                  if (value != null) player.setRate(value);
                },
              ),
              SettingsTile(
                icon: Icons.bedtime_outlined,
                title: tr('定时暂停'),
                value: sleep == null
                    ? tr('关闭')
                    : tr('{time} 暂停', {
                        'time': '${two(sleep.hour)}:${two(sleep.minute)}',
                      }),
                onTap: () async {
                  final value = await choose(context, tr('定时暂停'), [
                    (0, tr('关闭')),
                    for (final minutes in [15, 30, 45, 60, 90])
                      (minutes, tr('{minutes} 分钟后', {'minutes': minutes})),
                  ], -1);
                  if (value != null) {
                    player.setSleepTimer(
                      value == 0 ? null : Duration(minutes: value),
                    );
                  }
                },
              ),
              SettingsSwitchTile(
                icon: Icons.graphic_eq_rounded,
                title: tr('播放 / 暂停淡入淡出'),
                subtitle: tr('播放或暂停时平滑调整音量，避免突然的响声'),
                value: player.fadePlayback,
                onChanged: (value) =>
                    player.setFadePlayback(enabled: value),
              ),
              if (player.fadePlayback)
                SettingsControlTile(
                  title: tr('淡入淡出时长'),
                  value: tr('{seconds} 秒', {
                    'seconds': (player.fadeMilliseconds / 1000)
                        .toStringAsFixed(1),
                  }),
                  child: Slider(
                    min: 50,
                    max: 2000,
                    divisions: 39,
                    value: player.fadeMilliseconds.toDouble(),
                    onChanged: (value) => player.setFadePlayback(
                      milliseconds: value.round(),
                    ),
                  ),
                ),
              SettingsSwitchTile(
                icon: Icons.translate_rounded,
                title: tr('显示歌词翻译'),
                value: player.showTranslation,
                onChanged: (value) =>
                    player.setLyricPreferences(translation: value),
              ),
              if (player.engine is EffectsPlaybackEngine)
                SettingsTile(
                  icon: Icons.equalizer_rounded,
                  title: tr('音效'),
                  subtitle: tr('均衡器、低音增强、混响与母带处理'),
                  onTap: () => push(
                    context,
                    AudioEffectsPage(
                      engine: player.engine as EffectsPlaybackEngine,
                    ),
                  ),
                ),
            ],
          ),
          if (catalog.subscriptions != null)
            SettingsSection(
              title: tr('音源'),
              children: [
                SettingsTile(
                  icon: Icons.extension_outlined,
                  title: tr('音源与插件订阅'),
                  subtitle: tr('管理内置音源，导入订阅或单个脚本'),
                  value: tr('{count} 个音源', {
                    'count': catalog.subscriptions!.sources.length,
                  }),
                  onTap: () => push(
                    context,
                    PluginSubscriptionsPage(
                      subscriptions: catalog.subscriptions!,
                    ),
                  ),
                ),
              ],
            ),
          SettingsSection(
            title: tr('外观'),
            children: [
              if (appearance != null)
                SettingsTile(
                  icon: Icons.palette_outlined,
                  title: tr('主题与背景'),
                  subtitle: tr('深浅色、界面缩放、壁纸和播放页背景'),
                  value: switch (appearance.theme) {
                    ThemeMode.system => tr('跟随系统'),
                    ThemeMode.light => tr('浅色'),
                    ThemeMode.dark => tr('深色'),
                  },
                  onTap: () =>
                      push(context, AppearancePage(controller: appearance)),
                ),
              SettingsTile(
                icon: Icons.desktop_windows_outlined,
                title: tr('桌面歌词与系统控制'),
                subtitle: tr('桌面歌词窗口、媒体键与托盘'),
                value: integration.overlay ? tr('桌面歌词已开启') : null,
                onTap: () => push(
                  context,
                  DesktopSettingsPage(integration: integration),
                ),
              ),
            ],
          ),
          SettingsSection(
            title: tr('存储'),
            children: [
              if (player.downloads != null)
                SettingsTile(
                  icon: Icons.download_outlined,
                  title: tr('下载管理'),
                  onTap: () => push(
                    context,
                    DownloadsPage(
                      controller: player.downloads!,
                      onImport: (task) => player.importDownload(task),
                      onPlay: (task) => player.importDownload(task, play: true),
                    ),
                  ),
                ),
              if (appearance != null)
                SettingsTile(
                  icon: Icons.folder_outlined,
                  title: tr('默认下载目录'),
                  subtitle: appearance.downloadDirectory,
                  value: appearance.downloadDirectory == null
                      ? tr('每次下载时询问')
                      : null,
                  trailing: appearance.downloadDirectory == null
                      ? null
                      : IconButton(
                          tooltip: tr('恢复每次询问'),
                          onPressed: () =>
                              appearance.update(resetDownloads: true),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                  onTap: () => unawaited(_pickDownloads(context, appearance)),
                ),
              if (catalog.cache != null)
                SettingsTile(
                  icon: Icons.offline_pin_outlined,
                  title: tr('离线缓存'),
                  subtitle: tr('缓存听过的在线歌曲，断网也能播放'),
                  onTap: () => push(
                    context,
                    AudioCachePage(cache: catalog.cache!, player: player),
                  ),
                ),
              SettingsTile(
                icon: Icons.move_to_inbox_outlined,
                title: tr('从旧版导入'),
                subtitle: tr('导入安卓版或旧桌面版的备份'),
                onTap: () => push(
                  context,
                  LegacyImportPage(player: player, accounts: catalog.accounts),
                ),
              ),
            ],
          ),
          SettingsSection(
            title: tr('关于'),
            children: [
              SettingsTile(
                icon: Icons.keyboard_outlined,
                title: tr('键盘快捷键'),
                onTap: () => unawaited(_shortcuts(context)),
              ),
              SettingsTile(
                icon: Icons.bug_report_outlined,
                title: tr('崩溃日志与诊断'),
                subtitle: tr('查看或导出运行日志，反馈问题时附上'),
                onTap: () => push(context, const DiagnosticsPage()),
              ),
              SettingsTile(
                icon: Icons.description_outlined,
                title: tr('开源许可'),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'NekoPlayer',
                  applicationVersion: appVersion,
                ),
              ),
              SettingsTile(
                icon: Icons.info_outline_rounded,
                title: tr('版本'),
                value: appVersion.split('+').first,
              ),
            ],
          ),
          if (!catalog.accounts.readable)
                  Padding(
              padding: EdgeInsets.only(bottom: NekoSpace.xl),
              child: InlineNotice(
                tr('系统密钥环不可用，账号凭据暂时无法保存。Linux 请先解锁系统密钥环。'),
                error: true,
              ),
            ),
        ],
      );
    },
  );

  Future<void> _pickDownloads(
    BuildContext context,
    AppearanceController appearance,
  ) async {
    try {
      final directory = await getDirectoryPath();
      if (directory != null) appearance.update(downloads: directory);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(      SnackBar(content: Text(tr('目录选择未完成。'))));
      }
    }
  }

  Future<void> _shortcuts(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) {
      final text = Theme.of(context).textTheme;
      Widget row(String keys, String action) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 140, child: Text(keys, style: text.labelLarge)),
            Text(action, style: text.bodyMedium),
          ],
        ),
      );
      return AlertDialog(
        title:       Text(tr('键盘快捷键')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row(tr('Ctrl + 空格'), tr('播放 / 暂停')),
            row('Ctrl + ← / →', tr('上一首 / 下一首')),
            row('Ctrl + O', tr('导入音乐')),
            row('Ctrl + F', tr('搜索')),
            row(tr('空格'), tr('在播放页播放 / 暂停')),
            row('Esc', tr('关闭播放页')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:       Text(tr('知道了')),
          ),
        ],
      );
    },
  );
}
