import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'i18n/tr.dart';

import 'playback/playback_engine.dart';
import 'data/library_store.dart';
import 'player_controller.dart';

class DesktopIntegration extends ChangeNotifier {
  DesktopIntegration(
    this.player, {
    MethodChannel? channel,
    this.settings,
    this.settingsLoader,
  }) : channel = channel ?? const MethodChannel('top.nekoh2o/desktop');
  final PlayerController player;
  final MethodChannel channel;
  LibraryStore? settings;
  final Future<LibraryStore?> Function()? settingsLoader;
  bool mediaAvailable = false;
  bool lyricsAvailable = false;
  bool positioningAvailable = false;
  bool trayAvailable = false;
  bool closeToTray = false;
  bool overlay = false;
  bool locked = false;
  // Optional pieces of the desktop lyrics window; each can be turned off.
  bool overlayTitle = true;
  bool overlayProgress = true;
  bool overlayControls = true;
  double fontSize = 30;
  double opacity = .9;
  String? error;
  /// Receives URLs forwarded by native notifications (or the OS protocol
  /// handler, when the platform can route it through the channel).
  void Function(String uri)? onUri;
  bool _disposed = false;
  bool _sending = false;
  bool _dirty = false;
  String? _signature;
  bool _settingsReadable = true;
  Future<void> _writes = Future.value();
  Future<void> get flushed => _writes;

  Future<void> _readSettings() async {
    try {
      final raw = await settings?.read();
      if (raw == null || _disposed) return;
      final value = jsonDecode(raw);
      if (value is! Map ||
          value['version'] != 1 ||
          value['overlay'] is! bool ||
          value['locked'] is! bool ||
          value['fontSize'] is! num ||
          value['opacity'] is! num) {
        throw const FormatException();
      }
      final size = (value['fontSize'] as num).toDouble();
      final alpha = (value['opacity'] as num).toDouble();
      if (!size.isFinite || !alpha.isFinite) throw const FormatException();
      overlay = value['overlay'] as bool;
      locked = value['locked'] as bool;
      overlayTitle = value['overlayTitle'] as bool? ?? true;
      overlayProgress = value['overlayProgress'] as bool? ?? true;
      overlayControls = value['overlayControls'] as bool? ?? true;
      fontSize = size.clamp(18, 64);
      opacity = alpha.clamp(.25, 1);
    } catch (_) {
      _settingsReadable = false;
      error = tr('桌面歌词设置读取失败，已保留原数据；本次修改不会覆盖它。');
    }
  }

  void _saveSettings() {
    final store = settings;
    if (store == null || !_settingsReadable || _disposed) return;
    final encoded = jsonEncode({
      'version': 1,
      'overlay': overlay,
      'locked': locked,
      'overlayTitle': overlayTitle,
      'overlayProgress': overlayProgress,
      'overlayControls': overlayControls,
      'fontSize': fontSize,
      'opacity': opacity,
    });
    _writes = _writes.then((_) => store.write(encoded)).catchError((Object _) {
      if (_disposed) return;
      error = tr('桌面歌词设置保存失败，请检查磁盘空间与访问权限。');
      notifyListeners();
    });
  }

