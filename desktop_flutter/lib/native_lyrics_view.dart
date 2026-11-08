import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class LyricsViewEvent {
  const LyricsViewEvent(this.type, this.message);
  final String type;
  final String message;
}

class LyricsViewException implements Exception {
  const LyricsViewException(this.reason);
  final String reason;

  @override
  String toString() => reason;
}

/// Client of the runner's native web view overlay. The runner owns at most
/// one view, so a newly opened session replaces the previous one.
class NativeLyricsView {
  NativeLyricsView({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('top.nekoh2o/lyrics_view') {
    _channel.setMethodCallHandler(_handle);
  }

  static final shared = NativeLyricsView();

  final MethodChannel _channel;
  LyricsViewSession? _current;

  Future<dynamic> _handle(MethodCall call) async {
    if (call.method != 'event') return null;
    final values = call.arguments;
    if (values is! Map) return null;
    _current?._events.add(
      LyricsViewEvent('${values['type']}', '${values['message'] ?? ''}'),
    );
    return null;
  }

  /// Returns null when the embedded view can be used, otherwise the reason.
  Future<String?> unavailableReason() async {
    if (!Platform.isLinux && !Platform.isWindows) return '当前平台暂不支持内嵌动态歌词';
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'isAvailable',
      );
      if (result?['available'] == true) return null;
      return result?['reason'] as String? ?? '系统缺少内嵌网页组件';
    } on MissingPluginException {
      return '当前版本不包含内嵌网页组件';
    } on PlatformException catch (error) {
      return error.message ?? '内嵌网页组件不可用';
    }
  }

  Future<LyricsViewSession> open(
    Uri url, {
    Color background = const Color(0xFF14131B),
  }) async {
    final previous = _current;
    _current = null;
    previous?._events.close();
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('create', {
        'url': url.toString(),
        'background': background.toARGB32(),
      });
      if (result?['ok'] != true) {
        throw LyricsViewException(result?['reason'] as String? ?? '无法创建内嵌网页');
      }
    } on MissingPluginException {
      throw const LyricsViewException('当前版本不包含内嵌网页组件');
    } on PlatformException catch (error) {
      throw LyricsViewException(error.message ?? '无法创建内嵌网页');
    }
    return _current = LyricsViewSession._(this);
  }
}

class LyricsViewSession {
  LyricsViewSession._(this._owner);

  final NativeLyricsView _owner;
  final _events = StreamController<LyricsViewEvent>.broadcast();
  Stream<LyricsViewEvent> get events => _events.stream;
  bool get active => identical(_owner._current, this);

  Future<void> _call(String method, [Object? arguments]) async {
    if (!active) return;
    try {
      await _owner._channel.invokeMethod<void>(method, arguments);
    } on PlatformException {
      // The view is cosmetic; the host reports real failures through events.
    } on MissingPluginException {
      // Same as above.
    }
  }

  /// [bounds] are logical pixels relative to the Flutter view.
  Future<void> setBounds(Rect bounds, double devicePixelRatio) =>
      _call('setBounds', {
        'x': bounds.left,
        'y': bounds.top,
        'width': bounds.width,
        'height': bounds.height,
        'devicePixelRatio': devicePixelRatio,
      });

  Future<void> setVisible(bool visible) =>
      _call('setVisible', {'visible': visible});

  Future<void> close() async {
    if (!active) return;
    final call = _call('destroy');
    _owner._current = null;
    await call;
    await _events.close();
  }
}
