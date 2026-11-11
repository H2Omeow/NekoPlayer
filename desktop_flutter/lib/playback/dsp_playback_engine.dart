import '../i18n/tr.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as paths;

import '../diagnostics/crash_log.dart';
import '../diagnostics/process_tail.dart';
import '../domain/audio_effects.dart';
import '../domain/library.dart';
import '../domain/online_music.dart';
import 'pcm_sink.dart';
import 'playback_engine.dart';
import 'resolving_queue.dart';

class DspPlaybackEngine extends PlaybackEngine {
  DspPlaybackEngine({
    OnlineAudioSource? onlineSource,
    PcmSink Function()? sinkFactory,
  }) : _sinkFactory = sinkFactory ?? PcmSink.new {
    _queue = ResolvingQueue(
      source: onlineSource,
      load: (uri) async => _start(uri, Duration.zero, play: _playOnLoad),
      loadAudio: (audio) async {
        if (audio.headers.entries.any(
          (entry) =>
              !RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(entry.key) ||
              entry.value.contains(RegExp(r'[\r\n]')),
        )) {
          throw       FormatException(tr('音频请求头无效。'));
        }
        final previous = _headers;
        _headers = audio.headers;
        try {
          await _start(audio.uri, Duration.zero, play: _playOnLoad);
        } catch (_) {
          _headers = previous;
          rethrow;
        }
      },
    );
  }
  late final ResolvingQueue _queue;
  final PcmSink Function() _sinkFactory;
  AudioEffects effects = const AudioEffects();
  PcmSink? _sink;
  Process? _process;
  Future<void>? _pump;
  Timer? _ticker;
  Uri? _uri;
  Map<String, String> _headers = const {};
  int _generation = 0;
  int _reportedFaults = 0;
  bool _disposed = false;
  bool _playing = false;
  bool _playOnLoad = true;
  bool _buffering = false;
  int _index = 0;
  String? _currentPath;
  String? _error;
  Duration _offset = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 75;
  double _rate = 1;
  Future<void> _commands = Future.value();

  @override
  bool get playing => _playing;
  @override
  bool get buffering => _buffering;
  @override
  Duration get position =>
      _offset +
      Duration(
        microseconds: ((_sink?.playedFrames ?? 0) * _rate * 1000000 / 48000)
            .round(),
      );
  @override
  Duration get duration => _duration;
  @override
  int get index => _index;
  @override
  String? get currentPath => _currentPath;
  @override
  ResolvedAudio? get currentAudio => _queue.currentAudio;
  @override
  String? get error => _error;

  static String executable(String name) {
    final override = switch (name) {
      'ffmpeg' => Platform.environment['NEKOPLAYER_FFMPEG'],
      'ffprobe' => Platform.environment['NEKOPLAYER_FFPROBE'],
      _ => null,
    };
    if (override != null && override.isNotEmpty) {
      return override;
    }
    final filename = '$name${Platform.isWindows ? '.exe' : ''}';
    final bundled = paths.join(
      paths.dirname(Platform.resolvedExecutable),
      'native',
      filename,
    );
    return File(bundled).existsSync() ? bundled : filename;
  }

  List<String> inputOptions(Uri uri) => [
    '-protocol_whitelist',
    uri.scheme == 'file' ? 'file,pipe' : 'http,https,tcp,tls',
    if (uri.scheme == 'https') ...['-tls_verify', '1'],
    if (uri.scheme != 'file') ...['-rw_timeout', '15000000'],
    if (uri.scheme != 'file' && _headers.isNotEmpty) ...[
      '-headers',
      _headers.entries
          .map((entry) => '${entry.key}: ${entry.value}\r\n')
          .join(),
    ],
  ];

  Future<Duration> probe(Uri uri) async {
    Process? process;
    ProcessTail? tail;
    try {
      process = await Process.start(executable('ffprobe'), [
        '-v',
        'error',
        '-threads',
        '1',
        ...inputOptions(uri),
        '-show_entries',
        'format=duration',
        '-of',
        'json',
        uri.scheme == 'file' ? uri.toFilePath() : uri.toString(),
      ], runInShell: false);
      tail = ProcessTail(process.stderr);
      final bytes = <int>[];
      await for (final chunk in process.stdout.timeout(
        const Duration(seconds: 15),
      )) {
        if (bytes.length + chunk.length > 16384) return Duration.zero;
        bytes.addAll(chunk);
      }
      final code = await process.exitCode;
      if (code != 0) {
        CrashLog.warn(
          'ffprobe',
          'ffprobe exited with $code: ${await tail.settled()}',
        );
        return Duration.zero;
      }
      final body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final seconds = double.tryParse(
        (body['format'] as Map?)?['duration']?.toString() ?? '',
      );
      return seconds != null && seconds.isFinite && seconds > 0
          ? Duration(microseconds: (seconds * 1000000).round())
          : Duration.zero;
    } catch (failure) {
      CrashLog.warn('ffprobe', 'probe failed: $failure ${tail?.text ?? ''}');
      return Duration.zero;
    } finally {
      process?.kill();
    }
  }

