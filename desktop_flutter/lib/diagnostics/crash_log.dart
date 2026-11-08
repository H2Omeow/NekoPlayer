import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:path/path.dart' as paths;

import 'app_info.dart';
import 'log_redaction.dart';

/// Directory shared with the native crash handlers (same location as
/// path_provider's application support directory, plus `logs`).
Directory defaultLogRoot() {
  final override = Platform.environment['NEKOPLAYER_LOG_DIR'];
  if (override != null && override.isNotEmpty) return Directory(override);
  final env = Platform.environment;
  if (Platform.isWindows) {
    final base =
        env['APPDATA'] ?? env['USERPROFILE'] ?? Directory.systemTemp.path;
    return Directory(paths.join(base, 'top.nekoh2o', 'NekoPlayer', 'logs'));
  }
  final data = env['XDG_DATA_HOME'];
  final base = data != null && data.startsWith('/')
      ? data
      : paths.join(env['HOME'] ?? Directory.systemTemp.path, '.local', 'share');
  return Directory(paths.join(base, 'top.nekoh2o.nekoplayer_desktop', 'logs'));
}

/// Rotating, secret-redacting text log (`app-YYYYMMDD.log`). Logging never
/// throws; failures fall back to stderr.
class CrashLog {
  CrashLog({
    required this.root,
    this.maxBytes = 1024 * 1024,
    this.keep = 5,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    try {
      root.createSync(recursive: true);
    } catch (_) {}
  }

  static CrashLog? current;
  static const maxEntryChars = 16 * 1024;

  final Directory root;
  final int maxBytes;
  final int keep;
  final DateTime Function() _clock;
  String? _path;
  int _size = 0;
  String? _lastKey;
  int _repeats = 0;

  Directory get crashDirectory => Directory(paths.join(root.path, 'crash'));

  static void info(String tag, String message) =>
      current?.write('INFO', tag, message);
  static void warn(String tag, String message) =>
      current?.write('WARN', tag, message);
  static void error(
    String tag,
    String message, {
    Object? error,
    StackTrace? stack,
  }) => current?.write('ERROR', tag, message, error: error, stack: stack);

  String _header() {
    final now = _clock();
    return '==== NekoPlayer $appVersion | ${now.toIso8601String()} | pid $pid\n'
        'os: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n'
        'arch: ${Abi.current()}\n'
        'dart: ${Platform.version.split(' ').first}\n'
        'executable: ${Platform.resolvedExecutable}\n'
        '====\n';
  }

  String _fileName(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'app-${time.year}${two(time.month)}${two(time.day)}.log';
  }

  void write(
    String level,
    String tag,
    String message, {
    Object? error,
    StackTrace? stack,
  }) {
    try {
      var body = message;
      if (error != null) body += '\n  error: $error';
      if (stack != null) body += '\n$stack';
      body = redactSecrets(body);
      if (body.length > maxEntryChars) {
        body = '${body.substring(0, maxEntryChars)}\n  ...(truncated)';
      }
      final key = '$level|$tag|$body';
      if (key == _lastKey) {
        _repeats++;
        return;
      }
      final pending = _repeats;
      _repeats = 0;
      _lastKey = key;
      final now = _clock();
      final buffer = StringBuffer();
      if (pending > 0) {
        buffer.writeln('  (previous entry repeated $pending more times)');
      }
      buffer.writeln('${now.toIso8601String()} [$level] [$tag] $body');
      _append(now, buffer.toString());
    } catch (failure) {
      stderr.writeln('crash log write failed: $failure');
    }
  }

  /// Forget cached file state (after the files were deleted externally).
  void reset() {
    _path = null;
    _lastKey = null;
    _repeats = 0;
  }

  /// Writes any suppressed duplicate count; call before exit.
  void flush() {
    if (_repeats == 0) return;
    final pending = _repeats;
    _repeats = 0;
    _lastKey = null;
    try {
      _append(_clock(), '  (previous entry repeated $pending more times)\n');
    } catch (_) {}
  }

  void _append(DateTime now, String text) {
    final path = paths.join(root.path, _fileName(now));
    if (path != _path) {
      _path = path;
      final file = File(path);
      _size = file.existsSync() ? file.lengthSync() : 0;
      if (_size == 0) _writeRaw(path, _header());
    }
    if (_size + text.length > maxBytes && _size > 0) {
      _rotate(path, now);
      _writeRaw(path, _header());
    }
    _writeRaw(path, text);
  }

  void _writeRaw(String path, String text) {
    File(path).writeAsStringSync(text, mode: FileMode.append, flush: true);
    _size += text.length;
  }

  void _rotate(String path, DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp = '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final base = paths.withoutExtension(path);
    var target = '$base-$stamp.log';
    for (var index = 1; File(target).existsSync(); index++) {
      target = '$base-$stamp-$index.log';
    }
    File(path).renameSync(target);
    _size = 0;
    _prune(path);
  }

  /// Keeps the newest rotated logs so that, together with the [current] file
  /// about to be recreated, at most [keep] logs remain.
  void _prune(String current) {
    final files =
        root.listSync().whereType<File>().where((file) {
          final name = paths.basename(file.path);
          return file.path != current &&
              name.startsWith('app-') &&
              name.endsWith('.log');
        }).toList()..sort((a, b) {
          final byTime = b.statSync().modified.compareTo(a.statSync().modified);
          return byTime != 0 ? byTime : b.path.compareTo(a.path);
        });
    for (final stale in files.skip(keep - 1)) {
      try {
        stale.deleteSync();
      } catch (_) {}
    }
  }
}
