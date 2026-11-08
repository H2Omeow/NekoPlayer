import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/data/account_library_sync.dart';
import 'package:nekoplayer_desktop/data/account_music_repository.dart';
import 'package:nekoplayer_desktop/data/cloud_library.dart';
import 'package:nekoplayer_desktop/domain/library.dart';
import 'package:nekoplayer_desktop/domain/online_music.dart';
import 'package:nekoplayer_desktop/player_controller.dart';

import 'fakes.dart';

OnlineSong song(String id) => OnlineSong(
  provider: MusicProvider.netease,
  id: id,
  title: 'Song $id',
  artist: 'Neko',
);

void main() {
  late String account;
  late List<Map<String, dynamic>> writes;
  late AccountLibrarySync sync;

  setUp(() {
    account = 'first-account';
    writes = [];
    sync = AccountLibrarySync(
      sessionKey: () => account,
      merge: (body) async => writes.add(body),
    );
  });

  tearDown(() => sync.dispose());

  test(
    'serially reads every page and merges ordered unique favorites once',
    () async {
      var active = 0;
      final requested = <int>[];
      final count = await sync.run(
        destination: AccountLibraryDestination.favorites,
        load: (page) async {
          active++;
          expect(active, 1);
          expect(writes, isEmpty);
          requested.add(page);
          await Future<void>.delayed(Duration.zero);
          active--;
          return page == 1
              ? AccountPage([song('1'), song('2')], hasMore: true)
              : AccountPage([song('2'), song('3')]);
        },
      );
      expect(requested, [1, 2]);
      expect(count, 3);
      expect(sync.count, 3);
      expect(sync.pages, 2);
      expect(sync.busy, isFalse);
      // Cloud rows are newest first (like Android); the local set keeps
      // insertion order, oldest first.
      expect(CloudLibrary.decode(writes.single).favorites, [
        'netease:3',
        'netease:2',
        'netease:1',
      ]);
    },
  );

  test('empty unavailable-song pages do not truncate later results', () async {
    await sync.run(
      destination: AccountLibraryDestination.history,
      load: (page) async => page == 1
          ? const AccountPage([], hasMore: true)
          : AccountPage([song('3')]),
    );
    expect(CloudLibrary.decode(writes.single).history, ['netease:3']);
    expect(writes.single.containsKey('favorites'), isFalse);
  });

  test('failed later page retains the entire local library', () async {
    await expectLater(
      sync.run(
        destination: AccountLibraryDestination.favorites,
        load: (page) async {
          if (page == 2) throw StateError('network failed');
          return AccountPage([song('1')], hasMore: true);
        },
      ),
      throwsStateError,
    );
    expect(writes, isEmpty);
    expect(sync.busy, isFalse);
  });

  test(
    'cancelled requests never merge and cannot overlap a second sync',
    () async {
      final pending = Completer<AccountPage<OnlineSong>>();
      final operation = sync.run(
        destination: AccountLibraryDestination.favorites,
        load: (_) => pending.future,
      );
      sync.cancel();
      await expectLater(
        sync.run(
          destination: AccountLibraryDestination.history,
          load: (_) async => AccountPage([song('9')]),
        ),
        throwsStateError,
      );
      pending.complete(AccountPage([song('1')]));
      expect(await operation, isNull);
      expect(writes, isEmpty);
      expect(sync.busy, isFalse);
      expect(
        await sync.run(
          destination: AccountLibraryDestination.history,
          load: (_) async => AccountPage([song('2')]),
        ),
        1,
      );
      expect(writes, hasLength(1));
    },
  );

  test(
    'account switches during page reads discard all pending results',
    () async {
      final pending = Completer<AccountPage<OnlineSong>>();
      final operation = sync.run(
        destination: AccountLibraryDestination.favorites,
        load: (_) => pending.future,
      );
      account = 'second-account';
      pending.complete(AccountPage([song('1')]));
      expect(await operation, isNull);
      expect(writes, isEmpty);
    },
  );

  test(
    'a failed request after cancellation is treated as cancelled, not saved',
    () async {
      final pending = Completer<AccountPage<OnlineSong>>();
      final operation = sync.run(
        destination: AccountLibraryDestination.favorites,
        load: (_) => pending.future,
      );
      sync.cancel();
      pending.completeError(StateError('request aborted'));
      expect(await operation, isNull);
      expect(writes, isEmpty);
    },
  );

  test(
    'disposing an in-flight reader prevents writes and future operations',
    () async {
      final pending = Completer<AccountPage<OnlineSong>>();
      final old = sync;
      final operation = old.run(
        destination: AccountLibraryDestination.favorites,
        load: (_) => pending.future,
      );
      old.dispose();
      sync = AccountLibrarySync(
        sessionKey: () => account,
        merge: (body) async => writes.add(body),
      );
      pending.complete(AccountPage([song('1')]));
      expect(await operation, isNull);
      expect(writes, isEmpty);
      await expectLater(
        old.run(
          destination: AccountLibraryDestination.favorites,
          load: (_) async => const AccountPage([]),
        ),
        throwsStateError,
      );
    },
  );

  test('cancellation from progress callback prevents final commit', () async {
    sync.addListener(() {
      if (sync.pages > 0) sync.cancel();
    });
    expect(
      await sync.run(
        destination: AccountLibraryDestination.favorites,
        load: (_) async => AccountPage([song('1')]),
      ),
      isNull,
    );
    expect(writes, isEmpty);
  });

  test('unbounded server pagination fails without partial writes', () async {
    await expectLater(
      sync.run(
        destination: AccountLibraryDestination.favorites,
        load: (_) async => const AccountPage([], hasMore: true),
      ),
      throwsA(isA<MusicSearchException>()),
    );
    expect(sync.pages, AccountLibrarySync.maxPages);
    expect(writes, isEmpty);
  });

  test(
    'an account change from commit notification is checked before merge',
    () async {
      sync.addListener(() {
        if (sync.committing) account = 'other-account';
      });
      expect(
        await sync.run(
          destination: AccountLibraryDestination.favorites,
          load: (_) async => AccountPage([song('1')]),
        ),
        isNull,
      );
      expect(writes, isEmpty);
    },
  );

  test(
    'invalid identifiers reject all results and empty lists do not write',
    () async {
      await expectLater(
        sync.run(
          destination: AccountLibraryDestination.favorites,
          load: (_) async => AccountPage([song('1'), song('not-a-song')]),
        ),
        throwsFormatException,
      );
      expect(writes, isEmpty);
      expect(
        await sync.run(
          destination: AccountLibraryDestination.favorites,
          load: (_) async => const AccountPage([]),
        ),
        0,
      );
      expect(writes, isEmpty);
    },
  );

  test(
    'merge failures propagate and commit cannot claim cancellation',
    () async {
      sync.dispose();
      sync = AccountLibrarySync(
        sessionKey: () => account,
        merge: (_) async {
          expect(sync.committing, isTrue);
          sync.cancel();
          expect(sync.cancelled, isFalse);
          throw StateError('disk full');
        },
      );
      await expectLater(
        sync.run(
          destination: AccountLibraryDestination.favorites,
          load: (_) async => AccountPage([song('1')]),
        ),
        throwsStateError,
      );
      expect(sync.busy, isFalse);
      expect(sync.committing, isFalse);
    },
  );

  test(
    'playlist sync preserves local favorites, history and paused playback',
    () async {
      final engine = FakeEngine();
      final store = MemoryStore();
      final player = PlayerController(engine: engine, store: store);
      await player.initialize();
      sync.dispose();
      sync = AccountLibrarySync(
        sessionKey: () => account,
        merge: player.mergeCloud,
      );
      try {
        player.toggleFavorite(Track.fromOnline(song('9')));
        await sync.run(
          destination: AccountLibraryDestination.playlist,
          playlistId: 'account-netease-123',
          playlistName: 'Cloud playlist',
          load: (page) async =>
              AccountPage([song('$page')], hasMore: page == 1),
        );
        expect(player.playlists.single.paths, ['netease:1', 'netease:2']);
        expect(player.favorites, {'netease:9'});
        expect(player.history, isEmpty);
        expect(player.queue, isEmpty);
        expect(engine.playing, isFalse);
        final saved = LibraryData.decode(store.value!);
        expect(saved.playlists.single.paths, ['netease:1', 'netease:2']);
        await sync.run(
          destination: AccountLibraryDestination.history,
          load: (_) async => AccountPage([song('3'), song('4')]),
        );
        expect(player.history, ['netease:3', 'netease:4']);
        expect(player.favorites, {'netease:9'});
      } finally {
        await player.flushed;
        player.dispose();
      }
    },
  );
}
