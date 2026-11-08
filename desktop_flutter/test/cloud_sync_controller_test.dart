import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/data/account_store.dart';
import 'package:nekoplayer_desktop/data/site_client.dart';
import 'package:nekoplayer_desktop/domain/online_music.dart';
import 'package:nekoplayer_desktop/domain/library.dart';
import 'package:nekoplayer_desktop/player_controller.dart';
import 'package:nekoplayer_desktop/site_controller.dart';
import 'package:nekoplayer_desktop/sync/cloud_credentials.dart';
import 'package:nekoplayer_desktop/sync/cloud_sync_controller.dart';
import 'package:nekoplayer_desktop/sync/sync_section.dart';
import 'package:nekoplayer_desktop/sync/sync_state_store.dart';

import 'fakes.dart';

const token = 'site-token-valid-123';

Map<String, dynamic> remoteSong(String id) => {
  'id': int.parse(id),
  'nm': '歌曲$id',
  'ar': 'Neko',
  'source': 'netease',
};

Track localSong(String id) => Track.fromOnline(
  OnlineSong(
    provider: MusicProvider.netease,
    id: id,
    title: '歌曲$id',
    artist: 'Neko',
  ),
);

/// 内存中的云端：GET /user/data、PATCH /user/data/sections（含 409）。
class FakeCloud {
  final data = <String, dynamic>{};
  final meta = <String, Map<String, dynamic>>{};
  final requests = <SiteRequest>[];
  int clock = 1000;
  bool failGet = false;
  void Function()? beforePatch;

  Iterable<SiteRequest> get patches =>
      requests.where((request) => request.method == 'PATCH');
  Iterable<SiteRequest> get gets =>
      requests.where((request) => request.uri.path == '/user/data');

  // Like server.js, credentials live as flat fields of the user data.
  void store(String section, Object? value) {
    if (section == 'credentials') {
      data.addAll(value! as Map<String, dynamic>);
    } else {
      data[section] = value;
    }
  }

  void seed(String section, Object value, {int updatedAt = 500}) {
    store(section, value);
    meta[section] = {'updatedAt': updatedAt, 'device': 'Android · test'};
  }

  Future<Map<String, dynamic>> handle(SiteRequest request) async {
    requests.add(request);
    switch ('${request.method} ${request.uri.path}') {
      case 'GET /auth/sso/me':
        return {
          'code': 0,
          'user': {'id': '1', 'nickname': 'Neko'},
        };
      case 'GET /user/data':
        if (failGet) throw const SocketException('offline');
        return {
          'code': 0,
          'data': data,
          'meta': {'sections': meta},
        };
      case 'PATCH /user/data/sections':
        beforePatch?.call();
        beforePatch = null;
        final body = request.body!;
        final expected = body['expected'] as Map<String, dynamic>? ?? {};
        for (final entry in expected.entries) {
          if ((meta[entry.key]?['updatedAt'] ?? 0) != entry.value) {
            return {
              'code': 409,
              'meta': {'sections': meta},
            };
          }
        }
        for (final entry
            in (body['sections'] as Map<String, dynamic>).entries) {
          store(entry.key, entry.value);
          meta[entry.key] = {'updatedAt': ++clock, 'device': body['device']};
        }
        return {
          'code': 0,
          'meta': {'sections': meta},
        };
    }
    throw StateError('unexpected ${request.method} ${request.uri.path}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('section status', () {
    const synced = SectionState(
      localUpdatedAt: 10,
      lastSyncedAt: 20,
      lastRemoteUpdatedAt: 100,
    );
    SyncStatus status(
      SectionState state,
      int remoteUpdatedAt, {
      bool local = true,
      int count = 1,
    }) => sectionStatus(
      state: state,
      remote: RemoteSection(updatedAt: remoteUpdatedAt, count: count),
      localHasData: local,
    );

    test('local and remote dirty flags give the five states', () {
      expect(status(synced, 100), SyncStatus.synced);
      expect(
        status(synced.copyWith(localUpdatedAt: 30), 100),
        SyncStatus.localNewer,
      );
      expect(status(synced, 200), SyncStatus.remoteNewer);
      expect(
        status(synced.copyWith(localUpdatedAt: 30), 200),
        SyncStatus.conflict,
      );
    });

    test('never synced with data on both sides is a conflict', () {
      const fresh = SectionState();
      expect(status(fresh, 100), SyncStatus.conflict);
      expect(status(fresh, 0, count: 0), SyncStatus.localNewer);
      expect(status(fresh, 100, local: false), SyncStatus.remoteNewer);
      expect(status(fresh, 0, local: false, count: 0), SyncStatus.synced);
    });

    test('only one-sided changes are handled automatically', () {
      expect(autoAction(SyncStatus.localNewer), SyncAction.upload);
      expect(autoAction(SyncStatus.remoteNewer), SyncAction.pull);
      expect(autoAction(SyncStatus.conflict), SyncAction.none);
      expect(autoAction(SyncStatus.unknown), SyncAction.none);
    });

    test('state survives a persistence round trip with defaults', () {
      final state = SyncState(userId: '7');
      state.sections[SyncSection.favorites] = synced.copyWith(autoSync: false);
      final restored = SyncState.decode(state.encode());
      expect(restored.userId, '7');
      expect(restored.sections[SyncSection.favorites]!.lastSyncedAt, 20);
      expect(restored.sections[SyncSection.favorites]!.autoSync, isFalse);
      expect(restored.sections[SyncSection.history]!.autoSync, isTrue);
      expect(restored.sections[SyncSection.credentials]!.autoSync, isFalse);
      expect(SyncState.decode('{broken').sections, hasLength(4));
    });
  });

