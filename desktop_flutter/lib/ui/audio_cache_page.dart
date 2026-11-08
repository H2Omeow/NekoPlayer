import 'package:flutter/material.dart';
import 'package:path/path.dart' as paths;

import '../data/audio_cache.dart';
import '../domain/library.dart';
import '../player_controller.dart';
import 'neko_theme.dart';
import 'widgets/artwork.dart';
import 'widgets/page_layout.dart';
import 'widgets/settings_list.dart';

class AudioCachePage extends StatefulWidget {
  const AudioCachePage({super.key, required this.cache, required this.player});
  final AudioCache cache;
  final PlayerController player;
  @override
  State<AudioCachePage> createState() => _AudioCachePageState();
}

class _AudioCachePageState extends State<AudioCachePage> {
  bool busy = false;
  String? error;
  final selected = <String>{};

  AudioCache get cache => widget.cache;

  Future<void> action(Future<void> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } catch (_) {
      if (mounted) setState(() => error = '缓存操作未完成，请检查文件权限和占用。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> clear({bool selection = false}) async {
    final files = Set<String>.of(selected);
    if (selection && files.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(selection ? '删除选中的 ${files.length} 首缓存？' : '清空歌曲缓存？'),
        content: const Text('只删除本应用缓存的音频，不会删除你的本地音乐或下载。正在播放的缓存文件可能被系统占用。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(selection ? '删除' : '清空'),
          ),
        ],
      ),
    );
    if (mounted && confirm == true) {
      await action(() => selection ? cache.remove(files) : cache.clear());
      if (mounted) setState(selected.clear);
    }
  }

  void toggleAll() => setState(() {
    if (selected.length == cache.entries.length) {
      selected.clear();
    } else {
      selected.addAll(cache.entries.map((entry) => entry.file));
    }
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: cache,
    builder: (context, _) {
      final text = Theme.of(context).textTheme;
      final usable = !busy && cache.readable;
      final summary =
          '${cache.entries.length} 首 · ${(cache.totalBytes / 1048576).toStringAsFixed(1)} MB / 512 MB'
          '${cache.busy ? ' · 正在缓存一首歌曲' : ''}';
      return DetailPage(
        title: '离线缓存',
        children: [
          SettingsSection(
            description:
                '缓存会保留实际音质，并优先用于离线播放。'
                '不保存临时播放链接，也不会上传；单首上限 256 MB。',
            children: [
              SettingsSwitchTile(
                icon: Icons.offline_pin_outlined,
                title: '缓存听过的在线歌曲',
                subtitle: '默认关闭；开启后会额外消耗网络流量',
                value: cache.enabled,
                onChanged: usable
                    ? (value) => action(() => cache.setEnabled(value))
                    : null,
              ),
              SettingsTile(
                icon: Icons.storage_rounded,
                title: '已用空间',
                value: summary,
              ),
            ],
          ),
          if (error ?? cache.error case final String message) ...[
            InlineNotice(message, error: true),
            const SizedBox(height: NekoSpace.lg),
          ],
          if (busy || cache.busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: NekoSpace.lg),
          ],
          if (cache.entries.isNotEmpty) ...[
            Row(
              children: [
                Expanded(child: Text('缓存的歌曲', style: text.titleMedium)),
                TextButton(
                  onPressed: busy ? null : toggleAll,
                  child: Text(
                    selected.length == cache.entries.length ? '取消全选' : '全选',
                  ),
                ),
                if (selected.isNotEmpty)
                  TextButton(
                    onPressed: usable ? () => clear(selection: true) : null,
                    child: Text('删除所选（${selected.length}）'),
                  )
                else
                  TextButton(
                    onPressed: usable ? clear : null,
                    child: const Text('全部清空'),
                  ),
              ],
            ),
            const SizedBox(height: NekoSpace.sm),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final item in cache.entries)
                    ListTile(
                      shape: const RoundedRectangleBorder(),
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: selected.contains(item.file),
                            onChanged: busy
                                ? null
                                : (value) => setState(
                                    () => value == true
                                        ? selected.add(item.file)
                                        : selected.remove(item.file),
                                  ),
                          ),
                          const SizedBox(width: NekoSpace.xs),
                          Artwork(
                            size: 40,
                            url: item.song.artwork,
                            label: item.song.title,
                          ),
                        ],
                      ),
                      title: Text(
                        item.song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${item.song.artist} · ${item.quality} · ${(item.size / 1048576).toStringAsFixed(1)} MB',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.play_arrow_rounded),
                      onTap: () => widget.player.play([
                        Track(
                          path: paths.join(cache.directory.path, item.file),
                          title: item.song.title,
                          artist: item.song.artist,
                        ),
                      ], 0),
                    ),
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}
