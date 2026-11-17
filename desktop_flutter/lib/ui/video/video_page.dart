import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../i18n/tr.dart';
import '../../video/bili_client.dart';
import '../../video/video_settings.dart';
import '../neko_theme.dart';
import '../widgets/settings_list.dart';
import 'danmaku_overlay.dart';

/// 视频模块首页：搜索 + 推荐/热门/关注 + 双列封面墙。
class VideoPage extends StatefulWidget {
  const VideoPage({
    super.key,
    this.store,
    this.onPauseMusic,
  });

  final VideoSettingsStore? store;
  final VoidCallback? onPauseMusic;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  final client = BiliClient();
  final searchController = TextEditingController();
  final scrollController = ScrollController();

  List<BiliVideo> items = const [];
  String keyword = '';
  String order = 'totalrank';
  String feed = 'recommend';
  bool loading = false;
  String? error;
  int page = 1;
  BiliAccount account = BiliAccount.guest;
  StreamSubscription<BiliAccount>? accountSub;
  VideoSettingsStore? store;

  @override
  void initState() {
    super.initState();
    final injected = widget.store;
    if (injected != null) {
      store = injected;
    } else {
      unawaited(VideoSettingsStore.open().then((value) {
        if (mounted) setState(() => store = value);
      }));
    }
    BiliSession.instance.load().then((_) {
      if (!mounted) return;
      setState(() => account = BiliSession.instance.account);
    });
    accountSub = BiliSession.instance.changes.listen((next) {
      if (mounted) setState(() => account = next);
    });
    scrollController.addListener(_onScroll);
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    accountSub?.cancel();
    searchController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!scrollController.hasClients || loading) return;
    final position = scrollController.position;
    if (position.pixels > position.maxScrollExtent - 480) {
      unawaited(_load(reset: false));
    }
  }

  Future<void> _load({required bool reset}) async {
    if (loading) return;
    if (reset) {
      page = 1;
      setState(() {
        loading = true;
        error = null;
      });
    } else {
      setState(() => loading = true);
    }
    try {
      final List<BiliVideo> next;
      final trimmed = keyword.trim();
      if (trimmed.isNotEmpty) {
        next = await client.search(trimmed, page: page, order: order);
      } else if (feed == 'hot') {
        next = await client.popular(page: page);
      } else {
        next = await client.search('音乐现场', page: page, order: order);
      }
      if (!mounted) return;
      setState(() {
        items = reset
            ? next
            : {
                for (final item in [...items, ...next]) item.bvid: item,
              }.values.toList(growable: false);
        page = page + 1;
        loading = false;
        error = null;
      });
    } catch (failure) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = failure.toString();
      });
    }
  }

  void _submit(String value) {
    keyword = value.trim();
    scrollController.jumpTo(0);
    unawaited(_load(reset: true));
  }

  void _openVideo(BiliVideo video) {
    widget.onPauseMusic?.call();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerPage(
          video: video,
          client: client,
          store: store!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = NekoPalette.of(context);
    if (store == null) {
      return Container(
        color: palette.canvas,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return Container(
      color: palette.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(NekoSpace.xl, NekoSpace.lg, NekoSpace.xl, NekoSpace.sm),
            child: Row(
              children: [
                Text(
                  tr('视频'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: NekoSpace.lg),
                Expanded(
                  child: _SearchField(
                    controller: searchController,
                    onSubmitted: _submit,
                    onClear: () {
                      searchController.clear();
                      keyword = '';
                      unawaited(_load(reset: true));
                    },
                  ),
                ),
                const SizedBox(width: NekoSpace.md),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () async {
                    await showDialog<void>(
                      context: context,
                      builder: (_) => BiliLoginDialog(client: client),
                    );
                    if (mounted) {
                      setState(() => account = BiliSession.instance.account);
                      unawaited(_load(reset: true));
                    }
                  },
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 15,
                        backgroundColor: colors.surfaceContainerHigh,
                        foregroundImage: account.face.isEmpty ? null : NetworkImage(account.face),
                        child: Icon(Icons.person_outline, size: 17, color: colors.onSurfaceVariant),
                      ),
                      if (account.isLogin) ...[
                        const SizedBox(width: 8),
                        Text(account.name, style: Theme.of(context).textTheme.labelMedium),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NekoSpace.xl),
            child: Row(
              children: [
                _Chip(
                  label: tr('推荐'),
                  selected: feed == 'recommend' && keyword.isEmpty,
                  onTap: () {
                    feed = 'recommend';
                    keyword = '';
                    searchController.clear();
                    unawaited(_load(reset: true));
                  },
                ),
                const SizedBox(width: NekoSpace.sm),
                _Chip(
                  label: tr('热门'),
                  selected: feed == 'hot' && keyword.isEmpty,
                  onTap: () {
                    feed = 'hot';
                    keyword = '';
                    searchController.clear();
                    unawaited(_load(reset: true));
                  },
                ),
                const SizedBox(width: NekoSpace.sm),
                _Chip(
                  label: tr('最多播放'),
                  selected: order == 'click' && keyword.isNotEmpty,
                  onTap: () {
                    order = order == 'click' ? 'totalrank' : 'click';
                    if (keyword.isNotEmpty) unawaited(_load(reset: true));
                  },
                ),
                const Spacer(),
                if (account.isLogin)
                  Text(
                    tr('已登录 B 站 · 可播放 1080P'),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(height: NekoSpace.sm),
          Expanded(child: _buildGrid(context)),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      if (loading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (error != null) {
        return Center(
          child: InlineNotice(
            tr('加载失败：') + error!,
            error: true,
            action: TextButton(onPressed: () => _load(reset: true), child: Text(tr('重试'))),
          ),
        );
      }
      return Center(
        child: Text(
          tr('没有找到视频，换个关键词试试'),
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
      );
    }
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(NekoSpace.xl, NekoSpace.sm, NekoSpace.xl, NekoSpace.xxl),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 300,
              mainAxisSpacing: NekoSpace.lg,
              crossAxisSpacing: NekoSpace.lg,
              childAspectRatio: 16 / 13.4,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _VideoCard(item: items[index], onTap: () => _openVideo(items[index])),
              childCount: items.length,
            ),
          ),
        ),
        if (loading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(bottom: NekoSpace.xl),
              child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onSubmitted, required this.onClear});

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 38,
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmitted,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: tr('搜索视频、UP 主，或直接粘贴 BV 号'),
          hintStyle: TextStyle(color: colors.onSurfaceVariant.withValues(alpha: 0.8), fontSize: 13),
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: onClear,
                  tooltip: tr('清除'),
                ),
          filled: true,
          fillColor: colors.surfaceContainerHigh,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(NekoRadius.control),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.primary.withValues(alpha: 0.18) : colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? colors.primary : colors.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.item, required this.onTap});

  final BiliVideo item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(NekoRadius.card),
      onTap: onTap,
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
                  _CoverImage(url: item.cover),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        formatDuration(item.durationSec),
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${item.upName} · ${formatCount(item.views)} ${tr('播放')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (url.isEmpty) {
      return Container(color: colors.surfaceContainerHigh);
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      headers: const {
        'Referer': 'https://www.bilibili.com/',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/124.0.0.0 Safari/537.36',
      },
      errorBuilder: (_, _, _) => Container(
        color: colors.surfaceContainerHigh,
        child: Icon(Icons.movie_outlined, color: colors.onSurfaceVariant.withValues(alpha: 0.6)),
      ),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : Container(color: colors.surfaceContainerHigh),
    );
  }
}

/// 播放页：左播放器 + 右相关推荐，弹幕叠在画面上。
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.video,
    required this.client,
    required this.store,
  });

  final BiliVideo video;
  final BiliClient client;
  final VideoSettingsStore store;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final Player player;
  late final VideoController videoController;
  final focusNode = FocusNode();
  final subscriptions = <StreamSubscription<dynamic>>[];

  BiliDetail? detail;
  List<BiliDanmaku> danmaku = const [];
  List<BiliVideo> related = const [];
  String? error;
  bool loading = true;
  bool fullscreen = false;
  bool showControls = true;
  bool playing = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  DateTime lastHide = DateTime.now();
  Timer? autosave;
  Timer? hideTimer;

  VideoSettings get settings => widget.store.settings;

  @override
  void initState() {
    super.initState();
    player = Player(configuration: const PlayerConfiguration(bufferSize: 32 * 1024 * 1024));
    videoController = VideoController(player);
    subscriptions.add(player.stream.position.listen((value) {
      if (mounted) setState(() => position = value);
    }));
    subscriptions.add(player.stream.duration.listen((value) {
      if (mounted) setState(() => duration = value);
    }));
    subscriptions.add(player.stream.playing.listen((value) {
      if (mounted) setState(() => playing = value);
    }));
    subscriptions.add(player.stream.error.listen((message) {
      if (mounted) setState(() => error = message);
    }));
    autosave = Timer.periodic(const Duration(seconds: 5), (_) {
      final d = detail;
      if (d != null && settings.rememberPosition) {
        widget.store.savePosition(d.video.bvid, position.inMilliseconds);
      }
    });
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    autosave?.cancel();
    hideTimer?.cancel();
    for (final sub in subscriptions) {
      unawaited(sub.cancel());
    }
    focusNode.dispose();
    unawaited(player.dispose());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final loaded = await widget.client.detail(widget.video.bvid);
      if (!mounted) return;
      setState(() {
        detail = loaded;
        loading = false;
      });
      unawaited(widget.client.related(widget.video.bvid).then((list) {
        if (mounted) setState(() => related = list.where((v) => v.bvid != widget.video.bvid).take(12).toList());
      }));
      final source = await widget.client.playUrl(
        widget.video.bvid,
        loaded.cid,
        qn: settings.quality,
      );
      if (!mounted) return;
      await player.open(
        Media(
          source.url,
          httpHeaders: const {
            'Referer': 'https://www.bilibili.com/',
            'Origin': 'https://www.bilibili.com',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Range': 'bytes=0-',
          },
        ),
        play: true,
      );
      await player.setRate(settings.rate);
      final resume = widget.store.positionOf(widget.video.bvid);
      if (resume > 3000) await player.seek(Duration(milliseconds: resume));
      final list = await widget.client.allDanmaku(
        loaded.cid,
        loaded.video.aid,
        loaded.video.durationSec,
      );
      if (mounted) setState(() => danmaku = list);
    } catch (failure) {
      if (mounted) {
        setState(() {
          loading = false;
          error = failure.toString();
        });
      }
    }
  }

  void _toggleFullscreen() {
    setState(() => fullscreen = !fullscreen);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      player.playOrPause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      unawaited(player.seek(position + const Duration(seconds: 10)));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      unawaited(player.seek(position - const Duration(seconds: 10)));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyD) {
      _updateDanmaku(settings.danmaku.copyWith(enabled: !settings.danmaku.enabled));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && fullscreen) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _updateDanmaku(DanmakuSettings next) {
    widget.store.updateSettings(settings.copyWith(danmaku: next));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      flex: 7,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() => showControls = !showControls);
                          lastHide = DateTime.now();
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Video(
                              controller: videoController,
                              fit: BoxFit.contain,
                              controls: (_) => const SizedBox.shrink(),
                            ),
                            DanmakuOverlay(
                              items: danmaku,
                              settings: settings.danmaku,
                              position: position,
                              duration: duration,
                            ),
                            if (loading)
                              const Center(child: CircularProgressIndicator(color: Colors.white70)),
                            if (error != null)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(NekoSpace.xl),
                                  child: Text(
                                    tr('播放失败：') + error!,
                                    style: const TextStyle(color: Colors.white70),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            if (showControls) _buildChrome(context),
                            Positioned(
                              left: NekoSpace.lg,
                              top: NekoSpace.md,
                              child: Row(
                                children: [
                                  if (!fullscreen)
                                    IconButton(
                                      onPressed: () => Navigator.of(context).maybePop(),
                                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                                      tooltip: tr('返回'),
                                    ),
                                  Text(
                                    widget.video.title,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!fullscreen) Expanded(flex: 4, child: _buildInfoPanel(context, colors)),
                  ],
                ),
              ),
              if (!fullscreen)
                Container(
                  width: 320,
                  color: NekoPalette.of(context).canvas,
                  child: _buildRelated(context),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChrome(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(NekoSpace.lg, NekoSpace.xl, NekoSpace.lg, NekoSpace.sm),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Color(0xCC000000)],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
              child: Slider(
                value: duration.inMilliseconds == 0
                    ? 0.0
                    : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble(),
                onChanged: (value) {
                  unawaited(player.seek(Duration(milliseconds: (duration.inMilliseconds * value).round())));
                },
              ),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: player.playOrPause,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow, color: Colors.white),
                  tooltip: playing ? tr('暂停') : tr('播放'),
                ),
                Text(
                  '${formatDuration(position.inSeconds)} / ${formatDuration(duration.inSeconds)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const Spacer(),
                _PillButton(
                  label: settings.danmaku.enabled ? tr('弹幕开') : tr('弹幕关'),
                  active: settings.danmaku.enabled,
                  onTap: () => _updateDanmaku(settings.danmaku.copyWith(enabled: !settings.danmaku.enabled)),
                ),
                const SizedBox(width: 8),
                _PillButton(
                  label: qualityLabel(settings.quality),
                  onTap: () => _pickQuality(context),
                ),
                const SizedBox(width: 8),
                _PillButton(
                  label: '${settings.rate}x',
                  onTap: () {
                    const rates = [0.75, 1.0, 1.25, 1.5, 2.0];
                    final index = rates.indexOf(settings.rate);
                    final next = rates[(index + 1) % rates.length];
                    widget.store.updateSettings(settings.copyWith(rate: next));
                    unawaited(player.setRate(next));
                    setState(() {});
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _openDanmakuSettings(context),
                  icon: const Icon(Icons.tune, color: Colors.white, size: 20),
                  tooltip: tr('弹幕设置'),
                ),
                IconButton(
                  onPressed: _toggleFullscreen,
                  icon: Icon(fullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
                  tooltip: fullscreen ? tr('退出全屏') : tr('全屏'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoPanel(BuildContext context, ColorScheme colors) {
    final d = detail;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(NekoSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            d?.video.title ?? widget.video.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: NekoSpace.sm),
          Text(
            '${formatCount((d?.video.views ?? widget.video.views))} ${tr('播放')} · '
            '${formatCount(d?.video.danmakuCount ?? widget.video.danmakuCount)} ${tr('弹幕')} · ${d?.tname ?? ''}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: NekoSpace.lg),
          if ((d?.desc ?? '').isNotEmpty)
            Text(d!.desc, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildRelated(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(NekoSpace.lg, NekoSpace.lg, NekoSpace.lg, NekoSpace.sm),
          child: Text(tr('相关推荐'), style: Theme.of(context).textTheme.titleSmall),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: NekoSpace.lg),
            itemCount: related.length,
            itemBuilder: (context, index) {
              final item = related[index];
              return InkWell(
                borderRadius: BorderRadius.circular(NekoRadius.control),
                onTap: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => VideoPlayerPage(video: item, client: widget.client, store: widget.store),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(NekoRadius.cover),
                            child: _CoverImage(url: item.cover),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.upName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _pickQuality(BuildContext context) async {
    final choice = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(tr('选择清晰度')),
        children: [
          for (final qn in const [120, 80, 64, 32, 16])
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(qn),
              child: Text('${qualityLabel(qn)}${qn > 80 && !BiliSession.instance.account.isLogin ? tr('（需登录）') : ''}'),
            ),
        ],
      ),
    );
    if (choice == null) return;
    widget.store.updateSettings(settings.copyWith(quality: choice));
    setState(() {});
    final d = detail;
    if (d == null) return;
    try {
      final source = await widget.client.playUrl(widget.video.bvid, d.cid, qn: choice);
      final wasPlaying = playing;
      await player.open(
        Media(
          source.url,
          httpHeaders: const {
            'Referer': 'https://www.bilibili.com/',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/124.0.0.0 Safari/537.36',
          },
        ),
        play: wasPlaying,
      );
      await player.seek(position);
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.toString())));
      }
    }
  }

  Future<void> _openDanmakuSettings(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      constraints: const BoxConstraints(maxWidth: 520),
      isScrollControlled: true,
      builder: (context) => _DanmakuSettingsSheet(
        settings: settings.danmaku,
        onChange: (next) => _updateDanmaku(next),
        onReset: () {
          widget.store.resetDanmaku();
          setState(() {});
        },
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap, this.active = false});

  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? Colors.white.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
      ),
    );
  }
}

