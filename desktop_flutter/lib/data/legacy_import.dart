import '../i18n/tr.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../domain/library.dart';
import '../domain/audio_effects.dart';
import 'account_store.dart';
import 'android_datastore.dart';
import 'cloud_library.dart';
import 'legacy_audio_effects.dart';

class LegacyPlaybackPreferences {
  const LegacyPlaybackPreferences({
    this.rate,
    this.quality,
    this.translation,
    this.twoLines,
  });

  final double? rate;
  final String? quality;
  final bool? translation;
  final bool? twoLines;
  int get count => [rate, quality, translation, twoLines].nonNulls.length;

  factory LegacyPlaybackPreferences.parse(Map<String, String> values) {
    bool? boolean(String key) {
      final value = values[key];
      if (value == null) return null;
      if (value != 'true' && value != 'false') {
        throw FormatException(tr('旧版设置 {key} 不是有效布尔值。', {'key': key}));
      }
      return value == 'true';
    }

    final rawRate = values['playback_speed'];
    final rate = rawRate == null ? null : double.tryParse(rawRate);
    if (rawRate != null &&
        (rate == null || !rate.isFinite || rate < .5 || rate > 2)) {
      throw       FormatException(tr('旧版播放速度超出桌面端范围（0.5–2）。'));
    }
    final quality = values['audio_quality'] ?? values['quality_level'];
    if (quality != null && !RegExp(r'^[a-zA-Z0-9_]{1,40}$').hasMatch(quality)) {
      throw       FormatException(tr('旧版音质设置无效。'));
    }
    return LegacyPlaybackPreferences(
      rate: rate,
      quality: quality,
      translation: boolean('floating_translation'),
      twoLines: boolean('floating_double_row'),
    );
  }
}

class LegacyPlaybackQueue {
  const LegacyPlaybackQueue({
    required this.tracks,
    required this.session,
    this.skipped = 0,
    this.selectionChanged = false,
  });

  final List<Track> tracks;
  final PlaybackSession session;
  final int skipped;
  final bool selectionChanged;

  static LegacyPlaybackQueue? parse(Map<String, String> values) {
    final raw = values['play_queue'];
    if (raw == null) {
      if (values.containsKey('play_index') ||
          values.containsKey('play_position')) {
        throw       FormatException(tr('旧版播放状态缺少队列。'));
      }
      return null;
    }
    final rows = jsonDecode(raw);
    if (rows is! List ||
        rows.length > PlaybackSession.maxQueueLength ||
        rows.any((row) => row is! Map<String, dynamic>)) {
      throw       FormatException(tr('旧版播放队列结构无效。'));
    }
    if (rows.isEmpty) return null;
    final index = int.tryParse(values['play_index'] ?? '0');
    final position = int.tryParse(values['play_position'] ?? '0');
    if (index == null ||
        index < 0 ||
        index >= rows.length ||
        position == null ||
        position < 0 ||
        position > PlaybackSession.maxPosition.inMilliseconds) {
      throw       FormatException(tr('旧版播放队列索引或进度无效。'));
    }
    final tracks = <Track>[];
    final originalIndices = <int>[];
    for (var ordinal = 0; ordinal < rows.length; ordinal++) {
      final track = CloudLibrary.decodeSong(
        rows[ordinal] as Map<String, dynamic>,
      );
      if (track == null) continue;
      tracks.add(track);
      originalIndices.add(ordinal);
    }
    if (tracks.isEmpty) {
      throw       FormatException(tr('旧版播放队列没有可识别的音源，未替换当前队列。'));
    }
    var selected = originalIndices.indexOf(index);
    final selectionChanged = selected < 0;
    if (selectionChanged) {
      selected = originalIndices.indexWhere((ordinal) => ordinal > index);
      if (selected < 0) selected = 0;
    }
    return LegacyPlaybackQueue(
      tracks: tracks,
      session: PlaybackSession(
        paths: tracks.map((track) => track.path).toList(),
        index: selected,
        position: Duration(milliseconds: selectionChanged ? 0 : position),
      ),
      skipped: rows.length - tracks.length,
      selectionChanged: selectionChanged,
    );
  }
}

