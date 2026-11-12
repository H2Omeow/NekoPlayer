import '../../i18n/tr.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../appearance_controller.dart';
import '../../domain/library.dart';
import '../../domain/online_music.dart';
import '../../player_controller.dart';
import '../embedded_lyrics_view.dart';
import '../neko_theme.dart';
import '../playback_options.dart';
import '../player_background.dart';
import '../playlist_picker.dart';
import '../rotating_record.dart';
import '../shell/player_bar.dart';
import '../timed_lyric_text.dart';
import '../widgets/artwork.dart';
import '../widgets/empty_state.dart';

/// Full-window "now playing" view: artwork and transport on one side,
/// synchronised lyrics (plain or the dynamic engine) on the other.
class FullPlayer extends StatefulWidget {
  const FullPlayer({
    super.key,
    required this.controller,
    this.onDownload,
    this.onComments,
    this.onShare,
    this.onDynamicLyrics,
    this.dynamicLyricsUri,
  });
  final PlayerController controller;
  final void Function(OnlineSong)? onDownload;
  final void Function(OnlineSong)? onComments;
  final void Function(Track)? onShare;

  /// Opens the dynamic lyrics page in the system browser.
  final Future<void> Function()? onDynamicLyrics;

  /// Starts the dynamic lyrics server for the embedded view.
  final Future<Uri> Function()? dynamicLyricsUri;

  @override
  State<FullPlayer> createState() => _FullPlayerState();
}

class _FullPlayerState extends State<FullPlayer> {
  PlaybackView view = PlaybackView.split;
  bool dynamicLyrics = false;
  bool compactLyrics = false;
  final embeddedLyricsKey = GlobalKey();

