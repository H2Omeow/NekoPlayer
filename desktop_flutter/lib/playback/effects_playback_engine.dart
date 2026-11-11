import '../i18n/tr.dart';
import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/audio_effects.dart';
import '../domain/library.dart';
import '../domain/online_music.dart';
import 'dsp_playback_engine.dart';
import 'playback_engine.dart';

class EffectsPlaybackEngine extends PlaybackEngine {
  EffectsPlaybackEngine({
    OnlineAudioSource? onlineSource,
    PlaybackEngine? normal,
    DspPlaybackEngine? professional,
    Future<String?> Function()? readSettings,
    Future<void> Function(String)? writeSettings,
  }) : normal = normal ?? MediaKitEngine(onlineSource: onlineSource),
       professional =
           professional ?? DspPlaybackEngine(onlineSource: onlineSource),
       _readSettings =
           readSettings ??
           (() => SharedPreferencesAsync().getString(
             'nekoplayer.flutter.effects.v1',
           )),
       _writeSettings =
           writeSettings ??
           ((value) => SharedPreferencesAsync().setString(
             'nekoplayer.flutter.effects.v1',
             value,
           )) {
    this.normal.addListener(_changed);
    this.professional.addListener(_changed);
  }
  final PlaybackEngine normal;
  final DspPlaybackEngine professional;
  final Future<String?> Function() _readSettings;
  final Future<void> Function(String) _writeSettings;
  AudioEffects effects = const AudioEffects();
  PlaybackEngine get active => effects.enabled ? professional : normal;
  List<Track> _tracks = [];
  bool _disposed = false;
  bool changing = false;
  String? effectsError;
  bool _settingsReadable = true;
  Future<void> _writes = Future.value();

  Future<void> initializeEffects() async {
    try {
      final raw = await _readSettings();
      if (raw != null) {
        effects = AudioEffects.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        ).copyWith(enabled: false);
        professional.configure(effects);
      }
    } catch (_) {
      _settingsReadable = false;
      effectsError = tr('音效设置读取失败，已保留原配置；本次修改不覆盖它。');
    }
  }

  Future<void> configure(AudioEffects next) async {
    if (changing || _disposed) return;
    changing = true;
    effectsError = null;
    notifyListeners();
    final previous = effects;
    final old = active;
    final target = next.enabled ? professional : normal;
    final wasPlaying = old.playing;
    final offset = old.position;
    final selected = old.index;
    try {
      professional.configure(next);
      if (next.enabled != previous.enabled && _tracks.isNotEmpty) {
        await old.pause();
        try {
          await target.open(_tracks, selected, play: false);
          if (offset > Duration.zero) await target.seek(offset);
          if (wasPlaying) await target.toggle();
        } catch (_) {
          if (next.enabled) {
            await professional.stop();
          } else {
            await normal.pause();
          }
          if (wasPlaying && !old.playing) await old.toggle();
          rethrow;
        }
      }
      effects = next;
      if (!next.enabled && previous.enabled) await professional.stop();
      if (_settingsReadable) {
        final encoded = jsonEncode(effects.toJson());
        final write = _writes.then((_) => _writeSettings(encoded));
        _writes = write.catchError((Object _) {});
        try {
          await write;
        } catch (_) {
          effectsError = tr('音效已应用，但设置保存失败。');
        }
      }
    } catch (_) {
      professional.configure(previous);
      effectsError = tr('音效切换失败，已保留原播放模式。请确认同架构解码组件完整，且音频设备可用。');
    } finally {
      changing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> importParameters(AudioEffects imported) async {
    if (!_settingsReadable || changing || _disposed) {
      throw StateError(tr('音效设置不可写或正在切换，未导入。'));
    }
    final snapshot = AudioEffects.fromJson(imported.toJson());
    await configure(snapshot.copyWith(enabled: effects.enabled));
    if (effectsError != null) throw StateError(effectsError!);
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  bool get playing => active.playing;
  @override
  bool get buffering => changing || active.buffering;
  @override
  Duration get position => active.position;
  @override
  Duration get duration => active.duration;
  @override
  int get index => active.index;
  @override
  String? get currentPath => active.currentPath;
  @override
  ResolvedAudio? get currentAudio => active.currentAudio;
  @override
  String? get error => active.error;
  @override
  Future<void> open(List<Track> tracks, int index, {bool play = true}) async {
    if (changing) throw StateError('Audio effects switch in progress');
    await active.open(tracks, index, play: play);
    _tracks = List.of(tracks);
  }

  @override
  Future<void> replaceQueue(List<Track> tracks, int index) async {
    if (changing) throw StateError('Audio effects switch in progress');
    await active.replaceQueue(tracks, index);
    _tracks = List.of(tracks);
  }

  @override
  Future<void> clearQueue() async {
    if (changing) throw StateError('Audio effects switch in progress');
    await normal.clearQueue();
    await professional.clearQueue();
    _tracks = [];
  }

  @override
  Future<void> toggle() => active.toggle();
  @override
  Future<void> pause() => active.pause();
  @override
  Future<void> next() => active.next();
  @override
  Future<void> previous() => active.previous();
  @override
  Future<void> seek(Duration position) => active.seek(position);
  @override
  Future<void> setVolume(double value) async {
    await normal.setVolume(value);
    await professional.setVolume(value);
  }

  @override
  Future<void> setRate(double value) async {
    await normal.setRate(value);
    await professional.setRate(value);
  }

  @override
  Future<void> setRepeatMode(RepeatMode mode) async {
    await normal.setRepeatMode(mode);
    await professional.setRepeatMode(mode);
  }

  @override
  Future<void> setPreferredQuality(String quality) async {
    await normal.setPreferredQuality(quality);
    await professional.setPreferredQuality(quality);
  }

  @override
  void dispose() {
    _disposed = true;
    normal.removeListener(_changed);
    professional.removeListener(_changed);
    normal.dispose();
    professional.dispose();
    super.dispose();
  }
}