class LegacyImport {
  LegacyImport({
    required this.library,
    this.netease,
    this.kugou = const {},
    this.siteToken,
    this.platform,
    this.skippedSongs = 0,
    this.playback = const LegacyPlaybackPreferences(),
    this.queue,
    this.effects,
  });
  final Map<String, dynamic> library;
  final Map<String, String>? netease;
  final Map<int, Map<String, String>> kugou;
  final String? siteToken;
  final int? platform;
  final int skippedSongs;
  final LegacyPlaybackPreferences playback;
  final LegacyPlaybackQueue? queue;
  final AudioEffects? effects;
  LibraryData get decoded => CloudLibrary.decode(library);
  bool get hasCredentials =>
      netease != null || kugou.isNotEmpty || siteToken != null;
  static const maxFileBytes = 8 * 1024 * 1024;

  static Future<LegacyImport> readFiles(
    List<String> paths, {
    bool includeCredentials = false,
    bool includeSettings = false,
    bool includeQueue = false,
    bool includeEffects = false,
  }) async {
    if (paths.isEmpty || paths.length > 8) {
      throw       FormatException(tr('请选择 1–8 个旧版备份文件。'));
    }
    final values = <String, String>{};
    Map<String, dynamic>? library;
    var total = 0;
    for (final path in paths) {
      final bytes = BytesBuilder(copy: false);
      final file = File(path);
      if (await file.length() > maxFileBytes) {
        throw       FormatException(tr('单个备份不能超过 8MB。'));
      }
      await for (final chunk in file.openRead()) {
        total += chunk.length;
        if (total > 32 * 1024 * 1024 ||
            bytes.length + chunk.length > maxFileBytes) {
          throw       FormatException(tr('备份文件过大。'));
        }
        bytes.add(chunk);
      }
      final content = bytes.takeBytes();
      final extension = path.toLowerCase().split('.').last;
      if (extension == 'json') {
        if (library != null) throw FormatException(tr('一次只能导入一份音乐库备份。'));
        final decoded = jsonDecode(utf8.decode(content));
        if (decoded is! Map<String, dynamic>) {
          throw       FormatException(tr('备份 JSON 结构无效。'));
        }
        final body = decoded['data'] is Map<String, dynamic>
            ? decoded['data'] as Map<String, dynamic>
            : decoded;
        library = {
          for (final key in ['favorites', 'history', 'playlists'])
            if (body.containsKey(key)) key: body[key],
        };
        if (library.isEmpty) throw       FormatException(tr('JSON 中未找到旧版音乐库。'));
        if (includeCredentials) {
          for (final key in ['ncCookie', 'kgToken', 'kgPlatform']) {
            if (body[key] != null) values[key] = body[key].toString();
          }
          if (body['kgCookies'] is List) {
            final cookies = body['kgCookies'] as List;
            for (var index = 0; index < cookies.length && index < 2; index++) {
              if (cookies[index] is! String) {
                throw       FormatException(tr('酷狗会话格式异常。'));
              }
              values['cookies_$index'] = cookies[index] as String;
            }
          }
        }
      } else if (extension == 'properties' ||
          extension == 'xml' ||
          extension == 'pb' ||
          extension == 'preferences_pb') {
        final parsed = extension == 'properties'
            ? properties(content)
            : extension == 'pb' || extension == 'preferences_pb'
            ? {
                for (final entry in AndroidDataStore.preferences(
                  content,
                ).entries)
                  if (entry.value is String ||
                      entry.value is bool ||
                      entry.value is num)
                    entry.key: entry.value.toString(),
              }
            : androidPreferences(utf8.decode(content));
        for (final entry in parsed.entries) {
          if (values.containsKey(entry.key)) {
            throw       FormatException(tr('多个备份包含重复配置，请分开导入。'));
          }
          values[entry.key] = entry.value;
        }
      } else {
        throw       FormatException(
          tr('仅支持旧版 .properties、Android .xml / DataStore .pb 或音乐库 .json。'),
        );
      }
    }
    final rawLibrary = values['library'];
    if (rawLibrary != null) {
      if (library != null) throw FormatException(tr('一次只能导入一份音乐库备份。'));
      final decoded = jsonDecode(rawLibrary);
      if (decoded is! Map<String, dynamic>) {
        throw       FormatException(tr('音乐库结构无效。'));
      }
      library = decoded;
    }
    for (final entry in {
      'my_favorites': 'favorites',
      'my_history': 'history',
      'my_playlists': 'playlists',
    }.entries) {
      if (values.containsKey(entry.key)) {
        library ??= {};
        if (library.containsKey(entry.value)) {
          throw       FormatException(tr('发现重复音乐库，请分开导入。'));
        }
        library[entry.value] = jsonDecode(values[entry.key]!);
      }
    }
    final credentials = <int, Map<String, String>>{};
    Map<String, String>? netease;
    String? token;
    int? platform;
    if (includeCredentials) {
      final cookie =
          values['nc_user'] ?? values['ncCookie'] ?? values['nc_cookie'];
      if (cookie != null && cookie.isNotEmpty) {
        netease = AccountStore.parseCookies(cookie);
      }
      for (var index = 0; index < 2; index++) {
        final raw = values['cookies_$index'];
        if (raw != null && raw.isNotEmpty) {
          credentials[index] = AccountStore.parseCookies(raw);
        }
      }
      final selection = values['kg_platform'] ?? values['kgPlatform'];
      if (selection != null) {
        platform = int.tryParse(selection);
        if (platform != 0 && platform != 1) {
          throw       FormatException(tr('酷狗账号槽位无效。'));
        }
      }
      final legacyToken = values['kgToken'] ?? values['kg_token'];
      if (legacyToken != null &&
          legacyToken.isNotEmpty &&
          credentials[platform ?? 0] == null) {
        credentials[platform ?? 0] = AccountStore.parseCookies(
          [
            'token=$legacyToken',
            if (values['kg_userid']?.isNotEmpty ?? false)
              'userid=${values['kg_userid']}',
            if (values['kg_dfid']?.isNotEmpty ?? false)
              'dfid=${values['kg_dfid']}',
          ].join('; '),
        );
      }
      token = values['site_token'] ?? values['app_token'];
      if (token != null && token.isNotEmpty) {
        AccountStore.validateSiteToken(token);
      }
    }
    final playback = includeSettings
        ? LegacyPlaybackPreferences.parse(values)
        : const LegacyPlaybackPreferences();
    final queue = includeQueue ? LegacyPlaybackQueue.parse(values) : null;
    final effects = includeEffects ? LegacyAudioEffects.parse(values) : null;
    if (library == null &&
        netease == null &&
        credentials.isEmpty &&
        (token == null || token.isEmpty) &&
        playback.count == 0 &&
        queue == null &&
        effects == null) {
      throw       FormatException(tr('未找到可导入内容；账号、播放设置、队列或音效需要先勾选对应导入选项。'));
    }
    final safeLibrary = {
      for (final key in ['favorites', 'history', 'playlists'])
        if (library?.containsKey(key) ?? false) key: library![key],
    };
    final decoded = CloudLibrary.decode(safeLibrary);
    var skipped = 0;
    for (final list in [
      safeLibrary['favorites'],
      safeLibrary['history'],
      ...CloudLibrary.items(
        safeLibrary['playlists'],
      ).map((playlist) => playlist['songs']),
    ]) {
      for (final song in CloudLibrary.items(list)) {
        if (CloudLibrary.decodeSong(song) == null) skipped++;
      }
    }
    if (decoded.tracks.isEmpty && skipped > 0) {
      throw       FormatException(tr('所有歌曲都缺少可识别的音源 ID，未导入。'));
    }
    return LegacyImport(
      library: safeLibrary,
      netease: netease,
      kugou: credentials,
      siteToken: token?.isEmpty == true ? null : token,
      platform: platform,
      skippedSongs: skipped,
      playback: playback,
      queue: queue,
      effects: effects,
    );
  }

