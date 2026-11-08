import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/domain/library.dart';
import 'package:nekoplayer_desktop/dynamic_lyrics.dart';

class LyricsTestBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key != 'assets/lyric_engine/index.html' &&
        key != 'assets/lyric_engine/host.js' &&
        key != 'assets/fonts/NotoSansCJKsc-Regular.otf') {
      throw StateError('Missing asset');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(key)));
  }
}

Map<String, Object?> snapshot({
  Track? track = const Track(
    path: '/private/music/audio.flac?token=secret',
    title: '中文歌曲',
    artist: '歌手',
  ),
  List<LyricLine> lyrics = const [
    LyricLine(
      Duration(seconds: 1),
      '中文歌词',
      translation: 'Translation',
      words: [
        LyricWord('中文', Duration(seconds: 1), Duration(milliseconds: 1500)),
        LyricWord('歌词', Duration(milliseconds: 2500), Duration(seconds: 1)),
      ],
    ),
    LyricLine(Duration(seconds: 4), '下一行'),
  ],
  Duration position = const Duration(milliseconds: 2200),
  Duration duration = const Duration(seconds: 120),
  bool playing = true,
  double rate = 1.5,
  bool showTranslation = true,
}) => dynamicLyricsSnapshot(
  track: track,
  lyrics: lyrics,
  position: position,
  duration: duration,
  playing: playing,
  rate: rate,
  showTranslation: showTranslation,
  now: DateTime.fromMillisecondsSinceEpoch(1792850000123),
);

class RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'engine payload uses seconds and preserves timed words and translation',
    () {
      final value = snapshot();
      final clock = value['clock']! as Map;
      expect(clock['positionSec'], 2.2);
      expect(clock['durationSec'], 120);
      expect(clock['anchoredAtMs'], 1792850000123);
      expect(clock['playbackRate'], 1.5);
      expect(clock['playing'], isTrue);
      final lines = (value['lyrics']! as Map)['lines'] as List;
      expect(lines[0]['startTime'], 1);
      expect(lines[0]['endTime'], 4);
      expect(lines[0]['fullText'], '中文歌词');
      expect(lines[0]['translation'], 'Translation');
      expect(lines[0]['words'][0], {
        'text': '中文',
        'startTime': 1.0,
        'endTime': 2.5,
      });
      expect(lines[1]['endTime'], 120);
    },
  );

  test('embedded page address keeps the existing query', () {
    final uri = embeddedLyricsUri(
      Uri.parse('http://127.0.0.1:4321/?token=abc'),
    );
    expect(uri.queryParameters, {'token': 'abc', 'embedded': '1'});
    expect(uri.host, '127.0.0.1');
    expect(uri.port, 4321);
  });

  test('payload never sends private paths, media URLs, or credentials', () {
    final value = snapshot();
    final track = value['track']! as Map;
    expect(track['coverUrl'], isNull);
    expect(track['seed'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(track['seed'], (snapshot()['track']! as Map)['seed']);
    expect(jsonEncode(value), isNot(contains('secret')));
    expect(jsonEncode(value), isNot(contains('/private/')));
  });

  test('pause, seek, translation, and missing-track state are explicit', () {
    final paused = snapshot(
      playing: false,
      position: Duration.zero,
      rate: 0.75,
      showTranslation: false,
    );
    expect((paused['clock']! as Map)['playing'], isFalse);
    expect((paused['clock']! as Map)['positionSec'], 0);
    expect((paused['clock']! as Map)['playbackRate'], 0.75);
    expect((paused['appearance']! as Map)['showSubtitleTranslation'], isFalse);
    expect((paused['appearance']! as Map)['hideTranslationSubtitle'], isTrue);
    final cleared = snapshot(track: null);
    expect(cleared['track'], isNull);
    expect(cleared['lyrics'], isNull);
    expect((cleared['clock']! as Map)['playing'], isFalse);
  });

  test('unknown duration and overlapping words keep valid line end times', () {
    final value = snapshot(
      duration: Duration.zero,
      lyrics: const [
        LyricLine(
          Duration(seconds: 1),
          '前行',
          words: [LyricWord('前行', Duration(seconds: 1), Duration(seconds: 8))],
        ),
        LyricLine(Duration(seconds: 4), '末行'),
      ],
    );
    final lines = (value['lyrics']! as Map)['lines'] as List;
    expect(lines[0]['endTime'], 9);
    expect(lines[1]['endTime'], 9);
  });

  group('loopback lyrics server', () {
    late DynamicLyricsServer server;
    late Uri uri;
    late HttpClient client;
    var value = snapshot();

    setUp(() async {
      value = snapshot();
      server = DynamicLyricsServer(
        snapshot: () => value,
        bundle: LyricsTestBundle(),
      );
      uri = await server.start();
      client = HttpOverrides.runWithHttpOverrides(
        HttpClient.new,
        RealHttpOverrides(),
      );
    });

    tearDown(() async {
      client.close(force: true);
      await server.dispose();
    });

    Future<HttpClientResponse> request(
      Uri target, {
      String method = 'GET',
      Map<String, String> headers = const {},
    }) async {
      final outgoing = await client.openUrl(method, target);
      headers.forEach(outgoing.headers.set);
      return outgoing.close();
    }

    test(
      'binds loopback with unguessable session URL and reuses server',
      () async {
        expect(uri.host, '127.0.0.1');
        expect(base64Url.decode(uri.pathSegments.first), hasLength(32));
        expect(await server.start(), uri);
        final other = DynamicLyricsServer(snapshot: snapshot);
        try {
          expect(
            (await other.start()).pathSegments.first,
            isNot(uri.pathSegments.first),
          );
        } finally {
          await other.dispose();
        }
      },
    );

    test('serves assets with correct MIME, CSP, and no CORS', () async {
      final response = await request(uri);
      expect(response.statusCode, 200);
      expect(response.headers.contentType!.mimeType, 'text/html');
      expect(response.headers.value('cache-control'), 'no-store');
      expect(
        response.headers.value('content-security-policy'),
        contains("default-src 'none'"),
      );
      expect(response.headers.value('access-control-allow-origin'), isNull);
      expect(
        await utf8.decoder.bind(response).join(),
        'assets/lyric_engine/index.html',
      );
      final script = await request(uri.resolve('host.js'));
      expect(script.headers.contentType!.mimeType, 'text/javascript');
      await script.drain<void>();
      final font = await request(
        uri.resolve('../fonts/NotoSansCJKsc-Regular.otf'),
      );
      expect(font.statusCode, 200);
      expect(font.headers.contentType!.mimeType, 'font/otf');
      await font.drain<void>();
    });

    test(
      'reflects pause, seeking, track change, and clear on next snapshot',
      () async {
        final endpoint = uri.resolve('state.json');
        Future<Map> read() async =>
            jsonDecode(await utf8.decoder.bind(await request(endpoint)).join())
                as Map;
        expect((await read())['clock']['playing'], isTrue);
        value = snapshot(playing: false, position: const Duration(seconds: 80));
        expect((await read())['clock']['positionSec'], 80);
        expect((await read())['clock']['playing'], isFalse);
        value = snapshot(
          track: const Track(path: 'other', title: '切歌', artist: '歌手'),
        );
        expect((await read())['track']['name'], '切歌');
        value = snapshot(track: null);
        expect((await read())['track'], isNull);
      },
    );

    test(
      'rejects other origins, forged Host, cross-site fetch, and writes',
      () async {
        for (final headers in [
          {'Origin': 'https://malicious.invalid'},
          {'Host': 'malicious.invalid'},
          {'Sec-Fetch-Site': 'cross-site'},
        ]) {
          final response = await request(
            uri.resolve('state.json'),
            headers: headers,
          );
          expect(response.statusCode, 403);
          await response.drain<void>();
        }
        final response = await request(
          uri.resolve('state.json'),
          method: 'POST',
        );
        expect(response.statusCode, 405);
        await response.drain<void>();
      },
    );

    test(
      'rejects missing tokens, traversal, unknown assets and project files',
      () async {
        for (final target in [
          uri.replace(path: '/lyric_engine/state.json'),
          uri.resolve('source.json'),
          uri.resolve('../../pubspec.yaml'),
          uri.resolve('assets/nonexistent.js'),
          uri.replace(
            path: '/${uri.pathSegments.first}/lyric_engine/%2e%2e/host.js',
          ),
          uri.replace(
            path: '/${uri.pathSegments.first}/lyric_engine/assets/a%5cb.js',
          ),
        ]) {
          final response = await request(target);
          expect(response.statusCode, 404, reason: '$target');
          await response.drain<void>();
        }
      },
    );

    test('HEAD sends no payload and disposed servers cannot restart', () async {
      final response = await request(uri.resolve('state.json'), method: 'HEAD');
      expect(response.statusCode, 200);
      expect(
        await response.fold<int>(0, (total, bytes) => total + bytes.length),
        0,
      );
      await server.dispose();
      expect(server.start, throwsStateError);
    });
  });

  test(
    'original engine renders in Chromium without external network',
    () async {
      final server = DynamicLyricsServer(snapshot: snapshot);
      final directory = await Directory.systemTemp.createTemp(
        'neko-lyric-smoke-',
      );
      try {
        final uri = await server.start();
        final result = await Process.run(
          Platform.environment['NODE_BIN'] ?? 'node',
          ['tool/smoke_dynamic_lyrics.mjs', '$uri', directory.path],
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      } finally {
        await server.dispose();
        await directory.delete(recursive: true);
      }
    },
    skip: Platform.environment['NEKO_LYRICS_BROWSER_SMOKE'] != '1',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
