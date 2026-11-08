import '../../i18n/tr.dart';
import '../../domain/music_plugin.dart';
import '../../domain/online_music.dart';
import '../../domain/library.dart' show encodeLyrics;
import 'plugin_runtime.dart';

class ScriptMusicCatalog {
  ScriptMusicCatalog(this.runtime);
  final PluginScriptRuntime runtime;

  Future<SearchPage> search(
    MusicPluginSource source,
    String keyword,
    int page,
  ) async {
    final result = _object(
      await runtime.invoke(source, 'search', [keyword, page, 'music']),
    );
    final songs = <OnlineSong>[];
    for (final row in (result['data'] as List? ?? []).whereType<Map>()) {
      final item = Map<String, dynamic>.from(row);
      final id = '${item['id'] ?? item['hash'] ?? item['mid'] ?? ''}';
      final title = '${item['title'] ?? ''}';
      if (id.isEmpty || title.isEmpty) continue;
      songs.add(
        OnlineSong(
          provider: MusicProvider.gatewayKugou,
          id: id,
          title: title,
          artist: '${item['artist'] ?? ''}',
          album: '${item['album'] ?? ''}',
          artwork: '${item['artwork'] ?? ''}',
          pluginSource: source,
          pluginData: item,
        ),
      );
    }
    return SearchPage(
      songs: songs,
      hasMore: songs.isNotEmpty && result['isEnd'] == false,
    );
  }

  List<AudioQuality> qualities(MusicPluginSource source, OnlineSong song) {
    final declared = source.qualities.isNotEmpty
        ? source.qualities
        : source.format == 'musicfree'
        ? const ['low', 'standard', 'high', 'super']
        : const ['128k', '320k', 'flac'];
    final available = _object(song.pluginData['qualities']);
    return [
      for (var index = 0; index < declared.length; index++)
        if (available.isEmpty || available.containsKey(declared[index]))
          AudioQuality(
            declared[index],
            _labels[declared[index]] ?? declared[index],
            index,
          ),
    ];
  }

  Future<ResolvedAudio> resolve(
    MusicPluginSource source,
    OnlineSong song,
    String preferred, {
    bool exact = false,
  }) async {
    if (source.lx) throw       MusicSearchException(tr('洛雪音源需要搭配同平台搜索结果使用。'));
    final choices = qualities(source, song);
    var quality = preferred;
    if (!exact && !choices.any((item) => item.id == quality)) {
      quality = source.format == 'musicfree'
          ? const {
                  '128k': 'low',
                  'higher': 'low',
                  '192k': 'low',
                  'exhigh': 'standard',
                  '320k': 'standard',
                  'flac': 'high',
                  'lossless': 'high',
                  'hires': 'super',
                }[preferred] ??
                'standard'
          : const {
                  'standard': '128k',
                  'higher': '192k',
                  'exhigh': '320k',
                  'lossless': 'flac',
                  'hires': 'flac24bit',
                }[preferred] ??
                '320k';
      if (!choices.any((item) => item.id == quality) && choices.isNotEmpty) {
        quality = choices.last.id;
      }
    }
    final result = _object(
      await runtime.invoke(source, 'getMediaSource', [_item(song), quality]),
    );
    if (result['ekey'] != null || result['cek'] != null) {
      throw       AudioUnavailableException(tr('该插件返回加密音频，当前尚不支持解密播放。'));
    }
    final actual = '${result['quality'] ?? quality}';
    if (exact && actual != quality) {
      throw       AudioUnavailableException(tr('该音质不可用，插件返回了其他音质。'));
    }
    return _audio(result, actual, musicFree: source.format == 'musicfree');
  }

  Future<ResolvedAudio> resolveLx(
    MusicPluginSource source,
    String platform,
    OnlineSong song,
    String preferred, {
    bool exact = false,
  }) async {
    final descriptor = _object(source.lxSources[platform]);
    if (!(descriptor['actions'] as List? ?? []).contains('musicUrl')) {
      throw       AudioUnavailableException(tr('洛雪音源不支持该平台播放解析。'));
    }
    var quality =
        const {
          'standard': '128k',
          'higher': '192k',
          'exhigh': '320k',
          'lossless': 'flac',
          'hires': 'flac24bit',
          '128': '128k',
          '320': '320k',
          'high': 'flac24bit',
        }[preferred] ??
        preferred;
    final supported = descriptor['qualitys'] as List? ?? [];
    if (supported.isNotEmpty && !supported.contains(quality)) {
      if (exact) {
        throw       AudioUnavailableException(tr('洛雪音源不支持该音质。'));
      }
      final ranked = supported.whereType<String>().toList()
        ..sort(
          (first, second) =>
              _lxOrder.indexOf(first).compareTo(_lxOrder.indexOf(second)),
        );
      quality =
          ranked
              .where(
                (candidate) =>
                    _lxOrder.indexOf(candidate) <= _lxOrder.indexOf(quality),
              )
              .lastOrNull ??
          ranked.first;
    }
    final result = await runtime.invoke(source, 'lxRequest', [
      platform,
      'musicUrl',
      {'type': quality, 'musicInfo': _lxItem(source, platform, song)},
    ]);
    return _audio(
      result is String ? {'url': result} : _object(result),
      quality,
    );
  }

