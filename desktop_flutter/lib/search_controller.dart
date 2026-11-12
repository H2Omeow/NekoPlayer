import './i18n/tr.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'domain/online_music.dart';
import 'domain/music_plugin.dart';

class SearchController extends ChangeNotifier {
  SearchController(this.catalog);

  final MusicCatalog catalog;
  MusicProvider provider = MusicProvider.netease;
  MusicPluginSource? pluginSource;
  List<OnlineSong> songs = [];
  List<String> hotSearches = const [];
  List<String> suggestions = const [];
  String keyword = '';
  String? error;
  bool loading = false;
  bool hasMore = false;
  int _page = 0;
  int _request = 0;
  int _suggestRequest = 0;
  int _hotRequest = 0;
  Timer? _suggestTimer;
  bool _disposed = false;

  SearchRecommendations? get _recommendations =>
      catalog is SearchRecommendations
      ? catalog as SearchRecommendations
      : null;

  void selectProvider(MusicProvider value) {
    if (value == provider && pluginSource == null || _disposed) return;
    _request++;
    _suggestTimer?.cancel();
    _suggestRequest++;
    _hotRequest++;
    provider = value;
    pluginSource = null;
    songs = [];
    hotSearches = const [];
    suggestions = const [];
    keyword = '';
    error = null;
    loading = false;
    hasMore = false;
    _page = 0;
    notifyListeners();
  }

  void selectPlugin(MusicPluginSource source) {
    if (_disposed || pluginSource?.id == source.id) return;
    selectProvider(MusicProvider.netease);
    _request++;
    _suggestTimer?.cancel();
    _suggestRequest++;
    _hotRequest++;
    provider = MusicProvider.values.firstWhere(
      (item) => item.gateway == source.platform,
    );
    pluginSource = source;
    songs = [];
    hotSearches = const [];
    suggestions = const [];
    keyword = '';
    error = null;
    loading = false;
    hasMore = false;
    _page = 0;
    notifyListeners();
  }

  /// Loads the words shown while the search field is empty. Only the newest
  /// request may update the state; failures leave the page usable.
  Future<void> loadHotSearches() async {
    final recommendations = _recommendations;
    if (_disposed || recommendations == null) return;
    final request = ++_hotRequest;
    try {
      final words = await recommendations.hotSearches(
        provider,
        source: pluginSource,
      );
      if (_disposed ||
          request != _hotRequest ||
          listEquals(words, hotSearches)) {
        return;
      }
      hotSearches = words;
      notifyListeners();
    } catch (_) {
      if (_disposed || request != _hotRequest || hotSearches.isEmpty) return;
      hotSearches = const [];
      notifyListeners();
    }
  }

  /// Requests type-ahead keywords after a short pause. Empty input and
  /// catalogs without recommendation support clear the current chips.
  void suggest(String value) {
    _suggestTimer?.cancel();
    final request = ++_suggestRequest;
    final recommendations = _recommendations;
    final query = value.trim();
    if (_disposed ||
        recommendations == null ||
        query.isEmpty ||
        query.length > 200) {
      if (suggestions.isNotEmpty) {
        suggestions = const [];
        notifyListeners();
      }
      return;
    }
    _suggestTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        final words = await recommendations.searchSuggestions(
          provider,
          query,
          source: pluginSource,
        );
        if (_disposed ||
            request != _suggestRequest ||
            listEquals(words, suggestions)) {
          return;
        }
        suggestions = words;
        notifyListeners();
      } catch (_) {
        if (_disposed || request != _suggestRequest || suggestions.isEmpty) {
          return;
        }
        suggestions = const [];
        notifyListeners();
      }
    });
  }

  Future<void> search(String value) => _load(value.trim(), next: false);
  Future<void> loadMore() =>
      loading || !hasMore ? Future.value() : _load(keyword, next: true);

  Future<void> _load(String value, {required bool next}) async {
    if (_disposed || value.isEmpty) return;
    final request = ++_request;
    final page = next ? _page + 1 : 1;
    if (!next) {
      _suggestTimer?.cancel();
      _suggestRequest++;
      keyword = value;
      songs = [];
      suggestions = const [];
      hasMore = false;
      _page = 0;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final source = pluginSource;
      final result = source == null
          ? await catalog.search(provider, value, page)
          : await (catalog as PluginMusicCatalog).searchPlugin(
              source,
              value,
              page,
            );
      if (_disposed || request != _request) return;
      songs = {
        for (final song in [...songs, ...result.songs]) song.key: song,
      }.values.toList();
      _page = page;
      hasMore = result.hasMore;
    } catch (failure) {
      if (_disposed || request != _request) return;
      error = failure is MusicSearchException
          ? failure.message
          : tr('搜索未完成，请稍后重试。');
    } finally {
      if (!_disposed && request == _request) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _suggestTimer?.cancel();
    _suggestRequest++;
    _hotRequest++;
    super.dispose();
  }
}
