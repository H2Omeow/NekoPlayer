import '../i18n/tr.dart';
import 'package:flutter/foundation.dart';

import '../domain/library.dart';
import '../domain/online_music.dart';
import 'account_music_repository.dart';
import 'cloud_library.dart';

enum AccountLibraryDestination { playlist, favorites, history }

class AccountLibrarySync extends ChangeNotifier {
  AccountLibrarySync({required this.sessionKey, required this.merge});

  final String Function() sessionKey;
  final Future<void> Function(Map<String, dynamic>) merge;
  static const maxPages = 2000;
  static const maxSongs = 100000;
  bool busy = false;
  bool committing = false;
  bool cancelled = false;
  bool _disposed = false;
  int count = 0;
  int pages = 0;

  void cancel() {
    if (!busy || committing || cancelled) return;
    cancelled = true;
    _notify();
  }

  Future<int?> run({
    required Future<AccountPage<OnlineSong>> Function(int) load,
    required AccountLibraryDestination destination,
    String playlistId = '',
    String playlistName = '',
  }) async {
    if (_disposed || busy) throw StateError('Library sync unavailable');
    if (destination == AccountLibraryDestination.playlist &&
        (playlistId.isEmpty || playlistName.trim().isEmpty)) {
      throw       FormatException(tr('缺少本机歌单标识或名称。'));
    }
    final account = sessionKey();
    bool stale() => _disposed || cancelled || account != sessionKey();
    busy = true;
    cancelled = false;
    count = 0;
    pages = 0;
    _notify();
    try {
      final songs = <String, Map<String, dynamic>>{};
      for (var page = 1; page <= maxPages; page++) {
        if (stale()) return null;
        final result = await load(page);
        if (stale()) return null;
        for (final song in result.items) {
          final encoded = CloudLibrary.encodeSong(Track.fromOnline(song));
          if (CloudLibrary.decodeSong(encoded)?.path != song.key) {
            throw       FormatException(tr('平台返回的歌曲标识无效，未保存部分结果。'));
          }
          songs.putIfAbsent(song.key, () => encoded);
          if (songs.length > maxSongs) {
            throw       MusicSearchException(tr('歌曲数量超过安全上限，未保存部分结果。'));
          }
        }
        count = songs.length;
        pages = page;
        _notify();
        if (!result.hasMore) {
          if (stale()) return null;
          if (songs.isEmpty) return 0;
          final rows = songs.values.toList();
          committing = true;
          _notify();
          if (stale()) return null;
          await merge(switch (destination) {
            AccountLibraryDestination.favorites => {'favorites': rows},
            AccountLibraryDestination.history => {'history': rows},
            AccountLibraryDestination.playlist => {
              'playlists': [
                {'id': playlistId, 'name': playlistName, 'songs': rows},
              ],
            },
          });
          return count;
        }
      }
      throw       MusicSearchException(tr('平台分页超过安全上限，未保存部分结果。'));
    } catch (_) {
      if (!committing && stale()) return null;
      rethrow;
    } finally {
      committing = false;
      busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancelled = true;
    super.dispose();
  }
}
