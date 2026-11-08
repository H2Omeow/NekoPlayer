import '../i18n/tr.dart';
import '../domain/library.dart';
import '../domain/online_music.dart';
import '../domain/music_plugin.dart';

class CloudLibrary {
  static const historyLimit = 200;

  static List<Map<String, dynamic>> items(Object? value) =>
      value is List ? value.whereType<Map<String, dynamic>>().toList() : [];

  static String songKey(Map<String, dynamic> song) {
    final identity =
        [song['providerMediaId'], song['hash'], song['id']]
            .map((value) => value?.toString() ?? '')
            .where((value) => value.isNotEmpty)
            .firstOrNull ??
        '';
    final source = song['source'] ?? 'netease';
    return '$source:${source == 'kugou' ? identity.toLowerCase() : identity}';
  }

  static Track? decodeSong(Map<String, dynamic> song) {
    final source = song['source'] ?? 'netease';
    MusicPluginSource? plugin;
    if (song['pluginSource'] is Map<String, dynamic>) {
      try {
        plugin = MusicPluginSource.fromJson(
          song['pluginSource'] as Map<String, dynamic>,
          reference: true,
        );
      } catch (_) {
        return null;
      }
    }
    final provider =
        MusicProvider.values
            .where((provider) => provider.sourceId == source)
            .firstOrNull ??
        (plugin != null ? MusicProvider.gatewayKugou : null);
    if (provider == null) return null;
    final id = song['id']?.toString() ?? '';
    final rawHash = song['hash']?.toString() ?? '';
    final hash = source == 'kugou' ? rawHash.toLowerCase() : rawHash;
    if (source == 'netease' && !RegExp(r'^\d+$').hasMatch(id)) return null;
    if (source == 'kugou' && !RegExp(r'^[a-f0-9]{32}$').hasMatch(hash)) {
      return null;
    }
    return Track.fromOnline(
      OnlineSong(
        provider: provider,
        id: provider.gateway == null
            ? id
            : (song['providerMediaId']?.toString().isNotEmpty ?? false)
            ? song['providerMediaId'].toString()
            : hash.isNotEmpty
            ? hash
            : id,
        hash: hash,
        title: song['nm']?.toString() ?? '',
        artist: song['ar']?.toString() ?? '',
        albumId: song['albumId']?.toString() ?? '',
        albumAudioId: song['albumAudioId']?.toString() ?? '0',
        artwork: song['pc']?.toString() ?? '',
        pluginSource: plugin,
        pluginData: Map<String, dynamic>.from(song['pluginData'] as Map? ?? {}),
      ),
    );
  }

  static Map<String, dynamic> encodeSong(Track track) {
    final song = track.online!;
    return {
      'id':
          int.tryParse(song.id) ??
          (song.hash.isEmpty
              ? 0
              : int.tryParse(
                      song.hash.substring(0, song.hash.length.clamp(0, 15)),
                      radix: 16,
                    ) ??
                    0),
      'nm': song.title,
      'ar': song.artist,
      'source': song.pluginSource?.id ?? song.provider.sourceId,
      'hash': song.hash,
      'albumId': song.albumId,
      'albumAudioId': int.tryParse(song.albumAudioId) ?? 0,
      if (song.artwork.isNotEmpty) 'pc': song.artwork,
      if (song.provider.gateway != null) ...{
        'providerSource': song.provider.gateway,
        'providerMediaId': song.id,
      },
      if (song.pluginSource != null)
        'pluginSource': song.pluginSource!.toJson(includeScript: false),
      if (song.pluginData.isNotEmpty) 'pluginData': song.pluginData,
    };
  }

