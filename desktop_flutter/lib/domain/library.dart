import '../i18n/tr.dart';
import 'dart:convert';

import 'online_music.dart';

class Track {
  const Track({
    required this.path,
    required this.title,
    required this.artist,
    this.online,
  });

  factory Track.fromOnline(OnlineSong song) => Track(
    path: song.key,
    title: song.title,
    artist: song.artist,
    online: song,
  );

  final String path;
  final String title;
  final String artist;
  final OnlineSong? online;

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    path: json['path'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    online: json['online'] == null
        ? null
        : OnlineSong.fromJson(json['online'] as Map<String, dynamic>),
  );

  Map<String, dynamic> toJson() => {
    'path': path,
    'title': title,
    'artist': artist,
    if (online != null) 'online': online!.toJson(),
  };
}

class LocalPlaylist {
  const LocalPlaylist({
    required this.id,
    required this.name,
    this.paths = const [],
  });

  final String id;
  final String name;
  final List<String> paths;

  LocalPlaylist withPaths(List<String> value) =>
      LocalPlaylist(id: id, name: name, paths: value);

  factory LocalPlaylist.fromJson(Map<String, dynamic> json) => LocalPlaylist(
    id: json['id'] as String,
    name: json['name'] as String,
    paths: (json['paths'] as List).cast<String>().toSet().toList(),
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'paths': paths};
}

class PlaybackSession {
  static const maxQueueLength = 100000;
  static const maxPosition = Duration(days: 7);

  const PlaybackSession({
    required this.paths,
    required this.index,
    required this.position,
  });
  final List<String> paths;
  final int index;
  final Duration position;

  factory PlaybackSession.fromJson(Map<String, dynamic> json) {
    final paths = (json['paths'] as List).cast<String>();
    final index = json['index'] as int;
    final milliseconds = json['position'] as int;
    if (paths.isEmpty ||
        paths.length > maxQueueLength ||
        index < 0 ||
        index >= paths.length ||
        milliseconds < 0 ||
        milliseconds > maxPosition.inMilliseconds) {
      throw       FormatException(tr('播放恢复记录无效。'));
    }
    return PlaybackSession(
      paths: paths,
      index: index,
      position: Duration(milliseconds: milliseconds),
    );
  }

  Map<String, dynamic> toJson() => {
    'paths': paths,
    'index': index,
    'position': position.inMilliseconds,
  };
}

class LibraryData {
  const LibraryData({
    this.tracks = const [],
    this.favorites = const {},
    this.history = const [],
    this.playlists = const [],
    this.volume = 75,
    this.rate = 1,
    this.preferredQuality = 'exhigh',
    this.showTranslation = true,
    this.doubleLyrics = true,
    this.repeatMode = 'sequential',
    this.session,
  });

  final List<Track> tracks;
  final Set<String> favorites;
  final List<String> history;
  final List<LocalPlaylist> playlists;
  final double volume;
  final double rate;
  final String preferredQuality;
  final bool showTranslation;
  final bool doubleLyrics;
  final String repeatMode;
  final PlaybackSession? session;

  factory LibraryData.decode(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    if (json['version'] != 1) throw FormatException(tr('未知音乐库格式'));
    final unique = <String, Track>{};
    for (final item in json['tracks'] as List) {
      final track = Track.fromJson(item as Map<String, dynamic>);
      unique[track.path] = track;
    }
    final tracks = unique.values.toList();
    final paths = unique.keys.toSet();
    final session = json['session'] == null
        ? null
        : PlaybackSession.fromJson(json['session'] as Map<String, dynamic>);
    return LibraryData(
      tracks: tracks,
      favorites: (json['favorites'] as List)
          .cast<String>()
          .toSet()
          .intersection(paths),
      history: (json['history'] as List)
          .cast<String>()
          .where(paths.contains)
          .toSet()
          .take(200)
          .toList(),
      playlists: (json['playlists'] as List)
          .map((value) => LocalPlaylist.fromJson(value as Map<String, dynamic>))
          .map(
            (playlist) => playlist.withPaths(
              playlist.paths.where(paths.contains).toList(),
            ),
          )
          .toList(),
      volume: (json['volume'] as num).toDouble().clamp(0, 100),
      rate: (json['rate'] as num).toDouble().clamp(0.5, 2),
      preferredQuality: json['preferredQuality'] as String? ?? 'exhigh',
      showTranslation: json['showTranslation'] as bool? ?? true,
      doubleLyrics: json['doubleLyrics'] as bool? ?? true,
      repeatMode: json['repeatMode'] as String? ?? 'sequential',
      session: session != null && session.paths.every(paths.contains)
          ? session
          : null,
    );
  }

