import 'dart:async';

import 'package:flutter/material.dart' hide RepeatMode;

import '../../desktop_integration.dart';
import '../../playback/playback_engine.dart';
import '../../player_controller.dart';
import '../neko_theme.dart';
import '../widgets/artwork.dart';

String clock(Duration duration) =>
    '${duration.inMinutes.toString().padLeft(2, '0')}:${duration.inSeconds.remainder(60).toString().padLeft(2, '0')}';

/// Bottom transport bar. Wide windows get three zones (track, transport,
/// extras); narrow windows collapse to a mini player.
class PlayerBar extends StatelessWidget {
  const PlayerBar({
    super.key,
    required this.controller,
    required this.onOpenPlayer,
    this.onToggleQueue,
    this.queueOpen = false,
    this.integration,
  });

  final PlayerController controller;
  final VoidCallback onOpenPlayer;
  final VoidCallback? onToggleQueue;
  final bool queueOpen;
  final DesktopIntegration? integration;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, controller.engine, integration]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth >= 760 ? _wide(context) : _compact(context),
    ),
  );

  Widget _trackInfo(BuildContext context, {double art = 56}) {
    final track = controller.current;
    final text = Theme.of(context).textTheme;
    final palette = NekoPalette.of(context);
    final favorite = track != null && controller.favorites.contains(track.path);
    return Row(
      children: [
        Flexible(
          child: InkWell(
            onTap: track == null ? null : onOpenPlayer,
            borderRadius: BorderRadius.circular(NekoRadius.control),
            child: Padding(
              padding: const EdgeInsets.all(NekoSpace.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Artwork(size: art, track: track),
                  const SizedBox(width: NekoSpace.md),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track?.title ?? '未在播放',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          track?.artist ?? '选择一首歌开始播放',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (track != null)
          IconButton(
            tooltip: favorite ? '取消收藏' : '收藏',
            onPressed: () => controller.toggleFavorite(track),
            iconSize: 20,
            icon: Icon(
              favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: favorite ? palette.accent : null,
            ),
          ),
      ],
    );
  }

  Widget _wide(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lyrics = integration;
    return SizedBox(
      height: 88,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: NekoSpace.lg),
        child: Row(
          children: [
            Expanded(flex: 3, child: _trackInfo(context)),
            Expanded(
              flex: 4,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    PlaybackControls(controller: controller),
                    SeekBar(controller: controller, dense: true),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SleepTimerButton(controller: controller),
                  if (lyrics != null && lyrics.lyricsAvailable)
                    IconButton(
                      tooltip: lyrics.overlay ? '关闭桌面歌词' : '桌面歌词',
                      isSelected: lyrics.overlay,
                      onPressed: () =>
                          lyrics.configureOverlay(enabled: !lyrics.overlay),
                      icon: const Icon(Icons.subtitles_outlined),
                      selectedIcon: Icon(
                        Icons.subtitles_rounded,
                        color: colors.onSurface,
                      ),
                    ),
                  if (onToggleQueue != null)
                    IconButton(
                      tooltip: queueOpen ? '收起播放队列' : '播放队列',
                      isSelected: queueOpen,
                      onPressed: onToggleQueue,
                      icon: const Icon(Icons.queue_music_rounded),
                      selectedIcon: Icon(
                        Icons.queue_music_rounded,
                        color: colors.onSurface,
                      ),
                    ),
                  Flexible(child: VolumeControl(controller: controller)),
                  IconButton(
                    tooltip: '打开播放器',
                    onPressed: controller.current == null ? null : onOpenPlayer,
                    icon: const Icon(Icons.open_in_full_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compact(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final duration = controller.duration.inMilliseconds;
    final progress = duration <= 0
        ? 0.0
        : (controller.position.inMilliseconds / duration).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NekoSpace.sm,
        NekoSpace.xs,
        NekoSpace.sm,
        NekoSpace.xs,
      ),
      child: Material(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(NekoRadius.card),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NekoSpace.xs,
                NekoSpace.xs,
                NekoSpace.xs,
                NekoSpace.xs,
              ),
              child: Row(
                children: [
                  Expanded(child: _trackInfo(context, art: 44)),
                  PlayButton(controller: controller, size: 40),
                  IconButton(
                    tooltip: '下一首',
                    onPressed: controller.current == null
                        ? null
                        : controller.next,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                ],
              ),
            ),
            LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              color: colors.onSurface,
              backgroundColor: Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}

class PlayButton extends StatelessWidget {
  const PlayButton({super.key, required this.controller, this.size = 40});
  final PlayerController controller;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final playing = controller.engine.playing;
    return SizedBox.square(
      dimension: size + 8,
      child: Center(
        child: IconButton.filled(
          tooltip: playing ? '暂停' : '播放',
          onPressed: controller.tracks.isEmpty && controller.queue.isEmpty
              ? null
              : controller.toggle,
          style: IconButton.styleFrom(
            backgroundColor: colors.onSurface,
            foregroundColor: colors.surface,
            disabledBackgroundColor: colors.onSurface.withValues(alpha: 0.2),
            fixedSize: Size.square(size),
            minimumSize: Size.square(size),
          ),
          iconSize: size * 0.6,
          icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
      ),
    );
  }
}

class PlaybackControls extends StatelessWidget {
  const PlaybackControls({
    super.key,
    required this.controller,
    this.compact = false,
    this.large = false,
  });

  final PlayerController controller;
  final bool compact;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final palette = NekoPalette.of(context);
    final colors = Theme.of(context).colorScheme;
    final repeatActive = controller.repeat != RepeatMode.sequential;
    final iconSize = large ? 32.0 : 24.0;
    final gap = SizedBox(width: large ? NekoSpace.lg : NekoSpace.xs);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!compact) ...[
          IconButton(
            tooltip: switch (controller.repeat) {
              RepeatMode.sequential => '顺序播放',
              RepeatMode.loop => '列表循环',
              RepeatMode.single => '单曲循环',
              RepeatMode.shuffle => '随机播放',
            },
            onPressed: controller.cycleRepeat,
            iconSize: large ? 24 : 20,
            color: repeatActive ? palette.accent : colors.onSurfaceVariant,
            icon: Icon(switch (controller.repeat) {
              RepeatMode.single => Icons.repeat_one_rounded,
              RepeatMode.shuffle => Icons.shuffle_rounded,
              _ => Icons.repeat_rounded,
            }),
          ),
          gap,
          IconButton(
            tooltip: '上一首',
            onPressed: controller.current == null ? null : controller.previous,
            iconSize: iconSize,
            color: colors.onSurface,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          gap,
        ],
        PlayButton(controller: controller, size: large ? 64 : 36),
        gap,
        IconButton(
          tooltip: '下一首',
          onPressed: controller.current == null ? null : controller.next,
          iconSize: iconSize,
          color: colors.onSurface,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        if (!compact && large) ...[
          gap,
          SleepTimerButton(controller: controller, iconSize: 24),
        ],
      ],
    );
  }
}

class SleepTimerButton extends StatelessWidget {
  const SleepTimerButton({
    super.key,
    required this.controller,
    this.iconSize = 20,
  });
  final PlayerController controller;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final deadline = controller.sleepDeadline;
    String two(int value) => value.toString().padLeft(2, '0');
    return PopupMenuButton<int>(
      tooltip: deadline == null
          ? '定时暂停'
          : '将在 ${two(deadline.hour)}:${two(deadline.minute)} 暂停',
      iconSize: iconSize,
      icon: Icon(
        deadline == null ? Icons.bedtime_outlined : Icons.bedtime_rounded,
        color: deadline == null ? null : NekoPalette.of(context).accent,
      ),
      onSelected: (minutes) => controller.setSleepTimer(
        minutes == 0 ? null : Duration(minutes: minutes),
      ),
      itemBuilder: (_) => [
        for (final minutes in [15, 30, 45, 60, 90])
          PopupMenuItem(value: minutes, child: Text('$minutes 分钟后暂停')),
        if (deadline != null) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: 0, child: Text('取消定时')),
        ],
      ],
    );
  }
}

class VolumeControl extends StatelessWidget {
  const VolumeControl({super.key, required this.controller});
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final volume = controller.volume;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: volume == 0 ? '取消静音' : '静音',
          onPressed: () => controller.setVolume(volume == 0 ? 75 : 0),
          iconSize: 20,
          icon: Icon(
            volume == 0
                ? Icons.volume_off_rounded
                : volume < 50
                ? Icons.volume_down_rounded
                : Icons.volume_up_rounded,
          ),
        ),
        Flexible(
          child: SizedBox(
            width: 104,
            child: Slider(
              value: volume.clamp(0, 100),
              max: 100,
              semanticFormatterCallback: (value) => '音量 ${value.round()}%',
              onChanged: controller.setVolume,
            ),
          ),
        ),
      ],
    );
  }
}

