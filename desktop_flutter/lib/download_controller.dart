import './i18n/tr.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as paths;

import 'data/account_store.dart';
import 'data/audio_downloader.dart';
import 'data/library_store.dart';
import 'domain/online_music.dart';
import 'domain/library.dart' show parseLrc, renderLrc;

enum DownloadPhase { queued, downloading, paused, failed, completed }

class DownloadTask {
  DownloadTask({
    required this.id,
    required this.song,
    required this.directory,
    required this.quality,
    this.path,
    this.phase = DownloadPhase.queued,
    this.received = 0,
    this.total,
    this.lyricsOwned = false,
  });
  final String id;
  final OnlineSong song;
  final String directory;
  final String quality;
  String? path;
  DownloadPhase phase;
  int received;
  int? total;
  String? error;
  bool lyricsOwned;

  String get partialPath => paths.join(directory, '.nekoplayer-$id.part');

  Map<String, dynamic> toJson() => {
    'id': id,
    'song': song.toJson(),
    'directory': directory,
    'quality': quality,
    'path': path,
    'phase': phase.name,
    'received': received,
    'total': total,
    'lyricsOwned': lyricsOwned,
  };

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    final task = DownloadTask(
      id: json['id'] as String,
      song: OnlineSong.fromJson(json['song'] as Map<String, dynamic>),
      directory: json['directory'] as String,
      quality: json['quality'] as String,
      path: json['path'] as String?,
      phase: DownloadPhase.values.byName(json['phase'] as String),
      received: json['received'] as int,
      total: json['total'] as int?,
      lyricsOwned: json['lyricsOwned'] == true,
    );
    if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(task.id) ||
        !paths.isAbsolute(task.directory) ||
        (task.path != null && paths.dirname(task.path!) != task.directory)) {
      throw const FormatException('Invalid download path');
    }
    if (task.phase == DownloadPhase.downloading ||
        task.phase == DownloadPhase.queued) {
      task.phase = DownloadPhase.paused;
    }
    return task;
  }
}

class DownloadController extends ChangeNotifier {
  DownloadController({
    required this.source,
    required this.store,
    AudioDownloader? downloader,
  }) : downloader = downloader ?? AudioDownloader();

  final OnlineDownloadSource source;
  final LibraryStore store;
  final AudioDownloader downloader;
  final List<DownloadTask> _tasks = [];
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  bool isActive(DownloadTask task) => identical(task, _active);
  bool _readable = true;
  bool _disposed = false;
  bool _running = false;
  DownloadTask? _active;
  DownloadCancellation? _cancellation;
  Future<void> _writes = Future.value();
  String? error;
  Future<void> get flushed => _writes;

  Future<void> initialize() async {
    try {
      final encoded = await store.read();
      if (encoded != null) {
        final body = jsonDecode(encoded) as Map<String, dynamic>;
        if (body['version'] != 1) {
          throw const FormatException('Unknown download format');
        }
        final restored = (body['tasks'] as List)
            .map((item) => DownloadTask.fromJson(item as Map<String, dynamic>))
            .toList();
        if (restored.map((task) => task.id).toSet().length != restored.length) {
          throw const FormatException('Duplicate task identity');
        }
        _tasks.addAll(restored);
      }
    } catch (_) {
      _readable = false;
      error = tr('下载记录读取失败，已保护原数据，暂不创建新任务。');
    }
    _notify();
  }

  Future<void> enqueue(
    OnlineSong song,
    String directory,
    String quality,
  ) async {
    if (_disposed || !_readable) return;
    directory = paths.normalize(paths.absolute(directory));
    if (!await Directory(directory).exists()) {
      error = tr('下载目录不存在。');
      _notify();
      return;
    }
    if (_tasks.any(
      (task) =>
          task.song.key == song.key &&
          task.quality == quality &&
          task.directory == directory &&
          ![DownloadPhase.failed, DownloadPhase.completed].contains(task.phase),
    )) {
      return;
    }
    _tasks.add(
      DownloadTask(
        id: '${DateTime.now().microsecondsSinceEpoch}-${AccountStore.randomHex(4)}',
        song: song,
        directory: directory,
        quality: quality,
      ),
    );
    _persist();
    _notify();
    unawaited(_drain());
  }

  void pause(DownloadTask task) {
    if (![
      DownloadPhase.downloading,
      DownloadPhase.queued,
    ].contains(task.phase)) {
      return;
    }
    task.phase = DownloadPhase.paused;
    if (_active == task) _cancellation?.cancel();
    _persist();
    _notify();
  }

  void resume(DownloadTask task) {
    if (_disposed ||
        !_readable ||
        ![DownloadPhase.paused, DownloadPhase.failed].contains(task.phase) ||
        _active == task) {
      return;
    }
    task.phase = DownloadPhase.queued;
    task.error = null;
    _persist();
    _notify();
    unawaited(_drain());
  }

