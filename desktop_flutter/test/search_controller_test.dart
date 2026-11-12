import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/domain/music_plugin.dart';
import 'package:nekoplayer_desktop/domain/online_music.dart';
import 'package:nekoplayer_desktop/search_controller.dart';

class PendingCatalog implements MusicCatalog {
  final requests = <({MusicProvider provider, String keyword, int page})>[];
  final responses = <Completer<SearchPage>>[];

  @override
  Future<SearchPage> search(MusicProvider provider, String keyword, int page) {
    requests.add((provider: provider, keyword: keyword, page: page));
    final response = Completer<SearchPage>();
    responses.add(response);
    return response.future;
  }
}

class RecommendationCatalog extends PendingCatalog
    implements SearchRecommendations {
  final hotRequests = <MusicProvider>[];
  final suggestionRequests = <String>[];
  List<String> hot = const ['周深', '夜曲'];
  List<String> words = const ['大鱼 周深', '周深'];
  bool fail = false;

  @override
  Future<List<String>> hotSearches(
    MusicProvider provider, {
    MusicPluginSource? source,
  }) async {
    hotRequests.add(provider);
    if (fail) throw const MusicSearchException('网络错误');
    return hot;
  }

  @override
  Future<List<String>> searchSuggestions(
    MusicProvider provider,
    String keyword, {
    MusicPluginSource? source,
  }) async {
    suggestionRequests.add(keyword);
    if (fail) throw const MusicSearchException('网络错误');
    return words;
  }
}

class SlowRecommendationCatalog extends RecommendationCatalog {
  final pendingSuggestions = <Completer<List<String>>>[];

  @override
  Future<List<String>> searchSuggestions(
    MusicProvider provider,
    String keyword, {
    MusicPluginSource? source,
  }) {
    suggestionRequests.add(keyword);
    final response = Completer<List<String>>();
    pendingSuggestions.add(response);
    return response.future;
  }
}

OnlineSong song(String id) => OnlineSong(
  provider: MusicProvider.netease,
  id: id,
  title: id,
  artist: '歌手',
);

void main() {
  late PendingCatalog catalog;
  late SearchController controller;
  setUp(() {
    catalog = PendingCatalog();
    controller = SearchController(catalog);
  });
  tearDown(() => controller.dispose());

  test('empty search does not issue a request', () async {
    await controller.search('  ');
    expect(catalog.requests, isEmpty);
  });

  test('new search supersedes an older response', () async {
    final old = controller.search('old');
    final latest = controller.search(' latest ');
    catalog.responses[1].complete(
      SearchPage(songs: [song('new')], hasMore: false),
    );
    await latest;
    catalog.responses[0].complete(
      SearchPage(songs: [song('old')], hasMore: true),
    );
    await old;
    expect(controller.keyword, 'latest');
    expect(controller.songs.single.id, 'new');
    expect(controller.hasMore, isFalse);
  });

  test('switching source discards pending result and resets state', () async {
    final pending = controller.search('music');
    controller.selectProvider(MusicProvider.kugou);
    catalog.responses.single.complete(
      SearchPage(songs: [song('old')], hasMore: true),
    );
    await pending;
    expect(controller.songs, isEmpty);
    expect(controller.loading, isFalse);
    expect(controller.keyword, isEmpty);
    final search = controller.search('new');
    expect(catalog.requests.last.provider, MusicProvider.kugou);
    expect(catalog.requests.last.page, 1);
    catalog.responses.last.complete(
      const SearchPage(songs: [], hasMore: false),
    );
    await search;
  });

  test(
    'pagination deduplicates and retries the same page after failure',
    () async {
      final initial = controller.search('music');
      catalog.responses.last.complete(
        SearchPage(songs: [song('1')], hasMore: true),
      );
      await initial;
      final failed = controller.loadMore();
      await controller.loadMore();
      expect(catalog.requests, hasLength(2));
      catalog.responses.last.completeError(const MusicSearchException('网络错误'));
      await failed;
      expect(controller.error, '网络错误');
      expect(controller.songs, hasLength(1));
      final retry = controller.loadMore();
      expect(catalog.requests.last.page, 2);
      catalog.responses.last.complete(
        SearchPage(songs: [song('1'), song('2')], hasMore: false),
      );
      await retry;
      expect(controller.songs.map((song) => song.id), ['1', '2']);
      expect(controller.error, isNull);
      await controller.loadMore();
      expect(catalog.requests, hasLength(3));
    },
  );

  test('disposed controller ignores a pending completion', () async {
    final temporary = SearchController(catalog);
    final pending = temporary.search('music');
    temporary.dispose();
    catalog.responses.last.complete(
      SearchPage(songs: [song('1')], hasMore: true),
    );
    await pending;
    expect(temporary.songs, isEmpty);
  });

  test('hot searches load per source and failures clear them', () async {
    final recommendations = RecommendationCatalog();
    final search = SearchController(recommendations);
    addTearDown(search.dispose);
    await search.loadHotSearches();
    expect(search.hotSearches, ['周深', '夜曲']);
    search.selectProvider(MusicProvider.kugou);
    expect(search.hotSearches, isEmpty);
    await search.loadHotSearches();
    expect(recommendations.hotRequests.last, MusicProvider.kugou);
    expect(search.hotSearches, ['周深', '夜曲']);
    recommendations.fail = true;
    await search.loadHotSearches();
    expect(search.hotSearches, isEmpty);
  });

  test('suggestions debounce and clear on source changes', () async {
    final recommendations = RecommendationCatalog();
    final search = SearchController(recommendations);
    addTearDown(search.dispose);
    search.suggest('周');
    expect(recommendations.suggestionRequests, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(recommendations.suggestionRequests, ['周']);
    expect(search.suggestions, ['大鱼 周深', '周深']);
    search.suggest('  ');
    expect(search.suggestions, isEmpty);
    search.suggest('夜');
    search.selectProvider(MusicProvider.kugou);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(recommendations.suggestionRequests, ['周']);
    expect(search.suggestions, isEmpty);
  });

  test('search cancels a pending suggestion request', () async {
    final recommendations = RecommendationCatalog();
    final search = SearchController(recommendations);
    addTearDown(search.dispose);
    search.suggest('周');
    final pending = search.search('夜曲');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(recommendations.suggestionRequests, isEmpty);
    expect(search.suggestions, isEmpty);
    recommendations.responses.single.complete(
      const SearchPage(songs: [], hasMore: false),
    );
    await pending;
  });

  test('a stale suggestion response does not replace newer words', () async {
    final recommendations = SlowRecommendationCatalog();
    final search = SearchController(recommendations);
    addTearDown(search.dispose);
    search.suggest('a');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    search.suggest('b');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(recommendations.pendingSuggestions, hasLength(2));
    recommendations.pendingSuggestions[1].complete(['b']);
    await Future<void>.delayed(Duration.zero);
    expect(search.suggestions, ['b']);
    recommendations.pendingSuggestions[0].complete(['a']);
    await Future<void>.delayed(Duration.zero);
    expect(search.suggestions, ['b']);
  });

  test('catalogs without recommendations ignore suggestion requests', () async {
    controller.suggest('周');
    await controller.loadHotSearches();
    expect(controller.suggestions, isEmpty);
    expect(controller.hotSearches, isEmpty);
  });
}
