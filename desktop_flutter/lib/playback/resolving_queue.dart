import '../i18n/tr.dart';
import 'dart:math';

import '../domain/library.dart';
import '../domain/online_music.dart';
import 'playback_engine.dart' show RepeatMode;

class ResolvingQueue {
  ResolvingQueue({
    required this.load,
    this.loadAudio,
    this.source,
    Random? random,
  }) : random = random ?? Random();

  final Future<void> Function(Uri uri) load;
  final Future<void> Function(ResolvedAudio audio)? loadAudio;
  final OnlineAudioSource? source;
  final Random random;
  List<Track> _tracks = [];
  int index = 0;
  RepeatMode repeat = RepeatMode.sequential;
  String preferredQuality = 'exhigh';
  ResolvedAudio? currentAudio;
  Track? get current => _tracks.isEmpty ? null : _tracks[index];
  void clear() {
    _tracks = [];
    index = 0;
    currentAudio = null;
  }

  void replace(List<Track> tracks, int selected) {
    if (tracks.isEmpty ||
        selected < 0 ||
        selected >= tracks.length ||
        current?.path != tracks[selected].path) {
      throw ArgumentError(
        'Queue edits must preserve the currently playing track',
      );
    }
    _tracks = List.of(tracks);
    index = selected;
  }

  Future<void> open(List<Track> tracks, int selected) async {
    if (selected < 0 || selected >= tracks.length) return;
    final pending = List<Track>.of(tracks);
    await _load(pending[selected]);
    _tracks = pending;
    index = selected;
  }

  Future<bool> advance(int direction, {bool automatic = false}) async {
    if (_tracks.isEmpty) return false;
    var selected = index + direction;
    if (automatic && repeat == RepeatMode.single) {
      selected = index;
    } else if (repeat == RepeatMode.shuffle && _tracks.length > 1) {
      selected =
          (index + 1 + random.nextInt(_tracks.length - 1)) % _tracks.length;
    } else if (selected >= _tracks.length || selected < 0) {
      if (automatic && repeat == RepeatMode.sequential) return false;
      selected = (selected + _tracks.length) % _tracks.length;
    }
    await _load(_tracks[selected]);
    index = selected;
    return true;
  }

  Future<void> _load(Track track) async {
    if (track.online != null && source == null) {
      throw       MusicSearchException(tr('在线播放服务未初始化。'));
    }
    currentAudio = null;
    final audio = track.online == null
        ? ResolvedAudio(Uri.file(track.path), '')
        : await source!.resolve(track.online!, preferred: preferredQuality);
    currentAudio = audio;
    if (loadAudio != null) {
      await loadAudio!(audio);
    } else {
      await load(audio.uri);
    }
  }
}
