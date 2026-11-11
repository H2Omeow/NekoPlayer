import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/appearance_controller.dart';
import 'package:nekoplayer_desktop/performance_profile.dart';

DevicePerformance device({
  int width = 1920,
  int height = 1080,
  double dpr = 1,
  bool integrated = true,
}) => DevicePerformance(
  physicalWidth: width,
  physicalHeight: height,
  devicePixelRatio: dpr,
  refreshRate: 60,
  integrated: integrated,
);

void main() {
  group('DevicePerformance tiers', () {
    test('4K at 300% on integrated graphics uses the extreme tier', () {
      final value = device(width: 3840, height: 2160, dpr: 3);
      expect(value.recommendedLyricsTier, LyricsQualityTier.extreme);
      expect(value.shouldReduceUiEffects, isTrue);
      expect(value.resolutionLabel, '3840 × 2160');
    });

    test('4K on a discrete GPU uses the power tier', () {
      final value = device(
        width: 3840,
        height: 2160,
        dpr: 2,
        integrated: false,
      );
      expect(value.recommendedLyricsTier, LyricsQualityTier.power);
    });

    test('1080p integrated graphics uses the power tier without UI cuts', () {
      final value = device();
      expect(value.recommendedLyricsTier, LyricsQualityTier.power);
      expect(value.shouldReduceUiEffects, isFalse);
    });

    test('1080p discrete graphics uses balanced', () {
      expect(
        device(integrated: false).recommendedLyricsTier,
        LyricsQualityTier.balanced,
      );
    });

    test('unknown resolution has a stable placeholder', () {
      final value = device(width: 0, height: 0);
      expect(value.resolutionLabel, '—');
      expect(value.physicalPixels, 0);
    });
  });

  group('quality profiles', () {
    test('presets lower scale and frame cap in order', () {
      expect(LyricsQualityTier.high.profile.scale, 1);
      expect(LyricsQualityTier.high.profile.fps, 0);
      expect(LyricsQualityTier.balanced.profile.fps, 60);
      expect(LyricsQualityTier.power.profile.fps, 45);
      expect(LyricsQualityTier.extreme.profile.scale, .4);
      expect(LyricsQualityTier.extreme.profile.fps, 30);
      expect(LyricsQualityTier.extreme.profile.effects, isFalse);
    });
  });

  group('AppearanceController performance policy', () {
    test('auto mode reacts to high DPI and clamps physical blur', () {
      final controller = AppearanceController();
      controller.device = device(width: 3840, height: 2160, dpr: 3);
      expect(controller.performanceUiEnabled, isTrue);
      expect(controller.effectiveBlur(12, 3), closeTo(4, .001));
      expect(controller.effectiveBlur(4, 3), closeTo(4, .001));
    });

    test('1080p auto mode keeps full blur and effects', () {
      final controller = AppearanceController();
      controller.device = device();
      expect(controller.performanceUiEnabled, isFalse);
      expect(controller.effectiveBlur(12, 1), 12);
    });

    test('manual override wins over device detection', () {
      final controller = AppearanceController();
      controller.device = device();
      controller.performanceMode = PerformanceMode.off;
      expect(controller.performanceUiEnabled, isFalse);
      controller.performanceMode = PerformanceMode.on;
      expect(controller.performanceUiEnabled, isTrue);
    });

    test('lyricsQuery describes the selected preset', () {
      final controller = AppearanceController();
      controller.device = device();
      controller.lyricsQualityMode = LyricsQualityMode.custom;
      controller.lyricsScale = 1.25;
      controller.lyricsFps = 0;
      controller.lyricsEffects = false;
      expect(controller.lyricsProfile.scale, 1.25);
      expect(controller.lyricsQuery, {
        'scale': '1.25',
        'fps': '0',
        'effects': '0',
      });
    });

    test('custom values are clamped', () {
      final controller = AppearanceController();
      controller.lyricsQualityMode = LyricsQualityMode.custom;
      controller.lyricsScale = 4;
      controller.lyricsFps = 500;
      expect(controller.lyricsProfile.scale, 1.5);
      expect(controller.lyricsProfile.fps, 240);
    });

    test('auto profile follows the device recommendation', () {
      final controller = AppearanceController();
      controller.device = device(integrated: false);
      expect(controller.lyricsProfile.scale, .9);
      expect(controller.lyricsProfile.fps, 60);
    });
  });
}
