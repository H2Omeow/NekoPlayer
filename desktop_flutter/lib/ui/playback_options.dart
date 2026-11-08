import '../i18n/tr.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../player_controller.dart';
import 'library/library_actions.dart';
import 'playlist_picker.dart';
import 'shell/queue_panel.dart';

enum PlaybackView { split, record, lyrics }

class PlaybackOptionsButton extends StatelessWidget {
  const PlaybackOptionsButton({
    super.key,
    required this.controller,
    this.view = PlaybackView.split,
    this.onViewChanged,
  });
  final PlayerController controller;
  final PlaybackView view;
  final ValueChanged<PlaybackView>? onViewChanged;

  void select(BuildContext context, String action) {
    switch (action) {
      case 'view-split':
        onViewChanged?.call(PlaybackView.split);
      case 'view-record':
        onViewChanged?.call(PlaybackView.record);
      case 'view-lyrics':
        onViewChanged?.call(PlaybackView.lyrics);
      case 'playlist':
        final track = controller.current;
        if (track != null) {
          unawaited(showPlaylistPicker(context, controller, track));
        }
      case 'queue':
        unawaited(
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => PlaybackQueueSheet(controller: controller),
          ),
        );
      case 'rate':
        unawaited(
          showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title:       Text(tr('播放速度')),
              scrollable: true,
              content: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final rate in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                    ChoiceChip(
                      label: Text('${rate}x'),
                      selected: controller.rate == rate,
                      onSelected: (_) {
                        controller.setRate(rate);
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child:       Text(tr('关闭')),
                ),
              ],
            ),
          ),
        );
      case 'timer':
        unawaited(
          showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title:       Text(tr('定时暂停')),
              scrollable: true,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.sleepDeadline == null
                        ? tr('当前未开启')
                        : tr('将在 {time} 暂停', {
                            'time':
                                '${controller.sleepDeadline!.hour.toString().padLeft(2, '0')}:'
                                '${controller.sleepDeadline!.minute.toString().padLeft(2, '0')}',
                          }),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final minutes in [15, 30, 60, 90])
                        ActionChip(
                          label: Text(tr('{minutes} 分钟', {'minutes': minutes})),
                          onPressed: () {
                            controller.setSleepTimer(
                              Duration(minutes: minutes),
                            );
                            Navigator.pop(context);
                          },
                        ),
                      if (controller.sleepDeadline != null)
                        ActionChip(
                          label:       Text(tr('取消定时')),
                          onPressed: () {
                            controller.setSleepTimer(null);
                            Navigator.pop(context);
                          },
                        ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child:       Text(tr('关闭')),
                ),
              ],
            ),
          ),
        );
      case 'translation':
        controller.setLyricPreferences(
          translation: !controller.showTranslation,
        );
    }
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: tr('播放选项'),
    icon: const Icon(Icons.more_vert_rounded),
    onSelected: (action) => select(context, action),
    itemBuilder: (_) => [
      if (onViewChanged != null) ...[
        for (final mode in PlaybackView.values)
          CheckedPopupMenuItem(
            value: 'view-${mode.name}',
            checked: view == mode,
            child: Text(switch (mode) {
              PlaybackView.split => tr('封面与歌词'),
              PlaybackView.record => tr('唱片视图'),
              PlaybackView.lyrics => tr('专注歌词'),
            }),
          ),
        const PopupMenuDivider(),
      ],
            PopupMenuItem(value: 'queue', child: Text(tr('播放队列'))),
      if (controller.current != null)
              PopupMenuItem(value: 'playlist', child: Text(tr('加入本机歌单'))),
      PopupMenuItem(
        value: 'rate',
        child: Text(tr('播放速度 · {rate}x', {'rate': controller.rate})),
      ),
      PopupMenuItem(
        value: 'timer',
        child: Text(
          controller.sleepDeadline == null
              ? tr('定时暂停')
              : tr('定时暂停 · 已开启'),
        ),
      ),
      PopupMenuItem(
        value: 'translation',
        child: Text(controller.showTranslation ? tr('隐藏歌词翻译') : tr('显示歌词翻译')),
      ),
    ],
  );
}

class PlaybackQueueSheet extends StatelessWidget {
  const PlaybackQueueSheet({super.key, required this.controller});
  final PlayerController controller;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: QueuePanel(
        actions: LibraryActions(player: controller),
        onClose: () => Navigator.pop(context),
      ),
    ),
  );
}
