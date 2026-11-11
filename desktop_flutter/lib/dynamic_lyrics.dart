import './i18n/tr.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'domain/library.dart';

Map<String, Object?> dynamicLyricsSnapshot({
  required Track? track,
  required List<LyricLine> lyrics,
  required Duration position,
  required Duration duration,
  required bool playing,
  required double rate,
  required bool showTranslation,
  DateTime? now,
}) {
  double seconds(Duration value) => value.inMicroseconds / 1000000;
  return {
    'track': track == null
        ? null
        : {
            'name': track.title,
            'artist': track.artist,
            'coverUrl': null,
            'seed': sha256.convert(utf8.encode(track.path)).toString(),
          },
    'lyrics': track == null
        ? null
        : {
            'lines': [
              for (var index = 0; index < lyrics.length; index++)
                {
                  'startTime': seconds(lyrics[index].time),
                  'endTime': [
                    seconds(lyrics[index].time) + 0.001,
                    if (index + 1 < lyrics.length)
                      seconds(lyrics[index + 1].time)
                    else if (duration > lyrics[index].time)
                      seconds(duration)
                    else
                      seconds(lyrics[index].time) + 5,
                    for (final word in lyrics[index].words)
                      seconds(word.time + word.duration),
                  ].reduce((left, right) => left > right ? left : right),
                  'fullText': lyrics[index].text,
                  'translation': lyrics[index].translation,
                  'words': [
                    for (final word in lyrics[index].words)
                      {
                        'text': word.text,
                        'startTime': seconds(word.time),
                        'endTime': seconds(word.time + word.duration),
                      },
                  ],
                },
            ],
          },
    'clock': {
      'positionSec': seconds(position),
      'durationSec': seconds(duration),
      'anchoredAtMs': (now ?? DateTime.now()).millisecondsSinceEpoch,
      'playing': track != null && playing,
      'playbackRate': rate,
    },
    'appearance': {
      'showSubtitleTranslation': showTranslation,
      'hideTranslationSubtitle': !showTranslation,
    },
  };
}

/// Adds the selected dynamic-lyrics quality without discarding URL parameters
/// added by the local server or the embedded-view mode.
Uri lyricsUriWithQuality(Uri uri, Map<String, String> quality) =>
    uri.replace(queryParameters: {...uri.queryParameters, ...quality});

/// The page variant shown inside the app window (track info lives in the app).
Uri embeddedLyricsUri(
  Uri uri, [
  Map<String, String> quality = const {},
]) => lyricsUriWithQuality(uri, {...quality, 'embedded': '1'});

class DynamicLyricsServer {
  DynamicLyricsServer({required this.snapshot, AssetBundle? bundle})
    : bundle = bundle ?? rootBundle;

  final Map<String, Object?> Function() snapshot;
  final AssetBundle bundle;
  HttpServer? _server;
  Future<Uri>? _starting;
  bool _disposed = false;
  final String _token = _newToken();

  static String _newToken() {
    final random = Random.secure();
    return base64UrlEncode(List.generate(32, (_) => random.nextInt(256)));
  }

  Future<Uri> start() {
    if (_disposed) throw StateError(tr('动态歌词窗口已关闭'));
    return _starting ??= _start().catchError((Object error) {
      _starting = null;
      throw error;
    });
  }

  Future<Uri> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (_disposed) {
      await server.close(force: true);
      throw StateError(tr('动态歌词窗口已关闭'));
    }
    _server = server;
    server.listen((request) async {
      try {
        await _serve(request);
      } catch (_) {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
        } catch (_) {}
      } finally {
        try {
          await request.response.close();
        } catch (_) {}
      }
    });
    return Uri.parse(
      'http://127.0.0.1:${server.port}/$_token/lyric_engine/index.html',
    );
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('Referrer-Policy', 'no-referrer');
    response.headers.set('X-Frame-Options', 'DENY');
    response.headers.set(
      'Content-Security-Policy',
      "default-src 'none'; script-src 'self' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; "
          "img-src 'self' data: blob:; font-src 'self'; connect-src 'self' data: blob:; "
          "worker-src 'self' blob:; object-src 'none'; base-uri 'none'; "
          "form-action 'none'; frame-ancestors 'none'",
    );
    final origin = 'http://127.0.0.1:${_server!.port}';
    if (request.headers.value('host') != '127.0.0.1:${_server!.port}' ||
        (request.headers.value('origin') != null &&
            request.headers.value('origin') != origin) ||
        request.headers.value('sec-fetch-site') == 'cross-site') {
      response.statusCode = HttpStatus.forbidden;
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      return;
    }
    final segments = request.uri.pathSegments;
    if (segments.length < 3 ||
        segments.first != _token ||
        segments.any(
          (part) =>
              part.isEmpty ||
              part == '.' ||
              part == '..' ||
              part.contains('/') ||
              part.contains('\\'),
        )) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    final path = segments.skip(1).join('/');
    if (path == 'lyric_engine/state.json') {
      response.headers.contentType = ContentType.json;
      if (request.method == 'GET') response.write(jsonEncode(snapshot()));
      return;
    }
    final allowed =
        path == 'fonts/NotoSansCJKsc-Regular.otf' ||
        const {'index.html', 'host.js', 'host.css'}.contains(
          path.startsWith('lyric_engine/') ? path.substring(13) : '',
        ) ||
        path.startsWith('lyric_engine/assets/');
    if (!allowed) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    ByteData data;
    try {
      data = await bundle.load('assets/$path');
    } catch (_) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    final extension = path.split('.').last;
    response.headers.contentType = switch (extension) {
      'html' => ContentType.html,
      'js' => ContentType('text', 'javascript', charset: 'utf-8'),
      'css' => ContentType('text', 'css', charset: 'utf-8'),
      'png' => ContentType('image', 'png'),
      'svg' => ContentType('image', 'svg+xml'),
      'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
      'webp' => ContentType('image', 'webp'),
      'otf' => ContentType('font', 'otf'),
      _ => ContentType.binary,
    };
    if (request.method == 'GET') {
      response.add(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _server?.close(force: true);
    _server = null;
  }
}
