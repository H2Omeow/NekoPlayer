import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/domain/online_music.dart';
import 'package:nekoplayer_desktop/search_controller.dart' as online;
import 'package:nekoplayer_desktop/ui/neko_theme.dart';
import 'package:nekoplayer_desktop/ui/online_search_page.dart';

class TestCatalog implements MusicCatalog {
  final pages = <int>[];
  bool fail = false;

  @override
  Future<SearchPage> search(
    MusicProvider provider,
    String keyword,
    int page,
  ) async {
    pages.add(page);
    if (fail) throw const MusicSearchException('网络错误，请重试。');
    return SearchPage(
      songs: [
        OnlineSong(
          provider: provider,
          id: '$page',
          title: '$keyword $page',
          artist: '歌手',
        ),
      ],
      hasMore: page == 1,
    );
  }
}

void main() {
  testWidgets(
    'online results expose favorite toggle and local playlist actions without playing',
    (tester) async {
      final controller = online.SearchController(TestCatalog());
      addTearDown(controller.dispose);
      final favorites = <String>{};
      OnlineSong? selected;
      var plays = 0;
      await controller.search('Neko');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OnlineSearchPage(
              controller: controller,
              onPlay: (_, _) => plays++,
              isFavorite: (song) => favorites.contains(song.key),
              onFavorite: (song) {
                if (!favorites.remove(song.key)) favorites.add(song.key);
              },
              onPlaylist: (song) => selected = song,
            ),
          ),
        ),
      );
      for (final action in ['收藏', '取消收藏', '添加到歌单…']) {
        await tester.tap(find.byTooltip('歌曲操作'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
      }
      expect(favorites, isEmpty);
      expect(selected?.id, '1');
      expect(plays, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('submit, paginate and switch sources without network access', (
    tester,
  ) async {
    final catalog = TestCatalog();
    final controller = online.SearchController(catalog);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: nekoTheme(),
        home: Scaffold(body: OnlineSearchPage(controller: controller)),
      ),
    );
    await tester.enterText(find.byType(TextField), '夜晚');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('夜晚 1'), findsOneWidget);
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(catalog.pages, [1, 2]);
    expect(find.text('夜晚 2'), findsOneWidget);
    await tester.tap(find.text('酷狗'));
    await tester.pumpAndSettle();
    expect(find.text('夜晚 1'), findsNothing);
    catalog.fail = true;
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('网络错误，请重试。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact discovery page fits large system text', (tester) async {
    tester.view.physicalSize = const Size(360, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = online.SearchController(TestCatalog());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: nekoTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(body: OnlineSearchPage(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
