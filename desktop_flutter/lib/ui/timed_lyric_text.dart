import 'package:flutter/material.dart';

import '../domain/library.dart';

class TimedLyricText extends StatelessWidget {
  const TimedLyricText({
    super.key,
    required this.line,
    required this.position,
    required this.active,
    this.showTranslation = true,
    this.style,
    this.activeColor,
    this.idleColor,
    this.textAlign = TextAlign.start,
  });

  final LyricLine line;
  final Duration position;
  final bool active;
  final bool showTranslation;
  final TextStyle? style;
  final Color? activeColor;
  final Color? idleColor;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lit = activeColor ?? colors.onSurface;
    final idle = idleColor ?? colors.onSurfaceVariant.withValues(alpha: 0.7);
    final base = style ?? Theme.of(context).textTheme.titleLarge!;
    return Text.rich(
      TextSpan(
        children: [
          if (line.words.isEmpty || !active)
            TextSpan(text: line.text)
          else
            for (final word in line.words)
              TextSpan(
                text: word.text,
                style: TextStyle(
                  color: Color.lerp(idle, lit, word.progress(position)),
                ),
              ),
          if (showTranslation && line.translation.isNotEmpty)
            TextSpan(
              text: '\n${line.translation}',
              style: TextStyle(
                fontSize: (base.fontSize ?? 20) * 0.62,
                fontWeight: FontWeight.w500,
                height: 1.6,
                color: active ? lit.withValues(alpha: 0.75) : idle,
              ),
            ),
        ],
      ),
      textAlign: textAlign,
      style: base.copyWith(color: active && line.words.isEmpty ? lit : idle),
    );
  }
}