  Future<int> fillMissingAccounts(AccountStore accounts) async {
    var imported = 0;
    final hasLocalKugou = [
      0,
      1,
    ].any((slot) => (accounts.kugou(slot)['token'] ?? '').isNotEmpty);
    if (!accounts.neteaseLoggedIn && (netease?['MUSIC_U'] ?? '').isNotEmpty) {
      await accounts.update(netease: netease, replace: true);
      imported++;
    }
    for (final entry in kugou.entries) {
      if ((accounts.kugou(entry.key)['token'] ?? '').isEmpty &&
          (entry.value['token'] ?? '').isNotEmpty) {
        await accounts.update(
          kugou: entry.value,
          platform: entry.key,
          replace: true,
          selectPlatform: false,
        );
        imported++;
      }
    }
    if (!hasLocalKugou && kugou.isNotEmpty && platform != null) {
      await accounts.update(platform: platform);
    }
    if (accounts.siteToken.isEmpty && siteToken != null) {
      await accounts.update(siteToken: siteToken);
      imported++;
    }
    return imported;
  }

  static Map<String, String> androidPreferences(String source) {
    if (RegExp(
      r'<!\s*(DOCTYPE|ENTITY)',
      caseSensitive: false,
    ).hasMatch(source)) {
      throw       FormatException(tr('不接受带外部实体的 XML。'));
    }
    final root = XmlDocument.parse(source).rootElement;
    if (root.name.qualified != 'map') {
      throw FormatException(tr('不是 Android SharedPreferences 备份。'));
    }
    final values = <String, String>{};
    for (final element in root.childElements) {
      final type = element.name.qualified;
      if (!['string', 'boolean', 'int', 'long', 'float'].contains(type)) {
        continue;
      }
      final key = element.getAttribute('name');
      if (key == null ||
          values.containsKey(key) ||
          element.childElements.isNotEmpty) {
        throw FormatException(tr('SharedPreferences 字段无效或重复。'));
      }
      final value = type == 'string'
          ? element.innerText
          : element.getAttribute('value');
      if (value == null ||
          (type != 'string' && element.innerText.trim().isNotEmpty) ||
          (type == 'boolean' && value != 'true' && value != 'false') ||
          ((type == 'int' || type == 'long') && int.tryParse(value) == null) ||
          (type == 'int' &&
              (int.parse(value) < -2147483648 ||
                  int.parse(value) > 2147483647)) ||
          (type == 'float' && !(double.tryParse(value)?.isFinite ?? false))) {
        throw FormatException(tr('SharedPreferences 值类型无效。'));
      }
      values[key] = value;
    }
    return values;
  }

