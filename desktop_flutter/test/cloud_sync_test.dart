import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/data/account_store.dart';
import 'package:nekoplayer_desktop/data/cloud_library.dart';
import 'package:nekoplayer_desktop/data/site_client.dart';
import 'package:nekoplayer_desktop/domain/library.dart';
import 'package:nekoplayer_desktop/domain/online_music.dart';
import 'package:nekoplayer_desktop/player_controller.dart';
import 'package:nekoplayer_desktop/site_controller.dart';

import 'fakes.dart';

const token = 'site-token-valid-123';
Map<String, dynamic> remoteSong(String id, {String source = 'netease'}) => {
  'id': int.parse(id),
  'nm': '歌曲$id',
  'ar': 'Neko',
  'source': source,
};

void main() {
  test(
    'cloud merge unions playlist songs, keeps settings and never uploads local paths',
    () {
      const localFile = Track(
        path: '/private/music/secret.mp3',
        title: 'private',
        artist: 'local',
      );
      final localSong = Track.fromOnline(
        const OnlineSong(
          provider: MusicProvider.netease,
          id: '1',
          title: '歌曲1',
          artist: 'Neko',
        ),
      );
      final local = LibraryData(
        tracks: [localFile, localSong],
        favorites: {localFile.path, localSong.path},
        history: [localFile.path, localSong.path],
        playlists: [
          LocalPlaylist(
            id: 'p',
            name: '本机名称',
            paths: [localFile.path, localSong.path],
          ),
        ],
        volume: 34,
        rate: 1.5,
        preferredQuality: 'lossless',
      );
      final remote = <String, dynamic>{
        'favorites': [
          remoteSong('2'),
          remoteSong('3', source: 'animemusic-future'),
        ],
        'history': [remoteSong('2')],
        'playlists': [
          {
            'id': 'p',
            'name': '云端名称',
            'songs': [
              remoteSong('2'),
              remoteSong('3', source: 'animemusic-future'),
            ],
          },
        ],
        'futureField': 'preserved',
      };
      final merged = CloudLibrary.merge(local, CloudLibrary.decode(remote));
      expect(merged.playlists.single.name, '本机名称');
      expect(merged.playlists.single.paths, [
        localFile.path,
        localSong.path,
        'netease:2',
      ]);
      expect(merged.volume, 34);
      expect(merged.preferredQuality, 'lossless');
      final encoded = CloudLibrary.encode(merged, remote);
      expect(encoded['futureField'], 'preserved');
      expect((encoded['favorites'] as List), hasLength(3));
      expect(
        ((encoded['playlists'] as List).single as Map)['songs'],
        hasLength(3),
      );
      expect(jsonEncode(encoded), isNot(contains('/private/')));
      expect(jsonEncode(encoded), contains('animemusic-future'));
    },
  );

  test('malformed remote data is rejected before merge', () {
    expect(
      () => CloudLibrary.decode({'favorites': 'invalid'}),
      throwsFormatException,
    );
    expect(
      () => CloudLibrary.decode({
        'playlists': [
          {
            'id': '1',
            'songs': [1],
          },
        ],
      }),
      throwsFormatException,
    );
  });

  group('site controller', () {
    late AccountStore accounts;
    late MemoryStore library;
    late PlayerController player;
    late List<SiteRequest> requests;
    late Future<Map<String, dynamic>> Function(SiteRequest request) handler;
    late SiteController site;

    setUp(() async {
      accounts = AccountStore();
      await accounts.initialize();
      library = MemoryStore();
      player = PlayerController(engine: FakeEngine(), store: library);
      await player.initialize();
      requests = [];
      handler = (request) async => {
        'code': 0,
        'user': {'id': '123', 'nickname': 'Neko'},
        'data': {},
      };
      site = SiteController(
        accounts: accounts,
        player: player,
        client: SiteClient(
          transport: (request) async {
            requests.add(request);
            expect(request.uri.scheme, 'https');
            expect(request.uri.host, 'player.nekoh2o.top');
            expect(request.token, isNotEmpty);
            return handler(request);
          },
        ),
      );
    });
    tearDown(() async {
      site.dispose();
      await player.flushed;
      player.dispose();
    });

    test(
      'login validates token before storing and does not auto-sync',
      () async {
        await site.importToken('nekoplayer://auth?token=$token');
        expect(accounts.siteToken, token);
        expect(site.user?['id'], '123');
        expect(requests, hasLength(1));
        expect(requests.single.uri.path, '/auth/sso/me');
        handler = (_) async => {'code': -1};
        await site.importToken('invalid-token-123456');
        expect(accounts.siteToken, token);
        expect(site.message, contains('未确认操作成功'));
      },
    );

    test(
      'TLS failure during login preserves the verified account without retrying',
      () async {
        await site.importToken(token);
        requests.clear();
        final previousUser = site.user;
        final previousLibrary = player.snapshot.encode();
        final previousWrites = library.writes;
        handler = (_) async => throw const HandshakeException(
          'CERTIFICATE_VERIFY_FAILED: certificate has expired',
        );

        await site.importToken('pending-site-session-123');

        expect(accounts.siteToken, token);
        expect(site.user, same(previousUser));
        expect(site.busy, isFalse);
        expect(site.message, contains('TLS'));
        expect(site.message, isNot(contains('pending-site-session-123')));
        expect(requests, hasLength(1));
        expect(requests.single.uri.path, '/auth/sso/me');
        expect(player.snapshot.encode(), previousLibrary);
        expect(library.writes, previousWrites);
      },
    );

    test(
      'login verification cannot replace a site account changed while waiting',
      () async {
        await accounts.update(siteToken: token);
        handler = (_) async {
          await accounts.update(siteToken: 'new-site-session-123');
          return {
            'code': 0,
            'user': {'id': 'old-remote'},
          };
        };
        await site.importToken('pending-site-session-123');
        expect(accounts.siteToken, 'new-site-session-123');
        expect(site.user, isNull);
        expect(site.message, contains('账号已切换'));
      },
    );

    test(
      'loopback SSO validates random callback path then verifies token',
      () async {
        await site.login((loginUri) async {
          expect(loginUri.host, 'account.nekoh2o.top');
          final callback = Uri.parse(loginUri.queryParameters['redirect']!);
          expect(callback.host, '127.0.0.1');
          expect(callback.path, startsWith('/auth/'));
          final client = HttpClient();
          try {
            final badRequest = await client.getUrl(
              callback.replace(
                path: '/wrong',
                queryParameters: {'token': token},
              ),
            );
            final badResponse = await badRequest.close();
            expect(badResponse.statusCode, 400);
            await badResponse.drain<void>();
            final request = await client.getUrl(
              callback.replace(queryParameters: {'token': token}),
            );
            final response = await request.close();
            expect(response.statusCode, 200);
            expect(
              response.headers.value(HttpHeaders.cacheControlHeader),
              'no-store',
            );
            final text = await utf8.decoder.bind(response).join();
            expect(text, isNot(contains(token)));
          } finally {
            client.close(force: true);
          }
          return true;
        });
        expect(accounts.siteToken, token);
        expect(site.busy, isFalse);
      },
    );

    test('browser login can be cancelled without storing any token', () async {
      await site.login((_) async {
        site.cancelLogin();
        return true;
      });
      expect(accounts.siteToken, isEmpty);
      expect(site.busy, isFalse);
      expect(requests, isEmpty);
    });
  });
}
