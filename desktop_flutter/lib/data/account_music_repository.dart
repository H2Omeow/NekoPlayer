import '../i18n/tr.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../domain/online_music.dart';
import 'native_music_catalog.dart';
import 'native_crypto.dart';

class AccountPlaylist {
  const AccountPlaylist({
    required this.id,
    required this.name,
    this.count = 0,
    this.artist = false,
  });
  final String id;
  final String name;
  final int count;
  final bool artist;
}

class AccountPage<T> {
  const AccountPage(this.items, {this.hasMore = false});
  final List<T> items;
  final bool hasMore;
}

enum AccountCollection {
  playlists,
  likes,
  history,
  recommendations,
  newSongs,
  following,
}

class AccountMusicRepository {
  AccountMusicRepository(this.catalog);
  final NativeMusicCatalog catalog;
  static const pageSize = 50;

  static String text(Object? value) => value?.toString() ?? '';
  static int number(Object? value) => int.tryParse(text(value)) ?? 0;
  static Map<String, dynamic> object(Object? value) =>
      value is Map<String, dynamic> ? value : {};
  static List<Map<String, dynamic>> items(Object? value) =>
      value is List ? value.whereType<Map<String, dynamic>>().toList() : [];

  String get sessionKey => jsonEncode([
    catalog.accounts.netease['MUSIC_U'],
    catalog.accounts.platform,
    catalog.accounts.kugou()['token'],
    catalog.accounts.kugou()['userid'],
  ]);

  void requireAccount(MusicProvider provider) {
    if (provider != MusicProvider.netease && provider != MusicProvider.kugou) {
      throw       MusicSearchException(tr('此页面只支持原生平台账号。'));
    }
    if (provider == MusicProvider.netease
        ? !catalog.accounts.neteaseLoggedIn
        : !catalog.accounts.kugouLoggedIn()) {
      throw       MusicSearchException(tr('请先在平台账号中登录。'));
    }
  }

  Future<Map<String, dynamic>> nc(
    String path,
    Map<String, dynamic> data,
  ) async {
    final body = await catalog.neteaseApi(path, data, weapi: true);
    if (number(body['code']) != 200) {
      throw       MusicSearchException(tr('网易云未确认读取成功，请检查登录状态后重试。'));
    }
    return body;
  }

  Future<String> accountId() async {
    requireAccount(MusicProvider.netease);
    final body = await nc('/api/nuser/account/get', {});
    final id = text(
      object(body['account'])['id'] ?? object(body['profile'])['userId'],
    );
    if (number(id) <= 0) throw       MusicSearchException(tr('未取得网易云账号 ID，请重新登录。'));
    return id;
  }

  Future<AccountPage<AccountPlaylist>> playlists(
    MusicProvider provider,
    int page, {
    bool following = false,
  }) async {
    requireAccount(provider);
    if (page < 1) throw ArgumentError.value(page);
    if (provider == MusicProvider.netease) {
      final body = await nc('/api/user/playlist', {
        'uid': await accountId(),
        'limit': pageSize,
        'offset': (page - 1) * pageSize,
        'includeVideo': true,
      });
      final rows = items(body['playlist']);
      return AccountPage(
        [
          for (final row in rows)
            if (number(row['id']) > 0)
              AccountPlaylist(
                id: text(row['id']),
                name: text(row['name']),
                count: number(row['trackCount']),
              ),
        ],
        hasMore:
            body['more'] == true ||
            rows.length == pageSize && body['more'] != false,
      );
    }
    final session = catalog.accounts.kugou();
    if (following) {
      final body = await catalog.kugouApi(
        '/v4/follow_list',
        {'plat': '1'},
        router: 'relationuser.kugou.com',
        body: {
          'merge': 2,
          'need_iden_type': 1,
          'ext_params': 'k_pic,jumptype,singerid,score',
          'userid': session['userid'],
          'type': 0,
          'id_type': 0,
          'p': NativeCrypto.rsa(
            jsonEncode({
              'clienttime': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              'token': session['token'],
            }),
            catalog.accounts.platform == 1
                ? NativeCrypto.kugouLiteRsa
                : NativeCrypto.kugouRsa,
            padEnd: true,
          ).toUpperCase(),
        },
      );
      final rows = items(kgData(body)['info']);
      return AccountPage([
        for (final row in rows.skip((page - 1) * pageSize).take(pageSize))
          if (number(row['singerid'] ?? row['userid']) > 0)
            AccountPlaylist(
              id: text(row['singerid'] ?? row['userid']),
              name: text(row['singername'] ?? row['nickname']),
              artist: true,
            ),
      ], hasMore: page * pageSize < rows.length);
    }
    final body = await catalog.kugouApi(
      '/v7/get_all_list',
      {'plat': '1', 'userid': session['userid']!, 'token': session['token']!},
      router: 'cloudlist.service.kugou.com',
      body: {
        'userid': session['userid'],
        'token': session['token'],
        'total_ver': 979,
        'type': 2,
        'page': page,
        'pagesize': pageSize,
      },
    );
    final data = kgData(body);
    final rows = items(data['info'] ?? data['list']);
    return AccountPage([
      for (final row in rows)
        if (text(row['global_collection_id']).isNotEmpty)
          AccountPlaylist(
            id: text(row['global_collection_id']),
            name: text(row['name'] ?? row['specialname']),
            count: number(row['count'] ?? row['songcount']),
          ),
    ], hasMore: hasNext(data, page, rows.length));
  }