  Future<void> _serialize(Future<void> Function() action) {
    final command = _commands.then((_) async {
      if (_disposed) return;
      try {
        await action();
      } catch (failure, stack) {
        CrashLog.error(
          'dsp',
          'DSP command failed',
          error: failure,
          stack: stack,
        );
        _error = failure is MusicSearchException
            ? failure.message
            : tr('专业 DSP 播放失败，请检查 FFmpeg、系统音频设备和音源权限。');
        _buffering = false;
        if (!_disposed) notifyListeners();
        rethrow;
      }
    });
    _commands = command.catchError((Object _) {});
    return command;
  }

  Future<void> _stop() async {
    _generation++;
    _ticker?.cancel();
    _ticker = null;
    final process = _process;
    _process = null;
    process?.kill();
    if (process != null) {
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {
        process.kill(ProcessSignal.sigkill);
      }
    }
    try {
      await _pump;
    } catch (failure, stack) {
      CrashLog.error('dsp', 'Pump failed', error: failure, stack: stack);
    }
    _pump = null;
    _sink?.dispose();
    _sink = null;
  }

  Future<void> stop() => _serialize(() async {
    _offset = position;
    await _stop();
    _playing = false;
    if (!_disposed) notifyListeners();
  });

  @override
  Future<void> replaceQueue(List<Track> tracks, int index) =>
      _serialize(() async {
        _queue.replace(tracks, index);
        _index = index;
        notifyListeners();
      });

  @override
  Future<void> clearQueue() => _serialize(() async {
    await _stop();
    _queue.clear();
    _uri = null;
    _currentPath = null;
    _index = 0;
    _offset = Duration.zero;
    _duration = Duration.zero;
    _playing = false;
    _buffering = false;
    notifyListeners();
  });

