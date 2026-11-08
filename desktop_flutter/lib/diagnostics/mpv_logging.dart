import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'crash_log.dart';

const mpvLogConfigurationLevel = MPVLogLevel.warn;

/// Forwards libmpv warnings and errors to the crash log, capped per minute so
/// a noisy stream cannot flood the disk.
StreamSubscription<PlayerLog> attachMpvLog(Player player, String tag) {
  var window = DateTime.now();
  var count = 0;
  var dropped = 0;
  return player.stream.log.listen((entry) {
    if (entry.level == 'info' || entry.level == 'v') return;
    final now = DateTime.now();
    if (now.difference(window) > const Duration(minutes: 1)) {
      if (dropped > 0) CrashLog.warn(tag, 'mpv: $dropped log lines suppressed');
      window = now;
      count = 0;
      dropped = 0;
    }
    if (++count > 100) {
      dropped++;
      return;
    }
    final line = 'mpv ${entry.level} [${entry.prefix}] ${entry.text}';
    if (entry.level == 'warn') {
      CrashLog.warn(tag, line);
    } else {
      CrashLog.error(tag, line);
    }
  });
}
