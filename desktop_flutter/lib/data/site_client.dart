import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/online_music.dart';
import 'account_store.dart';

class SiteRequest {
  const SiteRequest(this.uri, this.method, this.token, {this.body});
  final Uri uri;
  final String method;
  final String token;
  final Map<String, dynamic>? body;
}

class SiteConflictException implements Exception {
  const SiteConflictException(this.meta);
  final Map<String, dynamic> meta;
}

typedef SiteTransport =
    Future<Map<String, dynamic>> Function(SiteRequest request);

class SiteClient {
  SiteClient({SiteTransport? transport}) : _transport = transport ?? _send;
  final SiteTransport _transport;

  Future<Map<String, dynamic>> _request(
    String path,
    String token, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? query,
    int expectedCode = 0,
    bool allowAnonymous = false,
  }) async {
    if (!allowAnonymous || token.isNotEmpty) {
      AccountStore.validateSiteToken(token);
    }
    try {
      final response = await _transport(
        SiteRequest(
          Uri.https('player.nekoh2o.top', '/$path', query),
          method,
          token,
          body: body,
        ),
      );
      if (response['code'] == 409) {
        throw SiteConflictException(
          response['meta'] is Map<String, dynamic>
              ? response['meta'] as Map<String, dynamic>
              : const {},
        );
      }
      if (response['code'] != expectedCode) {
        throw const MusicSearchException('本站未确认操作成功，请检查登录状态后重试。');
      }
      return response;
    } on HandshakeException {
      throw const MusicSearchException(
        '本站 TLS 证书验证失败。请联系站点维护者检查证书；客户端不会忽略安全校验。',
      );
    } on IOException {
      throw const MusicSearchException('无法连接本站，请检查网络。');
    } on TimeoutException {
      throw const MusicSearchException('本站请求超时，请稍后重试。');
    } on FormatException {
      throw const MusicSearchException('本站响应格式异常，未修改本地数据。');
    }
  }

  Future<Map<String, dynamic>> me(String token) async {
    final body = await _request('auth/sso/me', token);
    if (body['user'] is! Map<String, dynamic>) {
      throw const MusicSearchException('登录令牌无效或已过期。');
    }
    return body['user'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> pull(String token) async {
    final body = await _request('user/data', token);
    if (body['data'] == null) return {};
    if (body['data'] is! Map<String, dynamic>) {
      throw const MusicSearchException('云端数据格式异常。');
    }
    return body['data'] as Map<String, dynamic>;
  }

  /// 返回数据与每个分区的云端元数据（旧服务端没有 meta 时为空）。
  Future<({Map<String, dynamic> data, Map<String, dynamic> meta})> fetch(
    String token,
  ) async {
    final body = await _request('user/data', token);
    final data = body['data'] ?? {};
    if (data is! Map<String, dynamic>) {
      throw const MusicSearchException('云端数据格式异常。');
    }
    final meta = body['meta'] ?? data['meta'];
    return (
      data: data,
      meta: meta is Map<String, dynamic> ? meta : <String, dynamic>{},
    );
  }

  /// 只替换给出的分区；[expected] 为各分区期望的云端 updatedAt（乐观锁）。
  Future<Map<String, dynamic>> patchSections(
    String token, {
    required String device,
    required Map<String, Object?> sections,
    Map<String, int>? expected,
  }) async {
    final response = await _request(
      'user/data/sections',
      token,
      method: 'PATCH',
      body: {'device': device, 'sections': sections, 'expected': ?expected},
    );
    return response['meta'] is Map<String, dynamic>
        ? response['meta'] as Map<String, dynamic>
        : <String, dynamic>{};
  }

  Future<void> push(String token, Map<String, dynamic> data) async {
    await _request('user/data', token, method: 'PUT', body: data);
  }

  Future<void> logout(String token) async {
    await _request('auth/sso/logout', token, method: 'POST');
  }

  Future<List<Uri>> wallpapers() async {
    final body = await _request(
      'local/wallpaper/list',
      '',
      query: {'orientation': 'horizontal'},
      expectedCode: 200,
      allowAnonymous: true,
    );
    final rows = body['data'];
    if (rows is! List) throw const MusicSearchException('壁纸列表格式异常。');
    // The site serves images from /data/wallpaper/; very large originals
    // (tens of megapixels) are skipped because they exceed the download cap.
    bool reasonable(Map<String, dynamic> row) {
      final width = row['width'], height = row['height'];
      return width is! num || height is! num || width * height <= 40e6;
    }

    return [
          for (final row in rows.whereType<Map<String, dynamic>>())
            if (reasonable(row))
              Uri.https(
                'player.nekoh2o.top',
                '/',
              ).resolve(row['url']?.toString() ?? ''),
        ]
        .where(
          (uri) =>
              uri.scheme == 'https' &&
              uri.host == 'player.nekoh2o.top' &&
              uri.port == 443 &&
              uri.userInfo.isEmpty &&
              (uri.path.startsWith('/data/wallpaper/') ||
                  uri.path.startsWith('/local/wallpaper/')) &&
              !uri.path.contains('..'),
        )
        .toList();
  }

  Future<Map<String, dynamic>> commentRequest(
    String path,
    String token, {
    String method = 'GET',
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) {
    if (!RegExp(r'^comments(?:/[A-Za-z0-9_-]+(?:/like)?)?$').hasMatch(path)) {
      throw const MusicSearchException('评论地址无效。');
    }
    return _request(
      path,
      token,
      method: method,
      query: query,
      body: body,
      expectedCode: 200,
      allowAnonymous: method == 'GET',
    );
  }

  static Future<Map<String, dynamic>> _send(SiteRequest request) async {
    if (request.uri.scheme != 'https' ||
        request.uri.host != 'player.nekoh2o.top' ||
        request.uri.port != 443 ||
        request.uri.userInfo.isNotEmpty) {
      throw const MusicSearchException('拒绝向非本站地址发送登录凭据。');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      return await (() async {
        final outgoing = await client.openUrl(request.method, request.uri);
        outgoing.followRedirects = false;
        if (request.token.isNotEmpty) {
          outgoing.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer ${request.token}',
          );
        }
        if (request.body != null) {
          outgoing.headers.contentType = ContentType.json;
          outgoing.write(jsonEncode(request.body));
        }
        final response = await outgoing.close();
        if (response.statusCode == 204 &&
            request.uri.path == '/auth/sso/logout') {
          return {'code': 0};
        }
        if (response.statusCode == 401) {
          throw const MusicSearchException('本站登录已过期，请重新登录。');
        }
        if (response.statusCode != 200 && response.statusCode != 409) {
          throw MusicSearchException(
            response.statusCode == 500
                ? '云端数据读取或写入失败（HTTP 500），请稍后重试。'
                : '本站请求失败（HTTP ${response.statusCode}），未发送至重定向地址。',
          );
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 8 * 1024 * 1024) {
            throw const MusicSearchException('云端数据超过 8MB，已停止读取。');
          }
          bytes.addAll(chunk);
        }
        final result = jsonDecode(utf8.decode(bytes));
        if (result is! Map<String, dynamic>) {
          throw const FormatException('Expected an object');
        }
        return result;
      })().timeout(const Duration(seconds: 30));
    } finally {
      client.close(force: true);
    }
  }
}
