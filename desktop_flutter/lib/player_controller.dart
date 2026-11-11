import './i18n/tr.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as paths;

import 'data/library_store.dart';
import 'domain/library.dart';
import 'domain/online_music.dart';
import 'playback/playback_engine.dart';
import 'download_controller.dart';
import 'data/cloud_library.dart';

class PlayerController extends ChangeNotifier {
  PlayerController({
    required this.engine,
    required this.store,
    this.onlineSource,
    this.downloads,
    Random? random,
  }) : _random = random ?? Random() {
    engine.addListener(_playbackChanged);
  }

  final PlaybackEngine engine;
  final LibraryStore store;
  final OnlineAudioSource? onlineSource;
  final DownloadController? downloads;
  final Random _random;
  List<Track> tracks = [];
  Set<String> favorites = {};
  List<String> history = [];
  List<LocalPlaylist> playlists = [];
  List<Track> queue = [];
  List<LyricLine> lyrics = [];
  RepeatMode repeat = RepeatMode.sequential;
  double volume = 75;
  double rate = 1;
  String preferredQuality = 'exhigh';
  bool showTranslation = true;
  bool doubleLyrics = true;
  bool fadePlayback = true;
  int fadeMilliseconds = 300;
  String? error;
  String? _lyricPath;
  String? _historyPath;
  bool _disposed = false;
  bool _storageReadable = true;
  bool busy = false;
  Future<void> _writes = Future.value();
  Future<void> _commands = Future.value();
  Timer? _sleepTimer;
  DateTime? sleepDeadline;
  PlaybackSession? _pendingSession;
  Timer? _sessionTimer;
  int _savedPosition = -1;
  double _engineVolume = 75;
  int _fadeToken = 0;

  PlaybackSession? get _session {
    if (_pendingSession != null) return _pendingSession;
    if (queue.isEmpty ||
        engine.currentPath == null ||
        engine.index < 0 ||
        engine.index >= queue.length) {
      return null;
    }
    return PlaybackSession(
      paths: queue.map((track) => track.path).toList(),
      index: engine.index,
      position: engine.position,
    );
  }

  static const extensions = [
    'mp3',
    'flac',
    'wav',
    'm4a',
    'aac',
    'ogg',
    'opus',
    'ape',
    'wma',
    'alac',
  ];

  bool get sessionPending => _pendingSession != null;
  int get queueIndex => _pendingSession?.index ?? engine.index;
  Duration get position => _pendingSession?.position ?? engine.position;
  Duration get duration => sessionPending ? Duration.zero : engine.duration;
  Track? get current {
    final session = _pendingSession;
    if (session != null && session.index >= 0 && session.index < queue.length) {
      return queue[session.index];
    }
    if (engine.currentPath == null) return null;
    if (engine.index >= 0 &&
        engine.index < queue.length &&
        queue[engine.index].path == engine.currentPath) {
      return queue[engine.index];
    }
    return queue.where((track) => track.path == engine.currentPath).firstOrNull;
  }

  List<Track> get recent => history
      .map((path) => tracks.where((track) => track.path == path).firstOrNull)
      .nonNulls
      .toList();

  /// Quality actually returned for the current stream. Local files fall back
  /// to their container extension because no network quality was negotiated.
  String? get currentQuality {
    final audio = engine.currentAudio;
    if (audio != null) {
      final label = describeAudioQuality(audio.quality, format: audio.format);
      if (label.isNotEmpty) return label;
    }
    final track = current;
    if (track != null && track.online == null) {
      final extension = paths.extension(track.path).replaceFirst('.', '');
      if (extension.isNotEmpty) return extension.toUpperCase();
    }
    return null;
  }

  int get lyricIndex => lyrics.lastIndexWhere((line) => line.time <= position);
  Future<void> get flushed => _writes;

  LibraryData get snapshot => LibraryData(
    tracks: List.of(tracks),
    favorites: Set.of(favorites),
    history: List.of(history),
    playlists: List.of(playlists),
    volume: volume,
    rate: rate,
    preferredQuality: preferredQuality,
    showTranslation: showTranslation,
    doubleLyrics: doubleLyrics,
    fadePlayback: fadePlayback,
    fadeMilliseconds: fadeMilliseconds,
    repeatMode: repeat.name,
    session: _session,
  );

  final List<void Function(String section)> _sectionListeners = [];
  bool get storageReadable => _storageReadable;

