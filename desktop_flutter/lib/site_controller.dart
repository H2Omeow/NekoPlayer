import './i18n/tr.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'data/account_store.dart';
import 'data/site_client.dart';
import 'domain/online_music.dart';
import 'player_controller.dart';

class SiteController extends ChangeNotifier {
  SiteController({
    required this.accounts,
    required this.player,
    SiteClient? client,
  }) : client = client ?? SiteClient();
  final AccountStore accounts;
  final PlayerController player;
  final SiteClient client;
  Map<String, dynamic>? user;
  String _userToken = '';
  bool busy = false;
  String? message;
  bool _disposed = false;
  HttpServer? _server;
  Completer<String>? _callback;

  Future<void> _action(Future<void> Function() work) async {
    if (busy || _disposed) return;
    busy = true;
    message = null;
    _notify();
    try {
      await work();
    } catch (failure) {
      message = failure is MusicSearchException
          ? failure.message
          : failure is FormatException
          ? failure.message
          : failure is TimeoutException
          ? tr('等待登录超时，请重试。')
          : tr('操作未完成，请检查系统密钥环与网络后重试。');
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> importToken(String value) => _action(() async {
    value = value.trim();
    if (value.startsWith('nekoplayer://auth?')) {
      value = Uri.parse(value).queryParameters['token'] ?? '';
    }
    await _accept(value);
  });

  Future<void> _accept(String token) async {
    final previous = accounts.siteToken;
    AccountStore.validateSiteToken(token);
    final verified = await client.me(token);
    if (_disposed) return;
    await accounts.update(siteToken: token, expectedSiteToken: previous);
    user = verified;
    _userToken = token;
    message = tr('本站登录成功。');
  }

  Future<void> login(
    Future<bool> Function(Uri uri) launch,
  ) => _action(() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    final path = '/auth/${AccountStore.randomHex(24)}';
    final callback = Completer<String>();
    _callback = callback;
    server.listen((request) async {
      final token = request.uri.queryParameters['token'] ?? '';
      var valid =
          request.method == 'GET' &&
          request.uri.path == path &&
          request.headers.host == '127.0.0.1' &&
          request.headers.port == server.port &&
          !callback.isCompleted;
      try {
        AccountStore.validateSiteToken(token);
      } catch (_) {
        valid = false;
      }
      request.response.statusCode = valid ? 200 : 400;
      request.response.headers.contentType = ContentType.text;
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.response.headers.set('Referrer-Policy', 'no-referrer');
      request.response.write(
        valid
            ? 'You may return to NekoPlayer. Your session is being verified.'
            : 'Invalid login callback.',
      );
      await request.response.close();
      if (valid && !callback.isCompleted) callback.complete(token);
    });
    try {
      final redirect = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: server.port,
        path: path,
      );
      if (!await launch(
        Uri.https('account.nekoh2o.top', '/login', {
          'redirect': redirect.toString(),
        }),
      )) {
        throw       MusicSearchException(tr('无法打开浏览器，请使用令牌导入。'));
      }
      message = tr('浏览器已打开，等待本站登录；可取消。');
      _notify();
      final token = await callback.future.timeout(const Duration(minutes: 3));
      if (!_disposed && token.isNotEmpty) {
        await _accept(token);
      } else if (!_disposed) {
        message = tr('已取消登录。');
      }
    } finally {
      await server.close(force: true);
      if (_server == server) {
        _server = null;
        _callback = null;
      }
    }
  });

  void cancelLogin() {
    if (_callback != null && !_callback!.isCompleted) _callback!.complete('');
  }

  Future<void> refresh() => _action(() async {
    final token = accounts.siteToken;
    user = await client.me(token);
    _userToken = token;
    message = tr('本站账号已验证。');
  });

  Future<void> logout() => _action(() async {
    final token = accounts.siteToken;
    await accounts.update(siteToken: '');
    user = null;
    message = tr('已清除本机本站登录凭据。');
    if (token.isNotEmpty) {
      try {
        await client.logout(token);
      } catch (_) {
        message = tr('本机已退出；服务端会话注销失败，请在账号中心检查。');
      }
    }
  });

  /// 启动后令牌已保存但尚未验证账号时，静默取得当前账号信息。
  Future<Map<String, dynamic>> ensureUser() async {
    final token = accounts.siteToken;
    final known = user;
    if (known != null && _userToken == token) return known;
    final verified = await client.me(token);
    if (_disposed || token != accounts.siteToken) {
      throw       MusicSearchException(tr('本站账号已切换，已取消操作。'));
    }
    user = verified;
    _userToken = token;
    _notify();
    return verified;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancelLogin();
    unawaited(_server?.close(force: true));
    super.dispose();
  }
}