class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.controller,
    this.showClock = true,
    this.dense = false,
  });
  final PlayerController controller;
  final bool showClock;
  final bool dense;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? dragging;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final maximum =
        (controller.sessionPending ? controller.position : controller.duration)
            .inMilliseconds
            .toDouble()
            .clamp(1.0, double.maxFinite);
    final value = (dragging ?? controller.position.inMilliseconds.toDouble())
        .clamp(0.0, maximum);
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: widget.dense ? 3 : 4,
        thumbShape: RoundSliderThumbShape(
          enabledThumbRadius: widget.dense ? 5 : 6,
        ),
      ),
      child: Slider(
        value: value,
        max: maximum,
        semanticFormatterCallback: (value) =>
            clock(Duration(milliseconds: value.round())),
        onChanged:
            controller.current == null || controller.duration == Duration.zero
            ? null
            : (value) => setState(() => dragging = value),
        onChangeEnd: (value) {
          unawaited(controller.seek(Duration(milliseconds: value.round())));
          setState(() => dragging = null);
        },
      ),
    );
    if (!widget.showClock) return slider;
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            clock(Duration(milliseconds: value.round())),
            style: style,
            textAlign: TextAlign.right,
          ),
        ),
        Expanded(child: slider),
        SizedBox(
          width: 44,
          child: Text(
            controller.sessionPending ? '--:--' : clock(controller.duration),
            style: style,
          ),
        ),
      ],
    );
  }
}
