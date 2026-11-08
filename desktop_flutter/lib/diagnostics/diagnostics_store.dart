import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as paths;

import 'app_info.dart';
import '../i18n/tr.dart';

class DiagnosticFile {
  const DiagnosticFile({
    required this.file,
    required this.size,
    required this.modified,
    required this.crash,
  });
  final File file;
  final int size;
  final DateTime modified;
  final bool crash;

  String get name => paths.basename(file.path);
  bool get binary => name.endsWith('.dmp');
}

/// File access behind the diagnostics page: list, read, export, clear.
class DiagnosticsStore {
  DiagnosticsStore(this.root);
  final Directory root;

  Directory get crashDirectory => Directory(paths.join(root.path, 'crash'));

  /// Logs and crash files, newest first. Crash files come first on ties.
  List<DiagnosticFile> list() {
    final result = <DiagnosticFile>[];
    void collect(Directory directory, bool crash) {
      if (!directory.existsSync()) return;
      for (final entity in directory.listSync()) {
        if (entity is! File || paths.basename(entity.path) == 'session.json') {
          continue;
        }
        try {
          final stat = entity.statSync();
          result.add(
            DiagnosticFile(
              file: entity,
              size: stat.size,
              modified: stat.modified,
              crash: crash,
            ),
          );
        } catch (_) {}
      }
    }

    collect(root, false);
    collect(crashDirectory, true);
    result.sort((a, b) {
      final order = b.modified.compareTo(a.modified);
      return order != 0 ? order : (b.crash ? 1 : 0) - (a.crash ? 1 : 0);
    });
    return result;
  }

  /// Text of [entry], keeping only the last [maxBytes] of large files.
  Future<String> read(DiagnosticFile entry, {int maxBytes = 512 * 1024}) async {
    if (entry.binary) {
      return tr('这是二进制崩溃转储（{size}），请通过“导出诊断信息”或打开日志文件夹提交。', {
        'size': _size(entry.size),
      });
    }
    final handle = await entry.file.open();
    try {
      final length = await handle.length();
      final start = length > maxBytes ? length - maxBytes : 0;
      await handle.setPosition(start);
      final text = utf8.decode(
        await handle.read(length - start),
        allowMalformed: true,
      );
      return start > 0
          ? '${tr('...(仅显示末尾 {size})', {'size': _size(maxBytes)})}\n$text'
          : text;
    } finally {
      await handle.close();
    }
  }

  /// All text logs and crash sidecars concatenated into one report.
  Future<String> exportText() async {
    final buffer = StringBuffer()
      ..writeln('NekoPlayer diagnostics export')
      ..writeln('version: $appVersion')
      ..writeln('exported: ${DateTime.now().toIso8601String()}')
      ..writeln(
        'os: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      )
      ..writeln();
    final files = list().where((entry) => !entry.binary).toList().reversed;
    for (final entry in files) {
      buffer
        ..writeln(
          '######## ${entry.crash ? 'crash/' : ''}${entry.name} (${entry.modified.toIso8601String()})',
        )
        ..writeln(await read(entry, maxBytes: 1024 * 1024))
        ..writeln();
    }
    final dumps = list().where((entry) => entry.binary).toList();
    if (dumps.isNotEmpty) {
      buffer.writeln('######## minidumps (not embedded)');
      for (final dump in dumps) {
        buffer.writeln('${dump.file.path} ${_size(dump.size)}');
      }
    }
    return buffer.toString();
  }

  /// Deletes logs and crash files (the live session marker is kept).
  int clear() {
    var removed = 0;
    for (final entry in list()) {
      try {
        entry.file.deleteSync();
        removed++;
      } catch (_) {}
    }
    return removed;
  }

  static String _size(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).ceil()} KB';
}