  Future<void> remove(DownloadTask task, {bool deleteFiles = false}) async {
    if (_disposed || !_readable || !_tasks.contains(task)) return;
    if (_active == task) {
      pause(task);
      return;
    }
    try {
      if (deleteFiles &&
          task.phase == DownloadPhase.completed &&
          task.path != null) {
        final path = task.path!;
        final extension = paths.extension(path);
        if (paths.dirname(path) != task.directory ||
            extension.isEmpty ||
            !paths.basenameWithoutExtension(path).endsWith(' - ${task.id}')) {
          throw const FileSystemException(
            'Downloaded file ownership could not be verified',
          );
        }
        final audio = File(path);
        final type = await FileSystemEntity.type(path, followLinks: false);
        if (type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.file) {
          throw const FileSystemException(
            'Downloaded file is not a regular file',
          );
        }
        if (type == FileSystemEntityType.file) await audio.delete();
        if (task.lyricsOwned) {
          final lyric = File(paths.setExtension(path, '.lrc'));
          if (await FileSystemEntity.type(lyric.path, followLinks: false) ==
              FileSystemEntityType.file) {
            await lyric.delete();
          }
        }
      }
      final partial = File(task.partialPath);
      if (await partial.exists()) await partial.delete();
      _tasks.remove(task);
      _persist();
      _notify();
    } catch (_) {
      error = tr('无法移除下载记录或文件，请检查权限；不会删除无法确认归属的文件。');
      _notify();
    }
  }

  Future<void> _drain() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      while (!_disposed) {
        final task = _tasks
            .where((task) => task.phase == DownloadPhase.queued)
            .firstOrNull;
        if (task == null) break;
        _active = task;
        final cancellation = DownloadCancellation();
        _cancellation = cancellation;
        task.phase = DownloadPhase.downloading;
        _persist();
        _notify();
        try {
          final audio = await source.resolveDownload(task.song, task.quality);
          cancellation.check();
          const formats = [
            'mp3',
            'flac',
            'm4a',
            'aac',
            'ogg',
            'opus',
            'wav',
            'ape',
            'wma',
            'alac',
          ];
          var format = audio.format.toLowerCase();
          if (!formats.contains(format)) {
            format = paths
                .extension(audio.uri.path)
                .replaceFirst('.', '')
                .toLowerCase();
          }
          if (!formats.contains(format)) {
            throw       MusicSearchException(tr('平台未提供受支持的音频文件格式。'));
          }
          task.path ??= paths.join(
            task.directory,
            '${safeName('${task.song.artist} - ${task.song.title}')} - ${task.id}.$format',
          );
          _persist();
          await downloader.download(
            audio: audio,
            partial: File(task.partialPath),
            destination: File(task.path!),
            cancellation: cancellation,
            progress: (received, total) {
              task.received = received;
              task.total = total;
              _notify();
            },
          );
          task.phase = DownloadPhase.completed;
          task.error = null;
          await _saveLyrics(task, cancellation);
        } on DownloadCancelled {
          if (task.phase != DownloadPhase.completed) {
            task.phase = DownloadPhase.paused;
          }
        } catch (failure) {
          task.phase = DownloadPhase.failed;
          task.error = failure is MusicSearchException
              ? failure.message
              : tr('下载失败，请检查网络、磁盘空间与访问权限；可以重试续传。');
        } finally {
          _active = null;
          _cancellation = null;
          _persist();
          _notify();
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _saveLyrics(
    DownloadTask task,
    DownloadCancellation cancellation,
  ) async {
    final lyricSource = source;
    if (lyricSource is! OnlineAudioSource || task.path == null || _disposed) {
      return;
    }
    final file = File(paths.setExtension(task.path!, '.lrc'));
    var owned = false;
    try {
      final lyrics = await (lyricSource as OnlineAudioSource)
          .lyrics(task.song)
          .timeout(const Duration(seconds: 15));
      if (_disposed) return;
      cancellation.check();
      if (lyrics.trim().isEmpty) return;
      if (utf8.encode(lyrics).length > 2 * 1024 * 1024) {
        throw const FormatException('Lyrics too large');
      }
      final lrc = renderLrc(parseLrc(lyrics));
      if (lrc.isEmpty) return;
      final bytes = utf8.encode(lrc);
      if (bytes.length > 2 * 1024 * 1024) {
        throw const FormatException('Lyrics too large');
      }
      await file.create(exclusive: true);
      owned = true;
      await file.writeAsBytes(bytes, flush: true);
      task.lyricsOwned = true;
    } catch (_) {
      task.error = tr('音频已下载完成，但歌词未能保存；没有覆盖任何已有歌词文件。');
      if (owned) {
        try {
          await file.delete();
        } catch (_) {
          task.error = tr('音频已完成，但歌词写入及清理失败，请检查下载目录权限。');
        }
      }
    }
  }

  static String safeName(String value) {
    value = String.fromCharCodes(value.runes.take(100))
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '')
        .trim();
    if (value.isEmpty ||
        RegExp(
          r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)',
          caseSensitive: false,
        ).hasMatch(value)) {
      return 'NekoPlayer-$value';
    }
    return value;
  }

  void _persist() {
    if (!_readable || _disposed) return;
    final encoded = jsonEncode({
      'version': 1,
      'tasks': _tasks.map((task) => task.toJson()).toList(),
    });
    _writes = _writes.then((_) => store.write(encoded)).catchError((Object _) {
      error = tr('下载记录保存失败，请检查磁盘空间。');
      _notify();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_active?.phase == DownloadPhase.downloading) {
      _active!.phase = DownloadPhase.paused;
      _persist();
    }
    _disposed = true;
    _cancellation?.cancel();
    super.dispose();
  }
}
