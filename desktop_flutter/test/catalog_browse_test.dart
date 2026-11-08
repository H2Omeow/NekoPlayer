import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/data/catalog_browse_repository.dart';
import 'package:nekoplayer_desktop/player_controller.dart';
import 'package:nekoplayer_desktop/ui/catalog_browse_page.dart';

import 'comments_test.dart' show CommentCatalog;
import 'fakes.dart';

void main() {
  test(
    'artist, album and playlist searches use correct types and pagination',
    () async {
      final catalog = CommentCatalog();
      final repository = CatalogBrowseRepository(catalog);
      for (final kind in CatalogKind.values) {
        catalog.nc = (path, data) async {
          expect(path, '/api/search/get');
          expect(data['s'], 'Neko');
          expect(data['offset'], 30);
          expect(
            data['type'],
            kind == CatalogKind.artist
                ? 100
                : kind == CatalogKind.album
                ? 10
                : 1000,
          );
          final key = kind == CatalogKind.artist
              ? 'artists'
              : kind == CatalogKind.album
              ? 'albums'
              : 'playlists';
          return {
            'code': 200,
            'result': {
              key: [
                {'id': 1, 'name': 'Neko'},
              ],
            },
          };
        };
        final page = await repository.search(kind, ' Neko ', 2);
        expect(page.items.single.kind, kind);
        expect(page.hasMore, isFalse);
      }
    },
  );

  test(
    'artist songs, albums and public playlists work without an account',
    () async {
      final catalog = CommentCatalog();
      final repository = CatalogBrowseRepository(catalog);
      catalog.nc = (path, data) async {
        if (path == '/api/v6/playlist/detail') {
          return {
            'code': 200,
            'playlist': {
              'trackIds': [
                {'id': 1},
              ],
            },
          };
        }
        return {
          'code': 200,
          'songs': [
            {
              'id': 1,
              'name': 'Song',
              'ar': [
                {'name': 'Neko'},
              ],
            },
          ],
        };
      };
      for (final kind in CatalogKind.values) {
        final page = await repository.songs(
          CatalogItem(id: '1', name: 'Test', kind: kind),
          1,
        );
        expect(page.items.single.artist, 'Neko');
      }
      catalog.nc = (path, data) async => {
        'code': 200,
        'result': {
          'allMatch': [
            {'keyword': 'Neko'},
            {'keyword': 'Neko'},
            {'keyword': 'Player'},
          ],
        },
      };
      expect(await repository.suggestions('N'), ['Neko', 'Player']);
    },
  );

  testWidgets(
    'compact catalog page opens recommendation details without account controls',
    (tester) async {
      tester.view.physicalSize = const Size(480, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final catalog = CommentCatalog();
      await catalog.accounts.initialize();
      catalog.nc = (path, data) async {
        if (path == '/api/personalized/playlist') {
          return {
            'code': 200,
            'result': [
              {'id': 1, 'name': 'Daily'},
            ],
          };
        }
        if (path == '/api/v6/playlist/detail') {
          return {
            'code': 200,
            'playlist': {
              'trackIds': [
                {'id': 1},
              ],
            },
          };
        }
        return {
          'code': 200,
          'songs': [
            {'id': 1, 'name': 'Music'},
          ],
        };
      };
      final player = PlayerController(
        engine: FakeEngine(),
        store: MemoryStore(),
      );
      await player.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogBrowsePage(
            repository: CatalogBrowseRepository(catalog),
            player: player,
            onComments: (_) {},
          ),
        ),
      );
      await tester.tap(find.text('推荐歌单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily'));
      await tester.pumpAndSettle();
      expect(find.text('Music'), findsOneWidget);
      expect(find.text('账号歌单'), findsNothing);
      expect(find.text('保存全部歌曲到本机歌单'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      player.dispose();
    },
  );
}
