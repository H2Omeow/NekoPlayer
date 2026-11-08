import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/appearance_controller.dart';
import 'package:nekoplayer_desktop/data/site_client.dart';
import 'package:nekoplayer_desktop/domain/library.dart';
import 'package:nekoplayer_desktop/domain/online_music.dart';
import 'package:nekoplayer_desktop/ui/appearance_page.dart';
import 'package:nekoplayer_desktop/ui/neko_theme.dart';
import 'package:nekoplayer_desktop/ui/player_background.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'late random wallpaper response cannot replace a newer local choice',
    () async {
      final response = Completer<Map<String, dynamic>>();
      final appearance = AppearanceController()..readable = false;
      final pending = appearance.randomWallpaper(
        site: SiteClient(transport: (_) => response.future),
      );
      appearance.update(wallpaperPath: '/new/local.png', showWallpaper: true);
      response.complete({
        'code': 200,
        'data': [
          {'url': '/local/wallpaper/a.png'},
        ],
      });
      await pending;
      expect(appearance.wallpaper, '/new/local.png');
      expect(appearance.wallpaperEnabled, isTrue);
      expect(appearance.busy, isFalse);
      expect(appearance.error, isNull);
      appearance.dispose();
    },
  );

  test('disposed wallpaper request never applies a late response', () async {
    final response = Completer<Map<String, dynamic>>();
    final appearance = AppearanceController()..readable = false;
    final pending = appearance.randomWallpaper(
      site: SiteClient(transport: (_) => response.future),
    );
    appearance.dispose();
    response.complete({'code': 200, 'data': []});
    await pending;
    expect(appearance.wallpaper, isNull);
  });

  test(
    'appearance constrains resource-heavy effects and ignores nonfinite values',
    () {
      final appearance = AppearanceController()..readable = false;
      appearance.update(
        textScale: 20,
        darkness: 0,
        blurRadius: 200,
        controlAlpha: 0,
      );
      expect(appearance.scale, 1.4);
      expect(appearance.mask, .35);
      expect(appearance.blur, 20);
      expect(appearance.controls, .2);
      appearance.update(
        playerMode: PlayerBackground.wallpaper,
        playerDarkness: 0,
        playerBlurRadius: 500,
      );
      expect(appearance.playerBackground, PlayerBackground.wallpaper);
      expect(appearance.playerMask, .35);
      expect(appearance.playerBlur, 20);
      appearance.update(
        playerDarkness: double.nan,
        playerBlurRadius: double.infinity,
      );
      expect(appearance.playerMask, .35);
      expect(appearance.playerBlur, 20);
      appearance.update(textScale: double.nan, blurRadius: double.infinity);
      expect(appearance.scale, 1.4);
      expect(appearance.blur, 20);
      appearance.update(
        wallpaperPath: '/local/image.png',
        showWallpaper: true,
        downloads: '/local/music',
      );
      expect(appearance.wallpaperEnabled, isTrue);
      appearance.update(clearWallpaper: true, resetDownloads: true);
      expect(appearance.wallpaperEnabled, isFalse);
      expect(appearance.wallpaper, isNull);
      expect(appearance.downloadDirectory, isNull);
      appearance.dispose();
    },
  );

  test(
    'wallpaper list never sends auth or accepts external and traversal URLs',
    () async {
      final site = SiteClient(
        transport: (request) async {
          expect(request.token, isEmpty);
          expect(request.uri.path, '/local/wallpaper/list');
          expect(request.uri.queryParameters['orientation'], 'horizontal');
          return {
            'code': 200,
            'data': [
              {'url': '/local/wallpaper/a.png'},
              {'url': '/data/wallpaper/%E4%B8%BB%E5%9B%BE013.png'},
              {
                'url': '/data/wallpaper/huge.jpg',
                'width': 11004,
                'height': 6196,
              },
              {'url': 'https://evil.example/image.png'},
              {'url': 'http://player.nekoh2o.top/local/wallpaper/insecure.png'},
              {'url': '/local/wallpaper/../../secret'},
              {'url': 'https://user@player.nekoh2o.top/local/wallpaper/b.png'},
            ],
          };
        },
      );
      expect((await site.wallpapers()).map((uri) => uri.path), [
        '/local/wallpaper/a.png',
        '/data/wallpaper/%E4%B8%BB%E5%9B%BE013.png',
      ]);
    },
  );

  testWidgets(
    'player backdrop rejects unsafe artwork and falls back without network',
    (tester) async {
      final appearance = AppearanceController()..readable = false;
      for (final artwork in [
        'file:///secret',
        'https://token@host/art.jpg',
        'data:image/png;base64,123',
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: PlayerBackdrop(
              appearance: appearance,
              track: Track.fromOnline(
                OnlineSong(
                  provider: MusicProvider.netease,
                  id: '1',
                  title: 'Test',
                  artist: 'Neko',
                  artwork: artwork,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(Image), findsNothing);
        expect(tester.takeException(), isNull);
      }
      for (final mode in PlayerBackground.values) {
        appearance.update(playerMode: mode);
        await tester.pumpWidget(
          MaterialApp(
            home: PlayerBackdrop(appearance: appearance, track: null),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      appearance.dispose();
    },
  );

  testWidgets(
    'appearance controls fit compact windows with large system text',
    (tester) async {
      tester.view.physicalSize = const Size(480, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final appearance = AppearanceController()..readable = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: nekoTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.3)),
            child: child!,
          ),
          home: AppearancePage(controller: appearance),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('浅色'));
      expect(appearance.theme, ThemeMode.light);
      await tester.pumpWidget(const SizedBox());
      appearance.dispose();
    },
  );
}