class _DanmakuSettingsSheet extends StatefulWidget {
  const _DanmakuSettingsSheet({
    required this.settings,
    required this.onChange,
    required this.onReset,
  });

  final DanmakuSettings settings;
  final ValueChanged<DanmakuSettings> onChange;
  final VoidCallback onReset;

  @override
  State<_DanmakuSettingsSheet> createState() => _DanmakuSettingsSheetState();
}

class _DanmakuSettingsSheetState extends State<_DanmakuSettingsSheet> {
  late DanmakuSettings s = widget.settings;

  void _update(DanmakuSettings next) {
    setState(() => s = next);
    widget.onChange(next);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(NekoSpace.xl, NekoSpace.md, NekoSpace.xl, NekoSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(tr('弹幕设置'), style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    widget.onReset();
                    setState(() => s = const DanmakuSettings());
                  },
                  child: Text(tr('恢复默认')),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('显示弹幕')),
              value: s.enabled,
              onChanged: (value) => _update(s.copyWith(enabled: value)),
            ),
            _SliderRow(
              label: tr('不透明度'),
              value: s.opacity,
              min: 0.1,
              max: 1,
              display: '${(s.opacity * 100).round()}%',
              onChanged: (value) => _update(s.copyWith(opacity: value)),
            ),
            _SliderRow(
              label: tr('字号'),
              value: s.fontScale,
              min: 0.6,
              max: 1.8,
              display: '${(s.fontScale * 100).round()}%',
              onChanged: (value) => _update(s.copyWith(fontScale: value)),
            ),
            _SliderRow(
              label: tr('速度'),
              value: s.speed,
              min: 0.5,
              max: 2.5,
              display: '${s.speed.toStringAsFixed(1)}x',
              onChanged: (value) => _update(s.copyWith(speed: value)),
            ),
            _SliderRow(
              label: tr('显示区域'),
              value: s.area,
              min: 0.25,
              max: 1,
              display: '${(s.area * 100).round()}%',
              onChanged: (value) => _update(s.copyWith(area: value)),
            ),
            _SliderRow(
              label: tr('同屏密度'),
              value: s.density.toDouble(),
              min: 30,
              max: 300,
              display: '${s.density}',
              onChanged: (value) => _update(s.copyWith(density: value.round())),
            ),
            _SliderRow(
              label: tr('描边粗细'),
              value: s.strokeWidth,
              min: 0,
              max: 3,
              display: s.strokeWidth.toStringAsFixed(1),
              onChanged: (value) => _update(s.copyWith(strokeWidth: value)),
            ),
            Wrap(
              spacing: NekoSpace.sm,
              children: [
                _Toggle(tr('滚动'), s.showScroll, (v) => _update(s.copyWith(showScroll: v))),
                _Toggle(tr('顶部'), s.showTop, (v) => _update(s.copyWith(showTop: v))),
                _Toggle(tr('底部'), s.showBottom, (v) => _update(s.copyWith(showBottom: v))),
                _Toggle(tr('保留颜色'), s.keepColor, (v) => _update(s.copyWith(keepColor: v))),
                _Toggle(tr('加粗'), s.bold, (v) => _update(s.copyWith(bold: v))),
                _Toggle(tr('阴影'), s.shadow, (v) => _update(s.copyWith(shadow: v))),
              ],
            ),
            const SizedBox(height: NekoSpace.sm),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 76, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        Expanded(
          child: Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, onChanged: onChanged),
        ),
        SizedBox(
          width: 52,
          child: Text(
            display,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.label, this.selected, this.onChanged);

  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onChanged,
      showCheckmark: false,
      selectedColor: colors.primary.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        fontSize: 12,
        color: selected ? colors.primary : colors.onSurfaceVariant,
      ),
    );
  }
}