  static LibraryData decode(Map<String, dynamic> body) {
    for (final key in ['favorites', 'history', 'playlists']) {
      final value = body[key];
      if (value != null &&
          (value is! List ||
              value.any((item) => item is! Map<String, dynamic>))) {
        throw       FormatException(tr('云端音乐库格式异常。'));
      }
    }
    for (final playlist in items(body['playlists'])) {
      final songs = playlist['songs'];
      if (songs != null &&
          (songs is! List ||
              songs.any((song) => song is! Map<String, dynamic>))) {
        throw       FormatException(tr('云端歌单格式异常。'));
      }
    }
    final tracks = <String, Track>{};
    List<String> collect(Object? value) {
      final selected = <String>[];
      for (final song in items(value)) {
        final track = decodeSong(song);
        if (track == null) continue;
        tracks[track.path] = track;
        selected.add(track.path);
      }
      return selected.toSet().toList();
    }

    // 云端收藏最近在前，本机集合按加入顺序保存。
    final favorites = collect(body['favorites']).reversed.toSet();
    final history = collect(body['history']).take(historyLimit).toList();
    final playlists = [
      for (final playlist in items(body['playlists']))
        if ((playlist['id']?.toString() ?? '').isNotEmpty)
          LocalPlaylist(
            id: playlist['id'].toString(),
            name: playlist['name']?.toString() ?? tr('云端歌单'),
            paths: collect(playlist['songs']),
          ),
    ];
    return LibraryData(
      tracks: tracks.values.toList(),
      favorites: favorites,
      history: history,
      playlists: playlists,
    );
  }

  static LibraryData merge(LibraryData local, LibraryData remote) {
    final tracks = {
      for (final track in remote.tracks) track.path: track,
      for (final track in local.tracks) track.path: track,
    };
    final playlists = {
      for (final playlist in local.playlists) playlist.id: playlist,
    };
    for (final remotePlaylist in remote.playlists) {
      final current = playlists[remotePlaylist.id];
      playlists[remotePlaylist.id] = current == null
          ? remotePlaylist
          : current.withPaths(
              {...current.paths, ...remotePlaylist.paths}.toList(),
            );
    }
    return LibraryData(
      tracks: tracks.values.toList(),
      favorites: {...local.favorites, ...remote.favorites},
      history: {
        ...local.history,
        ...remote.history,
      }.take(historyLimit).toList(),
      playlists: playlists.values.toList(),
      volume: local.volume,
      rate: local.rate,
      preferredQuality: local.preferredQuality,
      showTranslation: local.showTranslation,
      doubleLyrics: local.doubleLyrics,
      repeatMode: local.repeatMode,
      session: local.session,
    );
  }

  static List<Map<String, dynamic>> _songs(
    LibraryData local,
    Iterable<String> keys,
  ) {
    final tracks = {for (final track in local.tracks) track.path: track};
    return keys
        .map((key) => tracks[key])
        .whereType<Track>()
        .where((track) => track.online != null)
        .map(encodeSong)
        .toList();
  }

  static List<Map<String, dynamic>> _union(
    List<Map<String, dynamic>> preferred,
    List<Map<String, dynamic>> previous,
  ) {
    final byKey = {for (final song in previous) songKey(song): song};
    final preferredByKey = {for (final song in preferred) songKey(song): song};
    return [
      for (final key in {...preferredByKey.keys, ...byKey.keys})
        {...?byKey[key], ...?preferredByKey[key]},
    ];
  }

  /// 用本地歌曲覆盖云端列表：本地没有的歌曲视为已删除；
  /// 本端无法解码的云端条目原样保留，同名歌曲保留云端的未知字段。
  static List<Map<String, dynamic>> overwriteSongs(
    List<Map<String, dynamic>> local,
    Object? remote, {
    int? limit,
  }) {
    final previous = items(remote);
    final raw = {for (final song in previous) songKey(song): song};
    final seen = <String>{};
    final result = [
      for (final song in local)
        if (seen.add(songKey(song))) {...?raw[songKey(song)], ...song},
      for (final song in previous)
        if (decodeSong(song) == null &&
            (songKey(song).endsWith(':') || seen.add(songKey(song))))
          song,
    ];
    return limit == null ? result : result.take(limit).toList();
  }

