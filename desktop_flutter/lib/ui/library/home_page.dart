import '../../i18n/tr.dart';
import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../appearance_controller.dart';
import '../../domain/library.dart';
import '../../player_controller.dart';
import '../neko_theme.dart';
import '../widgets/artwork.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_layout.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.player,
    required this.onOpenPlayer,
    required this.onOpenPlaylist,
    required this.onCreatePlaylist,
    required this.onDiscover,
    this.onImport,
    this.onFavorites,
    this.onRecent,
  });

  final PlayerController player;
  final VoidCallback onOpenPlayer;
  final ValueChanged<String> onOpenPlaylist;
  final VoidCallback onCreatePlaylist;
  final VoidCallback onDiscover;
  final VoidCallback? onImport;
  final VoidCallback? onFavorites;
  final VoidCallback? onRecent;

  static String greeting(DateTime now) => switch (now.hour) {
    < 5 => tr('夜深了'),
    < 11 => tr('早上好'),
    < 13 => tr('中午好'),
    < 18 => tr('下午好'),
    _ => tr('晚上好'),
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([player, player.engine]),
    builder: (context, _) {
      final recent = player.recent.take(12).toList();
      final empty = player.tracks.isEmpty && player.queue.isEmpty;
      return PanelPage(
        children: [
          PageHeader(
            title: greeting(DateTime.now()),
            subtitle: empty ? tr('从导入音乐或搜索一首歌开始。') : tr('接着听，或者找点新的。'),
            bottom: NekoSpace.lg,
          ),
          if (player.current != null)
            _ContinueCard(player: player, onOpenPlayer: onOpenPlayer)
          else
            _WelcomeCard(onImport: onImport, onDiscover: onDiscover),
          const SizedBox(height: NekoSpace.lg),
          _Shortcuts(
            player: player,
            onFavorites: onFavorites,
            onRecent: onRecent,
            onDiscover: onDiscover,
          ),
          SectionHeader(
            tr('最近播放'),
            action: recent.isEmpty || onRecent == null
                ? null
                : TextButton(onPressed: onRecent, child:       Text(tr('全部'))),
          ),
          if (recent.isEmpty)
                  Padding(
              padding: EdgeInsets.symmetric(vertical: NekoSpace.lg),
              child: EmptyState(
                icon: Icons.headphones_rounded,
                title: tr('还没有播放记录'),
                description: tr('播放过的歌曲会出现在这里。'),
              ),
            )
          else
            SizedBox(
              height: 212,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recent.length,
                separatorBuilder: (_, _) => const SizedBox(width: NekoSpace.lg),
                itemBuilder: (context, index) => MediaCard(
                  title: recent[index].title,
                  subtitle: recent[index].artist,
                  artwork: recent[index].online?.artwork,
                  onTap: () => unawaited(player.play(recent, index)),
                ),
              ),
            ),
          SectionHeader(
            tr('我的歌单'),
            action: TextButton.icon(
              onPressed: onCreatePlaylist,
              icon: const Icon(Icons.add_rounded, size: 18),
              label:       Text(tr('新建')),
            ),
          ),
          if (player.playlists.isEmpty)
            Text(
              tr('把喜欢的歌整理成歌单：在歌曲的“⋯”菜单中选择“添加到歌单”。'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: NekoSpace.lg,
              runSpacing: NekoSpace.lg,
              children: [
                for (final playlist in player.playlists)
                  MediaCard(
                    title: playlist.name,
                    subtitle: tr('{count} 首', {
                      'count': playlist.paths.length,
                    }),
                    artwork: _coverOf(player, playlist),
                    icon: Icons.queue_music_rounded,
                    onTap: () => onOpenPlaylist(playlist.id),
                  ),
              ],
            ),
        ],
      );
    },
  );

  static String? _coverOf(PlayerController player, LocalPlaylist playlist) =>
      player
          .playlistTracks(playlist)
          .map((track) => track.online?.artwork ?? '')
          .where((url) => url.isNotEmpty)
          .firstOrNull;
}