  /// 云同步分区（favorites / history / playlists）被本机修改时回调。
  void addSectionListener(void Function(String section) listener) =>
      _sectionListeners.add(listener);
  void removeSectionListener(void Function(String section) listener) =>
      _sectionListeners.remove(listener);
  void _touch(String section) {
    for (final listener in List.of(_sectionListeners)) {
      listener(section);
    }
  }

  /// 云同步拉取：直接采用 [next]，不记为本机修改。
  Future<void> applyCloudLibrary(LibraryData next) async {
    if (!_storageReadable) {
      throw       MusicSearchException(tr('本地音乐库读取失败，未覆盖原数据。'));
    }
    tracks = next.tracks;
    favorites = next.favorites.toSet();
    history = next.history.toList();
    playlists = next.playlists.toList();
    final write = _persist();
    _notify();
    await write;
  }

  Future<void> mergeCloud(Map<String, dynamic> remote) async {
    if (!_storageReadable) {
      throw       MusicSearchException(tr('本地音乐库读取失败，未合并或覆盖原数据。'));
    }
    final merged = CloudLibrary.merge(snapshot, CloudLibrary.decode(remote));
    tracks = merged.tracks;
    favorites = merged.favorites;
    history = merged.history;
    playlists = merged.playlists;
    for (final section in const ['favorites', 'history', 'playlists']) {
      _touch(section);
    }
    final write = _persist();
    _notify();
    await write;
  }

  Future<void> importPlaybackQueue(
    List<Track> importedTracks,
    PlaybackSession importedSession,
  ) async {
    final pendingTracks = List<Track>.of(importedTracks);
    final session = PlaybackSession.fromJson({
      ...importedSession.toJson(),
      'paths': List<String>.of(importedSession.paths),
    });
    final byPath = {for (final track in pendingTracks) track.path: track};
    if (pendingTracks.isEmpty ||
        pendingTracks.length > PlaybackSession.maxQueueLength ||
        pendingTracks.any(
          (track) => track.online == null || track.path != track.online!.key,
        ) ||
        session.paths.any((path) => !byPath.containsKey(path))) {
      throw       FormatException(tr('待导入的播放队列无效。'));
    }
    final command = _commands.then((_) async {
      if (_disposed) throw StateError('Player disposed');
      if (!_storageReadable) {
        throw       MusicSearchException(tr('本地音乐库读取失败，未覆盖播放队列。'));
      }
      await engine.clearQueue();
      final merged = {...byPath, for (final track in tracks) track.path: track};
      tracks = merged.values.toList();
      queue = session.paths.map((path) => merged[path]!).toList();
      _pendingSession = session;
      _savedPosition = -1;
      error = null;
      _historyPath = null;
      _lyricPath = null;
      lyrics = [];
      final write = _persist();
      _notify();
      await write;
    });
    _commands = command.catchError((Object failure) {
      error = failure is MusicSearchException
          ? failure.message
          : tr('播放队列导入未完成，请检查播放内核和存储空间。');
      _notify();
    });
    await command;
  }