  Future<void> _start(Uri uri, Duration offset, {bool play = true}) async {
    PcmSink? pendingSink;
    Process? pendingProcess;
    ProcessTail? tail;
    StreamIterator<List<int>>? stream;
    _buffering = true;
    notifyListeners();
    try {
      pendingProcess = await Process.start(executable('ffmpeg'), [
        '-hide_banner',
        '-loglevel',
        'error',
        '-nostdin',
        '-threads',
        '1',
        ...inputOptions(uri),
        '-ss',
        '${offset.inMicroseconds / 1000000}',
        '-i',
        uri.scheme == 'file' ? uri.toFilePath() : uri.toString(),
        '-vn',
        '-sn',
        '-dn',
        '-threads',
        '1',
        '-filter_threads',
        '1',
        if (_rate != 1) ...['-af', 'atempo=$_rate'],
        '-f',
        's16le',
        '-acodec',
        'pcm_s16le',
        '-ar',
        '48000',
        '-ac',
        '2',
        'pipe:1',
      ], runInShell: false);
      tail = ProcessTail(pendingProcess.stderr);
      stream = StreamIterator(pendingProcess.stdout);
      if (!await stream.moveNext().timeout(const Duration(seconds: 20))) {
        throw       MusicSearchException(tr('FFmpeg 未解码出音频；请确认音源可播放。'));
      }
      final duration = _uri == uri && _duration > Duration.zero
          ? _duration
          : await probe(uri);
      if (_disposed) return;
      // Release the previous audio device before opening the next one so two
      // devices are never alive at once.
      await _stop();
      if (_disposed) return;
      pendingSink = _sinkFactory();
      pendingSink.configure(effects);
      pendingSink.volume(_volume / 100);
      final sink = pendingSink;
      final process = pendingProcess;
      final input = stream;
      pendingSink = null;
      pendingProcess = null;
      stream = null;
      _sink = sink;
      _process = process;
      _uri = uri;
      _offset = offset;
      _duration = duration;
      _error = null;
      _playing = play;
      _buffering = false;
      sink.pause(!play);
      final generation = _generation;
      _pump = _consume(input, process, sink, generation, tail);
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (_disposed) return;
        _buffering = _playing && sink.bufferedSamples == 0;
        final faults = sink.faults;
        if (faults > _reportedFaults) {
          _reportedFaults = faults;
          CrashLog.error(
            'dsp',
            'Audio callback raised an exception ($faults total); '
                'native DSP produced silence for the affected buffers',
          );
        }
        notifyListeners();
      });
    } catch (failure) {
      if (pendingProcess != null) {
        CrashLog.error(
          'ffmpeg',
          'DSP start failed: $failure\nffmpeg stderr tail: ${await tail?.settled() ?? ''}',
        );
      }
      if (_sink == null) {
        // The previous session was already torn down above.
        _playing = false;
        _ticker?.cancel();
        _ticker = null;
      }
      rethrow;
    } finally {
      pendingProcess?.kill();
      await stream?.cancel();
      pendingSink?.dispose();
    }
  }

  Future<void> _consume(
    StreamIterator<List<int>> input,
    Process process,
    PcmSink sink,
    int generation,
    ProcessTail tail,
  ) async {
    final buffer = calloc<Int16>(32768);
    var carry = <int>[];
    try {
      do {
        if (_disposed || generation != _generation) return;
        final bytes = carry.isEmpty
            ? input.current
            : [...carry, ...input.current];
        final usable = bytes.length - bytes.length % 4;
        carry = bytes.sublist(usable);
        var offset = 0;
        while (offset < usable && !_disposed && generation == _generation) {
          final count = (usable - offset).clamp(0, 65536);
          buffer
              .cast<Uint8>()
              .asTypedList(count)
              .setRange(0, count, bytes, offset);
          var written = 0;
          while (written < count ~/ 2 &&
              !_disposed &&
              generation == _generation) {
            final accepted = sink.write(buffer + written, count ~/ 2 - written);
            if (accepted < 0) throw StateError('Invalid PCM frame');
            written += accepted;
            if (accepted == 0) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          }
          offset += count;
        }
      } while (await input.moveNext());
      if (_disposed || generation != _generation) return;
      final code = await process.exitCode;
      if (code != 0 || carry.isNotEmpty) {
        CrashLog.error(
          'ffmpeg',
          'ffmpeg exited with $code (partial frame bytes: ${carry.length})\n'
              'ffmpeg stderr tail: ${await tail.settled()}',
        );
        throw       MusicSearchException(tr('FFmpeg 解码中断，请重新播放。'));
      }
      while (sink.bufferedSamples > 0 &&
          !_disposed &&
          generation == _generation) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      if (_disposed || generation != _generation) return;
      _playing = false;
      _buffering = false;
      _ticker?.cancel();
      notifyListeners();
      scheduleMicrotask(() {
        unawaited(
          _serialize(
            () => _advance(1, automatic: true),
          ).catchError((Object _) {}),
        );
      });
    } catch (failure, stack) {
      if (!_disposed && generation == _generation) {
        if (failure is! MusicSearchException) {
          CrashLog.error(
            'dsp',
            'Decode pump failed\nffmpeg stderr tail: ${tail.text}',
            error: failure,
            stack: stack,
          );
        }
        _error = failure is MusicSearchException
            ? failure.message
            : tr('音频解码中断，请重试。');
        _playing = false;
        _buffering = false;
        sink.pause(true);
        _ticker?.cancel();
        notifyListeners();
      }
    } finally {
      await input.cancel();
      calloc.free(buffer);
    }
  }

  void configure(AudioEffects value) {
    effects = value;
    try {
      _sink?.configure(value);
    } catch (failure, stack) {
      CrashLog.error(
        'dsp',
        'Applying DSP settings failed',
        error: failure,
        stack: stack,
      );
      rethrow;
    }
  }

  Future<void> _advance(int direction, {bool automatic = false}) async {
    if (await _queue.advance(direction, automatic: automatic)) {
      _index = _queue.index;
      _currentPath = _queue.current?.path;
      notifyListeners();
    }
  }

  @override
  Future<void> open(List<Track> tracks, int index, {bool play = true}) =>
      _serialize(() async {
        if (tracks.isEmpty || index < 0 || index >= tracks.length) return;
        _playOnLoad = play;
        try {
          await _queue.open(tracks, index);
        } finally {
          _playOnLoad = true;
        }
        _index = _queue.index;
        _currentPath = _queue.current?.path;
        notifyListeners();
      });
  @override
  Future<void> toggle() async {
    if (_sink == null && _uri != null) {
      await _serialize(() => _start(_uri!, _offset));
      return;
    }
    _playing = !_playing;
    _sink?.pause(!_playing);
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _sink?.pause(true);
    notifyListeners();
  }

  @override
  Future<void> next() => _serialize(() => _advance(1));
  @override
  Future<void> previous() => _serialize(() => _advance(-1));
  @override
  Future<void> seek(Duration position) => _serialize(() async {
    if (_uri != null) {
      await _start(
        _uri!,
        position < Duration.zero ? Duration.zero : position,
        play: _playing,
      );
    }
    notifyListeners();
  });
  @override
  Future<void> setVolume(double value) async {
    _volume = value.clamp(0, 100);
    _sink?.volume(_volume / 100);
  }

  @override
  Future<void> setRate(double value) => _serialize(() async {
    final offset = position;
    final previous = _rate;
    _rate = value.clamp(.5, 2);
    try {
      if (_uri != null && _sink != null) {
        await _start(_uri!, offset, play: _playing);
      }
    } catch (_) {
      _rate = previous;
      rethrow;
    }
  });
  @override
  Future<void> setRepeatMode(RepeatMode mode) async {
    _queue.repeat = mode;
  }

  @override
  Future<void> setPreferredQuality(String quality) async {
    _queue.preferredQuality = quality;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _ticker?.cancel();
    _ticker = null;
    // Tear down synchronously: the queued _stop below may never get to run.
    _process?.kill(ProcessSignal.sigkill);
    _sink?.dispose();
    _sink = null;
    unawaited(
      _commands
          .then((_) => _stop())
          .catchError(
            (Object failure, StackTrace stack) => CrashLog.error(
              'dsp',
              'Dispose cleanup failed',
              error: failure,
              stack: stack,
            ),
          ),
    );
    super.dispose();
  }
}
