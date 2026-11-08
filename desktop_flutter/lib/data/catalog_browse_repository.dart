import '../i18n/tr.dart';
import '../domain/online_music.dart';
import 'account_music_repository.dart';
import 'native_music_catalog.dart';

enum CatalogKind { artist, album, playlist }

class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.name,
    required this.kind,
    this.subtitle = '',
    this.count = 0,
  });
  final String id;
  final String name;
  final CatalogKind kind;
  final String subtitle;
  final int count;
}

class CatalogBrowseRepository {
  CatalogBrowseRepository(this.catalog)
    : music = AccountMusicRepository(catalog);
  final NativeMusicCatalog catalog;
  final AccountMusicRepository music;
  static const pageSize = 30;

  Future<AccountPage<CatalogItem>> search(
    CatalogKind kind,
    String keyword,
    int page,
  ) async {
    if (page < 1) throw ArgumentError.value(page);
    final query = keyword.trim();
    if (query.isEmpty || query.length > 200) {
      throw       MusicSearchException(tr('请输入 1–200 字的搜索关键词。'));
    }
    final body = await catalog.neteaseApi('/api/search/get', {
      's': query,
      'type': kind == CatalogKind.artist
          ? 100
          : kind == CatalogKind.album
          ? 10
          : 1000,
      'limit': pageSize,
      'offset': (page - 1) * pageSize,
    });
    if (AccountMusicRepository.number(body['code']) != 200) {
      throw       MusicSearchException(tr('分类搜索失败，请稍后重试。'));
    }
    final result = AccountMusicRepository.object(body['result']);
    final key = kind == CatalogKind.artist
        ? 'artists'
        : kind == CatalogKind.album
        ? 'albums'
        : 'playlists';
    final rows = AccountMusicRepository.items(result[key]);
    final total = AccountMusicRepository.number(
      result[kind == CatalogKind.artist
          ? 'artistCount'
          : kind == CatalogKind.album
          ? 'albumCount'
          : 'playlistCount'],
    );
    return AccountPage(
      rows.map((row) => item(kind, row)).whereType<CatalogItem>().toList(),
      hasMore:
          rows.isNotEmpty &&
          (total > 0 ? page * pageSize < total : rows.length == pageSize),
    );
  }

  static CatalogItem? item(CatalogKind kind, Map<String, dynamic> row) {
    final id = AccountMusicRepository.text(row['id']);
    if (AccountMusicRepository.number(id) <= 0) return null;
    return CatalogItem(
      id: id,
      name: AccountMusicRepository.text(row['name']),
      kind: kind,
      subtitle: AccountMusicRepository.text(
        AccountMusicRepository.object(row['artist'])['name'] ??
            AccountMusicRepository.object(row['creator'])['nickname'],
      ),
      count: AccountMusicRepository.number(
        row['trackCount'] ?? row['size'] ?? row['musicSize'],
      ),
    );
  }

  Future<AccountPage<CatalogItem>> recommendedPlaylists() async {
    final body = await music.nc('/api/personalized/playlist', {
      'limit': pageSize,
      'total': true,
      'n': 1000,
    });
    return AccountPage(
      AccountMusicRepository.items(body['result'])
          .map((row) => item(CatalogKind.playlist, row))
          .whereType<CatalogItem>()
          .toList(),
    );
  }

  Future<AccountPage<OnlineSong>> songs(CatalogItem selection, int page) async {
    if (page < 1) throw ArgumentError.value(page);
    if (AccountMusicRepository.number(selection.id) <= 0) {
      throw       MusicSearchException(tr('分类内容 ID 无效。'));
    }
    if (selection.kind == CatalogKind.playlist) {
      return music.playlistSongs(
        MusicProvider.netease,
        AccountPlaylist(id: selection.id, name: selection.name),
        page,
      );
    }
    final body = selection.kind == CatalogKind.artist
        ? await music.nc('/api/artist/top/song', {'id': selection.id})
        : await music.nc('/api/v1/album/${selection.id}', {});
    final songs = AccountMusicRepository.items(
      body['songs'],
    ).map(AccountMusicRepository.neteaseSong).whereType<OnlineSong>().toList();
    return AccountPage(
      songs
          .skip((page - 1) * AccountMusicRepository.pageSize)
          .take(AccountMusicRepository.pageSize)
          .toList(),
      hasMore: page * AccountMusicRepository.pageSize < songs.length,
    );
  }

  Future<List<String>> suggestions(String keyword) async {
    if (keyword.trim().isEmpty || keyword.length > 200) return [];
    final body = await music.nc('/api/search/suggest/web', {
      's': keyword.trim(),
    });
    final result = AccountMusicRepository.object(body['result']);
    return AccountMusicRepository.items(result['allMatch'])
        .map((row) => AccountMusicRepository.text(row['keyword']))
        .where((word) => word.isNotEmpty)
        .toSet()
        .take(8)
        .toList();
  }
}
