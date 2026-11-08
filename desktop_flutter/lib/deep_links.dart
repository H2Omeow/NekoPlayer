import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 分享 / 私信 / 用户主页深链。
class AppDeepLink {
  const AppDeepLink({this.shareToken, this.chatPeer, this.userId});
  final String? shareToken;
  final String? chatPeer;
  final String? userId;

  static AppDeepLink? parse(Uri uri) {
    if (uri.scheme == 'https' || uri.scheme == 'http') {
      if (uri.host != 'player.nekoh2o.top') return null;
      final segments = uri.pathSegments;
      if (segments.length >= 2 && segments[0] == 's') {
        final token = segments[1];
        if (RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(token)) {
          return AppDeepLink(shareToken: token);
        }
      }
      return null;
    }
    if (uri.scheme != 'nekoplayer') return null;
    switch (uri.host) {
      case 'share':
        final token = uri.queryParameters['token'] ?? '';
        if (RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(token)) {
          return AppDeepLink(shareToken: token);
        }
        return null;
      case 'chat':
        final peer = (uri.queryParameters['peer'] ?? uri.queryParameters['id'] ?? '').trim();
        return peer.isEmpty ? null : AppDeepLink(chatPeer: peer);
      case 'user':
        final id = (uri.queryParameters['id'] ?? '').trim();
        return id.isEmpty ? null : AppDeepLink(userId: id);
    }
    return null;
  }
}

/// 单实例转发：第一个进程绑定回环端口，后续进程把参数发给它后退出。
/// 不依赖 GTK / Win32 单实例机制，Linux 和 Windows 行为一致。
class DeepLinkRouter extends ChangeNotifier {
  DeepLinkRouter._(this._server);

  static const port = 47653;
  final ServerSocket _server;
  AppDeepLink? _link;
  bool _disposed = false;

  AppDeepLink? get link => _link;

  /// 返回 null 表示另一个实例已接管参数（调用方应直接退出）。
  static Future<DeepLinkRouter?> start(List<String> arguments) async {
    final uriText = arguments
        .where((value) => value.startsWith('nekoplayer://') || value.contains('/s/'))
        .firstOrNull;
    try {
      final server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: false,
      );
      final router = DeepLinkRouter._(server);
      server.listen((socket) {
        final buffer = StringBuffer();
        socket.cast<List<int>>().transform(utf8.decoder).listen(
          (chunk) => buffer.write(chunk),
          onDone: () {
            router._consume(buffer.toString());
            socket.destroy();
          },
          onError: (_) => socket.destroy(),
        );
      });
      if (uriText != null) router._consume(uriText);
      return router;
    } on SocketException {
      if (uriText != null) {
        try {
          final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
          socket.write(uriText);
          await socket.flush();
          socket.destroy();
        } catch (_) {}
      }
      exit(0);
    }
  }

  void _consume(String value) {
    for (final line in value.split('\n')) {
      final text = line.trim();
      if (text.isEmpty) continue;
      final uri = Uri.tryParse(text);
      if (uri == null) continue;
      final parsed = AppDeepLink.parse(uri);
      if (parsed != null) {
        _link = parsed;
        if (!_disposed) notifyListeners();
        break;
      }
    }
  }

  void consume() {
    _link = null;
  }

  /// Injects a URL received outside the socket (e.g. native notification).
  void open(String value) => _consume(value);

  @override
  void dispose() {
    _disposed = true;
    unawaited(_server.close());
    super.dispose();
  }
}
