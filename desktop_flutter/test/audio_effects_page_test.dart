import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/domain/audio_effects.dart';
import 'package:nekoplayer_desktop/playback/effects_playback_engine.dart';
import 'package:nekoplayer_desktop/ui/audio_effects_page.dart';
import 'package:nekoplayer_desktop/ui/neko_theme.dart';

import 'fakes.dart';

void main() {
  testWidgets('mastering names and descriptions are usable in narrow windows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final engine = EffectsPlaybackEngine(
      normal: FakeEngine(),
      writeSettings: (_) async {},
    );
    await engine.importParameters(const AudioEffects(mastering: 33));
    await tester.pumpWidget(
      MaterialApp(
        theme: nekoTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: AudioEffectsPage(engine: engine),
      ),
    );
    // The page scrolls vertically; the equalizer has its own horizontal scroller.
    final page = find.byType(Scrollable).first;
    final dropdown = find.byType(DropdownButtonFormField<int>);
    await tester.scrollUntilVisible(dropdown, 180, scrollable: page);
    expect(find.text('跨界·碎梦').hitTestable(), findsOneWidget);
    final description = find.text('跨界 · 强削波与极限压缩；刻意失真风格');
    await tester.scrollUntilVisible(description, 100, scrollable: page);
    expect(description.hitTestable(), findsOneWidget);
    await tester.scrollUntilVisible(dropdown, -100, scrollable: page);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    final next = find.text('跨界·战歌');
    await tester.ensureVisible(next.last);
    await tester.tap(next.last);
    await tester.pumpAndSettle();
    expect(engine.effects.mastering, 34);
    expect(engine.effects.enabled, isFalse);
    expect(engine.playing, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    engine.dispose();
  });
}