  static Map<String, String> properties(List<int> bytes) {
    final values = <String, String>{};
    var logical = '';
    var continued = false;
    void parse(String line) {
      final trimmed = line.replaceFirst(RegExp(r'^[ \t\f]+'), '');
      if (trimmed.isEmpty ||
          trimmed.startsWith('#') ||
          trimmed.startsWith('!')) {
        return;
      }
      var escaped = false;
      var end = trimmed.length;
      for (var index = 0; index < trimmed.length; index++) {
        final character = trimmed[index];
        if (!escaped &&
            (character == '=' ||
                character == ':' ||
                ' \t\f'.contains(character))) {
          end = index;
          break;
        }
        escaped = !escaped && character == r'\';
      }
      var start = end;
      while (start < trimmed.length && ' \t\f'.contains(trimmed[start])) {
        start++;
      }
      if (start < trimmed.length &&
          (trimmed[start] == '=' || trimmed[start] == ':')) {
        start++;
      }
      while (start < trimmed.length && ' \t\f'.contains(trimmed[start])) {
        start++;
      }
      values[_unescape(trimmed.substring(0, end))] = _unescape(
        trimmed.substring(start),
      );
    }

    for (final physical in latin1.decode(bytes).split(RegExp(r'\r\n|\n|\r'))) {
      if (!continued && RegExp(r'^[ \t\f]*[#!]').hasMatch(physical)) continue;
      final line = continued
          ? physical.replaceFirst(RegExp(r'^[ \t\f]+'), '')
          : physical;
      logical += line;
      var slashes = 0;
      for (
        var index = logical.length - 1;
        index >= 0 && logical[index] == r'\';
        index--
      ) {
        slashes++;
      }
      continued = slashes.isOdd;
      if (continued) {
        logical = logical.substring(0, logical.length - 1);
      } else {
        parse(logical);
        logical = '';
      }
    }
    if (logical.isNotEmpty) parse(logical);
    return values;
  }

  static String _unescape(String source) {
    final result = StringBuffer();
    for (var index = 0; index < source.length; index++) {
      if (source[index] != r'\') {
        result.write(source[index]);
        continue;
      }
      index++;
      if (index >= source.length) break;
      final character = source[index];
      if (character == 'u') {
        if (index + 4 >= source.length) {
          throw FormatException(tr('Properties Unicode 转义不完整。'));
        }
        final code = int.tryParse(
          source.substring(index + 1, index + 5),
          radix: 16,
        );
        if (code == null) {
          throw FormatException(tr('Properties Unicode 转义无效。'));
        }
        result.writeCharCode(code);
        index += 4;
      } else {
        result.write(switch (character) {
          't' => '\t',
          'r' => '\r',
          'n' => '\n',
          'f' => '\f',
          _ => character,
        });
      }
    }
    return result.toString();
  }
}