  PlayerController get controller => widget.controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, controller.engine]),
    builder: (context, _) {
      final track = controller.current;
      final appearance = AppearanceScope.maybeOf(context);
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.maybePop(context),
          const SingleActivator(LogicalKeyboardKey.space): () =>
              unawaited(controller.toggle()),
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (appearance != null)
                PlayerBackdrop(appearance: appearance, track: track)
              else
                ColoredBox(color: Theme.of(context).colorScheme.surface),
              Scaffold(
                backgroundColor: Colors.transparent,
                body: SafeArea(
                  child: Column(
                    children: [
                      _topBar(context),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) =>
                              constraints.maxWidth >= 900
                              ? _wide(context, constraints)
                              : _narrow(context, constraints),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _topBar(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: NekoSpace.md,
      vertical: NekoSpace.sm,
    ),
    child: Row(
      children: [
        IconButton(
          tooltip: tr('返回'),
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
        ),
        const Spacer(),
        if (controller.current != null && widget.onShare != null)
          IconButton(
            tooltip: tr('分享歌曲'),
            onPressed: () {
              final current = controller.current;
              if (current != null) widget.onShare!(current);
            },
            icon: const Icon(Icons.ios_share_rounded, size: 20),
          ),
        if (widget.dynamicLyricsUri != null)
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(value: false, label: Text(tr('歌词'))),
              ButtonSegment(value: true, label: Text(tr('动态歌词'))),
            ],
            selected: {dynamicLyrics},
            onSelectionChanged: (value) => setState(() {
              dynamicLyrics = value.single;
              if (dynamicLyrics) compactLyrics = true;
            }),
          ),
        if (widget.onDynamicLyrics != null)
          IconButton(
            tooltip: tr('在浏览器中打开动态歌词'),
            onPressed: widget.onDynamicLyrics,
            icon: const Icon(Icons.open_in_new_rounded, size: 20),
          ),
        PlaybackOptionsButton(
          controller: controller,
          view: view,
          onViewChanged: (value) => setState(() => view = value),
        ),
      ],
    ),
  );

  Widget _lyricsPane() => dynamicLyrics && widget.dynamicLyricsUri != null
      ? Padding(
          padding: const EdgeInsets.all(NekoSpace.lg),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(NekoRadius.artwork),
            child: EmbeddedLyricsView(
              key: embeddedLyricsKey,
              start: widget.dynamicLyricsUri!,
              quality:
                  AppearanceScope.maybeOf(context)?.lyricsQuery ?? const {},
              onOpenInBrowser: widget.onDynamicLyrics == null
                  ? null
                  : () => unawaited(widget.onDynamicLyrics!()),
            ),
          ),
        )
      : LyricsView(controller: controller);

  Widget _artwork(Track? track, double size) => view == PlaybackView.record
      ? RotatingRecord(
          playing: controller.engine.playing,
          child: Artwork(size: size, track: track, radius: size),
        )
      : DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(NekoRadius.artwork),
            boxShadow: const [
              BoxShadow(
                blurRadius: 40,
                offset: Offset(0, 16),
                color: Color(0x59000000),
              ),
            ],
          ),
          child: Artwork(size: size, track: track),
        );

  Widget _info(BuildContext context, Track? track, {bool center = false}) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final palette = NekoPalette.of(context);
    final favorite = track != null && controller.favorites.contains(track.path);
    final online = track?.online;
    final quality = controller.currentQuality;
    final actions = <Widget>[
      if (track != null)
        IconButton(
          tooltip: favorite ? tr('取消收藏') : tr('收藏'),
          onPressed: () => controller.toggleFavorite(track),
          icon: Icon(
            favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: favorite ? palette.accent : null,
          ),
        ),
      if (track != null)
        IconButton(
          tooltip: tr('添加到歌单'),
          onPressed: () =>
              unawaited(showPlaylistPicker(context, controller, track)),
          icon: const Icon(Icons.playlist_add_rounded),
        ),
      if (online != null && widget.onComments != null)
        IconButton(
          tooltip: tr('查看评论'),
          onPressed: () => widget.onComments!(online),
          icon: const Icon(Icons.chat_bubble_outline_rounded),
        ),
      if (online != null && widget.onDownload != null)
        IconButton(
          tooltip: tr('下载歌曲'),
          onPressed: () => widget.onDownload!(online),
          icon: const Icon(Icons.download_rounded),
        ),
    ];
    return Column(
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          track?.title ?? tr('尚未播放'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: text.headlineMedium,
        ),
        const SizedBox(height: NekoSpace.xs),
        Text(
          [
            track?.artist ?? '',
            online?.album ?? '',
            if (quality != null && quality.isNotEmpty) quality,
          ].where((part) => part.isNotEmpty).join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: text.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: NekoSpace.sm),
        Wrap(children: actions),
      ],
    );
  }

  Widget _transport() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SeekBar(controller: controller),
      const SizedBox(height: NekoSpace.xs),
      PlaybackControls(controller: controller, large: true),
    ],
  );

  Widget _wide(BuildContext context, BoxConstraints constraints) {
    final track = controller.current;
    if (view == PlaybackView.lyrics) {
      return Column(
        children: [
          Expanded(child: _lyricsPane()),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                NekoSpace.xl,
                0,
                NekoSpace.xl,
                NekoSpace.xl,
              ),
              child: _transport(),
            ),
          ),
        ],
      );
    }
    final art = (constraints.maxHeight * 0.48)
        .clamp(200.0, constraints.maxWidth * 0.3)
        .clamp(200.0, 440.0);
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: NekoSpace.xxl),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: art + 80),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: _artwork(track, art)),
                    const SizedBox(height: NekoSpace.xl),
                    _info(context, track),
                    const SizedBox(height: NekoSpace.md),
                    _transport(),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(flex: 6, child: _lyricsPane()),
      ],
    );
  }

  Widget _narrow(BuildContext context, BoxConstraints constraints) {
    final track = controller.current;
    final showLyrics = view == PlaybackView.lyrics || compactLyrics;
    final heightLimit = constraints.maxHeight * 0.42;
    final art = (constraints.maxWidth - 64).clamp(
      120.0,
      heightLimit < 120.0 ? 120.0 : heightLimit,
    );
    return Column(
      children: [
        Expanded(
          child: showLyrics
              ? _lyricsPane()
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: NekoSpace.xl),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => compactLyrics = true),
                        child: _artwork(track, art),
                      ),
                      const SizedBox(height: NekoSpace.xl),
                      _info(context, track, center: true),
                    ],
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NekoSpace.lg,
            0,
            NekoSpace.lg,
            NekoSpace.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showLyrics && view != PlaybackView.lyrics)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      compactLyrics = false;
                      dynamicLyrics = false;
                    }),
                    icon: const Icon(Icons.album_rounded, size: 18),
                    label: Text(tr('封面')),
                  ),
                )
              else if (!showLyrics)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => setState(() => compactLyrics = true),
                    icon: const Icon(Icons.lyrics_outlined, size: 18),
                    label: Text(tr('歌词')),
                  ),
                ),
              _transport(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Plain synchronised lyrics: the current line is centred and highlighted,
/// clicking a line seeks to it.
class LyricsView extends StatefulWidget {
  const LyricsView({super.key, required this.controller});
  final PlayerController controller;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final scroll = ScrollController();
  final keys = <GlobalKey>[];
  int activeLine = -1;
  List<LyricLine>? _lines;
  bool userScrolling = false;
  Timer? resume;

  PlayerController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(update);
    controller.engine.addListener(update);
    WidgetsBinding.instance.addPostFrameCallback((_) => update(jump: true));
  }

  void update({bool jump = false}) {
    if (!mounted) return;
    final index = controller.lyricIndex;
    if (!identical(_lines, controller.lyrics)) {
      _lines = controller.lyrics;
      activeLine = -1;
      jump = true;
    }
    if (index == activeLine && !jump) return;
    activeLine = index;
    if (userScrolling) return;
    final target = index < 0 || index >= keys.length
        ? null
        : keys[index].currentContext;
    if (target == null) {
      if (jump && scroll.hasClients) scroll.jumpTo(0);
      return;
    }
    unawaited(
      Scrollable.ensureVisible(
        target,
        alignment: 0.4,
        duration: jump ? Duration.zero : const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    resume?.cancel();
    controller.removeListener(update);
    controller.engine.removeListener(update);
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = controller.lyrics;
    if (lyrics.isEmpty) {
      return EmptyState(
        icon: Icons.lyrics_outlined,
        title: tr('暂无歌词'),
        description: tr('在线歌曲会自动获取歌词；本地歌曲可把同名 .lrc 文件放在音频旁边。'),
      );
    }
    while (keys.length < lyrics.length) {
      keys.add(GlobalKey());
    }
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < 900;
    final style = (narrow ? text.titleLarge : text.headlineSmall)!.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.45,
    );
    final active = controller.lyricIndex;
    return NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        userScrolling = true;
        resume?.cancel();
        resume = Timer(const Duration(seconds: 3), () {
          userScrolling = false;
          update(jump: false);
        });
        return false;
      },
      child: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0, 0.12, 0.85, 1],
        ).createShader(bounds),
        blendMode: BlendMode.dstIn,
        child: SingleChildScrollView(
          controller: scroll,
          padding: EdgeInsets.symmetric(
            horizontal: narrow ? NekoSpace.xl : NekoSpace.xxl,
            vertical: MediaQuery.sizeOf(context).height * 0.3,
          ),
          child: Column(
            crossAxisAlignment: narrow
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < lyrics.length; index++)
                Padding(
                  key: keys[index],
                  padding: const EdgeInsets.symmetric(vertical: NekoSpace.xs),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(NekoRadius.control),
                    onTap: () => unawaited(controller.seek(lyrics[index].time)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: NekoSpace.sm,
                        vertical: NekoSpace.sm,
                      ),
                      child: AnimatedScale(
                        scale: index == active ? 1 : 0.94,
                        alignment: narrow
                            ? Alignment.center
                            : Alignment.centerLeft,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        child: TimedLyricText(
                          line: lyrics[index],
                          position: controller.position,
                          active: index == active,
                          showTranslation: controller.showTranslation,
                          style: style,
                          activeColor: colors.onSurface,
                          idleColor: colors.onSurface.withValues(alpha: 0.32),
                          textAlign: narrow
                              ? TextAlign.center
                              : TextAlign.start,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
