import '../../i18n/tr.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<Map<String, dynamic>> sendPluginHttp(
  Map<String, dynamic> payload,
) async {
  var uri = Uri.tryParse('${payload['url']}');
  if (uri == null) throw FormatException(tr('插件请求地址无效。'));
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    return await (() async {
      var method = '${payload['method'] ?? 'GET'}'.toUpperCase();
      if (!const {
        'GET',
        'POST',
        'PUT',
        'DELETE',
        'PATCH',
        'HEAD',
        'OPTIONS',
        'PROPFIND',
        'PROPPATCH',
        'COPY',
        'MOVE',
        'MKCOL',
        'LOCK',
        'UNLOCK',
      }.contains(method)) {
        throw       FormatException(tr('插件请求方法无效。'));
      }
      var body = payload['body'] as String?;
      if (body != null && utf8.encode(body).length > 2 * 1024 * 1024) {
        throw       FormatException(tr('插件请求内容过大。'));
      }
      final headers = <String, String>{};
      for (final entry in (payload['headers'] as Map? ?? {}).entries) {
        final name = '${entry.key}';
        final value = '${entry.value}';
        if (!RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(name) ||
            value.contains(RegExp(r'[\r\n]')) ||
            value.length > 8192) {
          throw       FormatException(tr('插件请求头无效。'));
        }
        if (!const {
          'host',
          'content-length',
          'connection',
          'transfer-encoding',
        }.contains(name.toLowerCase())) {
          headers[name] = value;
        }
      }
      for (var redirect = 0; redirect <= 4; redirect++) {
        if (!const {'https', 'http'}.contains(uri!.scheme) ||
            uri!.host.isEmpty ||
            uri!.userInfo.isNotEmpty ||
            '$uri'.length > 8192) {
          throw       FormatException(tr('插件仅能请求 HTTP(S) 地址。'));
        }
        final request = await client.openUrl(method, uri!);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, 'NekoPlayer/plugin');
        headers.forEach(request.headers.set);
        if (body != null) request.write(body);
        final response = await request.close();
        if (const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) throw FormatException(tr('插件请求重定向地址缺失。'));
          final next = uri!.resolve(location);
          if (uri!.scheme == 'https' && next.scheme != 'https') {
            throw       FormatException(tr('插件请求拒绝降级为 HTTP。'));
          }
          if (next.origin != uri!.origin) {
            headers.removeWhere(
              (key, _) => const {
                'authorization',
                'cookie',
                'proxy-authorization',
              }.contains(key.toLowerCase()),
            );
          }
          if (response.statusCode == 303 ||
              (const {301, 302}.contains(response.statusCode) &&
                  method == 'POST')) {
            method = 'GET';
            body = null;
          }
          uri = next;
          continue;
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 2 * 1024 * 1024) {
            throw       FormatException(tr('插件响应超过 2 MiB。'));
          }
          bytes.addAll(chunk);
        }
        final responseHeaders = <String, String>{};
        response.headers.forEach(
          (name, values) => responseHeaders[name] = values.join(', '),
        );
        return {
          'status': response.statusCode,
          'headers': responseHeaders,
          'url': '$uri',
          'body': base64Encode(bytes),
        };
      }
      throw       FormatException(tr('插件请求重定向次数过多。'));
    })().timeout(
      Duration(
        milliseconds: (payload['timeout'] as num? ?? 15000).toInt().clamp(
          100,
          20000,
        ),
      ),
    );
  } finally {
    client.close(force: true);
  }
}
