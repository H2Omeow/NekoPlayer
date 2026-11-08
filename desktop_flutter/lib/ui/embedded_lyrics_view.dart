import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../dynamic_lyrics.dart';
import '../native_lyrics_view.dart';

/// Renders the dynamic lyrics page in a native web view placed over this
/// widget's area, and falls back to a hint when the platform lacks one.
class EmbeddedLyricsView extends StatefulWidget {
  const EmbeddedLyricsView({
    super.key,
    required this.start,
    this.onOpenInBrowser,
    this.native,
  });

  /// Starts the local lyrics server and returns the page address.
  final Future<Uri> Function() start;
  final VoidCallback? onOpenInBrowser;
  final NativeLyricsView? native;

  @override
  State<EmbeddedLyricsView> createState() => _EmbeddedLyricsViewState();
}

class _EmbeddedLyricsViewState extends State<EmbeddedLyricsView> {
  static const background = Color(0xFF14131B);

  LyricsViewSession? _session;
  StreamSubscription<LyricsViewEvent>? _events;
  String? _failure;
  bool _ready = false;
  bool _disposed = false;
  int _attempt = 0;
  bool _tickerEnabled = true;
  bool _tickScheduled = false;
  Rect? _sentBounds;
  double? _sentRatio;
  bool? _sentVisible;
  ModalRoute<dynamic>? _route;

  NativeLyricsView get native => widget.native ?? NativeLyricsView.shared;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!identical(route, _route)) {
      _route?.animation?.removeStatusListener(_routeAnimation);
      _route = route;
      route?.animation?.addStatusListener(_routeAnimation);
    }
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _updateVisibility();
  }

  void _routeAnimation(AnimationStatus _) => _updateVisibility();

  // The native view is above all Flutter content, so it must step aside while
  // another route (dialog, menu), a transition or an inactive subtree is on top.
  bool get _shouldShow {
    final route = _route;
    final routeShown =
        route == null ||
        (route.isCurrent && route.animation?.isCompleted != false);
    return _ready && routeShown && _tickerEnabled;
  }

  void _updateVisibility() {
    if (_session == null) return;
    final visible = _shouldShow;
    if (visible == _sentVisible) return;
    _sentVisible = visible;
    unawaited(_session!.setVisible(visible));
  }

  void _retry() {
    setState(() => _failure = null);
    unawaited(_open());
  }

  Future<void> _open() async {
    final attempt = ++_attempt;
    LyricsViewSession? session;
    try {
      final reason = await native.unavailableReason();
      if (reason != null) throw LyricsViewException(reason);
      final uri = await widget.start();
      session = await native.open(embeddedLyricsUri(uri));
    } on LyricsViewException catch (error) {
      _fail(attempt, error.reason);
      return;
    } catch (_) {
      _fail(attempt, '无法启动动态歌词服务');
      return;
    }
    if (_disposed || attempt != _attempt) {
      unawaited(session.close());
      return;
    }
    _session = session;
    _events = session.events.listen((event) {
      if (event.type == 'loadFailed' || event.type == 'crashed') {
        _release();
        _fail(
          _attempt,
          event.message.isEmpty ? '动态歌词页面加载失败' : '动态歌词页面加载失败：${event.message}',
        );
      }
    });
    _sentBounds = null;
    _sentVisible = null;
    setState(() => _ready = true);
    _scheduleTick();
  }

  void _fail(int attempt, String reason) {
    if (_disposed || attempt != _attempt) return;
    setState(() {
      _ready = false;
      _failure = reason;
    });
  }

  void _release() {
    final session = _session;
    _session = null;
    unawaited(_events?.cancel());
    _events = null;
    if (session != null) unawaited(session.close());
  }

  // Layout, scrolling and window resizes all end in a frame; the last
  // post-frame callback of each frame forwards the resulting rectangle.
  void _scheduleTick() {
    if (_tickScheduled || _disposed || _session == null) return;
    _tickScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _tickScheduled = false;
      if (_disposed) return;
      _report();
      _scheduleTick();
    });
  }

  void _report() {
    final session = _session;
    final box = context.findRenderObject();
    if (session == null || box is! RenderBox || !box.attached || !box.hasSize) {
      return;
    }
    final ratio = View.of(context).devicePixelRatio;
    final bounds = box.localToGlobal(Offset.zero) & box.size;
    if (bounds != _sentBounds || ratio != _sentRatio) {
      _sentBounds = bounds;
      _sentRatio = ratio;
      unawaited(session.setBounds(bounds, ratio));
    }
    _updateVisibility();
  }

  @override
  void dispose() {
    _disposed = true;
    _route?.animation?.removeStatusListener(_routeAnimation);
    _release();
    super.dispose();
  }

  // Always fills the available area: a childless box would shrink to zero
  // under loose constraints and the native view would follow it.
  @override
  Widget build(BuildContext context) => SizedBox.expand(child: _content());

  Widget _content() {
    final failure = _failure;
    if (failure == null) {
      return ColoredBox(
        color: background,
        child: _ready ? null : const Center(child: CircularProgressIndicator()),
      );
    }
    return ColoredBox(
      color: background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_outlined, size: 40),
              const SizedBox(height: 12),
              Text(
                '无法在应用内显示动态歌词',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(failure, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton(onPressed: _retry, child: const Text('重试')),
                  if (widget.onOpenInBrowser != null)
                    FilledButton.icon(
                      onPressed: widget.onOpenInBrowser,
                      icon: const Icon(Icons.open_in_browser),
                      label: const Text('在浏览器中打开'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