  String encode() => jsonEncode({
    'version': 1,
    'tracks': tracks.map((track) => track.toJson()).toList(),
    'favorites': favorites.toList(),
    'history': history,
    'playlists': playlists.map((playlist) => playlist.toJson()).toList(),
    'volume': volume,
    'rate': rate,
    'preferredQuality': preferredQuality,
    'showTranslation': showTranslation,
    'doubleLyrics': doubleLyrics,
    'repeatMode': repeatMode,
    if (session != null) 'session': session!.toJson(),
  });
}

class LyricLine {
  const LyricLine(
    this.time,
    this.text, {
    this.translation = '',
    this.words = const [],
  });

  final Duration time;
  final String text;
  final String translation;
  final List<LyricWord> words;
}

class LyricWord {
  const LyricWord(this.text, this.time, this.duration);

  final String text;
  final Duration time;
  final Duration duration;

  double progress(Duration position) {
    if (position < time) return 0;
    if (duration <= Duration.zero) return 1;
    return ((position - time).inMicroseconds / duration.inMicroseconds).clamp(
      0.0,
      1.0,
    );
  }
}

String renderLrc(List<LyricLine> lines) {
  final output = <String>[];
  for (final line in lines) {
    final milliseconds = line.time.inMilliseconds.clamp(0, 1 << 53);
    final minutes = (milliseconds ~/ 60000).toString().padLeft(2, '0');
    final seconds = (milliseconds ~/ 1000 % 60).toString().padLeft(2, '0');
    final fraction = (milliseconds % 1000).toString().padLeft(3, '0');
    final timestamp = '[$minutes:$seconds.$fraction]';
    for (final text in [line.text, line.translation]) {
      for (final row in const LineSplitter().convert(text)) {
        if (row.trim().isNotEmpty) output.add('$timestamp$row');
      }
    }
  }
  return output.join('\n');
}

String encodeLyrics(String original, String translation) => translation.isEmpty
    ? original
    : jsonEncode({
        'format': 'nekoplayer.lyrics.v1',
        'original': original,
        'translation': translation,
      });

