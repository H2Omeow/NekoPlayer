import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/player_controller.dart';
import 'package:nekoplayer_desktop/domain/library.dart';
import 'package:nekoplayer_desktop/domain/online_music.dart';
import 'package:nekoplayer_desktop/ui/neko_app.dart';
import 'package:nekoplayer_desktop/ui/neko_theme.dart';
import 'package:nekoplayer_desktop/ui/shell/sidebar.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'fakes.dart';

void main() {
  // The shell's cloud-sync state lives in SharedPreferences.
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  testWidgets('deferred full player shows saved progress without autoplay', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final engine = FakeEngine();
    final controller = PlayerController(engine: engine, store: MemoryStore());
    await controller.initialize();
    final track = Track.fromOnline(
      const OnlineSong(
        provider: MusicProvider.netease,
        id: '1',
        title: 'Saved selection',
        artist: 'Neko',
      ),
    );
    await controller.importPlaybackQueue(
      [track],
      PlaybackSession(
        paths: [track.path],
        index: 0,
        position: const Duration(seconds: 23),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: nekoTheme(),
        home: FullPlayer(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved selection'), findsWidgets);
    expect(find.text('00:23'), findsOneWidget);
    expect(find.text('--:--'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider).first).onChanged, isNull);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '下一首',
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(engine.currentPath, isNull);
    expect(engine.playing, isFalse);
    await tester.ensureVisible(find.byTooltip('播放'));
    await tester.tap(find.byTooltip('播放'));
    await tester.pumpAndSettle();
    expect(engine.currentPath, track.path);
    expect(engine.position, const Duration(seconds: 23));
    expect(engine.playing, isTrue);
    expect(find.text('--:--'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await controller.flushed;
    controller.dispose();
  });
  testWidgets(
    'compact full player exposes download and comments for the current online song',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const song = OnlineSong(
        provider: MusicProvider.netease,
        id: '42',
        title: 'Song',
        artist: 'Neko',
      );
      final controller = PlayerController(
        engine: FakeEngine(),
        store: MemoryStore(),
      );
      await controller.initialize();
      await controller.play([Track.fromOnline(song)], 0);
      OnlineSong? downloaded;
      OnlineSong? commented;
      await tester.pumpWidget(
        MaterialApp(
          theme: nekoTheme(),
          home: FullPlayer(
            controller: controller,
            onDownload: (song) => downloaded = song,
            onComments: (song) => commented = song,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下载歌曲'));
      await tester.tap(find.byTooltip('查看评论'));
      expect(downloaded!.id, '42');
      expect(commented!.id, '42');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  for (final width in [360.0, 600.0, 839.0, 840.0, 1200.0, 1600.0]) {
    testWidgets('navigation and pages fit ${width.toInt()}px', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = PlayerController(
        engine: FakeEngine(),
        store: MemoryStore(),
      );
      await controller.initialize();
      await tester.pumpWidget(
        MaterialApp(
          theme: nekoTheme(),
          home: PlayerShell(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      final compact = width < 720;
      expect(find.byType(compact ? NavigationBar : Sidebar), findsOneWidget);
      expect(tester.takeException(), isNull);
      final labels = compact
          ? ['音乐库', '发现', '设置', '首页']
          : ['发现', '我喜欢', '最近播放', '全部歌曲', '设置', '首页'];
      for (final label in labels) {
        // The collapsed sidebar shows icons with tooltips instead of text.
        final target = width < 1100 && !compact
            ? find.byTooltip(label)
            : find.text(label);
        await tester.tap(target.last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$label at $width');
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testWidgets('large system text does not overflow compact home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PlayerController(
      engine: FakeEngine(),
      store: MemoryStore(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: nekoTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: PlayerShell(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('short window keeps empty library and player scrollable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PlayerController(
      engine: FakeEngine(),
      store: MemoryStore(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: nekoTheme(),
        home: PlayerShell(controller: controller),
      ),
    );
    await tester.tap(find.text('音乐库').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      MaterialApp(
        theme: nekoTheme(),
        home: FullPlayer(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
