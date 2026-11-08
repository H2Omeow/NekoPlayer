import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as paths;

import '../domain/audio_effects.dart';

class PcmSink {
  PcmSink._(this.library, this.handle);
  final DynamicLibrary library;
  final Pointer<Void> handle;
  bool _disposed = false;
  static DynamicLibrary openLibrary() {
    final executable = paths.dirname(Platform.resolvedExecutable);
    return DynamicLibrary.open(
      paths.join(
        executable,
        Platform.isWindows ? 'nekoplayer_dsp.dll' : 'lib/libnekoplayer_dsp.so',
      ),
    );
  }

  factory PcmSink({DynamicLibrary? library, bool silent = false}) {
    final loaded = library ?? openLibrary();
    final create = loaded
        .lookupFunction<
          Pointer<Void> Function(Int32),
          Pointer<Void> Function(int)
        >('neko_sink_create');
    final handle = create(silent ? 1 : 0);
    if (handle == nullptr) throw StateError('Audio device unavailable');
    return PcmSink._(loaded, handle);
  }

  late final _destroy = library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('neko_sink_destroy');
  late final _write = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Int16>, Int32),
        int Function(Pointer<Void>, Pointer<Int16>, int)
      >('neko_sink_write');
  late final _played = library
      .lookupFunction<
        Uint64 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('neko_sink_played');
  late final _buffered = library
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('neko_sink_buffered');
  late final _faults = library
      .lookupFunction<
        Uint64 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('neko_sink_faults');
  late final _pause = library
      .lookupFunction<
        Void Function(Pointer<Void>, Int32),
        void Function(Pointer<Void>, int)
      >('neko_sink_pause');
  late final _volume = library
      .lookupFunction<
        Void Function(Pointer<Void>, Float),
        void Function(Pointer<Void>, double)
      >('neko_sink_volume');
  late final _settings = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Float>, Int32),
        int Function(Pointer<Void>, Pointer<Float>, int)
      >('neko_sink_settings');
  int write(Pointer<Int16> samples, int count) =>
      _disposed ? 0 : _write(handle, samples, count);
  int get playedFrames => _disposed ? 0 : _played(handle);
  int get bufferedSamples => _disposed ? 0 : _buffered(handle);

  /// Exceptions swallowed by the native audio callback so far.
  int get faults => _disposed ? 0 : _faults(handle);
  void pause(bool paused) {
    if (!_disposed) _pause(handle, paused ? 1 : 0);
  }

  void volume(double value) {
    if (!_disposed) _volume(handle, value);
  }

  void configure(AudioEffects settings) {
    if (_disposed) return;
    final buffer = calloc<Float>(18);
    try {
      final values = settings.values;
      for (var index = 0; index < values.length; index++) {
        buffer[index] = values[index];
      }
      if (_settings(handle, buffer, 18) != 0) {
        throw const FormatException('Unsupported DSP settings');
      }
    } finally {
      calloc.free(buffer);
    }
  }

  /// Returns immediately; the native side joins the audio thread off the UI
  /// isolate.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _destroy(handle);
  }
}
