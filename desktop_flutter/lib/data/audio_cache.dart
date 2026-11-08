import '../i18n/tr.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as paths;

import '../domain/online_music.dart';
import 'audio_downloader.dart';
import 'library_store.dart';

class CachedAudio {
  const CachedAudio({
    required this.song,
    required this.file,
    required this.quality,
    required this.size,
    required this.created,
  });
  final OnlineSong song;
  final String file;
  final String quality;
  final int size;
  final int created;
  Map<String, dynamic> toJson() => {
    'song': song.toJson(),
    'file': file,
    'quality': quality,
    'size': size,
    'created': created,
  };
}

class AudioCache extends ChangeNotifier {
  AudioCache({
    required this.directory,
    required this.store,
    AudioDownloader? downloader,
  }) : downloader = downloader ?? AudioDownloader(limit: maxFileBytes);
  final Directory directory;
  final LibraryStore store;
  final AudioDownloader downloader;
  static const maxFileBytes = 256 * 1024 * 1024;
  static const maxBytes = 512 * 1024 * 1024;
  bool enabled = false;
  bool readable = true;
  String? error;
  List<CachedAudio> entries = [];
  bool _disposed = false;
  DownloadCancellation? _cancellation;
  Future<void>? _active;
  Future<void> _writes = Future.value();
  Future<void> _lyricWrites = Future.value();
  bool _clearing = false;
  int get totalBytes => entries.fold(0, (total, entry) => total + entry.size);
  bool get busy => _active != null;
  Future<void> get settled async {
    await _active;
    await _lyricWrites;
    await _writes;
  }

  Future<void> initialize() async {
    try {
      final raw = await store.read();
      if (raw == null) return;
      final body = jsonDecode(raw) as Map<String, dynamic>;
      if (body['version'] != 1 || body['entries'] is! List) {
        throw const FormatException();
      }
      final restored = <CachedAudio>[];
      for (final row in body['entries'] as List) {
        final item = row as Map<String, dynamic>;
        final file = item['file'] as String;
        if (!RegExp(r'^[a-f0-9]{64}\.audio$').hasMatch(file)) {
          throw const FormatException();
        }
        final song = OnlineSong.fromJson(item['song'] as Map<String, dynamic>);
        final quality = item['quality'] as String;
        final size = item['size'] as int;
        if (size <= 0 ||
            size > maxFileBytes ||
            file != filename(song, quality)) {
          throw const FormatException();
        }
        final cached = File(paths.join(directory.path, file));
        if (await FileSystemEntity.type(cached.path, followLinks: false) ==
                FileSystemEntityType.file &&
            await cached.length() == size) {
          restored.add(
            CachedAudio(
              song: song,
              file: file,
              quality: quality,
              size: size,
              created: item['created'] as int,
            ),
          );
        }
      }
      if (restored.fold<int>(0, (total, item) => total + item.size) >
          maxBytes) {
        throw const FormatException();
      }
      entries = {
        for (final entry in restored) entry.file: entry,
      }.values.toList();
      enabled = body['enabled'] == true;
    } catch (_) {
      readable = false;
      enabled = false;
      error = tr('缓存索引读取失败；已保留原数据，不覆盖或自动清理。');
    }
  }

  static String filename(OnlineSong song, String quality) =>
      '${sha256.convert(utf8.encode('${song.key}:$quality'))}.audio';

