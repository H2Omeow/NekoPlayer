import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/data/account_store.dart';
import 'package:nekoplayer_desktop/player_controller.dart';
import 'package:nekoplayer_desktop/playback/effects_playback_engine.dart';
import 'package:nekoplayer_desktop/ui/legacy_import_page.dart';
import 'package:nekoplayer_desktop/ui/neko_theme.dart';

import 'fakes.dart';

void main() {
  testWidgets(
    'settings and credentials are independent opt-ins in short windows',
    (tester) async {
      tester.view.physicalSize = const Size(600, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final player = PlayerController(
        engine: EffectsPlaybackEngine(normal: FakeEngine()),
        store: MemoryStore(),
      );
      await player.initialize();
      await tester.pumpWidget(
        MaterialApp(
          theme: nekoTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: LegacyImportPage(player: player, accounts: AccountStore()),
        ),
      );
      final credentials = find.text('账号凭据');
      await tester.scrollUntilVisible(credentials, 120);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.ancestor(
                of: credentials,
                matching: find.byType(CheckboxListTile),
              ),
            )
            .value,
        isFalse,
      );
      final settings = find.text('播放设置');
      await tester.scrollUntilVisible(settings, 120);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.ancestor(
                of: settings,
                matching: find.byType(CheckboxListTile),
              ),
            )
            .value,
        isFalse,
      );
      await tester.tap(settings);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.ancestor(
                of: settings,
                matching: find.byType(CheckboxListTile),
              ),
            )
            .value,
        isTrue,
      );
      await tester.scrollUntilVisible(credentials, -120);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.ancestor(
                of: credentials,
                matching: find.byType(CheckboxListTile),
              ),
            )
            .value,
        isFalse,
      );
      final select = find.text('选择备份并预览');
      final queue = find.text('播放队列和进度');
      await tester.scrollUntilVisible(queue, 120);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.ancestor(of: queue, matching: find.byType(CheckboxListTile)),
            )
            .value,
        isFalse,
      );
      await tester.tap(queue);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.ancestor(of: queue, matching: find.byType(CheckboxListTile)),
            )
            .value,
        isTrue,
      );
      await tester.scrollUntilVisible(settings, -120);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.ancestor(
                of: settings,
                matching: find.byType(CheckboxListTile),
              ),
            )
            .value,
        isTrue,
      );
      await tester.scrollUntilVisible(select, 120);
      final effects = find.text('专业音效参数');
      await tester.scrollUntilVisible(effects, -120);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.ancestor(
                of: effects,
                matching: find.byType(CheckboxListTile),
              ),
            )
            .value,
        isFalse,
      );
      await tester.tap(effects);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.ancestor(
                of: effects,
                matching: find.byType(CheckboxListTile),
              ),
            )
            .value,
        isTrue,
      );
      await tester.scrollUntilVisible(credentials, -120);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.ancestor(
                of: credentials,
                matching: find.byType(CheckboxListTile),
              ),
            )
            .value,
        isFalse,
      );
      await tester.scrollUntilVisible(select, 120);
      expect(select.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(player.engine.playing, isFalse);
      await tester.pumpWidget(const SizedBox());
      player.dispose();
    },
  );
}
