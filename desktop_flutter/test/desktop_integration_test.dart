import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/desktop_integration.dart';
import 'package:nekoplayer_desktop/domain/library.dart';
import 'package:nekoplayer_desktop/domain/online_music.dart';
import 'package:nekoplayer_desktop/playback/playback_engine.dart';
import 'package:nekoplayer_desktop/player_controller.dart';

import 'fakes.dart';

class SeekEngine extends FakeEngine {
  int nextCalls = 0;
  int opens = 0;
  @override
  Future<void> open(List<Track> tracks, int index, {bool play = true}) async {
    opens++;
    await super.open(tracks, index, play: play);
  }

  @override
  Future<void> next() async {
    nextCalls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/desktop');
  late List<MethodCall> calls;
  late PlayerController player;
  late SeekEngine engine;
  late DesktopIntegration desktop;
  setUp(() async {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'initialize') {
            return {
              'media': true,
              'lyrics': true,
              'positioning': false,
              'tray': true,
            };
          }
          if (call.method == 'configureTray') {
            return call.arguments['closeToTray'];
          }
          return null;
        });
    engine = SeekEngine();
    player = PlayerController(engine: engine, store: MemoryStore());
    await player.initialize();
    desktop = DesktopIntegration(player, channel: channel);
    await desktop.initialize();
  });
  tearDown(() async {
    desktop.dispose();
    await player.flushed;
    player.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> send(String method, [Map<String, dynamic>? arguments]) async {
    final complete = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, arguments),
          ),
          (_) => complete.complete(),
        );
    await complete.future;
  }

  Future<void> loadSong() => player.play([
    Track.fromOnline(
      const OnlineSong(
        provider: MusicProvider.netease,
        id: '1',
        title: 'Night',
        artist: 'Neko',
      ),
    ),
  ], 0);

  test(
    'system controls preserve a deferred selection without implicit decoding',
    () async {
      final tracks = [
        for (final id in ['1', '2', '1'])
          Track.fromOnline(
            OnlineSong(
              provider: MusicProvider.netease,
              id: id,
              title: 'Song $id',
              artist: 'Neko',
            ),
          ),
      ];
      await player.importPlaybackQueue(
        tracks,
        PlaybackSession(
          paths: tracks.map((track) => track.path).toList(),
          index: 2,
          position: const Duration(seconds: 23),
        ),
      );
      expect(desktop.state()['title'], 'Song 1');
      expect(desktop.state()['position'], 23000000);
      expect(desktop.state()['duration'], 0);
      expect(desktop.state()['hasTrack'], isTrue);
      expect(desktop.state()['playing'], isFalse);
      await send('action', {'action': 'pause'});
      await send('action', {'action': 'seek', 'value': 10000000});
      expect(player.position, const Duration(seconds: 23));
      expect(engine.opens, 0);
      await send('action', {'action': 'stop'});
      expect(player.position, Duration.zero);
      expect(engine.opens, 0);
      await send('action', {'action': 'next'});
      expect(engine.opens, 1);
      expect(engine.nextCalls, 0);
      expect(player.queueIndex, 0);
      expect(engine.playing, isTrue);
    },
  );

  test(
    'close to tray requires explicit opt in and a live system tray',
    () async {
      expect(desktop.trayAvailable, isTrue);
      expect(desktop.closeToTray, isFalse);
      await desktop.configureTray(true);
      expect(desktop.closeToTray, isTrue);
      await desktop.configureTray(false);
      expect(desktop.closeToTray, isFalse);
      await desktop.configureTray(true);
      await send('trayChanged', {'available': false});
      expect(desktop.trayAvailable, isFalse);
      expect(desktop.closeToTray, isFalse);
      final previous = calls.length;
      await desktop.configureTray(true);
      expect(calls.length, previous);
      await send('trayChanged', {'available': true});
      expect(desktop.closeToTray, isFalse);
    },
  );

  test('native rejection never marks close to tray enabled', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => false);
    await desktop.configureTray(true);
    expect(desktop.closeToTray, isFalse);
    expect(desktop.error, isNotNull);
  });

  test(
    'metadata uses opaque track IDs and never leaks paths or credentials',
    () async {
      expect(desktop.mediaAvailable, isTrue);
      expect(desktop.positioningAvailable, isFalse);
      engine.currentPath = '/private/music/song.mp3';
      player.queue = [
        const Track(
          path: '/private/music/song.mp3',
          title: 'Local',
          artist: 'Neko',
        ),
      ];
      final state = desktop.state();
      expect(state['trackId'], startsWith('/top/nekoh2o/track/t'));
      expect(state.toString(), isNot(contains('/private/')));
      expect(state['title'], 'Local');
    },
  );

  test(
    'system transport actions and bounded seek reach playback engine',
    () async {
      await loadSong();
      await send('action', {'action': 'pause'});
      expect(engine.playing, isFalse);
      await send('action', {'action': 'play'});
      expect(engine.playing, isTrue);
      await send('action', {'action': 'next'});
      expect(engine.nextCalls, 1);
      await send('action', {'action': 'seek', 'value': 999999999});
      expect(engine.position, engine.duration);
      await send('action', {'action': 'seekRelative', 'value': -999999999});
      expect(engine.position, Duration.zero);
      await send('action', {'action': 'seek', 'value': double.nan});
      expect(engine.position, Duration.zero);
      await send('action', {'action': 'stop'});
      expect(engine.playing, isFalse);
    },
  );

  test('system settings reject nonfinite values and clamp volume', () async {
    await send('action', {'action': 'volume', 'value': 1.5});
    expect(player.volume, 100);
    await send('action', {'action': 'volume', 'value': double.infinity});
    expect(player.volume, 100);
    await send('action', {'action': 'rate', 'value': 10});
    expect(player.rate, 2);
    await send('action', {'action': 'loop', 'value': 'Track'});
    expect(player.repeat, RepeatMode.single);
    await send('action', {'action': 'loop', 'value': 'bad'});
    expect(player.repeat, RepeatMode.single);
    await send('action', {'action': 'shuffle', 'value': true});
    expect(player.repeat, RepeatMode.shuffle);
  });

  test(
    'overlay synchronizes timed lyrics, settings and native close event',
    () async {
      await loadSong();
      player.lyrics = [
        const LyricLine(Duration.zero, 'Current'),
        const LyricLine(Duration(seconds: 10), 'Next'),
      ];
      desktop.configureOverlay(enabled: true, lock: true, size: 90, alpha: .1);
      expect(desktop.state()['lyric'], 'Current');
      expect(desktop.state()['nextLyric'], 'Next');
      expect(desktop.fontSize, 64);
      expect(desktop.opacity, .25);
      expect(desktop.locked, isTrue);
      await send('overlayClosed');
      expect(desktop.overlay, isFalse);
    },
  );

  test(
    'desktop lyric settings survive restart while close-to-tray stays opt in',
    () async {
      desktop.dispose();
      final settings = MemoryStore();
      desktop = DesktopIntegration(
        player,
        channel: channel,
        settings: settings,
      );
      await desktop.initialize();
      desktop.configureOverlay(
        enabled: true,
        lock: true,
        size: 42,
        alpha: .6,
        showTitle: false,
        showProgress: false,
        showControls: true,
      );
      await desktop.configureTray(true);
      await desktop.flushed;
      expect(settings.value, isNot(contains('closeToTray')));
      desktop.dispose();
      desktop = DesktopIntegration(
        player,
        channel: channel,
        settings: settings,
      );
      await desktop.initialize();
      expect(desktop.overlay, isTrue);
      expect(desktop.locked, isTrue);
      expect(desktop.fontSize, 42);
      expect(desktop.opacity, .6);
      expect(desktop.overlayTitle, isFalse);
      expect(desktop.overlayProgress, isFalse);
      expect(desktop.overlayControls, isTrue);
      expect(desktop.state()['showTitle'], isFalse);
      expect(desktop.state()['showProgress'], isFalse);
      expect(desktop.state()['showControls'], isTrue);
      expect(desktop.closeToTray, isFalse);
      await send('overlayClosed');
      await desktop.flushed;
      expect(jsonDecode(settings.value!)['overlay'], isFalse);
    },
  );

  test('unreadable desktop settings remain protected from overwrite', () async {
    desktop.dispose();
    final settings = MemoryStore()..value = '{invalid';
    desktop = DesktopIntegration(player, channel: channel, settings: settings);
    await desktop.initialize();
    expect(desktop.error, contains('读取失败'));
    desktop.configureOverlay(enabled: true, size: 40);
    await desktop.flushed;
    expect(settings.value, '{invalid');
    expect(settings.writes, 0);
    expect(desktop.mediaAvailable, isTrue);
  });

  test(
    'desktop setting writes recover after disk failure and preserve newest values',
    () async {
      desktop.dispose();
      final settings = MemoryStore()..failWrite = true;
      desktop = DesktopIntegration(
        player,
        channel: channel,
        settings: settings,
      );
      await desktop.initialize();
      desktop.configureOverlay(enabled: true);
      await desktop.flushed;
      expect(desktop.error, contains('保存失败'));
      settings.failWrite = false;
      desktop.configureOverlay(size: 40);
      desktop.configureOverlay(size: 50, alpha: .5);
      await desktop.flushed;
      final saved = jsonDecode(settings.value!);
      expect(saved['fontSize'], 50);
      expect(saved['opacity'], .5);
      expect(saved['overlay'], isTrue);
    },
  );
}