  List<AudioQuality> lxQualities(MusicPluginSource source, String platform) {
    final supported =
        _object(source.lxSources[platform])['qualitys'] as List? ?? [];
    return [
      for (var index = 0; index < supported.length; index++)
        AudioQuality(
          '${supported[index]}',
          _labels[supported[index]] ?? '${supported[index]}',
          index,
        ),
    ];
  }

  Map<String, dynamic> _lxItem(
    MusicPluginSource source,
    String platform,
    OnlineSong song,
  ) {
    final supported =
        _object(source.lxSources[platform])['qualitys'] as List? ?? [];
    return {
      ..._item(song),
      'source': platform,
      'songmid': song.id,
      'hash': song.hash.isEmpty ? song.id : song.hash,
      'name': song.title,
      'singer': song.artist,
      'albumId': song.albumId,
      'albumName': song.album,
      'album_audio_id': song.albumAudioId,
      'types': [
        for (final entry in supported) {'type': entry},
      ],
      '_types': {
        for (final entry in supported) '$entry': {'type': entry},
      },
    };
  }

  Future<String?> lxLyrics(
    MusicPluginSource source,
    String platform,
    OnlineSong song,
  ) async {
    final descriptor = _object(source.lxSources[platform]);
    if (!(descriptor['actions'] as List? ?? []).contains('lyric')) return null;
    final value = await runtime.invoke(source, 'lxRequest', [
      platform,
      'lyric',
      {'musicInfo': _lxItem(source, platform, song)},
    ]);
    return _lyricsValue(source, value);
  }

  Future<String> lyrics(MusicPluginSource source, OnlineSong song) async {
    if (!source.capabilities.contains('getLyric')) return '';
    final value = await runtime.invoke(source, 'getLyric', [_item(song)]);
    return _lyricsValue(source, value);
  }

  Future<String> _lyricsValue(MusicPluginSource source, Object? value) async {
    if (value is String) return encodeLyrics(value, '');
    final result = _object(value);
    var lrc = '${result['rawLrc'] ?? result['lyric'] ?? result['lrc'] ?? ''}';
    if (const {'https', 'http'}.contains(Uri.tryParse(lrc)?.scheme)) {
      final fetched = await runtime.invoke(source, '__nekoFetchLyric', [lrc]);
      lrc = fetched as String? ?? '';
    }
    var translation =
        '${result['translation'] ?? result['rawTranslation'] ?? result['tlyric'] ?? ''}';
    if (const {'https', 'http'}.contains(Uri.tryParse(translation)?.scheme)) {
      translation =
          await runtime.invoke(source, '__nekoFetchLyric', [translation])
              as String? ??
          '';
    }
    return encodeLyrics(lrc, translation);
  }

  Map<String, dynamic> _item(OnlineSong song) => {
    'id': song.id,
    'title': song.title,
    'artist': song.artist,
    'album': song.album,
    'artwork': song.artwork,
    ...song.pluginData,
  };

  ResolvedAudio _audio(
    Map<String, dynamic> result,
    String quality, {
    bool musicFree = false,
  }) {
    final uri = Uri.tryParse('${result['url'] ?? ''}');
    if (uri == null ||
        !const {'https', 'http'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw       AudioUnavailableException(tr('插件未返回有效的音频地址。'));
    }
    final headers = <String, String>{};
    for (final entry in _object(result['headers']).entries) {
      final value = '${entry.value}';
      if (!RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(entry.key) ||
          value.contains(RegExp(r'[\r\n]'))) {
        throw       FormatException(tr('插件返回了无效媒体请求头。'));
      }
      headers[entry.key] = value;
    }
    if (result['userAgent'] is String) {
      final agent = result['userAgent'] as String;
      if (agent.contains(RegExp(r'[\r\n]'))) {
        throw       FormatException(tr('插件返回了无效 User-Agent。'));
      }
      headers['User-Agent'] = agent;
    }
    final format =
        '${result['format'] ?? (quality == 'super' || quality.contains('flac') || musicFree && quality == 'high' ? 'flac' : 'mp3')}';
    return ResolvedAudio(
      uri,
      quality,
      size: (result['size'] as num? ?? 0).toInt(),
      format: format,
      headers: headers,
    );
  }

  static Map<String, dynamic> _object(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  static const _lxOrder = [
    '128k',
    '192k',
    '320k',
    'flac',
    'flac24bit',
    'hires',
    'dolby',
    'atmos',
    'master',
  ];
  static const _labels = {
    'low': '标准 128k',
    'standard': '高品质 320k',
    'high': '无损 FLAC',
    'super': 'Hi-Res',
    '128k': '标准 128k',
    '192k': '较高 192k',
    '320k': '高品质 320k',
    'flac': '无损 FLAC',
    'flac24bit': 'Hi-Res',
  };
}