  static Map<String, dynamic> kgData(Map<String, dynamic> body) {
    if (number(body['status']) != 1 ||
        number(body['error_code'] ?? body['errcode']) != 0) {
      throw       MusicSearchException(tr('酷狗未确认读取成功，请检查账号与设备验证。'));
    }
    return object(body['data']);
  }

  static bool hasNext(Map<String, dynamic> data, int page, int count) {
    final total = number(data['total'] ?? data['total_count']);
    return count > 0 &&
        (total > 0 ? page * pageSize < total : count == pageSize);
  }

  static OnlineSong? neteaseSong(Map<String, dynamic> row) {
    final id = text(row['id']);
    if (number(id) <= 0) return null;
    final album = object(row['al'] ?? row['album']);
    return OnlineSong(
      provider: MusicProvider.netease,
      id: id,
      title: text(row['name']),
      artist: items(
        row['ar'] ?? row['artists'],
      ).map((artist) => text(artist['name'])).join(' / '),
      album: text(album['name']),
      artwork: text(album['picUrl']),
      albumId: text(album['id']),
    );
  }

  static OnlineSong? kugouSong(Map<String, dynamic> row) {
    final hash = text(
      row['FileHash'] ?? row['Hash'] ?? row['hash'],
    ).toLowerCase();
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(hash)) return null;
    // Cloud playlists return a combined "歌手 - 歌名" in `name` and the cover
    // in `cover`; search lists use the other spellings handled below.
    final filename =
        text(
          row['FileName'] ??
              row['filename'] ??
              row['audio_name'] ??
              row['name'],
        ).replaceFirst(
          RegExp(r'\.(mp3|flac|m4a|aac|wav|ogg|ape)$', caseSensitive: false),
          '',
        );
    final separator = filename.indexOf(' - ');
    final audioId = text(
      row['MixSongID'] ??
          row['mixsongid'] ??
          row['album_audio_id'] ??
          row['Audioid'] ??
          row['audio_id'] ??
          row['songid'],
    );
    final title = text(
      row['SongName'] ??
          row['OriSongName'] ??
          row['song_name'] ??
          row['songname'] ??
          row['songName'],
    );
    final artist = text(
      row['SingerName'] ??
          row['singername'] ??
          row['singer_name'] ??
          row['author_name'],
    );
    final album = object(row['albuminfo'] ?? row['album_info']);
    final artwork = text(
      row['Image'] ??
          row['img'] ??
          row['album_img'] ??
          row['cover'] ??
          object(row['trans_param'])['union_cover'],
    ).replaceAll('{size}', '400');
    return OnlineSong(
      provider: MusicProvider.kugou,
      id: number(audioId) > 0
          ? audioId
          : '${int.parse(hash.substring(0, 15), radix: 16)}',
      title: title.isNotEmpty
          ? title
          : separator >= 0
          ? filename.substring(separator + 3)
          : filename,
      artist: artist.isNotEmpty
          ? artist
          : items(row['singerinfo']).isNotEmpty
          ? items(
              row['singerinfo'],
            ).map((singer) => text(singer['name'])).join(' / ')
          : separator >= 0
          ? filename.substring(0, separator)
          : '',
      hash: hash,
      album: text(
        row['AlbumName'] ??
            row['album_name'] ??
            row['albumname'] ??
            album['name'],
      ),
      albumId: text(row['AlbumID'] ?? row['album_id'] ?? row['albumid']),
      artwork: artwork.startsWith('//') ? 'https:$artwork' : artwork,
      albumAudioId: audioId,
    );
  }

  Future<AccountPage<OnlineSong>> songsByIds(List<String> ids, int page) async {
    if (page < 1) throw ArgumentError.value(page);
    final offset = (page - 1) * pageSize;
    final selected = ids.skip(offset).take(pageSize).toList();
    if (selected.isEmpty) return const AccountPage([]);
    final body = await nc('/api/v3/song/detail', {
      'c': jsonEncode([
        for (final id in selected) {'id': id},
      ]),
    });
    final byId = {
      for (final song in items(
        body['songs'],
      ).map(neteaseSong).whereType<OnlineSong>())
        song.id: song,
    };
    return AccountPage([
      for (final id in selected)
        if (byId[id] != null) byId[id]!,
    ], hasMore: offset + pageSize < ids.length);
  }

  Future<AccountPage<OnlineSong>> playlistSongs(
    MusicProvider provider,
    AccountPlaylist playlist,
    int page,
  ) async {
    if (provider != MusicProvider.netease) requireAccount(provider);
    if (page < 1) throw ArgumentError.value(page);
    if (provider == MusicProvider.netease) {
      final body = await nc('/api/v6/playlist/detail', {
        'id': playlist.id,
        'n': 0,
        's': 0,
      });
      final detail = object(body['playlist']);
      if (detail['trackIds'] is! List) {
        throw       MusicSearchException(tr('歌单未返回歌曲清单，可能没有访问权限。'));
      }
      return songsByIds(
        items(
          detail['trackIds'],
        ).map((row) => text(row['id'])).where((id) => number(id) > 0).toList(),
        page,
      );
    }
    if (playlist.artist) {
      final session = catalog.accounts.kugou();
      final lite = catalog.accounts.platform == 1;
      final seconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final appid = lite ? 3116 : 1005;
      final version = lite ? 11440 : 20489;
      final salt = lite
          ? 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA'
          : 'OIlwieks28dk2k092lksi2UIkp';
      final body = await catalog.kugouApi(
        '/kmr/v1/audio_group/author',
        {},
        host: 'openapi.kugou.com',
        extraHeaders: {'kg-tid': '220'},
        body: {
          'appid': appid,
          'clientver': version,
          'mid': session['KUGOU_API_MID'],
          'clienttime': seconds,
          'key': md5
              .convert(utf8.encode('$appid$salt$version$seconds'))
              .toString(),
          'author_id': playlist.id,
          'pagesize': pageSize,
          'page': page,
          'sort': 2,
          'area_code': 'all',
        },
      );
      final data = kgData(body);
      final rows = items(data['info']);
      return AccountPage(
        rows.map(kugouSong).whereType<OnlineSong>().toList(),
        hasMore: hasNext(data, page, rows.length),
      );
    }
    final body = await catalog
        .kugouApi('/pubsongs/v2/get_other_list_file_nofilt', {
          'area_code': '1',
          'begin_idx': '${(page - 1) * pageSize}',
          'plat': '1',
          'type': '1',
          'mode': '1',
          'personal_switch': '1',
          'extend_fields': 'abtags,hot_cmt,popularization',
          'pagesize': '$pageSize',
          'global_collection_id': playlist.id,
        });
    final data = kgData(body);
    final rows = items(data['songs'] ?? data['info']);
    return AccountPage(
      rows.map(kugouSong).whereType<OnlineSong>().toList(),
      hasMore: hasNext(data, page, rows.length),
    );
  }

  Future<AccountPage<OnlineSong>> collection(
    AccountCollection collection,
    int page, {
    MusicProvider provider = MusicProvider.netease,
  }) async {
    if (page < 1) throw ArgumentError.value(page);
    if (provider == MusicProvider.kugou) {
      requireAccount(provider);
      final session = catalog.accounts.kugou();
      final lite = catalog.accounts.platform == 1;
      final now = DateTime.now().millisecondsSinceEpoch;
      final salt = lite
          ? 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA'
          : 'OIlwieks28dk2k092lksi2UIkp';
      final history = collection == AccountCollection.history;
      if (!history && collection != AccountCollection.recommendations) {
        throw       MusicSearchException(tr('此酷狗分类暂不支持。'));
      }
      final body = await catalog.kugouApi(
        history ? '/playhistory/v1/get_songs' : '/v2/personal_recommend',
        {},
        router: history ? '' : 'persnfm.service.kugou.com',
        body: history
            ? {
                'token': session['token'],
                'userid': session['userid'],
                'source_classify': 'app',
                'to_subdivide_sr': 1,
              }
            : {
                'appid': lite ? 3116 : 1005,
                'clienttime': now,
                'mid': session['KUGOU_API_MID'],
                'action': 'play',
                'recommend_source_locked': 0,
                'song_pool_id': 0,
                'callerid': 0,
                'm_type': 1,
                'platform': 'ios',
                'area_code': 1,
                'remain_songcnt': 0,
                'clientver': lite ? 11440 : 20489,
                'is_overplay': 0,
                'mode': 'normal',
                'fakem': 'ca981cfc583a4c37f28d2d49000013c16a0a',
                'key': md5
                    .convert(
                      utf8.encode(
                        '${lite ? 3116 : 1005}$salt${lite ? 11440 : 20489}$now',
                      ),
                    )
                    .toString(),
                'userid': session['userid'],
                'kguid': session['userid'],
                'token': session['token'],
                if ((session['vip_type'] ?? '').isNotEmpty)
                  'vip_type': session['vip_type'],
              },
      );
      final data = kgData(body);
      final rows = items(
        history
            ? data['info'] ?? data['list']
            : data['song_list'] ?? data['lists'],
      );
      return AccountPage(
        rows
            .skip((page - 1) * pageSize)
            .take(pageSize)
            .map(kugouSong)
            .whereType<OnlineSong>()
            .toList(),
        hasMore: history && page * pageSize < rows.length,
      );
    }
    if (collection != AccountCollection.newSongs) {
      requireAccount(MusicProvider.netease);
    }
    if (collection == AccountCollection.likes) {
      final body = await nc('/api/song/like/get', {'uid': await accountId()});
      if (body['ids'] is! List) throw       MusicSearchException(tr('红心歌曲清单格式异常。'));
      return songsByIds(
        (body['ids'] as List).map(text).where((id) => number(id) > 0).toList(),
        page,
      );
    }
    final body = switch (collection) {
      AccountCollection.history => await nc('/api/v1/play/record', {
        'uid': await accountId(),
        'type': 1,
      }),
      AccountCollection.recommendations => await nc(
        '/api/v3/discovery/recommend/songs',
        {},
      ),
      AccountCollection.newSongs => await nc('/api/v1/discovery/new/songs', {
        'areaId': 0,
        'total': true,
      }),
      _ => throw       MusicSearchException(tr('请选择一个歌单。')),
    };
    final rows = switch (collection) {
      AccountCollection.history => items(
        body['weekData'],
      ).map((row) => object(row['song'])).toList(),
      AccountCollection.recommendations => items(
        object(body['data'])['dailySongs'] ?? body['recommend'],
      ),
      _ => items(body['data']),
    };
    final songs = rows.map(neteaseSong).whereType<OnlineSong>().toList();
    return AccountPage(
      songs.skip((page - 1) * pageSize).take(pageSize).toList(),
      hasMore: page * pageSize < songs.length,
    );
  }
}
