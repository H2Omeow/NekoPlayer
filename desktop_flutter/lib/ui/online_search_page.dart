import '../i18n/tr.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/music_plugin.dart';
import '../domain/online_music.dart';
import '../data/plugin_subscriptions.dart';
import '../search_controller.dart' as online;
import 'neko_theme.dart';
import 'widgets/empty_state.dart';
import 'widgets/page_layout.dart';
import 'widgets/song_row.dart';

class OnlineSearchPage extends StatefulWidget {
  const OnlineSearchPage({
    super.key,
    required this.controller,
    this.onPlay,
    this.onEnqueue,
    this.onFavorite,
    this.isFavorite,
    this.onPlaylist,
    this.onDownload,
    this.onComments,
    this.onBrowse,
    this.onAccountLibrary,
    this.onVideos,
    this.subscriptions,
    this.onSubscriptions,
    this.actionsFor,
    this.isPlaying,
  });

  final online.SearchController controller;
  final void Function(List<OnlineSong> songs, int index)? onPlay;
  final void Function(OnlineSong song)? onEnqueue;
  final void Function(OnlineSong song)? onFavorite;
  final bool Function(OnlineSong song)? isFavorite;
  final void Function(OnlineSong song)? onPlaylist;
  final void Function(OnlineSong song)? onDownload;
  final void Function(OnlineSong song)? onComments;
  final VoidCallback? onBrowse;
  final VoidCallback? onAccountLibrary;
  final VoidCallback? onVideos;
  final PluginSubscriptions? subscriptions;
  final VoidCallback? onSubscriptions;

  /// Supplies the shared song menu; when absent the page builds its own
  /// from the individual callbacks above.
  final List<SongAction> Function(BuildContext context, OnlineSong song)?
  actionsFor;
  final bool Function(OnlineSong song)? isPlaying;

  @override
  State<OnlineSearchPage> createState() => _OnlineSearchPageState();
}

