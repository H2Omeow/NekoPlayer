import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../data/native_music_catalog.dart';
import '../diagnostics/crash_log.dart';
import '../diagnostics/mpv_logging.dart';
import '../domain/online_music.dart';
import '../video_search_controller.dart';
import 'neko_theme.dart';
import 'widgets/artwork.dart';
import 'widgets/empty_state.dart';
import 'widgets/page_layout.dart';
import 'widgets/settings_list.dart';

class MusicVideosPage extends StatefulWidget {
  const MusicVideosPage({
    super.key,
    required this.catalog,
    required this.pauseMusic,
    this.provider = MusicProvider.netease,
    this.volume = 75,
  });
  final NativeMusicCatalog catalog;
  final Future<void> Function() pauseMusic;
  final MusicProvider provider;
  final double volume;
  @override
  State<MusicVideosPage> createState() => _MusicVideosPageState();
}

class _MusicVideosPageState extends State<MusicVideosPage> {
  late final VideoSearchController search = VideoSearchController(
    widget.catalog.searchVideos,
    provider: widget.provider,
  );
  final input = TextEditingController();
  bool resolving = false;
  String? error;

  Future<void> play(MusicVideo video) async {
    if (resolving) return;
    setState(() {
      resolving = true;
      error = null;
    });
    try {
      final uri = await widget.catalog.videoUrl(video);
      if (!mounted) return;
      await widget.pauseMusic();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _VideoPlaybackPage(
            uri: uri,
            title: video.title,
            volume: widget.volume,
          ),
        ),
      );
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is MusicSearchException
              ? failure.message
              : 'MV 暂时无法播放，请检查网络与播放设备。',
        );
      }
    } finally {
      if (mounted) setState(() => resolving = false);
    }
  }

  @override
  void dispose() {
    search.dispose();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gutter = pageGutter(context);
    return Scaffold(
      appBar: AppBar(title: const Text('音乐 MV')),
      body: ListenableBuilder(
        listenable: search,
        builder: (context, _) => CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, NekoSpace.sm, gutter, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: input,
                      maxLength: 200,
                      textInputAction: TextInputAction.search,
                      onSubmitted: search.search,
                      decoration: InputDecoration(
                        hintText: '搜索 MV、歌手',
                        counterText: '',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: IconButton(
                          tooltip: '搜索 MV',
                          onPressed: () => search.search(input.text),
                          icon: const Icon(Icons.arrow_forward_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: NekoSpace.md),
                    Wrap(
                      spacing: NekoSpace.sm,
                      runSpacing: NekoSpace.sm,
                      children: [
                        for (final provider in MusicProvider.values)
                          ChoiceChip(
                            label: Text(provider.label),
                            selected: search.provider == provider,
                            onSelected: resolving
                                ? null
                                : (_) => search.selectProvider(provider),
                          ),
                      ],
                    ),
                    const SizedBox(height: NekoSpace.lg),
                    if (search.loading || resolving)
                      const LinearProgressIndicator(),
                    if (error ?? search.error case final message?)
                      InlineNotice(message, error: true),
                    const SizedBox(height: NekoSpace.md),
                  ],
                ),
              ),
            ),
            if (search.videos.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.smart_display_outlined,
                  title: '搜索音乐 MV',
                  description: '由内置 Animemusic 插件提供，无需登录本站。播放视频时会暂停音乐。',
                ),
              )
            else ...[
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 320,
                    mainAxisSpacing: NekoSpace.lg,
                    crossAxisSpacing: NekoSpace.lg,
                    childAspectRatio: 16 / 14,
                  ),
                  itemCount: search.videos.length,
                  itemBuilder: (context, index) => _VideoCard(
                    video: search.videos[index],
                    onTap: resolving ? null : () => play(search.videos[index]),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(NekoSpace.lg),
                  child: search.hasMore
                      ? Center(
                          child: TextButton(
                            onPressed: search.loading ? null : search.loadMore,
                            child: const Text('加载更多'),
                          ),
                        )
                      : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.video, this.onTap});
  final MusicVideo video;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final uri = Artwork.safeUri(video.artwork);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NekoRadius.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(NekoRadius.card),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (uri == null)
                    ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    )
                  else
                    Image.network(
                      uri.toString(),
                      fit: BoxFit.cover,
                      cacheWidth: 480,
                      errorBuilder: (context, _, _) => ColoredBox(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHigh,
                      ),
                    ),
                  const Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0x73000000),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(NekoSpace.sm),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: NekoSpace.sm),
          Text(
            video.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            video.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _VideoPlaybackPage extends StatefulWidget {
  const _VideoPlaybackPage({
    required this.uri,
    required this.title,
    required this.volume,
  });
  final Uri uri;
  final String title;
  final double volume;
  @override
  State<_VideoPlaybackPage> createState() => _VideoPlaybackPageState();
}

class _VideoPlaybackPageState extends State<_VideoPlaybackPage> {
  late final Player player;
  late final VideoController video;
  StreamSubscription<String>? errors;
  StreamSubscription<PlayerLog>? logs;
  late final Future<void> ready;
  String? error;

  @override
  void initState() {
    super.initState();
    player = Player(
      configuration: const PlayerConfiguration(
        title: 'NekoPlayer MV',
        bufferSize: 16 * 1024 * 1024,
        logLevel: mpvLogConfigurationLevel,
      ),
    );
    video = VideoController(player);
    logs = attachMpvLog(player, 'mpv-video');
    errors = player.stream.error.listen((message) {
      CrashLog.error('mpv-video', 'playback error: $message');
      if (mounted) setState(() => error = '视频解码失败，请检查视频地址与播放依赖。');
    });
    ready =
        (() async {
          await player.setVolume(widget.volume.clamp(0, 100));
          await player.open(Media(widget.uri.toString()));
        })().catchError((Object failure, StackTrace stack) {
          CrashLog.error(
            'mpv-video',
            'Video open failed',
            error: failure,
            stack: stack,
          );
          if (mounted) setState(() => error = '视频无法播放，请稍后重试。');
        });
  }

  @override
  void dispose() {
    unawaited(errors?.cancel());
    unawaited(logs?.cancel());
    // The Video widget is already unmounted here; wait for any pending open
    // before tearing down libmpv and the render context.
    unawaited(
      ready.then((_) => player.dispose()).catchError((
        Object failure,
        StackTrace stack,
      ) {
        CrashLog.error(
          'mpv-video',
          'Video player dispose failed',
          error: failure,
          stack: stack,
        );
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(title: Text(widget.title)),
    body: Stack(
      children: [
        Video(controller: video),
        if (error case final message?)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(NekoSpace.xl),
              child: InlineNotice(message, error: true),
            ),
          ),
      ],
    ),
  );
}