  group('cloud credentials', () {
    test('tolerates cookies written by other clients', () async {
      final parsed = CloudCredentials.parse({
        'ncCookie': 'MUSIC_U=abc; JSESSIONID-WYYY=x; __csrf=y',
      });
      expect(parsed.netease, {'MUSIC_U': 'abc', '__csrf': 'y'});
      final accounts = AccountStore();
      await accounts.initialize();
      await accounts.update(siteToken: token);
      await accounts.replaceSessions(
        netease: parsed.netease,
        expectedSiteToken: token,
      );
      expect(accounts.neteaseLoggedIn, isTrue);
    });

    test('a cookie without MUSIC_U or token is skipped with a reason', () {
      final parsed = CloudCredentials.parse({
        'ncCookie': 'JSESSIONID-WYYY=x',
        'kgCookies': ['userid=1', ''],
      });
      expect(parsed.netease, isNull);
      expect(parsed.kugou, [null, null]);
      expect(parsed.platform, isNull);
      expect(parsed.notes, hasLength(2));
    });

    test('a token without userid is imported but flagged token-only', () async {
      final parsed = CloudCredentials.parse({
        'kgCookies': ['token=legacy', ''],
        'kgPlatform': 0,
      });
      final accounts = AccountStore();
      await accounts.initialize();
      await accounts.update(siteToken: token);
      await accounts.replaceSessions(
        kugou: parsed.kugou,
        platform: parsed.platform,
        expectedSiteToken: token,
      );
      expect(accounts.kugou(0)['token'], 'legacy');
      expect(accounts.kugouTokenOnly(0), isTrue);
      expect(accounts.kugouLoggedIn(0), isFalse);
    });

    test('upload payload is skipped when nothing is logged in', () async {
      final accounts = AccountStore();
      await accounts.initialize();
      expect(CloudCredentials.payload(accounts), isNull);
    });
  });

  group('cloud sync controller', () {
    late AccountStore accounts;
    late PlayerController player;
    late SiteController site;
    late MemoryStore syncStore;
    late FakeCloud cloud;
    late CloudSyncController sync;
    var now = 1000000;
    var verifyCalls = 0;

    CloudSyncController build() => CloudSyncController(
      site: site,
      player: player,
      store: syncStore,
      verifier: (provider) async {
        verifyCalls++;
        return 'Neko昵称';
      },
      deviceName: () => 'Linux · test',
      clock: () => now,
      debounce: const Duration(milliseconds: 20),
    );

    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await pumpEventQueue(times: 100);
        if (!sync.busy) break;
      }
    }

    setUp(() async {
      now = 1000000;
      verifyCalls = 0;
      cloud = FakeCloud();
      accounts = AccountStore();
      await accounts.initialize();
      player = PlayerController(engine: FakeEngine(), store: MemoryStore());
      await player.initialize();
      site = SiteController(
        accounts: accounts,
        player: player,
        client: SiteClient(transport: cloud.handle),
      );
      syncStore = MemoryStore();
      sync = build();
    });
    tearDown(() async {
      sync.dispose();
      site.dispose();
      await player.flushed;
      player.dispose();
    });

