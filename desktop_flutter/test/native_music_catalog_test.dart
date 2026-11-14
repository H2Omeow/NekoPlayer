import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/data/native_music_catalog.dart';
import 'package:nekoplayer_desktop/domain/music_plugin.dart';
import 'package:nekoplayer_desktop/domain/online_music.dart';

void main() {
  test(
    'Netease request uses native AES eapi with correct page and digest',
    () async {
      final catalog = NativeMusicCatalog(
        clock: () => 1234567890000,
        transport: (request) async {
          expect(
            request.uri.toString(),
            'https://interface.music.163.com/eapi/search/get',
          );
          final params = Uri.splitQueryString(request.body!)['params']!;
          final bytes = [
            for (var offset = 0; offset < params.length; offset += 2)
              int.parse(params.substring(offset, offset + 2), radix: 16),
          ];
          final text = Encrypter(
            AES(Key.fromUtf8('e82ckenh8dichen8'), mode: AESMode.ecb),
          ).decrypt(Encrypted.fromBase64(base64Encode(bytes)));
          final parts = text.split('-36cd479b6b5-');
          expect(parts.first, '/api/search/get');
          expect(
            parts.last,
            md5
                .convert(
                  utf8.encode('nobody${parts[0]}use${parts[1]}md5forencrypt'),
                )
                .toString(),
          );
          final data = jsonDecode(parts[1]) as Map<String, dynamic>;
          expect(data['s'], '夜晚 & music');
          expect(data['offset'], 30);
          expect(data['limit'], 30);
          return {
            'code': 200,
            'result': {
              'songCount': 61,
              'songs': [
                {
                  'id': 1,
                  'name': '夜晚',
                  'artists': [
                    {'name': 'Neko'},
                  ],
                  'album': {'name': '专辑'},
                },
                {'name': '缺少 id'},
              ],
            },
          };
        },
      );
      final result = await catalog.search(
        MusicProvider.netease,
        '夜晚 & music',
        2,
      );
      expect(result.songs.single.key, 'netease:1');
      expect(result.songs.single.artist, 'Neko');
      expect(result.songs.single.album, '专辑');
      expect(result.hasMore, isTrue);
    },
  );

  test('Netease search derives album artwork from picId', () async {
    final catalog = NativeMusicCatalog(
      clock: () => 1234,
      initializeSessions: false,
      transport: (request) async => {
        'code': 200,
        'result': {
          'songCount': 4,
          'songs': [
            {
              'id': 11,
              'name': '数字封面',
              'artists': [
                {'name': 'Neko'},
              ],
              'album': {'name': '专辑', 'picId': 5639395138885805},
            },
            {
              'id': 12,
              'name': '旧接口封面',
              'artists': [
                {'name': 'Neko'},
              ],
              'al': {
                'name': '旧专辑',
                'picUrl': 'http://p3.music.126.net/abc/123.jpg',
              },
            },
            {
              'id': 13,
              'name': '替代字段封面',
              'artists': [
                {'name': 'Neko'},
              ],
              'album': {'name': '专辑', 'pic': 109951163038292176},
            },
            {
              'id': 14,
              'name': '无封面',
              'artists': [
                {'name': 'Neko'},
              ],
              'album': {'name': '专辑', 'picId': 0},
            },
          ],
        },
      },
    );
    final result = await catalog.search(MusicProvider.netease, '封面', 1);
    expect(
      result.songs[0].artwork,
      'https://p1.music.126.net/6y-UleORITEDbvrOLV0Q8A==/5639395138885805.jpg',
    );
    expect(result.songs[1].artwork, 'https://p3.music.126.net/abc/123.jpg');
    expect(
      result.songs[2].artwork,
      'https://p1.music.126.net/yD9vbpuILH-tqNRIaP640g==/109951163038292176.jpg',
    );
    expect(result.songs[3].artwork, isEmpty);
  });

  test(
    'Kugou signature matches native protocol and keeps hash identity',
    () async {
      final catalog = NativeMusicCatalog(
        clock: () => 1234,
        transport: (request) async {
          expect(request.uri.host, 'songsearch.kugou.com');
          expect(request.body, isNull);
          final parameters = Map.of(request.uri.queryParameters);
          final signature = parameters.remove('signature');
          final keys = parameters.keys.toList()..sort();
          const salt = 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt';
          final text = keys.map((key) => '$key=${parameters[key]}').join();
          expect(
            signature,
            md5.convert(utf8.encode('$salt$text$salt')).toString(),
          );
          expect(parameters['keyword'], '夜晚 & music');
          expect(parameters['page'], '1');
          return {
            'status': 1,
            'error_code': 0,
            'data': {
              'total': 1,
              'lists': [
                {
                  'FileHash': 'ABCDEF0123456789ABCDEF0123456789',
                  'Audioid': 23,
                  'SongName': '<em>夜晚</em>',
                  'SingerName': 'Neko',
                },
                {'SongName': '没有 hash'},
              ],
            },
          };
        },
      );
      final result = await catalog.search(MusicProvider.kugou, '夜晚 & music', 1);
      expect(result.songs.single.title, '夜晚');
      expect(result.songs.single.key, 'kugou:abcdef0123456789abcdef0123456789');
      expect(result.hasMore, isFalse);
    },
  );

  test('business errors are not shown as empty success', () async {
    final catalog = NativeMusicCatalog(
      transport: (_) async => {'status': 0, 'code': 400},
    );
    for (final provider in MusicProvider.values) {
      await expectLater(
        catalog.search(provider, 'music', 1),
        throwsA(isA<MusicSearchException>()),
      );
    }
  });

  test('transport errors are safe and actionable', () async {
    for (final failure in [
      TimeoutException('private url'),
      const SocketException('private host'),
      const FormatException('body'),
    ]) {
      final catalog = NativeMusicCatalog(transport: (_) async => throw failure);
      await expectLater(
        catalog.search(MusicProvider.netease, 'music', 1),
        throwsA(isA<MusicSearchException>()),
      );
    }
  });

  test('invalid input does not send a request', () async {
    final catalog = NativeMusicCatalog(
      transport: (_) async => throw StateError('must not run'),
    );
    for (final keyword in ['', ' ' * 201, 'a' * 201]) {
      await expectLater(
        catalog.search(MusicProvider.netease, keyword, 1),
        throwsA(isA<MusicSearchException>()),
      );
    }
    await expectLater(
      catalog.search(MusicProvider.netease, 'music', 0),
      throwsA(isA<MusicSearchException>()),
    );
  });

  test(
    'hot searches and suggestions use the builtin recommendation endpoints',
    () async {
      final paths = <String>[];
      final catalog = NativeMusicCatalog(
        transport: (request) async {
          paths.add(request.uri.path);
          expect(request.uri.queryParameters['platform'], 'wy');
          if (request.uri.path.endsWith('/music/hotSearch')) {
            return {
              'code': 200,
              'list': [
                {'word': '周深'},
                {'word': ' 周深 '},
                {'word': ' '},
                {'word': '夜曲'},
              ],
            };
          }
          expect(request.uri.queryParameters['keyword'], '周');
          return {
            'code': 200,
            'songs': [
              {'title': '大鱼', 'artist': '周深'},
              {'title': '大鱼', 'artist': '周深'},
            ],
            'singers': [
              {'name': '周深'},
            ],
            'albums': [
              {'name': '深的深'},
            ],
          };
        },
      );
      expect(await catalog.hotSearches(MusicProvider.gatewayNetease), [
        '周深',
        '夜曲',
      ]);
      expect(
        await catalog.searchSuggestions(MusicProvider.gatewayNetease, ' 周 '),
        ['大鱼 周深', '周深', '深的深'],
      );
      expect(paths, [contains('/music/hotSearch'), contains('/music/suggest')]);
    },
  );

  test('recommendation failures and scripted sources stay silent', () async {
    final offline = NativeMusicCatalog(
      transport: (_) async => throw const SocketException('offline'),
    );
    expect(await offline.hotSearches(MusicProvider.gatewayNetease), isEmpty);
    expect(
      await offline.searchSuggestions(MusicProvider.gatewayNetease, '周'),
      isEmpty,
    );

    final catalog = NativeMusicCatalog(
      transport: (_) async => throw StateError('must not run'),
    );
    final source = MusicPluginSource(
      id: 'external',
      url: Uri.parse('https://example.com/plugin.js'),
      api: Uri.parse('https://example.com/api'),
      platform: 'wy',
      name: 'External',
      version: '1',
      author: 'test',
      capabilities: const ['search', 'suggest', 'hotSearch'],
      format: 'musicfree/1',
      script: 'module.exports = {};',
    );
    expect(
      await catalog.hotSearches(MusicProvider.gatewayNetease, source: source),
      isEmpty,
    );
    expect(
      await catalog.searchSuggestions(
        MusicProvider.gatewayNetease,
        '周',
        source: source,
      ),
      isEmpty,
    );
  });
}
