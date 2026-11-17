import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 弹幕外观设置。所有数值都在渲染层即时生效，不需要重新拉弹幕。
@immutable
class DanmakuSettings {
  const DanmakuSettings({
    this.enabled = true,
    this.opacity = 0.92,
    this.fontScale = 1.0,
    this.speed = 1.0,
    this.area = 0.75,
    this.density = 120,
    this.bold = true,
    this.strokeWidth = 1.0,
    this.shadow = true,
    this.showScroll = true,
    this.showTop = true,
    this.showBottom = true,
    this.keepColor = true,
    this.blockWords = const [],
  });

  final bool enabled;
  final double opacity;
  final double fontScale;
  final double speed;
  final double area;
  final int density;
  final bool bold;
  final double strokeWidth;
  final bool shadow;
  final bool showScroll;
  final bool showTop;
  final bool showBottom;
  final bool keepColor;
  final List<String> blockWords;

  DanmakuSettings copyWith({
    bool? enabled,
    double? opacity,
    double? fontScale,
    double? speed,
    double? area,
    int? density,
    bool? bold,
    double? strokeWidth,
    bool? shadow,
    bool? showScroll,
    bool? showTop,
    bool? showBottom,
    bool? keepColor,
    List<String>? blockWords,
  }) => DanmakuSettings(
    enabled: enabled ?? this.enabled,
    opacity: opacity ?? this.opacity,
    fontScale: fontScale ?? this.fontScale,
    speed: speed ?? this.speed,
    area: area ?? this.area,
    density: density ?? this.density,
    bold: bold ?? this.bold,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    shadow: shadow ?? this.shadow,
    showScroll: showScroll ?? this.showScroll,
    showTop: showTop ?? this.showTop,
    showBottom: showBottom ?? this.showBottom,
    keepColor: keepColor ?? this.keepColor,
    blockWords: blockWords ?? this.blockWords,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'opacity': opacity,
    'fontScale': fontScale,
    'speed': speed,
    'area': area,
    'density': density,
    'bold': bold,
    'strokeWidth': strokeWidth,
    'shadow': shadow,
    'showScroll': showScroll,
    'showTop': showTop,
    'showBottom': showBottom,
    'keepColor': keepColor,
    'blockWords': blockWords,
  };

  factory DanmakuSettings.fromJson(Map<String, dynamic> json) => DanmakuSettings(
    enabled: json['enabled'] as bool? ?? true,
    opacity: (json['opacity'] as num?)?.toDouble() ?? 0.92,
    fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1.0,
    speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
    area: (json['area'] as num?)?.toDouble() ?? 0.75,
    density: (json['density'] as num?)?.toInt() ?? 120,
    bold: json['bold'] as bool? ?? true,
    strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 1.0,
    shadow: json['shadow'] as bool? ?? true,
    showScroll: json['showScroll'] as bool? ?? true,
    showTop: json['showTop'] as bool? ?? true,
    showBottom: json['showBottom'] as bool? ?? true,
    keepColor: json['keepColor'] as bool? ?? true,
    blockWords: (json['blockWords'] as List?)?.map((e) => e.toString()).toList() ?? const [],
  );
}

@immutable
class VideoSettings {
  const VideoSettings({
    this.danmaku = const DanmakuSettings(),
    this.quality = 80,
    this.rate = 1.0,
    this.rememberPosition = true,
  });

  final DanmakuSettings danmaku;
  final int quality;
  final double rate;
  final bool rememberPosition;

  VideoSettings copyWith({
    DanmakuSettings? danmaku,
    int? quality,
    double? rate,
    bool? rememberPosition,
  }) => VideoSettings(
    danmaku: danmaku ?? this.danmaku,
    quality: quality ?? this.quality,
    rate: rate ?? this.rate,
    rememberPosition: rememberPosition ?? this.rememberPosition,
  );

  Map<String, dynamic> toJson() => {
    'danmaku': danmaku.toJson(),
    'quality': quality,
    'rate': rate,
    'rememberPosition': rememberPosition,
  };

  factory VideoSettings.fromJson(Map<String, dynamic> json) => VideoSettings(
    danmaku: json['danmaku'] is Map
        ? DanmakuSettings.fromJson(Map<String, dynamic>.from(json['danmaku'] as Map))
        : const DanmakuSettings(),
    quality: (json['quality'] as num?)?.toInt() ?? 80,
    rate: (json['rate'] as num?)?.toDouble() ?? 1.0,
    rememberPosition: json['rememberPosition'] as bool? ?? true,
  );
}

/// 视频模块设置 + 播放进度，持久化在 SharedPreferences。
class VideoSettingsStore extends ChangeNotifier {
  VideoSettingsStore._(this._prefs, this._settings, this._history);

  static const _keySettings = 'video_settings_v1';
  static const _keyHistory = 'video_history_v1';

  final SharedPreferences _prefs;
  VideoSettings _settings;
  final Map<String, int> _history;

  static Future<VideoSettingsStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    VideoSettings settings = const VideoSettings();
    final raw = prefs.getString(_keySettings);
    if (raw != null && raw.isNotEmpty) {
      try {
        settings = VideoSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        settings = const VideoSettings();
      }
    }
    Map<String, int> history = const {};
    final historyRaw = prefs.getString(_keyHistory);
    if (historyRaw != null && historyRaw.isNotEmpty) {
      try {
        history = (jsonDecode(historyRaw) as Map<String, dynamic>)
            .map((key, value) => MapEntry(key, (value as num).toInt()));
      } catch (_) {
        history = const {};
      }
    }
    return VideoSettingsStore._(prefs, settings, Map.of(history));
  }

  VideoSettings get settings => _settings;

  int positionOf(String bvid) => _history[bvid] ?? 0;

  void updateSettings(VideoSettings next) {
    _settings = next;
    notifyListeners();
    _prefs.setString(_keySettings, jsonEncode(next.toJson()));
  }

  void savePosition(String bvid, int positionMs) {
    _history[bvid] = positionMs;
    if (_history.length > 200) {
      _history.remove(_history.keys.first);
    }
    _prefs.setString(_keyHistory, jsonEncode(_history));
  }

  void clearHistory() {
    _history.clear();
    _prefs.remove(_keyHistory);
    notifyListeners();
  }

  void resetDanmaku() =>
      updateSettings(_settings.copyWith(danmaku: const DanmakuSettings()));

  void resetPlayer() => updateSettings(
    _settings.copyWith(quality: 80, rate: 1.0, rememberPosition: true),
  );
}
