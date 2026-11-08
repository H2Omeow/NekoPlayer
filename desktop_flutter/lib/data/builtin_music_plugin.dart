import '../i18n/tr.dart';
import 'dart:async';
import 'dart:io';

import '../domain/online_music.dart';
import '../domain/music_plugin.dart';
import 'catalog_transport.dart';

class BuiltinMusicPlugin {
  BuiltinMusicPlugin({CatalogTransport? transport})
    : _transport = transport ?? sendCatalogRequest;

  final CatalogTransport _transport;
  final Set<Uri> _queryRoutes = {};
  static const version = '2.3.1';
  static const author = '惜缘惜梦';
  static const subscription =
      'https://animemusic.bzxhkj.com/animemusic/subscription.json';
  static const platforms = {'kg', 'kw', 'wy', 'tx', 'mg', 'bilibili', 'qishui'};
  static const endpoints = {
    'music/search',
    'music/url',
    'music/lyric',
    'music/lyric/word',
    'music/comment',
    'music/mv/search',
    'music/mv/url',
    'music/toplist',
    'music/toplist/detail',
    'music/playlist',
    'music/import',
    'music/recommend',
    'music/artist',
    'music/artist/desc',
    'music/artist/albums',
    'music/album',
    'music/album/list',
    'music/suggest',
    'music/hotSearch',
  };

  Future<Map<String, dynamic>> request(
    String endpoint,
    Map<String, String> query, {
    MusicPluginSource? source,
  }) async {
    final platform = query['platform'] ?? query['source'];
    if (!endpoints.contains(endpoint) ||
        query.containsKey('route') ||
        platform != null && !platforms.contains(platform)) {
      throw       MusicSearchException(tr('内置插件请求参数无效。'));
    }
    final api =
        source?.api ?? Uri.https('animemusic.bzxhkj.com', '/v1/index.php');
    var queryRoute = _queryRoutes.contains(api);
    Future<Map<String, dynamic>> send(bool useQueryRoute) => _transport(
      CatalogRequest(
        api.replace(
          path: '${api.path}${useQueryRoute ? '' : '/$endpoint'}',
          queryParameters: {if (useQueryRoute) 'route': endpoint, ...query},
        ),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'NekoPlayer/animemusic-1',
        },
      ),
    );

    try {
      Map<String, dynamic> body;
      try {
        body = await send(queryRoute);
      } on MusicHttpException catch (failure) {
        if (queryRoute || failure.status != 404) rethrow;
        body = await send(true);
        queryRoute = true;
        _queryRoutes.add(api);
      }
      if (!queryRoute && '${body['code']}' == '404') {
        body = await send(true);
        _queryRoutes.add(api);
      }
      final code = int.tryParse('${body['code']}');
      if (code == null) {
        throw       MusicSearchException(tr('内置插件返回格式异常。'));
      }
      if ([401, 403, 429].contains(code)) {
        throw       MusicSearchException(tr('内置插件服务拒绝请求或请求过于频繁，请稍后重试。'));
      }
      return body;
    } on HandshakeException {
      throw       MusicSearchException(tr('内置插件 TLS 证书验证失败；不会忽略安全校验。'));
    } on TimeoutException {
      throw       MusicSearchException(tr('内置插件请求超时，请稍后重试。'));
    } on IOException {
      throw       MusicSearchException(tr('无法连接内置插件服务，请检查网络。'));
    } on FormatException {
      throw       MusicSearchException(tr('内置插件响应格式异常。'));
    }
  }

  Future<Map<String, dynamic>> lyrics(
    OnlineSong song, {
    MusicPluginSource? source,
  }) async {
    var platform = song.provider.gateway!;
    var id = song.id;
    var title = song.title;
    if (platform == 'bilibili') {
      Map<String, dynamic>? best;
      var bestScore = 0.0;
      for (final target in ['kw', 'wy']) {
        Map<String, dynamic> body;
        try {
          body = await request('music/search', {
            'platform': target,
            'keyword': '${song.title} ${song.artist}'.trim(),
            'page': '1',
            'limit': '10',
          }, source: source);
        } on MusicSearchException {
          continue;
        }
        final items = body['data'];
        if (items is! List) continue;
        for (final item in items.whereType<Map<String, dynamic>>()) {
          final score = _titleScore(song.title, '${item['title'] ?? ''}');
          if (score > bestScore && '${item['id'] ?? ''}'.isNotEmpty) {
            best = {...item, 'platform': target};
            bestScore = score;
          }
        }
        if (bestScore >= .95) break;
      }
      if (best == null || bestScore < .5) return {'code': 200, 'lyric': ''};
      platform = '${best['platform']}';
      id = '${best['id']}';
      title = '${best['title']}';
    }
    final query = {
      'platform': platform,
      'musicId': id,
      'name': title,
      'interval': '200',
    };
    try {
      final word = await request('music/lyric/word', query, source: source);
      if ('${word['code']}' == '200' &&
          '${word['lyric'] ?? ''}'.trim().isNotEmpty) {
        return word;
      }
    } on MusicSearchException catch (_) {}
    final line = await request('music/lyric', query, source: source);
    if ('${line['code']}' != '200') {
      throw       MusicSearchException(tr('内置插件歌词读取失败。'));
    }
    return line;
  }

  static double _titleScore(String title, String candidate) {
    String normalize(String value) => value.toLowerCase().replaceAll(
      RegExp(r'''[\s\-_·、，,。.！!？?（）()\[\]【】"'’“”：:;；~—]+'''),
      '',
    );
    final original = normalize(title);
    final other = normalize(candidate);
    if (original.isEmpty || other.isEmpty) return 0;
    if (original == other) return 1;
    if (original.contains(other) || other.contains(original)) return .85;
    final letters = other.runes.toSet();
    return original.runes.where(letters.contains).length /
        original.runes.length *
        .7;
  }

  static String quality(String value) => switch (value) {
    'standard' || '128' => '128k',
    'higher' => '192k',
    'exhigh' || '320' => '320k',
    'lossless' => 'flac',
    'hires' || 'master' || 'atmos' || '24bit' || 'hifi' => 'flac24bit',
    _ => value,
  };

  static String videoQuality(String platform) => switch (platform) {
    'wy' || 'tx' => '1080',
    'kw' => 'MP4BD',
    'bilibili' => '80',
    'qishui' => '1080p',
    _ => '',
  };

  static String platformFor(MusicProvider provider) =>
      provider.gateway ?? (provider == MusicProvider.netease ? 'wy' : 'kg');
}