    test(
      'upload overwrites the cloud section and deletions propagate',
      () async {
        await accounts.update(siteToken: token);
        cloud.seed('favorites', [remoteSong('2'), remoteSong('3')]);
        cloud.seed('history', [remoteSong('2')]);
        player.toggleFavorite(localSong('1'));

        await sync.upload({SyncSection.favorites});

        final request = cloud.patches.single;
        expect(request.body!['device'], 'Linux · test');
        expect(request.body!.containsKey('expected'), isFalse);
        final sections = request.body!['sections'] as Map<String, dynamic>;
        expect(sections.keys, ['favorites']);
        expect((sections['favorites'] as List).single['id'], 1);
        expect(cloud.data['history'], hasLength(1));
        expect(sync.error, isNull);
        expect(sync.results.single.ok, isTrue);
        final state = sync.stateOf(SyncSection.favorites);
        expect(state.lastSyncedAt, greaterThan(0));
        expect(
          state.lastRemoteUpdatedAt,
          cloud.meta['favorites']!['updatedAt'],
        );
      },
    );

    test('upload keeps cloud entries this client cannot decode', () async {
      await accounts.update(siteToken: token);
      final foreign = {
        'id': 9,
        'nm': '插件歌曲',
        'source': 'plugin-0123456789abcdef01234567',
        'futureField': {'keep': true},
      };
      cloud.seed('favorites', [remoteSong('2'), foreign]);
      player.toggleFavorite(localSong('1'));

      await sync.upload({SyncSection.favorites});

      final uploaded = cloud.data['favorites'] as List;
      expect(uploaded, hasLength(2));
      expect(uploaded.last, foreign);
    });

    test(
      'pull overwrites the local section and removes extra entries',
      () async {
        await accounts.update(siteToken: token);
        cloud.seed('favorites', [remoteSong('2')]);
        player.toggleFavorite(localSong('1'));
        final history = [...player.history];

        await sync.pull({SyncSection.favorites});

        expect(player.favorites, {'netease:2'});
        expect(player.history, history);
        expect(cloud.patches, isEmpty);
        expect(sync.results.single.ok, isTrue);
        expect(
          sync.stateOf(SyncSection.favorites).lastSyncedAt,
          greaterThan(0),
        );
      },
    );

    test(
      'merge is a union, uploads it and carries the expected value',
      () async {
        await accounts.update(siteToken: token);
        cloud.seed('favorites', [remoteSong('2')], updatedAt: 700);
        player.toggleFavorite(localSong('1'));

        await sync.merge({SyncSection.favorites});

        expect(player.favorites, {'netease:1', 'netease:2'});
        expect(cloud.data['favorites'], hasLength(2));
        expect(cloud.patches.single.body!['expected'], {'favorites': 700});
      },
    );

    test('a failed GET never uploads', () async {
      await accounts.update(siteToken: token);
      cloud.failGet = true;
      player.toggleFavorite(localSong('1'));

      await sync.upload({SyncSection.favorites});
      await sync.merge({SyncSection.favorites});

      expect(cloud.patches, isEmpty);
      expect(sync.error, isNotNull);
      expect(player.favorites, {'netease:1'});
    });

    test('nothing happens without a site login', () async {
      await sync.start();
      player.toggleFavorite(localSong('1'));
      await sync.autoSync();
      await sync.upload({SyncSection.favorites});
      await settle();
      expect(cloud.gets, isEmpty);
      expect(cloud.patches, isEmpty);
      expect(sync.error, isNotNull);
    });

    test(
      'credentials upload is skipped when nothing is logged in locally',
      () async {
        await accounts.update(siteToken: token);
        cloud.seed('credentials', {'ncCookie': 'MUSIC_U=remote'});

        await sync.upload({SyncSection.credentials});

        expect(cloud.patches, isEmpty);
        expect(sync.results.single.ok, isFalse);
        expect(cloud.data['ncCookie'], 'MUSIC_U=remote');
      },
    );

    test(
      'credential pull replaces the local login and verifies the account',
      () async {
        await accounts.update(
          siteToken: token,
          netease: {'MUSIC_U': 'incomplete-old'},
        );
        cloud.seed('credentials', {
          'ncCookie': 'MUSIC_U=abc; JSESSIONID-WYYY=x; __csrf=y',
          'kgCookies': ['token=legacy', ''],
          'kgPlatform': 0,
          'kgToken': 'legacy',
        });

        await sync.pull({SyncSection.credentials});

        expect(accounts.neteaseLoggedIn, isTrue);
        expect(accounts.netease['MUSIC_U'], 'abc');
        expect(accounts.neteaseNickname, 'Neko昵称');
        expect(verifyCalls, greaterThan(0));
        expect(accounts.kugouTokenOnly(0), isTrue);
        final result = sync.results.single;
        expect(result.ok, isTrue);
        expect(result.message, contains('已导入并验证'));
        expect(result.message, contains('没有 userid'));
        expect(
          sync.stateOf(SyncSection.credentials).lastSyncedAt,
          greaterThan(0),
        );
      },
    );

