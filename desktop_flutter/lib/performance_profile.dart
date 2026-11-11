import 'dart:async';
import 'dart:ui' show Display;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A quality preset for the embedded dynamic-lyrics engine.
///
/// [scale] is relative to the physical output resolution, so 1.0 renders at
/// native pixels and 0.4 uses 40% of each axis. [fps] is 0 for no software
/// frame cap (the web view still follows the display refresh rate).
class LyricsQualityProfile {
  const LyricsQualityProfile({
    required this.scale,
    required this.fps,
    required this.effects,
  });

  final double scale;
  final int fps;
  final bool effects;
}

/// User-selectable dynamic-lyrics quality.
enum LyricsQualityMode { auto, high, balanced, power, extreme, custom }

/// Controls the wider UI performance policy.
enum PerformanceMode { auto, on, off }

/// Information used by the automatic performance tiers.
class DevicePerformance {
  const DevicePerformance({
    required this.physicalWidth,
    required this.physicalHeight,
    required this.devicePixelRatio,
    required this.refreshRate,
    this.gpu = '',
    this.dedicatedVideoMemoryMb = 0,
    this.integrated = true,
  });

  final int physicalWidth;
  final int physicalHeight;
  final double devicePixelRatio;
  final double refreshRate;
  final String gpu;
  final int dedicatedVideoMemoryMb;
  final bool integrated;

  int get physicalPixels => physicalWidth * physicalHeight;

  bool get highResolution => physicalPixels >= 5000000;

  bool get veryHighDpi => devicePixelRatio >= 2;

  /// Large 4K/300% surfaces are especially expensive because Flutter's blur
  /// radius is logical, so the physical kernel grows with the DPR.
  bool get shouldReduceUiEffects => highResolution || veryHighDpi;

  String get resolutionLabel =>
      physicalWidth > 0 && physicalHeight > 0
      ? '$physicalWidth × $physicalHeight'
      : '—';

  LyricsQualityTier get recommendedLyricsTier {
    if (physicalPixels >= 7000000 || devicePixelRatio >= 2.5) {
      return integrated ? LyricsQualityTier.extreme : LyricsQualityTier.power;
    }
    return integrated ? LyricsQualityTier.power : LyricsQualityTier.balanced;
  }

  static Future<DevicePerformance> detect() async {
    var width = 0;
    var height = 0;
    var dpr = 1.0;
    var refreshRate = 60.0;
    try {
      final view = WidgetsBinding.instance.platformDispatcher.implicitView;
      final Display? display = view?.display ?? _largestDisplay();
      if (display != null) {
        width = display.size.width.round();
        height = display.size.height.round();
        dpr = display.devicePixelRatio;
        refreshRate = display.refreshRate;
      }
      if (view != null) dpr = view.devicePixelRatio;
    } catch (_) {
      // WidgetsBinding may not be ready in some tests; keep conservative values.
    }

    var gpu = '';
    var dedicated = 0;
    try {
      final info = await const MethodChannel('top.nekoh2o/desktop')
          .invokeMapMethod<String, Object?>('deviceInfo')
          .timeout(const Duration(milliseconds: 1500));
      if (info != null) {
        gpu = '${info['gpu'] ?? ''}'.trim();
        dedicated = (info['dedicatedVideoMemoryMb'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {
      // The channel is optional (tests, non-Windows runners, older builds).
    }
    final integrated = _looksIntegrated(gpu, dedicated);
    return DevicePerformance(
      physicalWidth: width,
      physicalHeight: height,
      devicePixelRatio: dpr.isFinite && dpr > 0 ? dpr : 1,
      refreshRate: refreshRate.isFinite && refreshRate > 0 ? refreshRate : 60,
      gpu: gpu,
      dedicatedVideoMemoryMb: dedicated,
      integrated: integrated,
    );
  }

  static Display? _largestDisplay() {
    final displays = WidgetsBinding.instance.platformDispatcher.displays.toList();
    if (displays.isEmpty) return null;
    displays.sort(
      (a, b) => (b.size.width * b.size.height).compareTo(
        a.size.width * a.size.height,
      ),
    );
    return displays.first;
  }

  static bool _looksIntegrated(String gpu, int dedicatedMb) {
    final name = gpu.toLowerCase();
    if (name.isEmpty) return true;
    if (name.contains('intel') ||
        name.contains('uhd') ||
        name.contains('iris') ||
        name.contains('radeon graphics') ||
        name.contains('vega') ||
        name.contains('apple m')) {
      return true;
    }
    if (dedicatedMb >= 2048) return false;
    if (dedicatedMb > 0) return dedicatedMb < 1024;
    final discrete = name.contains('geforce') ||
        name.contains('nvidia') ||
        name.contains('rtx') ||
        name.contains('radeon rx');
    return !discrete;
  }
}

enum LyricsQualityTier { high, balanced, power, extreme }

extension LyricsQualityTierProfile on LyricsQualityTier {
  LyricsQualityProfile get profile => switch (this) {
    LyricsQualityTier.high => const LyricsQualityProfile(
      scale: 1,
      fps: 0,
      effects: true,
    ),
    LyricsQualityTier.balanced => const LyricsQualityProfile(
      scale: .9,
      fps: 60,
      effects: false,
    ),
    LyricsQualityTier.power => const LyricsQualityProfile(
      scale: .7,
      fps: 45,
      effects: false,
    ),
    LyricsQualityTier.extreme => const LyricsQualityProfile(
      scale: .4,
      fps: 30,
      effects: false,
    ),
  };
}