List<LyricLine> parseLrc(String source, {String translation = ''}) {
  if (source.trimLeft().startsWith('{')) {
    try {
      final envelope = jsonDecode(source);
      if (envelope is Map &&
          envelope['format'] == 'nekoplayer.lyrics.v1' &&
          envelope['original'] is String &&
          envelope['translation'] is String) {
        return parseLrc(
          envelope['original'] as String,
          translation: envelope['translation'] as String,
        );
      }
    } on FormatException catch (_) {}
  }
  final offset =
      int.tryParse(
        RegExp(
              r'\[offset:([+-]?\d+)\]',
              caseSensitive: false,
            ).firstMatch(source)?.group(1) ??
            '',
      ) ??
      0;
  final timestamp = RegExp(r'\[(\d+):(\d{2})(?:[.:](\d{1,3}))?\]');
  final wordLine = RegExp(r'^\[(\d+),(\d+)\]');
  final wordTag = RegExp(r'\((\d+),(\d+),\d+\)');
  final enhancedTag = RegExp(r'<(\d+):(\d{2})(?:[.:](\d{1,3}))?>');
  int timestampMs(RegExpMatch match) =>
      int.parse(match.group(1)!) * 60000 +
      int.parse(match.group(2)!) * 1000 +
      int.parse((match.group(3) ?? '').padRight(3, '0'));
  final result = <LyricLine>[];
  for (final raw in const LineSplitter().convert(source)) {
    final line = raw.trim();
    if (line.startsWith('{')) {
      try {
        final item = jsonDecode(line);
        if (item is Map && item['c'] is List) {
          final time = num.tryParse('${item['t']}');
          final text = (item['c'] as List)
              .whereType<Map>()
              .map((part) => part['tx'] is String ? part['tx'] as String : '')
              .join();
          if (time != null &&
              time.isFinite &&
              time >= 0 &&
              time <= (1 << 53) &&
              text.isNotEmpty) {
            result.add(LyricLine(Duration(milliseconds: time.round()), text));
          }
        }
      } on FormatException catch (_) {}
      continue;
    }
    final header = wordLine.firstMatch(line);
    if (header != null) {
      final start = int.tryParse(header.group(1)!);
      if (start == null) continue;
      final body = line.substring(header.end);
      final tags = wordTag.allMatches(body).toList();
      final words = <LyricWord>[];
      if (tags.isNotEmpty && tags.first.start > 0) {
        words.add(
          LyricWord(
            body.substring(0, tags.first.start),
            Duration(milliseconds: (start + offset).clamp(0, 1 << 53)),
            Duration.zero,
          ),
        );
      }
      for (var index = 0; index < tags.length; index++) {
        final tag = tags[index];
        final time = int.tryParse(tag.group(1)!);
        final duration = int.tryParse(tag.group(2)!);
        final text = body.substring(
          tag.end,
          index + 1 < tags.length ? tags[index + 1].start : body.length,
        );
        if (time != null && duration != null && text.isNotEmpty) {
          words.add(
            LyricWord(
              text,
              Duration(milliseconds: (time + offset).clamp(0, 1 << 53)),
              Duration(milliseconds: duration.clamp(0, 1 << 53)),
            ),
          );
        }
      }
      final text = body.replaceAll(wordTag, '').trim();
      if (text.isNotEmpty) {
        result.add(
          LyricLine(
            Duration(milliseconds: (start + offset).clamp(0, 1 << 53)),
            text,
            words: List.unmodifiable(words),
          ),
        );
      }
      continue;
    }
    final matches = timestamp.allMatches(raw).toList();
    if (matches.isEmpty) continue;
    final body = raw.substring(matches.last.end).trim();
    final text = body.replaceAll(enhancedTag, '').trim();
    if (text.isEmpty) continue;
    for (final match in matches) {
      final seconds = int.parse(match.group(2)!);
      if (seconds >= 60) continue;
      final milliseconds = timestampMs(match) + offset;
      final tags = enhancedTag.allMatches(body).toList();
      final words = <LyricWord>[];
      final shift = timestampMs(match) - timestampMs(matches.first);
      if (tags.isNotEmpty && tags.first.start > 0) {
        words.add(
          LyricWord(
            body.substring(0, tags.first.start),
            Duration(milliseconds: milliseconds.clamp(0, 1 << 53)),
            Duration.zero,
          ),
        );
      }
      for (var index = 0; index < tags.length; index++) {
        final tag = tags[index];
        if (int.parse(tag.group(2)!) >= 60) continue;
        final word = body.substring(
          tag.end,
          index + 1 < tags.length ? tags[index + 1].start : body.length,
        );
        if (word.isEmpty) continue;
        final start = timestampMs(tag) + offset + shift;
        final end = index + 1 < tags.length
            ? timestampMs(tags[index + 1]) + offset + shift
            : start + 500;
        words.add(
          LyricWord(
            word,
            Duration(milliseconds: start.clamp(0, 1 << 53)),
            Duration(milliseconds: (end - start).clamp(0, 1 << 53)),
          ),
        );
      }
      result.add(
        LyricLine(
          Duration(milliseconds: milliseconds.clamp(0, 1 << 53)),
          text,
          words: List.unmodifiable(words),
        ),
      );
    }
  }
  final grouped = <Duration, List<LyricLine>>{};
  for (final line in result) {
    grouped.putIfAbsent(line.time, () => []).add(line);
  }
  final merged = [
    for (final entry in grouped.entries)
      LyricLine(
        entry.key,
        entry.value.first.text,
        words: entry.value.first.words,
        translation: entry.value
            .skip(1)
            .map((line) => line.text)
            .where((text) => text != entry.value.first.text)
            .toSet()
            .join('\n'),
      ),
  ];
  merged.sort((left, right) => left.time.compareTo(right.time));
  if (translation.isEmpty) return merged;
  final translated = parseLrc(translation);
  final aligned = <LyricLine>[];
  var cursor = 0;
  for (final line in merged) {
    while (cursor + 1 < translated.length &&
        translated[cursor + 1].time <= line.time) {
      cursor++;
    }
    LyricLine? closest;
    for (final index in [cursor, cursor + 1]) {
      if (index >= translated.length) continue;
      final candidate = translated[index];
      final distance = (candidate.time - line.time).inMicroseconds.abs();
      if (distance < 500000 &&
          (closest == null ||
              distance < (closest.time - line.time).inMicroseconds.abs())) {
        closest = candidate;
      }
    }
    aligned.add(
      LyricLine(
        line.time,
        line.text,
        words: line.words,
        translation: closest?.text ?? line.translation,
      ),
    );
  }
  return aligned;
}