  Future<String?> lyrics(OnlineSong song) async {
    if (!enabled || !readable || _disposed || _clearing) return null;
    for (final entry in entries.where((entry) => entry.song.key == song.key)) {
      final file = File(
        paths.join(directory.path, paths.setExtension(entry.file, '.lrc')),
      );
      try {
        if (await FileSystemEntity.type(file.path, followLinks: false) ==
                FileSystemEntityType.file &&
            await file.length() <= 2 * 1024 * 1024) {
          return await file.readAsString();
        }
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  void rememberLyrics(OnlineSong song, String content) {
    if (!enabled ||
        !readable ||
        _disposed ||
        _clearing ||
        content.trim().isEmpty ||
        content.length > 2 * 1024 * 1024) {
      return;
    }
    final encoded = utf8.encode(content);
    if (encoded.length > 2 * 1024 * 1024) return;
    final audio = _active;
    _lyricWrites = _lyricWrites
        .then((_) async {
          await audio;
          if (!enabled || _disposed || _clearing) return;
          for (final entry
              in entries
                  .where((entry) => entry.song.key == song.key)
                  .toList()) {
            final file = File(
              paths.join(
                directory.path,
                paths.setExtension(entry.file, '.lrc'),
              ),
            );
            final partial = File('${file.path}.part');
            try {
              final type = await FileSystemEntity.type(
                file.path,
                followLinks: false,
              );
              final partialType = await FileSystemEntity.type(
                partial.path,
                followLinks: false,
              );
              if ((type != FileSystemEntityType.notFound &&
                      type != FileSystemEntityType.file) ||
                  (partialType != FileSystemEntityType.notFound &&
                      partialType != FileSystemEntityType.file)) {
                continue;
              }
              await partial.writeAsBytes(encoded, flush: true);
              if (!_disposed &&
                  !_clearing &&
                  enabled &&
                  entries.contains(entry)) {
                await partial.rename(file.path);
              }
            } finally {
              if (await FileSystemEntity.type(
                    partial.path,
                    followLinks: false,
                  ) ==
                  FileSystemEntityType.file) {
                await partial.delete();
              }
            }
          }
        })
        .catchError((Object _) {
          error = tr('歌词缓存未完成，不影响音频播放。');
        });
  }

  Future<ResolvedAudio?> find(OnlineSong song, String preferred) async {
    if (!enabled || !readable || _disposed) return null;
    final candidates = entries
        .where((entry) => entry.song.key == song.key)
        .toList();
    candidates.sort(
      (first, second) => first.quality == preferred
          ? -1
          : second.quality == preferred
          ? 1
          : second.created.compareTo(first.created),
    );
    for (final entry in candidates) {
      final file = File(paths.join(directory.path, entry.file));
      try {
        if (await FileSystemEntity.type(file.path, followLinks: false) ==
                FileSystemEntityType.file &&
            await file.length() == entry.size) {
          return ResolvedAudio(file.uri, entry.quality, size: entry.size);
        }
      } on FileSystemException {
        error = tr('部分缓存不可读，将尝试正常在线播放。');
      }
      entries.removeWhere((item) => item.file == entry.file);
    }
    return null;
  }

  void remember(OnlineSong song, ResolvedAudio audio) {
    if (!enabled ||
        !readable ||
        _disposed ||
        _clearing ||
        _active != null ||
        audio.size > maxFileBytes ||
        audio.uri.scheme == 'file') {
      return;
    }
    final file = filename(song, audio.quality);
    if (entries.any((entry) => entry.file == file)) return;
    _cancellation = DownloadCancellation();
    final pending = _save(song, audio, file, _cancellation!).catchError((
      Object _,
    ) {
      error = tr('缓存未完成，不影响普通播放。');
    });
    _active = pending;
    notifyListeners();
    unawaited(
      pending.whenComplete(() {
        _active = null;
        _cancellation = null;
        if (!_disposed) notifyListeners();
      }),
    );
  }

  Future<void> _save(
    OnlineSong song,
    ResolvedAudio audio,
    String name,
    DownloadCancellation cancellation,
  ) async {
    final partial = File(paths.join(directory.path, '$name.part'));
    final destination = File(paths.join(directory.path, name));
    try {
      await directory.create(recursive: true);
      final destinationType = await FileSystemEntity.type(
        destination.path,
        followLinks: false,
      );
      if (destinationType != FileSystemEntityType.notFound) {
        if (destinationType != FileSystemEntityType.file) {
          throw const FileSystemException('Unsafe cache destination');
        }
        await destination.delete();
      }
      final partialType = await FileSystemEntity.type(
        partial.path,
        followLinks: false,
      );
      if (partialType != FileSystemEntityType.notFound &&
          partialType != FileSystemEntityType.file) {
        throw const FileSystemException('Unsafe cache partial');
      }
      await downloader.download(
        audio: audio,
        partial: partial,
        destination: destination,
        cancellation: cancellation,
        progress: (_, _) {},
      );
      cancellation.check();
      entries = [
        ...entries.where((entry) => entry.file != name),
        CachedAudio(
          song: song,
          file: name,
          quality: audio.quality,
          size: await destination.length(),
          created: DateTime.now().millisecondsSinceEpoch,
        ),
      ];
      entries.sort((first, second) => first.created.compareTo(second.created));
      while (totalBytes > maxBytes && entries.length > 1) {
        await _remove(entries.first);
      }
      await _persist();
      error = null;
    } on DownloadCancelled {
      if (await destination.exists() &&
          !entries.any((entry) => entry.file == name)) {
        await destination.delete();
      }
    } catch (_) {
      error = tr('本首歌曲缓存未完成，不影响在线播放。');
    } finally {
      if (await partial.exists()) {
        try {
          await partial.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _persist() {
    if (!readable) return Future.error(StateError('Cache index protected'));
    final encoded = jsonEncode({
      'version': 1,
      'enabled': enabled,
      'entries': entries.map((entry) => entry.toJson()).toList(),
    });
    final write = _writes.then((_) => store.write(encoded));
    _writes = write.catchError((Object _) {});
    return write;
  }

  Future<void> setEnabled(bool value) async {
    if (!readable || _disposed) return;
    enabled = value;
    if (!value) {
      _cancellation?.cancel();
      await _active;
      await _lyricWrites;
    }
    try {
      await _persist();
    } catch (_) {
      enabled = false;
      error = tr('缓存设置保存失败。');
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _remove(CachedAudio entry) async {
    final file = File(paths.join(directory.path, entry.file));
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.file) {
      await file.delete();
    }
    final lyrics = File(paths.setExtension(file.path, '.lrc'));
    if (await FileSystemEntity.type(lyrics.path, followLinks: false) ==
        FileSystemEntityType.file) {
      await lyrics.delete();
    }
    entries.removeWhere((item) => item.file == entry.file);
  }

  Future<void> remove(Set<String> files) => _clearEntries(files);

  Future<void> clear() => _clearEntries(null);

  Future<void> _clearEntries(Set<String>? files) async {
    if (!readable || _disposed || _clearing) return;
    _clearing = true;
    try {
      _cancellation?.cancel();
      await _active;
      await _lyricWrites;
      for (final entry in List<CachedAudio>.of(entries)) {
        if (files == null || files.contains(entry.file)) await _remove(entry);
      }
      await _persist();
    } finally {
      _clearing = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancellation?.cancel();
    super.dispose();
  }
}
