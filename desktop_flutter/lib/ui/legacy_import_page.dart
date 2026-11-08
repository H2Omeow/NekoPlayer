import '../i18n/tr.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/account_store.dart';
import '../data/legacy_import.dart';
import '../player_controller.dart';
import '../playback/effects_playback_engine.dart';
import 'neko_theme.dart';
import 'widgets/page_layout.dart';
import 'widgets/settings_list.dart';

class LegacyImportPage extends StatefulWidget {
  const LegacyImportPage({
    super.key,
    required this.player,
    required this.accounts,
  });
  final PlayerController player;
  final AccountStore accounts;
  @override
  State<LegacyImportPage> createState() => _LegacyImportPageState();
}

class _LegacyImportPageState extends State<LegacyImportPage> {
  bool includeCredentials = false;
  bool includeSettings = false;
  bool includeQueue = false;
  bool includeEffects = false;
  bool busy = false;
  LegacyImport? preview;
  String? message;

  Future<void> select() async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
      preview = null;
    });
    try {
      final files = await openFiles(
        acceptedTypeGroups: [
                XTypeGroup(
            label: tr('旧版备份'),
            extensions: ['properties', 'xml', 'json', 'pb', 'preferences_pb'],
          ),
        ],
      );
      if (!mounted || files.isEmpty) return;
      final imported = await LegacyImport.readFiles(
        files.map((file) => file.path).toList(),
        includeCredentials: includeCredentials,
        includeSettings: includeSettings,
        includeQueue: includeQueue,
        includeEffects: includeEffects,
      );
      if (mounted) setState(() => preview = imported);
    } on FormatException catch (failure) {
      if (mounted) setState(() => message = failure.message);
    } catch (_) {
      if (mounted) setState(() => message = tr('未能读取备份，请检查文件权限和备份格式。'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> apply() async {
    final imported = preview;
    if (busy || imported == null) return;
    setState(() {
      busy = true;
      message = null;
    });
    var librarySaved = false;
    try {
      await widget.player.mergeCloud(imported.library);
      librarySaved = true;
      final accounts = await imported.fillMissingAccounts(widget.accounts);
      if (imported.queue != null) {
        await widget.player.importPlaybackQueue(
          imported.queue!.tracks,
          imported.queue!.session,
        );
      }
      if (imported.playback.count > 0) {
        await widget.player.importPlaybackPreferences(
          speed: imported.playback.rate,
          quality: imported.playback.quality,
          translation: imported.playback.translation,
          twoLines: imported.playback.twoLines,
        );
      }
      if (imported.effects != null) {
        final engine = widget.player.engine;
        if (engine is! EffectsPlaybackEngine) {
          throw StateError(tr('当前播放引擎不支持音效导入。'));
        }
        await engine.importParameters(imported.effects!);
      }
      if (mounted) {
        setState(() {
          preview = null;
          message =
              tr('音乐库合并完成，导入 {accounts} 份空缺账号凭据、{count} 项播放设置。{queue}{effects}原备份文件未修改；未访问云端。', {
                'accounts': accounts,
                'count': imported.playback.count,
                'queue': imported.queue == null
                    ? ''
                    : tr('旧版队列和进度已保存，点击播放后继续。'),
                'effects': imported.effects == null
                    ? ''
                    : tr('音效参数已保存，专业模式开关保持不变。'),
              });
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message = librarySaved
              ? tr('音乐库已保存，但部分凭据、播放设置、队列或音效应用失败。已保存的内容不会回滚；检查密钥环、空间和播放设备后可安全重试。')
              : tr('本机音乐库保存失败，未继续导入账号，请检查存储权限和空间。'),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget option({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool available = true,
  }) => CheckboxListTile(
    shape: const RoundedRectangleBorder(),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: NekoSpace.lg,
      vertical: 2,
    ),
    secondary: Icon(icon),
    value: value,
    onChanged: busy || !available
        ? null
        : (value) => setState(() {
            onChanged(value ?? false);
            preview = null;
          }),
    title: Text(title),
    subtitle: Text(subtitle),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final pending = preview;
    return DetailPage(
      title: tr('从旧版导入'),
      children: [
        SettingsSection(
          description:
              tr('只读取你主动选择的文件，不扫描旧版目录，也不会修改或上传原文件。')
              + tr('支持 Compose 桌面端 .properties、Android SharedPreferences .xml、player_prefs.preferences_pb（.pb）和音乐库 JSON；')
              + tr('导入 Android 酷狗账号槽位时可同时选择 kugou_sessions.xml。'),
          title: tr('音乐库之外，还要导入'),
          children: [
            option(
              icon: Icons.key_rounded,
              title: tr('账号凭据'),
              subtitle: tr('只填补本机空缺的账号，写入系统密钥环，不覆盖已有登录。备份中的凭据可能已失效。'),
              value: includeCredentials,
              onChanged: (value) => includeCredentials = value,
            ),
            option(
              icon: Icons.tune_rounded,
              title: tr('播放设置'),
              subtitle: tr('播放速度、音质、双行歌词和翻译偏好。不导入手机目录权限、悬浮窗权限或自动播放。'),
              value: includeSettings,
              onChanged: (value) => includeSettings = value,
            ),
            option(
              icon: Icons.queue_music_rounded,
              title: tr('播放队列和进度'),
              subtitle: tr('确认后会停止当前播放并替换队列，不会自动开始播放。'),
              value: includeQueue,
              onChanged: (value) => includeQueue = value,
            ),
            option(
              icon: Icons.equalizer_rounded,
              title: tr('专业音效参数'),
              subtitle: tr('替换全部均衡器、低音、声场、混响、响度与母带参数，专业模式开关保持不变。'),
              value: includeEffects,
              available: widget.player.engine is EffectsPlaybackEngine,
              onChanged: (value) => includeEffects = value,
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: busy ? null : select,
            icon: const Icon(Icons.file_open_outlined, size: 18),
            label:       Text(tr('选择备份并预览')),
          ),
        ),
        if (busy) ...[
          const SizedBox(height: NekoSpace.lg),
          const LinearProgressIndicator(),
        ],
        if (pending != null) ...[
          const SizedBox(height: NekoSpace.xl),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(NekoSpace.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('预览'), style: text.titleMedium),
                  const SizedBox(height: NekoSpace.sm),
                  for (final line in [
                    tr('{tracks} 首歌曲、{favorites} 首收藏、{playlists} 个歌单将合并到本机。', {
                      'tracks': pending.decoded.tracks.length,
                      'favorites': pending.decoded.favorites.length,
                      'playlists': pending.decoded.playlists.length,
                    }),
                    if (pending.skippedSongs > 0)
                      tr('{count} 条无法识别的音源记录会被跳过。', {
                        'count': pending.skippedSongs,
                      }),
                    if (pending.hasCredentials) tr('包含账号凭据，只保存在本机，界面不会显示凭据内容。'),
                    if (pending.playback.count > 0)
                      tr('将覆盖 {count} 项播放设置，其他设置不变。', {
                        'count': pending.playback.count,
                      }),
                    if (pending.effects != null) tr('将替换全部专业音效参数。'),
                    if (pending.queue case final queue?) ...[
                      tr('将恢复 {count} 项队列，从第 {index} 项的 {seconds} 秒继续；当前队列会被替换。', {
                        'count': queue.tracks.length,
                        'index': queue.session.index + 1,
                        'seconds': queue.session.position.inSeconds,
                      }),
                      if (queue.skipped > 0)
                        tr('队列中 {count} 项无法识别的音源会被跳过。', {
                          'count': queue.skipped,
                        }),
                      if (queue.selectionChanged)
                        tr('原先选中的歌曲无法识别，将改为选中下一首可用歌曲，进度归零。'),
                    ],
                  ])
                    Padding(
                      padding: const EdgeInsets.only(top: NekoSpace.xs),
                      child: Text('· $line', style: text.bodyMedium),
                    ),
                  const SizedBox(height: NekoSpace.lg),
                  FilledButton.icon(
                    onPressed: busy ? null : apply,
                    icon: const Icon(Icons.merge_rounded, size: 18),
                    label:       Text(tr('确认合并到本机')),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (message case final value?) ...[
          const SizedBox(height: NekoSpace.xl),
          InlineNotice(value),
        ],
      ],
    );
  }
}
