import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../video/bili_client.dart';
import '../../video/video_settings.dart';

/// 弹幕渲染层。
///
/// 位置由外部传进来的播放进度驱动（不自己计时），所以暂停/拖动进度条时
/// 弹幕会立刻跟着停在正确的位置。轨道在数据到达时一次性分配好，
/// 每帧只做一次二分查找 + 绘制，几千条弹幕也不会掉帧。
class DanmakuOverlay extends StatefulWidget {
  const DanmakuOverlay({
    super.key,
    required this.items,
    required this.settings,
    required this.position,
    required this.duration,
    this.width,
    this.height,
  });

  final List<BiliDanmaku> items;
  final DanmakuSettings settings;
  final Duration position;
  final Duration duration;
  final double? width;
  final double? height;

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay> {
  _DanmakuLayout? _layout;
  List<BiliDanmaku>? _layoutSource;
  DanmakuSettings? _layoutSettings;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = widget.width ?? constraints.maxWidth;
        final height = widget.height ?? constraints.maxHeight;
        if (_layoutSource != widget.items ||
            _layoutSettings != widget.settings ||
            _layout?.width != width ||
            _layout?.height != height) {
          _layoutSource = widget.items;
          _layoutSettings = widget.settings;
          _layout = _buildLayout(widget.items, widget.settings, width, height);
        }
        return IgnorePointer(
          child: ClipRect(
            child: CustomPaint(
              painter: _DanmakuPainter(
                layout: _layout!,
                positionMs: widget.position.inMilliseconds,
                settings: widget.settings,
              ),
              size: Size(width, height),
            ),
          ),
        );
      },
    );
  }
}

class _PlacedDanmaku {
  const _PlacedDanmaku({
    required this.item,
    required this.lane,
    required this.startMs,
    required this.endMs,
    required this.kind,
  });

  final BiliDanmaku item;
  final int lane;
  final int startMs;
  final int endMs;
  final _DanmakuKind kind;
}

enum _DanmakuKind { scroll, top, bottom }

class _DanmakuLayout {
  const _DanmakuLayout({
    required this.width,
    required this.height,
    required this.laneHeight,
    required this.lanes,
    required this.entries,
    required this.byStart,
  });

  final double width;
  final double height;
  final double laneHeight;
  final int lanes;
  final List<_PlacedDanmaku> entries;

  /// 按开始时间排序后的同一批数据，二分查找用。
  final List<_PlacedDanmaku> byStart;
}

_DanmakuLayout _buildLayout(
  List<BiliDanmaku> items,
  DanmakuSettings settings,
  double width,
  double height,
) {
  final laneHeight = 26.0 * settings.fontScale;
  final usable = height * settings.area.clamp(0.2, 1.0).toDouble();
  final lanes = math.max(1, (usable / laneHeight).floor());
  final laneFreeAt = List<int>.filled(lanes, 0);

  final placed = <_PlacedDanmaku>[];
  var emitted = 0;

  for (final item in items) {
    if (emitted >= settings.density * 4) break; // 总体上限，防止极端视频
    final isTop = item.mode == 5;
    final isBottom = item.mode == 4;
    if (!settings.enabled) break;
    if (!isTop && !isBottom && !settings.showScroll) continue;
    if (isTop && !settings.showTop) continue;
    if (isBottom && !settings.showBottom) continue;
    if (!settings.keepColor && item.color != 0xFFFFFF) continue;
    if (settings.blockWords.any(
      (w) => w.isNotEmpty && item.content.toLowerCase().contains(w.toLowerCase()),
    )) {
      continue;
    }
    if (item.content.trim().isEmpty) continue;

    final duration = isBottom || isTop
        ? 4200
        : (9000 / settings.speed.clamp(0.4, 3.0)).round();
    final start = item.progressMs;
    final end = start + duration;

    if (isBottom || isTop) {
      var lane = isTop ? 0 : lanes - 1;
      // 固定弹幕也做简单去重：找到第一个空闲轨道
      for (var i = 0; i < lanes; i++) {
        final candidate = isTop ? i : lanes - 1 - i;
        if (laneFreeAt[candidate] <= start) {
          lane = candidate;
          break;
        }
      }
      if (laneFreeAt[lane] > start) continue;
      laneFreeAt[lane] = end;
      placed.add(
        _PlacedDanmaku(
          item: item,
          lane: lane,
          startMs: start,
          endMs: end,
          kind: isTop ? _DanmakuKind.top : _DanmakuKind.bottom,
        ),
      );
    } else {
      var lane = -1;
      for (var i = 0; i < lanes; i++) {
        if (laneFreeAt[i] <= start) {
          lane = i;
          break;
        }
      }
      if (lane < 0) continue;
      laneFreeAt[lane] = end;
      placed.add(
        _PlacedDanmaku(
          item: item,
          lane: lane,
          startMs: start,
          endMs: end,
          kind: _DanmakuKind.scroll,
        ),
      );
    }
    emitted++;
  }

  placed.sort((a, b) => a.startMs.compareTo(b.startMs));
  return _DanmakuLayout(
    width: width,
    height: height,
    laneHeight: laneHeight,
    lanes: lanes,
    entries: placed,
    byStart: placed,
  );
}

