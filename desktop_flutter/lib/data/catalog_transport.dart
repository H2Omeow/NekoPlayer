import '../i18n/tr.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/online_music.dart';

class CatalogRequest {
  const CatalogRequest(
    this.uri, {
    required this.headers,
    this.body,
    this.decodeResponse,
    this.captureCookies = false,
  });
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
  final String Function(List<int> bytes)? decodeResponse;
  final bool captureCookies;
}

typedef CatalogTransport =
    Future<Map<String, dynamic>> Function(CatalogRequest request);

Future<Map<String, dynamic>> sendCatalogRequest(CatalogRequest request) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    return await (() async {
      final outgoing = await client.openUrl(
        request.body == null ? 'GET' : 'POST',
        request.uri,
      );
      outgoing.followRedirects = false;
      request.headers.forEach(outgoing.headers.set);
      if (request.body != null) outgoing.write(request.body);
      final response = await outgoing.close();
      if (response.statusCode != HttpStatus.ok) {
        throw MusicHttpException(response.statusCode);
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > 2 * 1024 * 1024) {
          throw       MusicSearchException(tr('音乐平台响应过大，已停止读取。'));
        }
        bytes.addAll(chunk);
      }
      final body = jsonDecode(
        request.decodeResponse?.call(bytes) ?? utf8.decode(bytes),
      );
      if (body is! Map<String, dynamic>) {
        throw const FormatException('Expected an object');
      }
      if (request.captureCookies) {
        body['_cookies'] = {
          for (final cookie in response.cookies) cookie.name: cookie.value,
        };
      }
      return body;
    })().timeout(const Duration(seconds: 30));
  } finally {
    client.close(force: true);
  }
}
