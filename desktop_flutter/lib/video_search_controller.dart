import './i18n/tr.dart';
import 'package:flutter/foundation.dart';

import 'domain/online_music.dart';

typedef VideoSearch =
    Future<SearchVideoPage> Function(
      MusicProvider provider,
      String keyword,
      int page,
    );

class VideoSearchController extends ChangeNotifier {
  VideoSearchController(
    this.searchVideos, {
    this.provider = MusicProvider.netease,
  });
  final VideoSearch searchVideos;
  MusicProvider provider;
  String keyword = '';
  List<MusicVideo> videos = [];
  bool loading = false;
  bool hasMore = false;
  String? error;
  int _page = 0;
  int _generation = 0;
  bool _disposed = false;

  Future<void> search(String query) async {
    final generation = ++_generation;
    keyword = query.trim();
    videos = [];
    hasMore = false;
    _page = 0;
    error = null;
    if (keyword.isEmpty) {
      loading = false;
      _notify();
      return;
    }
    await _load(generation, 1);
  }

  Future<void> selectProvider(MusicProvider value) async {
    if (provider == value) return;
    provider = value;
    await search(keyword);
  }

  Future<void> loadMore() async {
    if (!loading && hasMore) await _load(_generation, _page + 1);
  }

  Future<void> _load(int generation, int page) async {
    if (_disposed) return;
    loading = true;
    error = null;
    _notify();
    try {
      final result = await searchVideos(provider, keyword, page);
      if (_disposed || generation != _generation) return;
      videos = {
        for (final video in videos) video.key: video,
        for (final video in result.videos) video.key: video,
      }.values.toList();
      _page = page;
      hasMore = result.hasMore;
    } catch (failure) {
      if (_disposed || generation != _generation) return;
      error = failure is MusicSearchException
          ? failure.message
          : tr('MV 搜索失败，请稍后重试。');
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
