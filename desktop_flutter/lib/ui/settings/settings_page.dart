import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../appearance_controller.dart';
import '../../data/native_music_catalog.dart';
import '../../desktop_integration.dart';
import '../../diagnostics/app_info.dart';
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

const qualities = [
  ('standard', '标准'),
  ('exhigh', '极高'),
  ('lossless', '无损'),
  ('hires', 'Hi-Res'),
  ('jymaster', '超清母带'),
];

const rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

String rateLabel(double rate) =>
    rate == 1 ? '正常' : '${rate.toString().replaceAll(RegExp(r'\.0$'), '')}×';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.player,
    required this.catalog,
    required this.site,
    required this.cloudSync,
    required this.integration,
  });

  final PlayerController player;
  final NativeMusicCatalog catalog;
  final SiteController site;
  final CloudSyncController cloudSync;
  final DesktopIntegration integration;

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
    if (catalog.accounts.siteToken.isEmpty) return '未登录';
    final name = user?['nickname'] ?? user?['username'];
    return name?.toString() ?? '已登录';
  }

  String syncSummary() {
    if (!cloudSync.signedIn) return '登录后可用';
    if (cloudSync.busy) return '正在同步…';
    if (cloudSync.conflicts.isNotEmpty) return '有冲突需要处理';
    if (cloudSync.error != null) return '上次同步失败';
    final last = cloudSync.lastCheckedAt;
    return last == 0
        ? '尚未同步'
        : '上次检查 ${describeTime(last, DateTime.now()).split(' · ').first}';
  }

  String platformSummary() {
    final accounts = catalog.accounts;
    final parts = [
      if (accounts.neteaseLoggedIn) '网易云',
      if (accounts.kugouLoggedIn() || accounts.kugouTokenOnly()) '酷狗',
    ];
    return parts.isEmpty ? '未登录' : '已登录 ${parts.join('、')}';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      player,
      site,
      cloudSync,
      catalog.accounts,
      integration,
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
          const PageHeader(title: '设置'),
          SettingsSection(
            title: '账号与同步',
            children: [
              SettingsTile(
                icon: Icons.cloud_sync_outlined,
                title: 'NekoPlayer 账号与云端同步',
                subtitle: cloudSync.signedIn
                    ? '${accountSummary()} · 收藏、歌单、播放记录与平台登录'
                    : '登录后在设备间同步收藏、歌单、播放记录与平台登录',
                value: cloudSync.signedIn ? syncSummary() : '未登录',
                onTap: () => push(
                  context,
                  CloudSyncPage(controller: cloudSync, site: site),
                ),
              ),
              SettingsTile(
                icon: Icons.person_outline_rounded,
                title: '音乐平台账号',
                subtitle: '网易云音乐、酷狗音乐',
                value: platformSummary(),
                onTap: () => push(
                  context,
                  DetailPage(
                    title: '音乐平台账号',
                    children: [AccountsPanel(catalog: catalog)],
                  ),
                ),
              ),
            ],
          ),
          SettingsSection(
            title: '播放',
            children: [
              SettingsTile(
                icon: Icons.high_quality_outlined,
                title: '在线播放音质',
                subtitle: '从下一首开始生效，实际音质取决于账号权益',
                value: quality?.$2 ?? player.preferredQuality,
                onTap: () async {
                  final value = await choose(
                    context,
                    '在线播放音质',
                    qualities,
                    player.preferredQuality,
                  );
                  if (value != null) player.setPreferredQuality(value);
                },
              ),
              SettingsTile(
                icon: Icons.speed_rounded,
                title: '播放速度',
                value: rateLabel(player.rate),
                onTap: () async {
                  final value = await choose(context, '播放速度', [
                    for (final rate in rates) (rate, rateLabel(rate)),
                  ], player.rate);
                  if (value != null) player.setRate(value);
                },
              ),
              SettingsTile(
                icon: Icons.bedtime_outlined,
                title: '定时暂停',
                value: sleep == null
                    ? '关闭'
                    : '${two(sleep.hour)}:${two(sleep.minute)} 暂停',
                onTap: () async {
                  final value = await choose(context, '定时暂停', [
                    (0, '关闭'),
                    for (final minutes in [15, 30, 45, 60, 90])
                      (minutes, '$minutes 分钟后'),
                  ], -1);
                  if (value != null) {
                    player.setSleepTimer(
                      value == 0 ? null : Duration(minutes: value),
                    );
                  }
                },
              ),
              SettingsSwitchTile(
                icon: Icons.translate_rounded,
                title: '显示歌词翻译',
                value: player.showTranslation,
                onChanged: (value) =>
                    player.setLyricPreferences(translation: value),
              ),
              if (player.engine is EffectsPlaybackEngine)
                SettingsTile(
                  icon: Icons.equalizer_rounded,
                  title: '音效',
                  subtitle: '均衡器、低音增强、混响与母带处理',
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
              title: '音源',
              children: [
                SettingsTile(
                  icon: Icons.extension_outlined,
                  title: '音源与插件订阅',
                  subtitle: '管理内置音源，导入订阅或单个脚本',
                  value: '${catalog.subscriptions!.sources.length} 个音源',
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
            title: '外观',
            children: [
              if (appearance != null)
                SettingsTile(
                  icon: Icons.palette_outlined,
                  title: '主题与背景',
                  subtitle: '深浅色、界面缩放、壁纸和播放页背景',
                  value: switch (appearance.theme) {
                    ThemeMode.system => '跟随系统',
                    ThemeMode.light => '浅色',
                    ThemeMode.dark => '深色',
                  },
                  onTap: () =>
                      push(context, AppearancePage(controller: appearance)),
                ),
              SettingsTile(
                icon: Icons.desktop_windows_outlined,
                title: '桌面歌词与系统控制',
                subtitle: '桌面歌词窗口、媒体键与托盘',
                value: integration.overlay ? '桌面歌词已开启' : null,
                onTap: () => push(
                  context,
                  DesktopSettingsPage(integration: integration),
                ),
              ),
            ],
          ),
          SettingsSection(
            title: '存储',
            children: [
              if (player.downloads != null)
                SettingsTile(
                  icon: Icons.download_outlined,
                  title: '下载管理',
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
                  title: '默认下载目录',
                  subtitle: appearance.downloadDirectory,
                  value: appearance.downloadDirectory == null
                      ? '每次下载时询问'
                      : null,
                  trailing: appearance.downloadDirectory == null
                      ? null
                      : IconButton(
                          tooltip: '恢复每次询问',
                          onPressed: () =>
                              appearance.update(resetDownloads: true),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                  onTap: () => unawaited(_pickDownloads(context, appearance)),
                ),
              if (catalog.cache != null)
                SettingsTile(
                  icon: Icons.offline_pin_outlined,
                  title: '离线缓存',
                  subtitle: '缓存听过的在线歌曲，断网也能播放',
                  onTap: () => push(
                    context,
                    AudioCachePage(cache: catalog.cache!, player: player),
                  ),
                ),
              SettingsTile(
                icon: Icons.move_to_inbox_outlined,
                title: '从旧版导入',
                subtitle: '导入安卓版或旧桌面版的备份',
                onTap: () => push(
                  context,
                  LegacyImportPage(player: player, accounts: catalog.accounts),
                ),
              ),
            ],
          ),
          SettingsSection(
            title: '关于',
            children: [
              SettingsTile(
                icon: Icons.keyboard_outlined,
                title: '键盘快捷键',
                onTap: () => unawaited(_shortcuts(context)),
              ),
              SettingsTile(
                icon: Icons.bug_report_outlined,
                title: '崩溃日志与诊断',
                subtitle: '查看或导出运行日志，反馈问题时附上',
                onTap: () => push(context, const DiagnosticsPage()),
              ),
              SettingsTile(
                icon: Icons.description_outlined,
                title: '开源许可',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'NekoPlayer',
                  applicationVersion: appVersion,
                ),
              ),
              SettingsTile(
                icon: Icons.info_outline_rounded,
                title: '版本',
                value: appVersion.split('+').first,
              ),
            ],
          ),
          if (!catalog.accounts.readable)
            const Padding(
              padding: EdgeInsets.only(bottom: NekoSpace.xl),
              child: InlineNotice(
                '系统密钥环不可用，账号凭据暂时无法保存。Linux 请先解锁系统密钥环。',
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
        ).showSnackBar(const SnackBar(content: Text('目录选择未完成。')));
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
        title: const Text('键盘快捷键'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row('Ctrl + 空格', '播放 / 暂停'),
            row('Ctrl + ← / →', '上一首 / 下一首'),
            row('Ctrl + O', '导入音乐'),
            row('Ctrl + F', '搜索'),
            row('空格', '在播放页播放 / 暂停'),
            row('Esc', '关闭播放页'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      );
    },
  );
}
