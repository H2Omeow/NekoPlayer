import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart' hide RepeatMode;

import '../../domain/library.dart';
import '../../playback/playback_engine.dart';
import '../../player_controller.dart';
import '../neko_theme.dart';
import '../widgets/artwork.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_layout.dart';
import 'library_actions.dart';

enum CollectionKind { local, favorites, recent, playlist }

/// A list of tracks with a large header: the local library, liked songs,
/// recently played and user playlists all share this page.
class TrackCollectionPage extends StatefulWidget {
  const TrackCollectionPage({
    super.key,
    required this.kind,
    required this.actions,
    this.playlistId,
    this.onImport,
    this.importing = false,
    this.onPlaylistDeleted,
  });

  final CollectionKind kind;
  final LibraryActions actions;
  final String? playlistId;
  final VoidCallback? onImport;
  final bool importing;
  final VoidCallback? onPlaylistDeleted;

  @override
  State<TrackCollectionPage> createState() => _TrackCollectionPageState();
}

class _TrackCollectionPageState extends State<TrackCollectionPage> {
  String query = '';

  PlayerController get player => widget.actions.player;

  LocalPlaylist? get playlist => player.playlists
      .where((item) => item.id == widget.playlistId)
      .firstOrNull;

  List<Track> get tracks => switch (widget.kind) {
    CollectionKind.local => player.tracks,
    CollectionKind.favorites =>
      player.tracks
          .where((track) => player.favorites.contains(track.path))
          .toList(),
    CollectionKind.recent => player.recent,
    CollectionKind.playlist =>
      playlist == null ? const [] : player.playlistTracks(playlist!),
  };

  String get title => switch (widget.kind) {
    CollectionKind.local => '全部歌曲',
    CollectionKind.favorites => '我喜欢',
    CollectionKind.recent => '最近播放',
    CollectionKind.playlist => playlist?.name ?? '歌单',
  };

  IconData get icon => switch (widget.kind) {
    CollectionKind.local => Icons.library_music_rounded,
    CollectionKind.favorites => Icons.favorite_rounded,
    CollectionKind.recent => Icons.history_rounded,
    CollectionKind.playlist => Icons.queue_music_rounded,
  };

  Future<void> playAll(List<Track> list, {bool shuffle = false}) async {
    if (list.isEmpty) return;
    if (shuffle) {
      player.setRepeatMode(RepeatMode.shuffle);
      await player.play(list, Random().nextInt(list.length));
    } else {
      if (player.repeat == RepeatMode.shuffle) {
        player.setRepeatMode(RepeatMode.loop);
      }
      await player.play(list, 0);
    }
  }

  Future<void> deletePlaylist() async {
    final target = playlist;
    if (target == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除歌单？'),
        content: Text('“${target.name}”将被删除，歌曲文件和收藏不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      player.deletePlaylist(target.id);
      widget.onPlaylistDeleted?.call();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([player, player.engine]),
    builder: (context, _) {
      if (widget.kind == CollectionKind.playlist && playlist == null) {
        return const EmptyState(
          icon: Icons.queue_music_rounded,
          title: '歌单不存在',
          description: '它可能已被删除或在其他设备上同步移除。',
        );
      }
      final all = tracks;
      final needle = query.trim().toLowerCase();
      final indices = [
        for (var index = 0; index < all.length; index++)
          if (needle.isEmpty ||
              '${all[index].title} ${all[index].artist}'.toLowerCase().contains(
                needle,
              ))
            index,
      ];
      final gutter = pageGutter(context);
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(gutter, NekoSpace.xl, gutter, 0),
            sliver: SliverToBoxAdapter(child: _header(context, all)),
          ),
          if (all.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: _empty())
          else if (indices.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: '没有匹配的歌曲',
                description: '换个关键词试试。',
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                gutter - NekoSpace.sm,
                NekoSpace.sm,
                gutter - NekoSpace.sm,
                NekoSpace.xxl,
              ),
              sliver: SliverList.builder(
                itemCount: indices.length,
                itemBuilder: (context, position) {
                  final index = indices[position];
                  return widget.actions.row(
                    context,
                    all[index],
                    index: index,
                    playlistId: widget.playlistId,
                    onTap: () => unawaited(player.play(all, index)),
                  );
                },
              ),
            ),
        ],
      );
    },
  );

  Widget _header(BuildContext context, List<Track> all) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 720;
    final cover = all.where(
      (track) => track.online?.artwork.isNotEmpty ?? false,
    );
    final art = Artwork(
      size: compact ? 112 : 168,
      url: cover.firstOrNull?.online?.artwork,
      label: title,
      icon: icon,
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.kind == CollectionKind.playlist ? '歌单' : '资料库',
          style: text.labelLarge?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: NekoSpace.xs),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: compact ? text.headlineSmall : text.displaySmall,
        ),
        const SizedBox(height: NekoSpace.sm),
        Text(
          all.isEmpty ? '暂无歌曲' : '${all.length} 首歌曲',
          style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: NekoSpace.lg),
        Wrap(
          spacing: NekoSpace.sm,
          runSpacing: NekoSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: all.isEmpty ? null : () => unawaited(playAll(all)),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('播放'),
            ),
            OutlinedButton.icon(
              onPressed: all.isEmpty
                  ? null
                  : () => unawaited(playAll(all, shuffle: true)),
              icon: const Icon(Icons.shuffle_rounded, size: 18),
              label: const Text('随机播放'),
            ),
            if (widget.kind == CollectionKind.local && widget.onImport != null)
              OutlinedButton.icon(
                onPressed: widget.importing || player.busy
                    ? null
                    : widget.onImport,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(widget.importing || player.busy ? '正在导入…' : '导入音乐'),
              ),
            if (widget.kind == CollectionKind.playlist)
              IconButton(
                tooltip: '删除歌单',
                onPressed: deletePlaylist,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
          ],
        ),
      ],
    );
    final filter = SizedBox(
      width: compact ? double.infinity : 240,
      child: TextField(
        onChanged: (value) => setState(() => query = value),
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search_rounded, size: 20),
          hintText: '在列表中查找',
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            art,
            SizedBox(width: compact ? NekoSpace.lg : NekoSpace.xl),
            Expanded(child: info),
            if (!compact && all.isNotEmpty) filter,
          ],
        ),
        if (compact && all.isNotEmpty) ...[
          const SizedBox(height: NekoSpace.lg),
          filter,
        ],
        const SizedBox(height: NekoSpace.lg),
      ],
    );
  }

  Widget _empty() => switch (widget.kind) {
    CollectionKind.local => EmptyState(
      icon: Icons.library_music_outlined,
      title: '音乐库还是空的',
      description: '导入电脑上的音乐文件，或在“发现”中搜索在线歌曲。文件会保留在原位置。',
      action: widget.onImport == null
          ? null
          : FilledButton.icon(
              onPressed: widget.onImport,
              icon: const Icon(Icons.add_rounded),
              label: const Text('导入音乐'),
            ),
    ),
    CollectionKind.favorites => const EmptyState(
      icon: Icons.favorite_border_rounded,
      title: '还没有喜欢的歌',
      description: '点歌曲旁的爱心，就会收进这里。',
    ),
    CollectionKind.recent => const EmptyState(
      icon: Icons.history_rounded,
      title: '最近没有播放记录',
      description: '播放过的歌曲会按时间出现在这里。',
    ),
    CollectionKind.playlist => const EmptyState(
      icon: Icons.playlist_add_rounded,
      title: '歌单还是空的',
      description: '在任意歌曲的“⋯”菜单中选择“添加到歌单”。',
    ),
  };
}