  Future<void> initialize() async {
    channel.setMethodCallHandler(_handle);
    try {
      settings ??= await settingsLoader?.call();
    } catch (_) {
      settings = null;
    }
    await _readSettings();
    if (_disposed) return;
    try {
      final result = await channel.invokeMapMethod<String, dynamic>(
        'initialize',
      );
      if (_disposed) return;
      mediaAvailable = result?['media'] == true;
      lyricsAvailable = result?['lyrics'] == true;
      positioningAvailable = result?['positioning'] == true;
      trayAvailable = result?['tray'] == true;
      if (trayAvailable) unawaited(refreshTrayLabels());
      player.addListener(_changed);
      // Position, play state and lyrics advance on the engine, not through
      // PlayerController notifications.
      player.engine.addListener(_changed);
      _changed();
    } on MissingPluginException {
      error = tr('当前运行环境没有桌面系统集成。');
    } catch (_) {
      error = tr('系统集成初始化失败，不影响普通播放。');
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _handle(MethodCall call) async {
    if (_disposed) return;
    final arguments = call.arguments is Map ? call.arguments as Map : const {};
    final action = arguments['action'];
    if (call.method == 'trayChanged') {
      trayAvailable = arguments['available'] == true;
      if (!trayAvailable) closeToTray = false;
      notifyListeners();
      return;
    }
    if (call.method == 'overlayClosed') {
      overlay = false;
      _saveSettings();
      _changed();
      notifyListeners();
      return;
    }
    if (call.method == 'deepLink') {
      final uri = arguments['uri'];
      if (uri is String && uri.isNotEmpty) onUri?.call(uri);
      return;
    }
    if (call.method != 'action') return;
    switch (action) {
      case 'play':
        await player.resume();
      case 'pause':
        await player.pause();
      case 'toggle':
        await player.toggle();
      case 'next':
        await player.next();
      case 'previous':
        await player.previous();
      case 'stop':
        await player.stop();
      case 'seek':
      case 'seekRelative':
        final value = arguments['value'];
        if (value is! num || !value.isFinite || player.current == null) return;
        final duration = player.duration.inMicroseconds;
        if (duration <= 0) return;
        final target =
            (value +
                    (action == 'seekRelative'
                        ? player.position.inMicroseconds
                        : 0))
                .round()
                .clamp(0, duration);
        await player.seek(Duration(microseconds: target));
      case 'volume':
        final value = arguments['value'];
        if (value is num && value.isFinite) {
          player.setVolume(value.toDouble() * 100);
        }
      case 'rate':
        final value = arguments['value'];
        if (value is num && value.isFinite) player.setRate(value.toDouble());
      case 'loop':
        final mode = switch (arguments['value']) {
          'Track' => RepeatMode.single,
          'Playlist' => RepeatMode.loop,
          'None' => RepeatMode.sequential,
          _ => null,
        };
        if (mode != null) player.setRepeatMode(mode);
      case 'shuffle':
        if (arguments['value'] is bool) {
          player.setRepeatMode(
            arguments['value'] == true
                ? RepeatMode.shuffle
                : RepeatMode.sequential,
          );
        }
    }
  }

  void configureOverlay({
    bool? enabled,
    bool? lock,
    bool? showTitle,
    bool? showProgress,
    bool? showControls,
    double? size,
    double? alpha,
  }) {
    if (!lyricsAvailable || _disposed) return;
    overlay = enabled ?? overlay;
    locked = lock ?? locked;
    overlayTitle = showTitle ?? overlayTitle;
    overlayProgress = showProgress ?? overlayProgress;
    overlayControls = showControls ?? overlayControls;
    if (size != null && size.isFinite) fontSize = size.clamp(18, 64);
    if (alpha != null && alpha.isFinite) opacity = alpha.clamp(.25, 1);
    if (enabled != null ||
        lock != null ||
        showTitle != null ||
        showProgress != null ||
        showControls != null ||
        size != null ||
        alpha != null) {
      _saveSettings();
    }
    _signature = null;
    _changed();
    notifyListeners();
  }

  /// Shows a system notification. Clicking it forwards [uri] through
  /// [onUri] on platforms where notifications support actions.
  Future<void> notify(String title, String body, String? uri) async {
    if (_disposed) return;
    try {
      await channel.invokeMethod<void>('notify', {
        'title': title,
        'body': body,
        'uri': uri ?? '',
      });
    } catch (_) {
      // Desktop notifications are best effort; a failure must not disturb
      // message handling.
    }
  }

  Map<String, String> _trayLabels() => {
    'tooltip': tr('NekoPlayer — 点击显示播放器'),
    'show': tr('显示播放器'),
    'toggle': tr('播放 / 暂停'),
    'previous': tr('上一首'),
    'next': tr('下一首'),
    'quit': tr('退出'),
    'lyricsTitle': tr('NekoPlayer 桌面歌词'),
  };

  /// Re-sends localized tray and lyrics-window labels after a language change.
  Future<void> refreshTrayLabels() async {
    if (_disposed || !trayAvailable) return;
    try {
      await channel.invokeMethod<bool>('configureTray', {
        'closeToTray': closeToTray,
        'labels': _trayLabels(),
      });
    } catch (_) {
      // Labels are best effort; the previous language remains usable.
    }
  }

  Future<void> configureTray(bool enabled) async {
    if (_disposed || (enabled && !trayAvailable)) return;
    try {
      final result = await channel.invokeMethod<bool>('configureTray', {
        'closeToTray': enabled,
        'labels': _trayLabels(),
      });
      if (_disposed) return;
      closeToTray = enabled && result == true && trayAvailable;
      if (enabled && !closeToTray) error = tr('系统托盘当前不可用，关闭窗口仍会正常退出。');
    } catch (_) {
      if (_disposed) return;
      error = tr('托盘设置失败，未启用关闭到托盘。');
    }
    notifyListeners();
  }

  Map<String, dynamic> state() {
    final track = player.current;
    final lyricIndex = player.lyricIndex;
    return {
      'trackId': track == null
          ? '/org/mpris/MediaPlayer2/TrackList/NoTrack'
          : '/top/nekoh2o/track/t${sha256.convert(utf8.encode(track.path))}',
      'title': track?.title ?? 'NekoPlayer',
      'artist': track?.artist ?? '',
      'album': track?.online?.album ?? '',
      'playing': player.engine.playing,
      'hasTrack': track != null,
      'position': player.position.inMicroseconds,
      'duration': player.duration.inMicroseconds,
      'volume': player.volume / 100,
      'rate': player.rate,
      'loop': player.repeat == RepeatMode.single
          ? 'Track'
          : player.repeat == RepeatMode.loop
          ? 'Playlist'
          : 'None',
      'shuffle': player.repeat == RepeatMode.shuffle,
      'lyricsVisible': overlay,
      'lyric': lyricIndex >= 0
          ? player.lyrics[lyricIndex].text
          : track?.title ?? 'NekoPlayer',
      'nextLyric': !player.doubleLyrics
          ? ''
          : player.showTranslation &&
                lyricIndex >= 0 &&
                player.lyrics[lyricIndex].translation.isNotEmpty
          ? player.lyrics[lyricIndex].translation
          : lyricIndex + 1 < player.lyrics.length
          ? player.lyrics[lyricIndex + 1].text
          : track?.artist ?? '',
      'lyricsLocked': locked,
      'lyricsSize': fontSize,
      'lyricsOpacity': opacity,
      'showTitle': overlayTitle,
      'showProgress': overlayProgress,
      'showControls': overlayControls,
    };
  }

  void _changed() {
    if (_disposed) return;
    _dirty = true;
    if (!_sending) unawaited(_send());
  }

  Future<void> _send() async {
    _sending = true;
    try {
      while (_dirty && !_disposed) {
        _dirty = false;
        final current = state();
        final signature = jsonEncode({
          ...current,
          'position': (current['position'] as int) ~/ 500000,
        });
        if (signature == _signature) continue;
        await channel.invokeMethod<void>('state', current);
        _signature = signature;
      }
    } catch (_) {
      if (!_disposed) {
        error = tr('系统控制或桌面歌词更新失败；普通播放仍可用。');
        notifyListeners();
      }
    } finally {
      _sending = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    player.removeListener(_changed);
    player.engine.removeListener(_changed);
    channel.setMethodCallHandler(null);
    unawaited(channel.invokeMethod<void>('dispose').catchError((Object _) {}));
    super.dispose();
  }
}
