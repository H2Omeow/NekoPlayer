import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'crash_log.dart';
import 'session_marker.dart';

/// Wires every Dart-side error channel into [CrashLog] and tracks whether the
/// previous run ended cleanly.
class CrashGuard {
  CrashGuard._();

  static SessionMarker? _marker;
  static SessionReport report = const SessionReport();
  static AppLifecycleListener? _lifecycle;
  static RawReceivePort? _isolateErrors;

  static String? get logPath => CrashLog.current?.root.path;

  /// Runs [body] (which must call runApp) inside a guarded zone.
  static void run(Future<void> Function() body) {
    _open();
    runZonedGuarded(
      () {
        WidgetsFlutterBinding.ensureInitialized();
        _install();
        unawaited(body());
      },
      (error, stack) => CrashLog.error(
        'uncaught',
        'Unhandled asynchronous error',
        error: error,
        stack: stack,
      ),
    );
  }

  static void _open() {
    try {
      final log = CrashLog(root: defaultLogRoot());
      CrashLog.current = log;
      _marker = SessionMarker(log.root);
      report = _marker!.begin();
      log.write(
        'INFO',
        'session',
        report.uncleanShutdown
            ? 'start; previous session ended unexpectedly '
                  '(${report.crashFiles.length} crash file(s))'
            : 'start',
      );
    } catch (_) {}
  }

  static void _install() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      CrashLog.error(
        'flutter',
        details.context?.toDescription() ?? 'Flutter framework error',
        error: details.exception,
        stack: details.stack,
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      CrashLog.error(
        'platform',
        'Unhandled platform error',
        error: error,
        stack: stack,
      );
      return true;
    };
    _isolateErrors = RawReceivePort((dynamic pair) {
      final data = pair as List<dynamic>;
      CrashLog.error(
        'isolate',
        'Uncaught error in main isolate',
        error: data.first,
        stack: StackTrace.fromString('${data.last}'),
      );
    });
    Isolate.current.addErrorListener(_isolateErrors!.sendPort);
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        shutdown();
        return AppExitResponse.exit;
      },
    );
  }

  /// Orderly exit: flush the log and remove the unclean-shutdown marker.
  static void shutdown() {
    CrashLog.info('session', 'clean exit');
    CrashLog.current?.flush();
    _marker?.end();
  }

  @visibleForTesting
  static void dispose() {
    _lifecycle?.dispose();
    _isolateErrors?.close();
  }
}
