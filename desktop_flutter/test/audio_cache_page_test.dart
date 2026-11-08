import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/data/audio_cache.dart';
import 'package:nekoplayer_desktop/player_controller.dart';
import 'package:nekoplayer_desktop/ui/audio_cache_page.dart';
import 'package:nekoplayer_desktop/ui/neko_theme.dart';

import 'fakes.dart';

void main() {
  testWidgets(
    'cache controls remain scrollable in short windows with large text',
    (tester) async {
      tester.view.physicalSize = const Size(480, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = Directory(
        '${Directory.systemTemp.path}/neko-cache-page-unused',
      );
      final cache = AudioCache(directory: directory, store: MemoryStore());
      final player = PlayerController(
        engine: FakeEngine(),
        store: MemoryStore(),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: nekoTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.6)),
            child: child!,
          ),
          home: AudioCachePage(cache: cache, player: player),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      cache.dispose();
      player.dispose();
    },
  );
}