/// B 站扫码登录：二维码 + 2 秒轮询 + Cookie 手动导入。
class BiliLoginDialog extends StatefulWidget {
  const BiliLoginDialog({super.key, required this.client});

  final BiliClient client;

  @override
  State<BiliLoginDialog> createState() => _BiliLoginDialogState();
}

class _BiliLoginDialogState extends State<BiliLoginDialog> {
  BiliQrTicket? ticket;
  String status = '正在生成二维码…';
  bool expired = false;
  Timer? poller;
  final cookieController = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_generate());
  }

  @override
  void dispose() {
    poller?.cancel();
    cookieController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    poller?.cancel();
    setState(() {
      status = '正在生成二维码…';
      expired = false;
    });
    try {
      final next = await widget.client.qrGenerate();
      if (!mounted) return;
      setState(() {
        ticket = next;
        status = '打开哔哩哔哩 App 扫一扫';
      });
      poller = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (ticket == null) return;
        try {
          final result = await widget.client.qrPoll(ticket!.key);
          if (!mounted) return;
          switch (result.state) {
            case BiliQrState.waiting:
              setState(() => status = '等待扫码');
              break;
            case BiliQrState.scanned:
              setState(() => status = '已扫码，请在手机上确认');
              break;
            case BiliQrState.success:
              poller?.cancel();
              if (mounted) Navigator.of(context).pop();
              break;
            case BiliQrState.expired:
              poller?.cancel();
              setState(() {
                expired = true;
                status = result.message;
              });
              break;
          }
        } catch (_) {
          // 轮询失败继续重试
        }
      });
    } catch (failure) {
      if (mounted) setState(() => status = '二维码生成失败：$failure');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Text(tr('登录 B 站账号')),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(NekoSpace.md),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(NekoRadius.card)),
              child: Column(
                children: [
                  ticket == null
                      ? const SizedBox(
                          height: 200,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : Opacity(
                          opacity: expired ? 0.25 : 1,
                          child: QrImageView(data: ticket!.url, size: 200, backgroundColor: Colors.white),
                        ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _generate,
                    child: Text(
                      expired ? tr('点击刷新二维码') : tr('二维码 180 秒后失效 · 点击刷新'),
                      style: TextStyle(fontSize: 11, color: colors.primary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: NekoSpace.md),
            Text(status, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
            const SizedBox(height: NekoSpace.md),
            Text(
              tr('登录后可播放 1080P / 4K、发送弹幕，并同步收藏与历史。'),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: cookieController,
              maxLines: 2,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: tr('已有 Cookie？粘贴 SESSDATA=...; bili_jct=...'),
                hintStyle: const TextStyle(fontSize: 11),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    final text = data?.text?.trim() ?? '';
                    if (text.isEmpty) return;
                    cookieController.text = text;
                  },
                  icon: const Icon(Icons.content_paste, size: 16),
                  label: Text(tr('从剪贴板粘贴')),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    var raw = cookieController.text.trim();
                    if (raw.isEmpty) return;
                    // 只贴了 SESSDATA 的值时补上键名
                    if (!raw.contains('=')) raw = 'SESSDATA=$raw';
                    await BiliSession.instance.importCookie(raw);
                    await widget.client.refreshAccount();
                    if (mounted) Navigator.of(context).pop();
                  },
                  child: Text(tr('导入 Cookie')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 视频页骨架状态：还没加载时给个占位，避免首帧闪白。
class VideoPagePlaceholder extends StatelessWidget {
  const VideoPagePlaceholder({super.key});

  @override
  Widget build(BuildContext context) => Container(color: NekoPalette.of(context).canvas);
}