  Future<void> initialize() async {
    try {
      final encoded = await store.read();
      final library = encoded == null
          ? const LibraryData()
          : LibraryData.decode(encoded);
      tracks = library.tracks;
      favorites = library.favorites.toSet();
      history = library.history.toList();
      playlists = library.playlists.toList();
      volume = library.volume;
      rate = library.rate;
      preferredQuality = library.preferredQuality;
      showTranslation = library.showTranslation;
      doubleLyrics = library.doubleLyrics;
      fadePlayback = library.fadePlayback;
      fadeMilliseconds = library.fadeMilliseconds;
      repeat =
          RepeatMode.values
              .where((mode) => mode.name == library.repeatMode)
              .firstOrNull ??
          RepeatMode.sequential;
      _pendingSession = library.session;
      if (_pendingSession != null) {
        final byPath = {for (final track in tracks) track.path: track};
        queue = _pendingSession!.paths.map((path) => byPath[path]!).toList();
      }
    } catch (_) {
      _storageReadable = false;
      error = tr('音乐库读取失败，已保留原数据；本次会话的修改不会覆盖它。');
    }
    await perform(() async {
      await engine.setVolume(volume);
      _engineVolume = volume;
      await engine.setRate(rate);
      await engine.setPreferredQuality(preferredQuality);
      await engine.setRepeatMode(repeat);
    });
    _sessionTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (engine.currentPath == null || _pendingSession != null) return;
      final position = engine.position.inSeconds;
      if (position != _savedPosition) {
        _savedPosition = position;
        unawaited(_persist().catchError((Object _) {}));
      }
    });
    _notify();
  }

  Future<void> _restoreSession({required bool play}) async {
    final session = _pendingSession;
    if (session == null || queue.isEmpty) return;
    await engine.open(queue, session.index, play: false);
    final offset =
        engine.duration > Duration.zero && session.position > engine.duration
        ? engine.duration
        : session.position;
    if (offset > Duration.zero) await engine.seek(offset);
    if (play) await _startWithFade(engine.toggle);
    _pendingSession = null;
    _playbackChanged();
    _notify();
  }

  /// Smoothly ramps the engine volume without changing the persisted user
  /// volume. Commands stay serialized by [perform], so the fade cannot fight
  /// with a seek/next operation.
  Future<void> _rampVolumeTo(double target) async {
    final total = fadePlayback ? fadeMilliseconds.clamp(0, 3000) : 0;
    if (total == 0 || volume <= 0) {
      _engineVolume = target;
      await engine.setVolume(target);
      return;
    }
    final token = ++_fadeToken;
    final steps = max(1, (total / 20).ceil());
    final start = _engineVolume;
    for (var step = 1; step <= steps; step++) {
      if (_disposed || token != _fadeToken) return;
      final value = start + (target - start) * step / steps;
      _engineVolume = value;
      await engine.setVolume(value);
      if (step < steps) {
        await Future<void>.delayed(
          Duration(milliseconds: max(1, (total / steps).round())),
        );
      }
    }
    _engineVolume = target;
  }

  Future<void> _startWithFade(Future<void> Function() start) async {
    if (!fadePlayback || fadeMilliseconds <= 0 || volume <= 0) {
      await start();
      _engineVolume = volume;
      return;
    }
    ++_fadeToken;
    _engineVolume = 0;
    await engine.setVolume(0);
    try {
      await start();
    } catch (_) {
      _engineVolume = volume;
      await engine.setVolume(volume);
      rethrow;
    }
    await _rampVolumeTo(volume);
  }

  Future<void> _pauseWithFade() async {
    if (!fadePlayback || fadeMilliseconds <= 0 || volume <= 0) {
      await engine.pause();
      _engineVolume = volume;
      return;
    }
    try {
      await _rampVolumeTo(0);
      await engine.pause();
    } finally {
      _engineVolume = volume;
      await engine.setVolume(volume);
    }
  }

  Future<void> perform(Future<void> Function() action) {
    _commands = _commands.then((_) async {
      if (_disposed) return;
      try {
        await action();
      } catch (failure) {
        error = failure is MusicSearchException
            ? failure.message
            : engine.error ?? tr('操作未完成，请检查音频文件与播放设备。');
        _notify();
      }
    });
    return _commands;
  }

  Future<void> importFiles(List<String> files) async {
    if (busy || _disposed) return;
    busy = true;
    _notify();
    try {
      final imported = <String, Track>{
        for (final track in tracks) track.path: track,
      };
      for (final file in files) {
        final path = paths.normalize(paths.absolute(file));
        if (!extensions.contains(
          paths.extension(path).replaceFirst('.', '').toLowerCase(),
        )) {
          continue;
        }
        if (imported.containsKey(path)) continue;
        if (!await File(path).exists()) continue;
        final name = paths.basenameWithoutExtension(path);
        final separator = name.indexOf(' - ');
        imported[path] = Track(
          path: path,
          title: separator < 0 ? name : name.substring(separator + 3),
          artist: separator < 0 ? tr('本地音乐') : name.substring(0, separator),
        );
      }
      tracks = imported.values.toList();
      _persist();
    } catch (_) {
      error = tr('部分文件无法读取，请检查访问权限。');
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> importDownload(DownloadTask task, {bool play = false}) =>
      perform(() async {
        final downloadedPath = task.path;
        if (task.phase != DownloadPhase.completed || downloadedPath == null) {
          throw       MusicSearchException(tr('下载尚未完成，请完成下载后再播放或导入。'));
        }
        final path = paths.normalize(paths.absolute(downloadedPath));
        if (!extensions.contains(
              paths.extension(path).replaceFirst('.', '').toLowerCase(),
            ) ||
            await FileSystemEntity.type(path, followLinks: false) !=
                FileSystemEntityType.file) {
          throw       MusicSearchException(tr('下载文件不存在或无法读取，请重新下载。'));
        }
        final track = Track(
          path: path,
          title: task.song.title,
          artist: task.song.artist,
        );
        tracks = {
          for (final existing in tracks) existing.path: existing,
          path: track,
        }.values.toList();
        error = null;
        await _persist();
        _notify();
        if (play) await _play([track], 0);
      });

  Future<void> play(List<Track> list, int index) =>
      perform(() => _play(list, index));

  Future<void> _play(List<Track> list, int index) async {
    if (list.length > PlaybackSession.maxQueueLength) {
      throw       MusicSearchException(tr('播放队列最多 100000 项。'));
    }
    if (list.isEmpty || index < 0 || index >= list.length) return;
    if (list[index].online == null && !await File(list[index].path).exists()) {
      error = tr('文件已移动或删除，请重新导入。');
      _notify();
      return;
    }
    final previousQueue = queue;
    queue = List.of(list);
    final imported = {for (final track in tracks) track.path: track};
    for (final track in list.where((track) => track.online != null)) {
      imported[track.path] = track;
    }
    tracks = imported.values.toList();
    error = null;
    _historyPath = null;
    await engine.setRepeatMode(repeat);
    try {
      await _startWithFade(() => engine.open(queue, index));
    } catch (_) {
      queue = previousQueue;
      rethrow;
    }
    _pendingSession = null;
    _playbackChanged();
    _persist();
    _notify();
  }

  Future<void> toggle() => perform(() async {
    if (_pendingSession != null) {
      await _restoreSession(play: true);
    } else if (current == null) {
      await _play(tracks, 0);
    } else if (engine.playing) {
      await _pauseWithFade();
    } else {
      await _startWithFade(engine.toggle);
    }
  });

  Future<void> pause() => perform(() async {
    if (!sessionPending || engine.playing) await _pauseWithFade();
  });

  Future<void> resume() => perform(() async {
    if (sessionPending) {
      await _restoreSession(play: true);
    } else if (current == null) {
      await _play(tracks, 0);
    } else if (!engine.playing) {
      await _startWithFade(engine.toggle);
    }
  });

  Future<void> next() => perform(() => _advance(1));
  Future<void> previous() => perform(() => _advance(-1));

  Future<void> _advance(int direction) async {
    final session = _pendingSession;
    if (session == null) {
      if (direction > 0) {
        await _startWithFade(engine.next);
      } else {
        await _startWithFade(engine.previous);
      }
      return;
    }
    if (queue.isEmpty) return;
    final selected = repeat == RepeatMode.shuffle && queue.length > 1
        ? (session.index + 1 + _random.nextInt(queue.length - 1)) % queue.length
        : (session.index + direction + queue.length) % queue.length;
    _pendingSession = PlaybackSession(
      paths: session.paths,
      index: selected,
      position: Duration.zero,
    );
    _persist();
    _notify();
    await _restoreSession(play: true);
  }

  Future<void> seek(Duration target) => perform(() => _seek(target));

  Future<void> _seek(Duration target) async {
    if (current == null) return;
    final session = _pendingSession;
    final upper = session != null
        ? PlaybackSession.maxPosition
        : engine.duration;
    if (upper <= Duration.zero) return;
    final bounded = Duration(
      microseconds: target.inMicroseconds.clamp(0, upper.inMicroseconds),
    );
    if (session != null) {
      _pendingSession = PlaybackSession(
        paths: session.paths,
        index: session.index,
        position: bounded,
      );
    } else {
      await engine.seek(bounded);
    }
    _persist();
    _notify();
  }

  Future<void> stop() => perform(() async {
    if (!sessionPending || engine.playing) await _pauseWithFade();
    await _seek(Duration.zero);
  });

  Future<void> enqueue(Track track) => perform(() async {
    if (queue.length >= PlaybackSession.maxQueueLength) {
      throw       MusicSearchException(tr('播放队列最多 100000 项。'));
    }
    final session = _pendingSession;
    if (session != null) {
      queue = [...queue, track];
      _pendingSession = PlaybackSession(
        paths: queue.map((track) => track.path).toList(),
        index: session.index,
        position: session.position,
      );
      if (!tracks.any((item) => item.path == track.path)) {
        tracks = [...tracks, track];
      }
      _persist();
      _notify();
      return;
    }
    if (queue.isEmpty || current == null) {
      await _play([track], 0);
      return;
    }
    final selected = engine.index;
    final pending = [...queue, track];
    await engine.replaceQueue(pending, selected);
    queue = pending;
    if (track.online != null &&
        !tracks.any((item) => item.path == track.path)) {
      tracks = [...tracks, track];
    }
    _persist();
    _notify();
  });

  Future<void> moveInQueue(int from, int to) => perform(() async {
    if (from < 0 ||
        from >= queue.length ||
        to < 0 ||
        to >= queue.length ||
        from == to) {
      return;
    }
    final session = _pendingSession;
    var selected = session?.index ?? engine.index;
    final pending = List<Track>.of(queue);
    pending.insert(to, pending.removeAt(from));
    if (selected == from) {
      selected = to;
    } else if (from < selected && to >= selected) {
      selected--;
    } else if (from > selected && to <= selected) {
      selected++;
    }
    if (session == null) {
      await engine.replaceQueue(pending, selected);
    } else {
      _pendingSession = PlaybackSession(
        paths: pending.map((track) => track.path).toList(),
        index: selected,
        position: session.position,
      );
    }
    queue = pending;
    _persist();
    _notify();
  });

  Future<void> removeFromQueue(int index) => perform(() async {
    if (index < 0 || index >= queue.length) return;
    if (queue.length == 1) {
      await engine.clearQueue();
      queue = [];
      _pendingSession = null;
      _persist();
      _notify();
      return;
    }
    final session = _pendingSession;
    final selected = session?.index ?? engine.index;
    final pending = List<Track>.of(queue)..removeAt(index);
    if (session != null) {
      queue = pending;
      _pendingSession = PlaybackSession(
        paths: pending.map((track) => track.path).toList(),
        index: index < selected
            ? selected - 1
            : selected.clamp(0, pending.length - 1),
        position: index == selected ? Duration.zero : session.position,
      );
      _persist();
      _notify();
      return;
    }
    if (index == selected) {
      await _play(pending, index.clamp(0, pending.length - 1));
      return;
    }
    await engine.replaceQueue(
      pending,
      index < selected ? selected - 1 : selected,
    );
    queue = pending;
    _persist();
    _notify();
  });

  Future<void> clearQueue() => perform(() async {
    await engine.clearQueue();
    queue = [];
    _pendingSession = null;
    lyrics = [];
    _lyricPath = null;
    _persist();
    _notify();
  });

  void toggleFavorite(Track track) {
    if (!tracks.any((item) => item.path == track.path)) {
      tracks = [...tracks, track];
    }
    if (!favorites.remove(track.path)) favorites.add(track.path);
    _touch('favorites');
    _persist();
    _notify();
  }

  String? createPlaylist(String name) {
    if (name.trim().isEmpty) return null;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    playlists = [...playlists, LocalPlaylist(id: id, name: name.trim())];
    _touch('playlists');
    _persist();
    _notify();
    return id;
  }

  void deletePlaylist(String id) {
    playlists = playlists.where((playlist) => playlist.id != id).toList();
    _touch('playlists');
    _persist();
    _notify();
  }

  void addToPlaylist(String id, Track track) {
    if (!playlists.any((playlist) => playlist.id == id)) return;
    if (!tracks.any((item) => item.path == track.path)) {
      tracks = [...tracks, track];
    }
    playlists = playlists
        .map(
          (playlist) => playlist.id == id
              ? playlist.withPaths({...playlist.paths, track.path}.toList())
              : playlist,
        )
        .toList();
    _touch('playlists');
    _persist();
    _notify();
  }

  void removeFromPlaylist(String id, Track track) {
    playlists = playlists
        .map(
          (playlist) => playlist.id == id
              ? playlist.withPaths(
                  playlist.paths.where((path) => path != track.path).toList(),
                )
              : playlist,
        )
        .toList();
    _touch('playlists');
    _persist();
    _notify();
  }

  List<Track> playlistTracks(LocalPlaylist playlist) => playlist.paths
      .map((path) => tracks.where((track) => track.path == path).firstOrNull)
      .nonNulls
      .toList();

  void setVolume(double value) {
    volume = value.clamp(0, 100);
    ++_fadeToken;
    _engineVolume = volume;
    unawaited(perform(() => engine.setVolume(volume)));
    _persist();
    _notify();
  }

  void setFadePlayback({bool? enabled, int? milliseconds}) {
    fadePlayback = enabled ?? fadePlayback;
    if (milliseconds != null) {
      fadeMilliseconds = milliseconds.clamp(50, 3000).toInt();
    }
    _persist();
    _notify();
  }

  void setRate(double value) {
    rate = value.clamp(0.5, 2);
    unawaited(perform(() => engine.setRate(rate)));
    _persist();
    _notify();
  }

  void setPreferredQuality(String quality) {
    preferredQuality = quality;
    unawaited(perform(() => engine.setPreferredQuality(quality)));
    _persist();
    _notify();
  }

  void setLyricPreferences({bool? translation, bool? twoLines}) {
    showTranslation = translation ?? showTranslation;
    doubleLyrics = twoLines ?? doubleLyrics;
    _persist();
    _notify();
  }

  Future<void> importPlaybackPreferences({
    double? speed,
    String? quality,
    bool? translation,
    bool? twoLines,
  }) async {
    if (!_storageReadable) {
      throw       MusicSearchException(tr('本地音乐库读取失败，未覆盖播放设置。'));
    }
    if (speed != null && (!speed.isFinite || speed < .5 || speed > 2)) {
      throw       FormatException(tr('播放速度无效。'));
    }
    if (speed != null) await engine.setRate(speed);
    if (quality != null) await engine.setPreferredQuality(quality);
    rate = speed ?? rate;
    preferredQuality = quality ?? preferredQuality;
    showTranslation = translation ?? showTranslation;
    doubleLyrics = twoLines ?? doubleLyrics;
    final write = _persist();
    _notify();
    await write;
  }

  void cycleRepeat() {
    setRepeatMode(
      RepeatMode.values[(repeat.index + 1) % RepeatMode.values.length],
    );
  }

  void setRepeatMode(RepeatMode mode) {
    repeat = mode;
    unawaited(perform(() => engine.setRepeatMode(repeat)));
    _persist();
    _notify();
  }

  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    sleepDeadline = duration == null ? null : DateTime.now().add(duration);
    if (duration != null) {
      _sleepTimer = Timer(duration, () {
        sleepDeadline = null;
        unawaited(pause());
        _notify();
      });
    }
    _notify();
  }

  void dismissError() {
    error = null;
    _notify();
  }

  void _playbackChanged() {
    if (sessionPending) {
      if (engine.error != null && engine.error != error) {
        error = engine.error;
        _notify();
      }
      return;
    }
    final track = current;
    var changed = false;
    if (track?.path != _lyricPath) {
      changed = true;
      _lyricPath = track?.path;
      lyrics = [];
      if (track != null) unawaited(_readLyrics(track));
    }
    if (track != null && engine.playing && _historyPath != track.path) {
      changed = true;
      _historyPath = track.path;
      history = [
        track.path,
        ...history.where((path) => path != track.path),
      ].take(CloudLibrary.historyLimit).toList();
      _touch('history');
      _persist();
    }
    if (engine.error != null && engine.error != error) {
      error = engine.error;
      changed = true;
    }
    if (changed) _notify();
  }

  Future<void> _readLyrics(Track track) async {
    final path = track.path;
    try {
      String content;
      if (track.online != null) {
        content = await onlineSource?.lyrics(track.online!) ?? '';
      } else {
        final file = File(paths.setExtension(path, '.lrc'));
        content = await file.exists() && await file.length() <= 2 * 1024 * 1024
            ? await file.readAsString()
            : '';
      }
      if (_lyricPath == path && !_disposed) {
        lyrics = parseLrc(content);
        _notify();
      }
    } catch (_) {
      if (_lyricPath == path && !_disposed) {
        lyrics = [];
        _notify();
      }
    }
  }

  Future<void> _persist() {
    if (!_storageReadable) return Future.value();
    final encoded = snapshot.encode();
    final write = _writes.then((_) => store.write(encoded));
    _writes = write.catchError((Object failure) {
      error = tr('保存音乐库失败，请检查磁盘空间与访问权限。');
      _notify();
    });
    return write;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_persist().catchError((Object _) {}));
    _disposed = true;
    _sessionTimer?.cancel();
    _sleepTimer?.cancel();
    engine.removeListener(_playbackChanged);
    engine.dispose();
    downloads?.dispose();
    super.dispose();
  }
}
