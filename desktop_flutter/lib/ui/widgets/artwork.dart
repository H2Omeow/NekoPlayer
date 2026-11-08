import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/library.dart';
import '../neko_theme.dart';

/// Cover art for a track. Tracks without artwork get a soft colour derived
/// from the title so grids of local files don't look identical.
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.size,
    this.track,
    this.url,
    this.label,
    this.radius,
    this.icon = Icons.music_note_rounded,
  });

  final double size;
  final Track? track;
  final String? url;
  final String? label;
  final double? radius;
  final IconData? icon;

  static Uri? safeUri(String? value) {
    final uri = Uri.tryParse(value ?? '');
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }

  @override
  Widget build(BuildContext context) {
    final corner = BorderRadius.circular(
      radius ??
          (size >= 120
              ? NekoRadius.artwork
              : size >= 64
              ? NekoRadius.card
              : NekoRadius.cover),
    );
    final uri = safeUri(url ?? track?.online?.artwork);
    final placeholder = _Placeholder(
      seed: label ?? track?.title ?? '',
      size: size,
      icon: icon,
    );
    return ClipRRect(
      borderRadius: corner,
      child: SizedBox.square(
        dimension: size,
        child: uri == null
            ? placeholder
            : Image.network(
                uri.toString(),
                cacheWidth: size > 100 ? 600 : 160,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                frameBuilder: (context, child, frame, synchronous) =>
                    frame == null && !synchronous ? placeholder : child,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.seed,
    required this.size,
    required this.icon,
  });
  final String seed;
  final double size;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hue = seed.isEmpty
        ? 340.0
        : (seed.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0xffff) % 360)
              .toDouble();
    Color tone(double shift, double lightness) =>
        HSLColor.fromAHSL(1, (hue + shift) % 360, 0.28, lightness).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [tone(0, 0.26), tone(36, 0.16)]
              : [tone(0, 0.86), tone(36, 0.76)],
        ),
      ),
      child: icon == null
          ? null
          : Center(
              child: Icon(
                icon,
                size: math.max(16, size * 0.36),
                color: (dark ? Colors.white : Colors.black).withValues(
                  alpha: 0.45,
                ),
              ),
            ),
    );
  }
}