class _OnlineSearchPageState extends State<OnlineSearchPage> {
  late final TextEditingController input;
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    input = TextEditingController(text: widget.controller.keyword);
  }

  @override
  void dispose() {
    input.dispose();
    focus.dispose();
    super.dispose();
  }

  // Favourites live outside this widget, so rebuild to refresh the heart.
  void toggleFavorite(OnlineSong song) =>
      setState(() => widget.onFavorite!(song));

  List<SongAction> actions(BuildContext context, OnlineSong song) {
    if (widget.actionsFor != null) return widget.actionsFor!(context, song);
    return [
      if (widget.onEnqueue != null)
        SongAction(
          tr('加入播放队列'),
          Icons.playlist_play_rounded,
          () => widget.onEnqueue!(song),
        ),
      if (widget.onFavorite != null)
        SongAction(
          widget.isFavorite?.call(song) == true
              ? tr('取消收藏')
              : tr('收藏'),
          Icons.favorite_border_rounded,
          () => toggleFavorite(song),
        ),
      if (widget.onPlaylist != null)
        SongAction(
          tr('添加到歌单…'),
          Icons.playlist_add_rounded,
          () => widget.onPlaylist!(song),
        ),
      if (widget.onDownload != null)
        SongAction(
          tr('下载'),
          Icons.download_rounded,
          () => widget.onDownload!(song),
        ),
      if (widget.onComments != null)
        SongAction(
          tr('查看评论'),
          Icons.chat_bubble_outline_rounded,
          () => widget.onComments!(song),
        ),
    ];
  }

  String sourceLabel(MusicPluginSource source) {
    final name = source.name.replaceAll('-xm', '');
    return name;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.controller, widget.subscriptions]),
    builder: (context, child) {
      final controller = widget.controller;
      final gutter = pageGutter(context);
      final shortcuts = [
        if (widget.onBrowse != null)
          (Icons.album_outlined, tr('歌手、专辑与歌单'), widget.onBrowse!),
        if (widget.onAccountLibrary != null)
          (Icons.cloud_outlined, tr('我的平台曲库'), widget.onAccountLibrary!),
        if (widget.onVideos != null)
          (Icons.smart_display_outlined, tr('音乐 MV'), widget.onVideos!),
        if (widget.onSubscriptions != null)
          (Icons.extension_outlined, tr('音源管理'), widget.onSubscriptions!),
      ];
      return NotificationListener<ScrollEndNotification>(
        onNotification: (notification) {
          final metrics = notification.metrics;
          if (metrics.pixels >= metrics.maxScrollExtent - 200 &&
              controller.hasMore &&
              !controller.loading &&
              controller.songs.isNotEmpty) {
            unawaited(controller.loadMore());
          }
          return false;
        },
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                          PageHeader(title: tr('发现'), bottom: NekoSpace.lg),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: TextField(
                        controller: input,
                        focusNode: focus,
                        maxLength: 200,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (value) =>
                            unawaited(controller.search(value)),
                        style: Theme.of(context).textTheme.bodyLarge,
                        decoration: InputDecoration(
                          hintText: tr('搜索歌曲、歌手或专辑'),
                          counterText: '',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: NekoSpace.lg,
                            vertical: 16,
                          ),
                          border: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(28)),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(28)),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: const BorderRadius.all(
                              Radius.circular(28),
                            ),
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.outline,
                              width: 1.5,
                            ),
                          ),
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(Icons.search_rounded),
                          ),
                          suffixIcon: IconButton(
                            tooltip: tr('搜索'),
                            onPressed: () =>
                                unawaited(controller.search(input.text)),
                            icon: const Icon(Icons.arrow_forward_rounded),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: NekoSpace.md),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final provider in MusicProvider.values)
                            if (widget.subscriptions == null ||
                                provider.gateway == null)
                              Padding(
                                padding: const EdgeInsets.only(
                                  right: NekoSpace.sm,
                                ),
                                child: ChoiceChip(
                                  label: Text(provider.label),
                                  selected:
                                      controller.pluginSource == null &&
                                      controller.provider == provider,
                                  onSelected: (_) =>
                                      controller.selectProvider(provider),
                                ),
                              ),
                          for (final source
                              in widget.subscriptions?.sources ?? [])
                            if (source.capabilities.contains('search'))
                              Padding(
                                padding: const EdgeInsets.only(
                                  right: NekoSpace.sm,
                                ),
                                child: ChoiceChip(
                                  label: Text(sourceLabel(source)),
                                  selected:
                                      controller.pluginSource?.id == source.id,
                                  onSelected: (_) =>
                                      controller.selectPlugin(source),
                                ),
                              ),
                        ],
                      ),
                    ),
                    const SizedBox(height: NekoSpace.md),
                    if (controller.loading && controller.songs.isEmpty)
                      const LinearProgressIndicator(),
                    if (controller.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: NekoSpace.md),
                        child: Text(
                          controller.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (controller.songs.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: controller.keyword.isEmpty && controller.error == null
                    ? _Shortcuts(items: shortcuts, gutter: gutter)
                    : EmptyState(
                        icon: controller.error != null
                            ? Icons.wifi_off_rounded
                            : Icons.search_off_rounded,
                        title: controller.loading
                            ? tr('正在搜索…')
                            : controller.error != null
                            ? tr('搜索没有完成')
                            : tr('没有找到相关歌曲'),
                        description: controller.error != null
                            ? tr('可以重新搜索，或切换到其他音源。')
                            : tr('换个关键词，或切换音源试试。'),
                      ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  gutter - NekoSpace.sm,
                  0,
                  gutter - NekoSpace.sm,
                  NekoSpace.xxl,
                ),
                sliver: SliverList.builder(
                  itemCount: controller.songs.length + 1,
                  itemBuilder: (context, index) {
                    if (index == controller.songs.length) {
                      return Padding(
                        padding: const EdgeInsets.all(NekoSpace.lg),
                        child: Center(
                          child: controller.hasMore
                              ? TextButton(
                                  onPressed: controller.loading
                                      ? null
                                      : controller.loadMore,
                                  child: Text(
                                    controller.loading ? tr('正在加载…') : tr('加载更多'),
                                  ),
                                )
                              : Text(
                                  tr('已显示全部结果'),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                        ),
                      );
                    }
                    final song = controller.songs[index];
                    return SongRow(
                      title: song.title,
                      subtitle: [
                        song.artist,
                        if (controller.pluginSource == null)
                          song.provider.label,
                      ].where((value) => value.isNotEmpty).join(' · '),
                      album: song.album,
                      artwork: song.artwork,
                      index: index,
                      playing: widget.isPlaying?.call(song) ?? false,
                      favorite: widget.isFavorite?.call(song),
                      onFavorite: widget.onFavorite == null
                          ? null
                          : () => toggleFavorite(song),
                      onTap: widget.onPlay == null
                          ? null
                          : () => widget.onPlay!(controller.songs, index),
                      actions: actions(context, song),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.items, required this.gutter});
  final List<(IconData, String, VoidCallback)> items;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, NekoSpace.lg, gutter, NekoSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (items.isNotEmpty) ...[
            Text(tr('浏览'), style: text.titleLarge),
            const SizedBox(height: NekoSpace.md),
            Wrap(
              spacing: NekoSpace.md,
              runSpacing: NekoSpace.md,
              children: [
                for (final (icon, label, onTap) in items)
                  SizedBox(
                    width: 200,
                    height: 96,
                    child: Material(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(NekoRadius.card),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(NekoRadius.card),
                        onTap: onTap,
                        child: Padding(
                          padding: const EdgeInsets.all(NekoSpace.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Icon(icon, color: colors.onSurface),
                              Text(
                                label,
                                style: text.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const Spacer(),
          Center(
            child: Text(
              tr('输入关键词，发现下一首喜欢的歌。'),
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