class MediaCard extends StatefulWidget {
  const MediaCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.artwork,
    this.icon = Icons.music_note_rounded,
    this.onTap,
    this.size = 160,
  });

  final String title;
  final String subtitle;
  final String? artwork;
  final IconData icon;
  final VoidCallback? onTap;
  final double size;

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.size,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Artwork(
                    size: widget.size,
                    url: widget.artwork,
                    label: widget.title,
                    icon: widget.icon,
                    radius: NekoRadius.card,
                  ),
                  Positioned(
                    right: NekoSpace.sm,
                    bottom: NekoSpace.sm,
                    child: AnimatedOpacity(
                      opacity: hovered ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.onSurface,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(blurRadius: 12, color: Colors.black38),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(NekoSpace.sm),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: colors.surface,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NekoSpace.sm),
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                widget.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.player, required this.onOpenPlayer});
  final PlayerController player;
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final track = player.current!;
    final text = Theme.of(context).textTheme;
    final uri = Artwork.safeUri(track.online?.artwork);
    final compact = MediaQuery.sizeOf(context).width < 720;
    final appearance = AppearanceScope.maybeOf(context);
    final blur = appearance?.effectiveBlur(
          40,
          MediaQuery.devicePixelRatioOf(context),
        ) ??
        40.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(NekoRadius.artwork),
      child: Stack(
        children: [
          Positioned.fill(
            child: uri == null
                ? Artwork(size: 1000, track: track, radius: 0, icon: null)
                : ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                    child: Image.network(
                      uri.toString(),
                      fit: BoxFit.cover,
                      cacheWidth: 200,
                      errorBuilder: (_, _, _) => Artwork(
                        size: 1000,
                        track: track,
                        radius: 0,
                        icon: null,
                      ),
                    ),
                  ),
          ),
          const Positioned.fill(child: ColoredBox(color: Color(0x8C000000))),
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onOpenPlayer,
              child: Padding(
                padding: const EdgeInsets.all(NekoSpace.xl),
                child: Row(
                  children: [
                    Artwork(size: compact ? 88 : 128, track: track),
                    const SizedBox(width: NekoSpace.xl),
                    Expanded(
                      child: DefaultTextStyle.merge(
                        style: const TextStyle(color: Colors.white),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              player.engine.playing ? tr('正在播放') : tr('继续播放'),
                              style: text.labelLarge?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: NekoSpace.xs),
                            Text(
                              track.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  (compact
                                          ? text.titleLarge
                                          : text.headlineMedium)
                                      ?.copyWith(color: Colors.white),
                            ),
                            const SizedBox(height: NekoSpace.xs),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyLarge?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: NekoSpace.lg),
                            Wrap(
                              spacing: NekoSpace.sm,
                              runSpacing: NekoSpace.sm,
                              children: [
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                  ),
                                  onPressed: player.toggle,
                                  icon: Icon(
                                    player.engine.playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                                  label: Text(
                                    player.engine.playing ? tr('暂停') : tr('播放'),
                                  ),
                                ),
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(
                                      color: Colors.white38,
                                    ),
                                  ),
                                  onPressed: onOpenPlayer,
                                  child:       Text(tr('歌词与播放器')),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({this.onImport, required this.onDiscover});
  final VoidCallback? onImport;
  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(NekoSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('欢迎使用 NekoPlayer'), style: text.titleLarge),
            const SizedBox(height: NekoSpace.xs),
            Text(
              tr('导入本地音乐，或者搜索在线曲库。登录本站账号后，收藏和歌单可以在手机与电脑间同步。'),
              style: text.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: NekoSpace.lg),
            Wrap(
              spacing: NekoSpace.sm,
              runSpacing: NekoSpace.sm,
              children: [
                if (onImport != null)
                  FilledButton.icon(
                    onPressed: onImport,
                    icon: const Icon(Icons.add_rounded),
                    label:       Text(tr('导入音乐')),
                  ),
                OutlinedButton.icon(
                  onPressed: onDiscover,
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label:       Text(tr('搜索歌曲')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts({
    required this.player,
    this.onFavorites,
    this.onRecent,
    required this.onDiscover,
  });
  final PlayerController player;
  final VoidCallback? onFavorites;
  final VoidCallback? onRecent;
  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final text = Theme.of(context).textTheme;
    Widget tile(
      IconData icon,
      String label,
      String value,
      VoidCallback? onTap,
    ) {
      final title = Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      );
      final body = Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(NekoRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(NekoRadius.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(NekoSpace.md),
            child: compact
                ? Column(
                    children: [
                      Icon(icon, size: 22),
                      const SizedBox(height: NekoSpace.xs),
                      title,
                    ],
                  )
                : Row(
                    children: [
                      Icon(icon, size: 22),
                      const SizedBox(width: NekoSpace.md),
                      Expanded(child: title),
                      Text(value, style: text.bodySmall),
                    ],
                  ),
          ),
        ),
      );
      return compact
          ? Expanded(child: body)
          : SizedBox(width: 220, child: body);
    }

    final tiles = [
      tile(
        Icons.favorite_rounded,
        tr('我喜欢'),
        '${player.favorites.length}',
        onFavorites,
      ),
      tile(Icons.history_rounded, tr('最近播放'), '${player.history.length}', onRecent),
      tile(Icons.explore_rounded, tr('发现音乐'), '', onDiscover),
    ];
    if (compact) {
      return Row(
        children: [
          for (final (index, item) in tiles.indexed) ...[
            if (index > 0) const SizedBox(width: NekoSpace.sm),
            item,
          ],
        ],
      );
    }
    return Wrap(
      spacing: NekoSpace.md,
      runSpacing: NekoSpace.md,
      children: tiles,
    );
  }
}
