import '../i18n/tr.dart';
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/online_music.dart';

class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

class DownloadCancellation {
  bool cancelled = false;
  HttpClient? _client;

  void cancel() {
    cancelled = true;
    _client?.close(force: true);
  }

  void check() {
    if (cancelled) throw const DownloadCancelled();
  }
}

class AudioDownloader {
  AudioDownloader({this.limit = maxBytes});
  static const maxBytes = 2 * 1024 * 1024 * 1024;
  final int limit;

  Future<void> download({
    required ResolvedAudio audio,
    required File partial,
    required File destination,
    required DownloadCancellation cancellation,
    required void Function(int received, int? total) progress,
  }) async {
    cancellation.check();
    if (audio.size > limit) throw       MusicSearchException(tr('音频超过文件大小限制。'));
    if (await destination.exists()) {
      throw       MusicSearchException(tr('目标文件已存在，未覆盖。'));
    }
    var offset = await partial.exists() ? await partial.length() : 0;
    if (audio.size > 0 && offset == audio.size) {
      await _checksum(partial, audio.checksum);
      cancellation.check();
      await destination.create(exclusive: true);
      try {
        await partial.rename(destination.path);
      } catch (_) {
        await destination.delete();
        rethrow;
      }
      progress(offset, offset);
      return;
    }
    var uri = audio.uri;
    final headers = Map<String, String>.from(audio.headers);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    cancellation._client = client;
    IOSink? output;
    var reserved = false;
    try {
      HttpClientResponse? response;
      for (var redirects = 0; redirects <= 5; redirects++) {
        cancellation.check();
        if (!['http', 'https'].contains(uri.scheme) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          throw       MusicSearchException(tr('下载地址无效。'));
        }
        final request = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 20));
        request.followRedirects = false;
        headers.forEach(request.headers.set);
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        if (offset > 0) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
        }
        response = await request.close().timeout(const Duration(seconds: 30));
        if (![301, 302, 303, 307, 308].contains(response.statusCode)) break;
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null || redirects == 5) {
          throw       MusicSearchException(tr('下载重定向无效。'));
        }
        final next = uri.resolve(location);
        if (uri.scheme == 'https' && next.scheme != 'https') {
          throw       MusicSearchException(tr('拒绝不安全的下载重定向。'));
        }
        if (uri.origin != next.origin) {
          headers.removeWhere(
            (name, _) => const {
              'authorization',
              'cookie',
              'proxy-authorization',
            }.contains(name.toLowerCase()),
          );
        }
        uri = next;
      }
      cancellation.check();
      if (response == null || ![200, 206].contains(response.statusCode)) {
        throw MusicSearchException(
          tr('下载请求失败（HTTP {status}）。', {'status': response?.statusCode ?? 0}),
        );
      }
      final contentType = response.headers.contentType?.mimeType ?? '';
      if (contentType.startsWith('text/') ||
          contentType.contains('json') ||
          contentType.contains('xml')) {
        throw       MusicSearchException(tr('平台返回的内容不是音频文件。'));
      }
      int? total;
      if (response.statusCode == 206) {
        final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(
          response.headers.value(HttpHeaders.contentRangeHeader) ?? '',
        );
        if (match == null || int.parse(match[1]!) != offset) {
          throw       MusicSearchException(tr('断点响应与本地文件不匹配，请重新下载。'));
        }
        total = int.parse(match[3]!);
        final end = int.parse(match[2]!);
        if (end < offset ||
            end >= total ||
            (response.contentLength >= 0 &&
                response.contentLength != end - offset + 1)) {
          throw       MusicSearchException(tr('断点响应长度无效。'));
        }
      } else {
        offset = 0;
        if (response.contentLength >= 0) total = response.contentLength;
      }
      total ??= audio.size > 0 ? audio.size : null;
      if ((total ?? 0) > limit || (audio.size > 0 && total != audio.size)) {
        throw       MusicSearchException(tr('下载文件大小与平台信息不符。'));
      }
      output = partial.openWrite(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
      var received = offset;
      var lastProgress = DateTime.fromMillisecondsSinceEpoch(0);
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        cancellation.check();
        received += chunk.length;
        if (received > limit || (total != null && received > total)) {
          throw       MusicSearchException(tr('下载内容超出预期大小。'));
        }
        output.add(chunk);
        await output.flush();
        if (DateTime.now().difference(lastProgress).inMilliseconds >= 250) {
          progress(received, total);
          lastProgress = DateTime.now();
        }
      }
      await output.close();
      output = null;
      cancellation.check();
      if (received == 0 ||
          (total != null && received != total) ||
          (audio.size > 0 && received != audio.size)) {
        throw       MusicSearchException(tr('下载不完整，可以重试续传。'));
      }
      await _checksum(partial, audio.checksum);
      cancellation.check();
      await destination.create(exclusive: true);
      reserved = true;
      await partial.rename(destination.path);
      reserved = false;
      progress(received, total ?? received);
    } catch (_) {
      if (cancellation.cancelled) throw const DownloadCancelled();
      rethrow;
    } finally {
      if (output != null) await output.close();
      client.close(force: true);
      cancellation._client = null;
      if (reserved && await destination.exists()) await destination.delete();
    }
  }

  Future<void> _checksum(File partial, String expected) async {
    if (RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(expected)) {
      final actual = await md5.bind(partial.openRead()).first;
      if (actual.toString() != expected.toLowerCase()) {
        await partial.delete();
        throw       MusicSearchException(tr('文件校验失败，已移除损坏文件，请重试。'));
      }
    }
  }
}
