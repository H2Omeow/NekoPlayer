import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as paths;

import 'app_info.dart';

/// What the previous launch left behind.
class SessionReport {
  const SessionReport({
    this.uncleanShutdown = false,
    this.previousStart,
    this.previousVersion,
    this.crashFiles = const [],
  });
  final bool uncleanShutdown;
  final DateTime? previousStart;
  final String? previousVersion;
  final List<File> crashFiles;
}

/// `logs/session.json`: written at launch, removed on an orderly exit. A
/// leftover marker at the next launch means the previous run died.
class SessionMarker {
  SessionMarker(this.root);
  final Directory root;

  File get file => File(paths.join(root.path, 'session.json'));
  Directory get _crashDirectory => Directory(paths.join(root.path, 'crash'));

  SessionReport begin() {
    SessionReport report = const SessionReport();
    try {
      report = _readPrevious();
    } catch (_) {}
    try {
      root.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({
          'pid': pid,
          'startedAt': DateTime.now().toUtc().toIso8601String(),
          'version': appVersion,
        }),
        flush: true,
      );
    } catch (_) {}
    return report;
  }

  void end() {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  /// Whether [other] is a live NekoPlayer process. Comparing executables
  /// rather than only checking the pid guards against pid reuse.
  static bool _isRunning(int other) {
    if (!Platform.isLinux) return false;
    try {
      return Link('/proc/$other/exe').resolveSymbolicLinksSync() ==
          File(Platform.resolvedExecutable).resolveSymbolicLinksSync();
    } catch (_) {
      return false;
    }
  }

  SessionReport _readPrevious() {
    if (!file.existsSync()) return const SessionReport();
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final previousPid = data['pid'];
    if (previousPid is int && previousPid != pid && _isRunning(previousPid)) {
      return const SessionReport(); // another instance is still running
    }
    final started = DateTime.tryParse('${data['startedAt']}')?.toLocal();
    final crashes = <File>[];
    if (_crashDirectory.existsSync()) {
      for (final entity in _crashDirectory.listSync()) {
        if (entity is! File) continue;
        if (started == null ||
            entity.statSync().modified.isAfter(
              started.subtract(const Duration(seconds: 2)),
            )) {
          crashes.add(entity);
        }
      }
    }
    return SessionReport(
      uncleanShutdown: true,
      previousStart: started,
      previousVersion: data['version'] as String?,
      crashFiles: crashes,
    );
  }
}
