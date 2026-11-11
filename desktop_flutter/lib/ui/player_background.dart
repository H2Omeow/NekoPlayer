import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../appearance_controller.dart';
import '../domain/library.dart';

class PlayerBackdrop extends StatelessWidget {
  const PlayerBackdrop({
    super.key,
    required this.appearance,
    required this.track,
  });
  final AppearanceController appearance;
  final Track? track;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surface;
    final fallback = ColoredBox(color: base);
    Widget image = fallback;
    switch (appearance.playerBackground) {
      case PlayerBackground.solid:
        return fallback;
      case PlayerBackground.cover:
        final uri = Uri.tryParse(track?.online?.artwork ?? '');
        if (uri != null &&
            ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty) {
          image = Image.network(
            uri.toString(),
            fit: BoxFit.cover,
            cacheWidth: 1280,
            cacheHeight: 720,
            errorBuilder: (_, _, _) => fallback,
          );
        }
      case PlayerBackground.wallpaper:
        if (appearance.wallpaper != null) {
          image = Image.file(
            File(appearance.wallpaper!),
            fit: BoxFit.cover,
            cacheWidth: 1280,
            cacheHeight: 720,
            errorBuilder: (_, _, _) => fallback,
          );
        }
    }
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: appearance.effectiveBlur(
                appearance.playerBlur,
                MediaQuery.devicePixelRatioOf(context),
              ),
              sigmaY: appearance.effectiveBlur(
                appearance.playerBlur,
                MediaQuery.devicePixelRatioOf(context),
              ),
            ),
            child: image,
          ),
          ColoredBox(color: base.withValues(alpha: appearance.playerMask)),
        ],
      ),
    );
  }
}
