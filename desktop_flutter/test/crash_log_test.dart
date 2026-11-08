import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/diagnostics/app_info.dart';
import 'package:nekoplayer_desktop/diagnostics/crash_log.dart';
import 'package:nekoplayer_desktop/diagnostics/diagnostics_store.dart';
import 'package:nekoplayer_desktop/diagnostics/log_redaction.dart';
import 'package:nekoplayer_desktop/diagnostics/process_tail.dart';
import 'package:nekoplayer_desktop/diagnostics/session_marker.dart';
import 'package:path/path.dart' as paths;

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('neko-log-test'));
  tearDown(() => root.deleteSync(recursive: true));

  test('app version constant matches pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: $appVersion'));
  });

  group('redaction', () {
    test('removes URL queries, headers and secret fields', () {
      final text = redactSecrets(
        'GET https://a.example/play?MUSIC_U=abc&token=xyz#f failed\n'
        'Authorization: Bearer top-secret\n'
        'Cookie: MUSIC_U=abc; other=1\n'
        '{"siteToken":"s3cr3t","title":"keep"} token=plain',
      );
      expect(text, isNot(contains('abc')));
      expect(text, isNot(contains('xyz')));
      expect(text, isNot(contains('top-secret')));
      expect(text, isNot(contains('s3cr3t')));
      expect(text, isNot(contains('plain')));
      expect(text, contains('https://a.example/play?<redacted>'));
      expect(text, contains('keep'));
    });

    test('leaves ordinary diagnostics untouched', () {
      const text = 'mpv warn [ffmpeg] Stream ends prematurely at 1234';
      expect(redactSecrets(text), text);
    });
  });

  group('CrashLog', () {
    test('writes a header once and redacts entries', () {
      final log = CrashLog(root: root);
      log.write('ERROR', 'test', 'open https://h/x?token=zzz failed');
      log.write('WARN', 'test', 'second');
      final files = root.listSync().whereType<File>().toList();
      expect(files, hasLength(1));
      final text = files.single.readAsStringSync();
      expect(text, startsWith('==== NekoPlayer $appVersion'));
      expect('==== NekoPlayer'.allMatches(text), hasLength(1));
      expect(text, contains('arch:'));
      expect(text, contains('dart:'));
      expect(text, isNot(contains('zzz')));
      expect(text, contains('[WARN] [test] second'));
    });

    test('rotates by size and keeps a bounded number of files', () {
      var tick = 0;
      final log = CrashLog(
        root: root,
        maxBytes: 600,
        keep: 3,
        clock: () => DateTime(2026, 1, 1, 0, 0, tick++),
      );
      for (var index = 0; index < 40; index++) {
        log.write('INFO', 'rot', 'entry $index ${'x' * 120}');
      }
      final logs = root
          .listSync()
          .whereType<File>()
          .where((file) => paths.basename(file.path).startsWith('app-'))
          .toList();
      expect(logs.length, lessThanOrEqualTo(3));
      expect(logs.length, greaterThan(1));
      for (final file in logs) {
        expect(file.lengthSync(), lessThan(1500));
      }
      final names = logs.map((file) => paths.basename(file.path)).toList();
      expect(names, contains('app-20260101.log'));
    });

    test('collapses consecutive duplicates and caps entry size', () {
      final log = CrashLog(root: root);
      for (var index = 0; index < 5; index++) {
        log.write('WARN', 'dup', 'same');
      }
      log.write('WARN', 'big', 'y' * 100000);
      log.flush();
      final text = root.listSync().whereType<File>().single.readAsStringSync();
      expect('same'.allMatches(text), hasLength(1));
      expect(text, contains('repeated 4 more times'));
      expect(text.length, lessThan(40000));
    });

    test('never throws when the directory is unusable', () {
      final blocker = File(paths.join(root.path, 'file'))
        ..writeAsStringSync('');
      final log = CrashLog(root: Directory(paths.join(blocker.path, 'sub')));
      expect(() => log.write('ERROR', 't', 'm'), returnsNormally);
    });
  });

  group('SessionMarker', () {
    test('clean exit leaves no marker; leftover marker reports a crash', () {
      final first = SessionMarker(root);
      expect(first.begin().uncleanShutdown, isFalse);
      expect(first.file.existsSync(), isTrue);
      first.end();
      expect(first.file.existsSync(), isFalse);

      first.begin();
      final crash = File(paths.join(root.path, 'crash', 'crash-1.txt'))
        ..createSync(recursive: true);
      // Simulates a dead previous process: rewrite the marker with a stale pid.
      first.file.writeAsStringSync(
        '{"pid":1,"startedAt":"${DateTime.now().subtract(const Duration(minutes: 1)).toUtc().toIso8601String()}","version":"1.0.0+1"}',
      );
      final report = SessionMarker(root).begin();
      expect(report.uncleanShutdown, isTrue);
      expect(report.previousVersion, '1.0.0+1');
      expect(report.crashFiles.map((file) => file.path), [crash.path]);
    });
  });

  test('ProcessTail keeps only the last bytes', () async {
    final tail = ProcessTail(
      Stream.fromIterable([List.filled(3000, 97), List.filled(3000, 98)]),
      limit: 4096,
    );
    final text = await tail.settled();
    expect(text.length, 4096);
    expect(text.endsWith('b'), isTrue);
  });

  test('DiagnosticsStore lists newest first, exports and clears', () async {
    final log = CrashLog(root: root);
    log.write('ERROR', 'a', 'boom');
    final crash = File(paths.join(root.path, 'crash', 'crash-1.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('signal 11');
    crash.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
    File(paths.join(root.path, 'session.json')).writeAsStringSync('{}');
    final store = DiagnosticsStore(root);
    final entries = store.list();
    expect(entries.first.crash, isTrue);
    expect(entries.map((entry) => entry.name), isNot(contains('session.json')));
    final exported = await store.exportText();
    expect(exported, contains('boom'));
    expect(exported, contains('signal 11'));
    expect(store.clear(), 2);
    expect(store.list(), isEmpty);
  });
}
