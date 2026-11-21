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
/// 一条观看记录：首页「继续观看」和历史页都用它。
@immutable
class WatchEntry {
  const WatchEntry({
    required this.bvid,
    required this.title,
    required this.cover,
    required this.upName,
    required this.durationSec,
    required this.positionMs,
    required this.updatedAt,
  });

  final String bvid;
  final String title;
  final String cover;
  final String upName;
  final int durationSec;
  final int positionMs;
  final int updatedAt;

  double get progress {
    if (durationSec <= 0) return 0;
    final ratio = positionMs / (durationSec * 1000);
    return ratio.clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
    'bvid': bvid,
    'title': title,
    'cover': cover,
    'up': upName,
    'duration': durationSec,
    'position': positionMs,
    'at': updatedAt,
  };

  static WatchEntry? fromJson(Map<String, dynamic> raw) {
    final bvid = raw['bvid'] as String? ?? '';
    if (bvid.isEmpty) return null;
    return WatchEntry(
      bvid: bvid,
      title: raw['title'] as String? ?? '',
      cover: raw['cover'] as String? ?? '',
      upName: raw['up'] as String? ?? '',
      durationSec: (raw['duration'] as num?)?.toInt() ?? 0,
      positionMs: (raw['position'] as num?)?.toInt() ?? 0,
      updatedAt: (raw['at'] as num?)?.toInt() ?? 0,
    );
  }
}

class VideoSettingsStore extends ChangeNotifier {
  VideoSettingsStore._(this._prefs, this._settings, this._history, this._watchList);

  static const _keySettings = 'video_settings_v1';
  static const _keyHistory = 'video_history_v1';
  static const _keyWatch = 'video_watch_v1';

  final SharedPreferences _prefs;
  VideoSettings _settings;
  final Map<String, int> _history;
  final List<WatchEntry> _watchList;

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
    final watchList = <WatchEntry>[];
    final watchRaw = prefs.getString(_keyWatch);
    if (watchRaw != null && watchRaw.isNotEmpty) {
      try {
        for (final item in (jsonDecode(watchRaw) as List)) {
          if (item is Map<String, dynamic>) {
            final entry = WatchEntry.fromJson(item);
            if (entry != null) watchList.add(entry);
          }
        }
      } catch (_) {
        watchList.clear();
      }
    }
    return VideoSettingsStore._(prefs, settings, Map.of(history), watchList);
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
    _watchList.clear();
    _prefs.remove(_keyHistory);
    _prefs.remove(_keyWatch);
    notifyListeners();
  }

  /// 首页「继续观看」与历史页：最近的在前。
  List<WatchEntry> get watchHistory => List.unmodifiable(_watchList);

  void recordWatch({
    required String bvid,
    required String title,
    required String cover,
    required String upName,
    required int durationSec,
    required int positionMs,
  }) {
    if (bvid.isEmpty) return;
    _watchList.removeWhere((entry) => entry.bvid == bvid);
    _watchList.insert(
      0,
      WatchEntry(
        bvid: bvid,
        title: title,
        cover: cover,
        upName: upName,
        durationSec: durationSec,
        positionMs: positionMs,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (_watchList.length > 100) _watchList.removeRange(100, _watchList.length);
    _history[bvid] = positionMs;
    _prefs.setString(_keyHistory, jsonEncode(_history));
    _prefs.setString(_keyWatch, jsonEncode(_watchList.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  void removeWatch(String bvid) {
    _watchList.removeWhere((entry) => entry.bvid == bvid);
    _history.remove(bvid);
    _prefs.setString(_keyHistory, jsonEncode(_history));
    _prefs.setString(_keyWatch, jsonEncode(_watchList.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  void resetDanmaku() =>
      updateSettings(_settings.copyWith(danmaku: const DanmakuSettings()));

  void resetPlayer() => updateSettings(
    _settings.copyWith(quality: 80, rate: 1.0, rememberPosition: true),
  );
}