class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter({
    required this.layout,
    required this.positionMs,
    required this.settings,
  });

  final _DanmakuLayout layout;
  final int positionMs;
  final DanmakuSettings settings;

  @override
  void paint(Canvas canvas, Size size) {
    if (!settings.enabled) return;
    // 只画 4.2 秒窗口内的弹幕：往前找 start <= position 的最后一条，往前回溯。
    final startIndex = _lowerBound(layout.byStart, positionMs);
    for (var i = startIndex; i < layout.byStart.length; i++) {
      final entry = layout.byStart[i];
      if (entry.startMs > positionMs) break;
      if (entry.endMs <= positionMs) continue;
      _paintEntry(canvas, size, entry);
    }
  }

  int _lowerBound(List<_PlacedDanmaku> list, int value) {
    var low = 0;
    var high = list.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (list[mid].startMs < value) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    // 回退一段，保证跨窗口仍在显示的长弹幕不会漏画
    return math.max(0, low - 400);
  }

  void _paintEntry(Canvas canvas, Size size, _PlacedDanmaku entry) {
    final text = entry.item.content;
    final fontSize =
        15.0 * settings.fontScale * (entry.item.fontSize / 25).clamp(0.7, 1.8).toDouble();
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: settings.bold ? FontWeight.w600 : FontWeight.w400,
          color: settings.keepColor
              ? Color(0xFF000000 | entry.item.color)
              : Colors.white,
          shadows: settings.shadow
              ? const [Shadow(color: Color(0x99000000), blurRadius: 3, offset: Offset(0, 1))]
              : null,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final progress =
        ((positionMs - entry.startMs) / (entry.endMs - entry.startMs)).clamp(0.0, 1.0).toDouble();
    final y = entry.lane * layout.laneHeight + 6;
    double x;
    switch (entry.kind) {
      case _DanmakuKind.scroll:
        x = size.width - progress * (size.width + painter.width);
      case _DanmakuKind.top:
      case _DanmakuKind.bottom:
        x = (size.width - painter.width) / 2;
    }

    if (settings.strokeWidth > 0) {
      final stroke = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: settings.bold ? FontWeight.w600 : FontWeight.w400,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = settings.strokeWidth * 1.6
              ..color = const Color(0xCC000000),
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout();
      stroke.paint(canvas, Offset(x, y));
    }
    if (settings.opacity < 1) {
      canvas.saveLayer(
        Rect.fromLTWH(x, y, painter.width, painter.height),
        Paint()..color = Colors.white.withValues(alpha: settings.opacity.clamp(0.1, 1.0).toDouble()),
      );
      painter.paint(canvas, Offset(x, y));
      canvas.restore();
    } else {
      painter.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(covariant _DanmakuPainter old) =>
      old.positionMs != positionMs ||
      old.layout != layout ||
      old.settings != settings;
}
