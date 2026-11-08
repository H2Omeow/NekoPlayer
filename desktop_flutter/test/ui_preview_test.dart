// Renders key screens to PNG for visual review:
//   NEKO_UI_PREVIEW_DIR=/tmp/neko-preview flutter test test/ui_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/domain/library.dart';
import 'package:nekoplayer_desktop/domain/online_music.dart';
import 'package:nekoplayer_desktop/player_controller.dart';
import 'package:nekoplayer_desktop/ui/neko_app.dart';
import 'package:nekoplayer_desktop/ui/neko_theme.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'fakes.dart';

final String? _output = Platform.environment['NEKO_UI_PREVIEW_DIR'];

Future<void> _loadFont(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('preview-root')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '${_output!}/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
  });
}

Future<PlayerController> _sampleController() async {
  final controller = PlayerController(
    engine: FakeEngine(),
    store: MemoryStore(),
  );
  await controller.initialize();
  const songs = [
    ('晴天', '周杰伦'),
    ('夜に駆ける', 'YOASOBI'),
    ('Blinding Lights', 'The Weeknd'),
    ('稻香', '周杰伦'),
    ('打上花火', 'DAOKO / 米津玄師'),
    ('起风了', '买辣椒也用券'),
    ('Shape of You', 'Ed Sheeran'),
    ('平凡之路', '朴树'),
  ];
  final tracks = [
    for (var index = 0; index < songs.length; index++)
      Track.fromOnline(
        OnlineSong(
          provider: MusicProvider.netease,
          id: '${index + 1}',
          title: songs[index].$1,
          artist: songs[index].$2,
          album: '示例专辑',
        ),
      ),
  ];
  await controller.importPlaybackQueue(
    tracks,
    PlaybackSession(
      paths: [for (final track in tracks) track.path],
      index: 0,
      position: const Duration(seconds: 42),
    ),
  );
  for (final track in tracks.take(3)) {
    controller.toggleFavorite(track);
  }
  final id = controller.createPlaylist('通勤路上')!;
  controller.createPlaylist('深夜循环');
  for (final track in tracks.skip(2).take(4)) {
    controller.addToPlaylist(id, track);
  }
  controller.history = [for (final track in tracks.reversed) track.path];
  controller.lyrics = parseLrc(
    '[00:30.00]故事的小黄花\n[00:34.00]从出生那年就飘着\n[00:38.00]童年的荡秋千\n'
    '[00:42.00]随记忆一直晃到现在\n[00:47.00]Re So So Si Do Si La\n'
    '[00:51.00]So La Si Si Si Si La Si La So\n[00:55.00]吹着前奏望着天空',
  );
  return controller;
}

void main() {
  if (_output == null) return;
  setUpAll(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    Directory(_output!).createSync(recursive: true);
    await _loadFont('Neko CJK', 'assets/fonts/NotoSansCJKsc-Regular.otf');
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      await _loadFont(
        'Roboto',
        '${artifacts.path}/material_fonts/Roboto-$weight.ttf',
      );
    }
    await _loadFont(
      'MaterialIcons',
      '${artifacts.path}/material_fonts/MaterialIcons-Regular.otf',
    );
  });

  for (final brightness in [Brightness.dark, Brightness.light]) {
    for (final size in [
      const Size(1440, 900),
      const Size(1000, 760),
      const Size(420, 860),
    ]) {
      final suffix = '${brightness.name}-${size.width.toInt()}';
      testWidgets('preview $suffix', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        // flutter_test draws shadows as solid shapes unless told otherwise.
        debugDisableShadows = false;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = await _sampleController();
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('preview-root'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: nekoTheme(brightness: brightness),
              home: PlayerShell(controller: controller),
            ),
          ),
        );
        await _capture(tester, 'home-$suffix');
        for (final (label, name) in [
          ('发现', 'discover'),
          ('我喜欢', 'favorites'),
          ('通勤路上', 'playlist'),
          ('音乐库', 'library'),
          ('设置', 'settings'),
        ]) {
          final target = find.text(label);
          if (target.evaluate().isEmpty) continue;
          await tester.tap(target.last);
          await _capture(tester, '$name-$suffix');
        }
        for (final (label, name) in [
          ('NekoPlayer 账号与云端同步', 'sync'),
          ('音乐平台账号', 'accounts'),
          ('桌面歌词与系统控制', 'desktop'),
          ('从旧版导入', 'legacy'),
          ('崩溃日志与诊断', 'diagnostics'),
        ]) {
          final target = find.text(label);
          if (target.evaluate().isEmpty) continue;
          await tester.ensureVisible(target.last);
          await tester.pumpAndSettle();
          await tester.tap(target.last);
          await _capture(tester, '$name-$suffix');
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('preview-root'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: nekoTheme(brightness: brightness),
              home: FullPlayer(controller: controller),
            ),
          ),
        );
        await _capture(tester, 'player-$suffix');
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        debugDisableShadows = true;
      });
    }
  }
}
