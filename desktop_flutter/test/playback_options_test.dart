import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/domain/library.dart';
import 'package:nekoplayer_desktop/domain/online_music.dart';
import 'package:nekoplayer_desktop/player_controller.dart';
import 'package:nekoplayer_desktop/ui/playback_options.dart';
import 'package:nekoplayer_desktop/ui/widgets/song_row.dart';

import 'fakes.dart';

void main() {
  Future<void> withPlayer(
    WidgetTester tester,
    Future<void> Function(PlayerController, FakeEngine) work,
  ) async {
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final engine = FakeEngine();
    final player = PlayerController(engine: engine, store: MemoryStore());
    try {
      await player.initialize();
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
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            appBar: AppBar(
              actions: [PlaybackOptionsButton(controller: player)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await work(player, engine);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      player.dispose();
      await tester.pump();
    }
  }

  Future<void> select(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('播放选项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'player options adjust speed, sleep timer and translation without decoding',
    (tester) async {
      await withPlayer(tester, (player, engine) async {
        await select(tester, '播放速度 · 1.0x');
        await tester.ensureVisible(find.text('1.5x'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('1.5x'));
        await tester.pumpAndSettle();
        expect(player.rate, 1.5);
        await select(tester, '定时暂停');
        await tester.tap(find.text('15 分钟'));
        await tester.pumpAndSettle();
        expect(player.sleepDeadline, isNotNull);
        await select(tester, '定时暂停 · 已开启');
        await tester.ensureVisible(find.text('取消定时'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消定时'));
        await tester.pumpAndSettle();
        expect(player.sleepDeadline, isNull);
        await select(tester, '隐藏歌词翻译');
        expect(player.showTranslation, isFalse);
        await select(tester, '显示歌词翻译');
        expect(player.showTranslation, isTrue);
        expect(engine.currentPath, isNull);
        expect(engine.playing, isFalse);
      });
    },
  );

  testWidgets(
    'queue menu edits duplicate occurrences and keeps offscreen actions reachable',
    (tester) async {
      await withPlayer(tester, (player, engine) async {
        await select(tester, '播放队列');
        expect(find.text('3 首 · 拖动可调整顺序'), findsOneWidget);
        expect(
          tester
              .widgetList<SongRow>(find.byType(SongRow))
              .map((row) => row.playing),
          [false, false, true],
        );
        await tester.tap(find.byTooltip('歌曲操作').at(0));
        await tester.pumpAndSettle();
        await tester.tap(find.text('下移'));
        await tester.pumpAndSettle();
        expect(player.queue.map((track) => track.online!.id), ['2', '1', '1']);
        expect(player.queueIndex, 2);
        expect(player.position, const Duration(seconds: 23));
        await tester.ensureVisible(find.byTooltip('歌曲操作').at(2));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('歌曲操作').at(2));
        await tester.pumpAndSettle();
        await tester.tap(find.text('从队列移除'));
        await tester.pumpAndSettle();
        expect(player.queue, hasLength(2));
        expect(player.queueIndex, 1);
        expect(player.position, Duration.zero);
        expect(engine.currentPath, isNull);
        await tester.ensureVisible(find.text('Song 2'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Song 2'));
        await tester.pumpAndSettle();
        expect(engine.currentPath, player.queue.first.path);
        expect(engine.playing, isTrue);
      });
    },
  );
}