  /// 上传用的分区内容（覆盖语义）。favorites 最近收藏在前。
  static List<Map<String, dynamic>> overwriteSection(
    LibraryData local,
    String section,
    Map<String, dynamic> remote,
  ) {
    switch (section) {
      case 'favorites':
        return overwriteSongs(
          _songs(local, local.favorites.toList().reversed),
          remote['favorites'],
        );
      case 'history':
        return overwriteSongs(
          _songs(local, local.history),
          remote['history'],
          limit: historyLimit,
        );
      case 'playlists':
        final remotePlaylists = {
          for (final playlist in items(remote['playlists']))
            playlist['id']?.toString() ?? '': playlist,
        };
        return [
          for (final playlist in local.playlists)
            {
              ...?remotePlaylists[playlist.id],
              'id': playlist.id,
              'name': playlist.name,
              'songs': overwriteSongs(
                _songs(local, playlist.paths),
                remotePlaylists[playlist.id]?['songs'],
              ),
            },
        ];
    }
    throw ArgumentError.value(section, 'section');
  }

  static LibraryData _with(
    LibraryData base, {
    List<Track>? tracks,
    Set<String>? favorites,
    List<String>? history,
    List<LocalPlaylist>? playlists,
  }) => LibraryData(
    tracks: tracks ?? base.tracks,
    favorites: favorites ?? base.favorites,
    history: history ?? base.history,
    playlists: playlists ?? base.playlists,
    volume: base.volume,
    rate: base.rate,
    preferredQuality: base.preferredQuality,
    showTranslation: base.showTranslation,
    doubleLyrics: base.doubleLyrics,
    repeatMode: base.repeatMode,
    session: base.session,
  );

  static List<Track> _unionTracks(LibraryData local, LibraryData other) {
    final merged = {
      for (final track in other.tracks) track.path: track,
      for (final track in local.tracks) track.path: track,
    };
    return merged.values.toList();
  }

  /// 拉取覆盖：所选分区以云端为准（删除随之传播）；
  /// 本机文件条目不会上传，因此保留在对应分区中。
  static LibraryData replaceSections(
    LibraryData local,
    LibraryData remote,
    Set<String> sections,
  ) {
    final localFiles = {
      for (final track in local.tracks)
        if (track.online == null) track.path,
    };
    final localById = {
      for (final playlist in local.playlists) playlist.id: playlist,
    };
    return _with(
      local,
      tracks: _unionTracks(local, remote),
      favorites: sections.contains('favorites')
          ? {...local.favorites.where(localFiles.contains), ...remote.favorites}
          : null,
      history: sections.contains('history')
          ? [
              ...remote.history,
              ...local.history.where(localFiles.contains),
            ].take(historyLimit).toList()
          : null,
      playlists: sections.contains('playlists')
          ? [
              for (final playlist in remote.playlists)
                playlist.withPaths([
                  ...playlist.paths,
                  ...?localById[playlist.id]?.paths.where(localFiles.contains),
                ]),
            ]
          : null,
    );
  }

  /// 合并：[merged] 为 [merge] 的结果，只采用所选分区。
  static LibraryData takeSections(
    LibraryData local,
    LibraryData merged,
    Set<String> sections,
  ) => _with(
    local,
    tracks: _unionTracks(local, merged),
    favorites: sections.contains('favorites') ? merged.favorites : null,
    history: sections.contains('history') ? merged.history : null,
    playlists: sections.contains('playlists') ? merged.playlists : null,
  );

  static Map<String, dynamic> encode(
    LibraryData local,
    Map<String, dynamic> remote,
  ) {
    final remotePlaylists = {
      for (final playlist in items(remote['playlists']))
        playlist['id']?.toString() ?? '': playlist,
    };
    final localPlaylists = {
      for (final playlist in local.playlists) playlist.id: playlist,
    };
    return {
      ...remote,
      'favorites': _union(
        _songs(local, local.favorites.toList().reversed),
        items(remote['favorites']),
      ),
      'history': _union(
        _songs(local, local.history),
        items(remote['history']),
      ).take(historyLimit).toList(),
      'playlists': [
        for (final id in {...localPlaylists.keys, ...remotePlaylists.keys})
          if (id.isNotEmpty)
            {
              ...?remotePlaylists[id],
              'id': id,
              'name':
                  localPlaylists[id]?.name ??
                  remotePlaylists[id]?['name'] ??
                  tr('云端歌单'),
              'songs': _union(
                _songs(local, localPlaylists[id]?.paths ?? []),
                items(remotePlaylists[id]?['songs']),
              ),
            },
      ],
    };
  }
}
