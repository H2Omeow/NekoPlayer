import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/domain/library.dart';
import 'package:nekoplayer_desktop/domain/online_music.dart';
import 'package:nekoplayer_desktop/player_controller.dart';
import 'package:nekoplayer_desktop/ui/neko_app.dart';
import 'package:nekoplayer_desktop/ui/rotating_record.dart';

import 'fakes.dart';

void main() {
  testWidgets(
    'opening a paused player scrolls directly to its saved lyric line',
    (tester) async {
      // Wide layout: lyrics sit beside the cover instead of behind a toggle.
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = FakeEngine();
      final player = PlayerController(engine: engine, store: MemoryStore());
      await player.initialize();
      final track = Track.fromOnline(
        const OnlineSong(
          provider: MusicProvider.netease,
          id: '42',
          title: 'Paused song',
          artist: 'Neko',
        ),
      );
      await player.importPlaybackQueue(
        [track],
        PlaybackSession(
          paths: [track.path],
          index: 0,
          position: const Duration(seconds: 35),
        ),
      );
      player.lyrics = [
        for (var index = 0; index < 50; index++)
          LyricLine(Duration(seconds: index), 'Lyric $index'),
      ];
      try {
        await tester.pumpWidget(
          MaterialApp(home: FullPlayer(controller: player)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Lyric 35').hitTestable(), findsOneWidget);
        expect(find.text('Lyric 0').hitTestable(), findsNothing);
        expect(engine.currentPath, isNull);
        expect(engine.playing, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await player.flushed;
        player.dispose();
        await tester.pump();
      }
    },
  );

  testWidgets('record rotation pauses in place and respects reduced motion', (
    tester,
  ) async {
    Future<void> render({required bool playing, bool reducedMotion = false}) =>
        tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reducedMotion),
              child: RotatingRecord(
                playing: playing,
                child: const SizedBox(width: 180, height: 180),
              ),
            ),
          ),
        );
    double angle() => tester
        .widget<RotationTransition>(find.byType(RotationTransition))
        .turns
        .value;
    await render(playing: true);
    await tester.pump(const Duration(seconds: 1));
    expect(angle(), greaterThan(0));
    await render(playing: false);
    final paused = angle();
    await tester.pump(const Duration(seconds: 2));
    expect(angle(), paused);
    await render(playing: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(angle(), greaterThan(paused));
    await render(playing: true, reducedMotion: true);
    final reduced = angle();
    await tester.pump(const Duration(seconds: 2));
    expect(angle(), reduced);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact player switches views and seeks lyrics without starting a deferred session',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final engine = FakeEngine();
      final store = MemoryStore();
      final player = PlayerController(engine: engine, store: store);
      await player.initialize();
      final track = Track.fromOnline(
        const OnlineSong(
          provider: MusicProvider.netease,
          id: '42',
          title: 'Saved song',
          artist: 'Neko',
        ),
      );
      await player.importPlaybackQueue(
        [track],
        PlaybackSession(
          paths: [track.path],
          index: 0,
          position: const Duration(seconds: 23),
        ),
      );
      player.lyrics = parseLrc('[00:05.000]First line\n[00:20.000]Second line');
      try {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: FullPlayer(controller: player),
          ),
        );
        await tester.pumpAndSettle();
        for (final mode in ['唱片视图', '专注歌词', '封面与歌词']) {
          await tester.tap(find.byTooltip('播放选项'));
          await tester.pumpAndSettle();
          final item = find.ancestor(
            of: find.text(mode),
            matching: find.byType(CheckedPopupMenuItem<String>),
          );
          await tester.ensureVisible(item);
          await tester.pumpAndSettle();
          await tester.tap(item);
          await tester.pumpAndSettle();
          expect(
            find.byType(RotatingRecord),
            mode == '唱片视图' ? findsOneWidget : findsNothing,
          );
          expect(find.byType(SeekBar), findsOneWidget);
          if (mode == '专注歌词') {
            await tester.tap(find.text('Second line'));
            await tester.pumpAndSettle();
            expect(player.position, const Duration(seconds: 20));
          }
        }
        expect(player.sessionPending, isTrue);
        expect(engine.currentPath, isNull);
        expect(engine.playing, isFalse);
        expect(player.queueIndex, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await player.flushed;
        player.dispose();
        await tester.pump();
      }
    },
  );
}
