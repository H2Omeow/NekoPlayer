import './i18n/tr.dart';
import 'package:flutter/foundation.dart';

import 'domain/online_music.dart';
import 'domain/music_plugin.dart';

class SearchController extends ChangeNotifier {
  SearchController(this.catalog);

  final MusicCatalog catalog;
  MusicProvider provider = MusicProvider.netease;
  MusicPluginSource? pluginSource;
  List<OnlineSong> songs = [];
  String keyword = '';
  String? error;
  bool loading = false;
  bool hasMore = false;
  int _page = 0;
  int _request = 0;
  bool _disposed = false;

  void selectProvider(MusicProvider value) {
    if (value == provider && pluginSource == null || _disposed) return;
    _request++;
    provider = value;
    pluginSource = null;
    songs = [];
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
    provider = MusicProvider.values.firstWhere(
      (item) => item.gateway == source.platform,
    );
    pluginSource = source;
    songs = [];
    keyword = '';
    error = null;
    loading = false;
    hasMore = false;
    _page = 0;
    notifyListeners();
  }

  Future<void> search(String value) => _load(value.trim(), next: false);
  Future<void> loadMore() =>
      loading || !hasMore ? Future.value() : _load(keyword, next: true);

  Future<void> _load(String value, {required bool next}) async {
    if (_disposed || value.isEmpty) return;
    final request = ++_request;
    final page = next ? _page + 1 : 1;
    if (!next) {
      keyword = value;
      songs = [];
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
    super.dispose();
  }
}