    test(
      'credential pull with an unusable cookie keeps the local login',
      () async {
        await accounts.update(
          siteToken: token,
          netease: {'MUSIC_U': 'local-secret'},
        );
        cloud.seed('credentials', {'ncCookie': 'JSESSIONID-WYYY=x'});

        await sync.pull({SyncSection.credentials});

        expect(accounts.netease['MUSIC_U'], 'local-secret');
        expect(sync.results.single.ok, isFalse);
        expect(sync.results.single.message, contains('没有可导入的有效登录凭据'));
      },
    );

    test(
      'auto sync pulls a newer remote section when local is untouched',
      () async {
        cloud.seed('favorites', [remoteSong('2')]);
        await sync.start();
        await accounts.update(siteToken: token);
        await settle();

        expect(player.favorites, {'netease:2'});
        expect(cloud.patches, isEmpty);
        expect(sync.stateOf(SyncSection.favorites).lastRemoteUpdatedAt, 500);
        expect(sync.conflicts, isEmpty);
      },
    );

    test('auto sync uploads local-only data with the expected value', () async {
      await sync.start();
      player.toggleFavorite(localSong('1'));
      await accounts.update(siteToken: token);
      await settle();

      final request = cloud.patches.single;
      expect(request.body!['expected'], {'favorites': 0});
      expect((cloud.data['favorites'] as List).single['id'], 1);
      expect(sync.statusOf(SyncSection.favorites), SyncStatus.synced);
    });

    test(
      'auto sync leaves a two-sided change alone and reports a conflict',
      () async {
        cloud.seed('favorites', [remoteSong('2')]);
        await sync.start();
        player.toggleFavorite(localSong('1'));
        await accounts.update(siteToken: token);
        await settle();

        expect(cloud.patches, isEmpty);
        expect(player.favorites, {'netease:1'});
        expect(sync.conflicts, [SyncSection.favorites]);
      },
    );

    test('auto sync skips sections whose switch is off', () async {
      cloud.seed('favorites', [remoteSong('2')]);
      await sync.start();
      await sync.setAuto(SyncSection.favorites, false);
      await accounts.update(siteToken: token);
      await settle();

      expect(player.favorites, isEmpty);
      expect(cloud.patches, isEmpty);
    });

    test(
      'a 409 from the optimistic lock does not overwrite the cloud',
      () async {
        cloud.seed('favorites', [remoteSong('2')], updatedAt: 500);
        await sync.start();
        await accounts.update(siteToken: token);
        await settle();
        expect(player.favorites, {'netease:2'});

        cloud.beforePatch = () {
          cloud.meta['favorites'] = {
            'updatedAt': 900,
            'device': 'Android · test',
          };
          cloud.data['favorites'] = [remoteSong('5')];
        };
        now += 1000;
        player.toggleFavorite(localSong('1'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await settle();

        expect(cloud.patches, hasLength(1));
        expect(cloud.data['favorites'], [remoteSong('5')]);
        expect(player.favorites, {'netease:2', 'netease:1'});
        expect(sync.statusOf(SyncSection.favorites), SyncStatus.conflict);
        expect(sync.conflicts, [SyncSection.favorites]);
      },
    );

    test('local changes are debounced into one upload', () async {
      await sync.start();
      await accounts.update(siteToken: token);
      await settle();
      cloud.requests.clear();

      player.toggleFavorite(localSong('1'));
      player.toggleFavorite(localSong('2'));
      player.toggleFavorite(localSong('3'));
      expect(cloud.requests, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await settle();

      expect(cloud.patches, hasLength(1));
      expect((cloud.data['favorites'] as List), hasLength(3));
    });

    test(
      'window focus checks the cloud at most once per throttle window',
      () async {
        await sync.start();
        await accounts.update(siteToken: token);
        await settle();
        cloud.requests.clear();

        now += 10 * 1000;
        sync.onFocus();
        await settle();
        expect(cloud.gets, isEmpty);

        now += 61 * 1000;
        sync.onFocus();
        await settle();
        expect(cloud.gets, hasLength(1));
      },
    );

    test('sync state is persisted and restored', () async {
      await accounts.update(siteToken: token);
      cloud.seed('favorites', [remoteSong('2')]);
      await sync.pull({SyncSection.favorites});
      await sync.setAuto(SyncSection.history, false);
      await pumpEventQueue();

      final restored = build();
      addTearDown(restored.dispose);
      await restored.start();
      expect(restored.stateOf(SyncSection.favorites).lastRemoteUpdatedAt, 500);
      expect(restored.stateOf(SyncSection.history).autoSync, isFalse);
    });
  });
}
