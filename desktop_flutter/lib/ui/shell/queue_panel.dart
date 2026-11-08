import '../../i18n/tr.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../player_controller.dart';
import '../library/library_actions.dart';
import '../neko_theme.dart';
import '../widgets/empty_state.dart';

class QueuePanel extends StatelessWidget {
  const QueuePanel({super.key, required this.actions, this.onClose});
  final LibraryActions actions;
  final VoidCallback? onClose;

  PlayerController get player => actions.player;

  Future<void> clear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title:       Text(tr('清空播放队列？')),
        content:       Text(tr('会停止当前播放；歌曲、收藏和歌单都不受影响。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:       Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child:       Text(tr('清空')),
          ),
        ],
      ),
    );
    if (confirmed == true) await player.clearQueue();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([player, player.engine]),
    builder: (context, _) {
      final text = Theme.of(context).textTheme;
      final queue = player.queue;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NekoSpace.lg,
              NekoSpace.md,
              NekoSpace.xs,
              NekoSpace.xs,
            ),
            child: Row(
              children: [
                Expanded(child: Text(tr('播放队列'), style: text.titleLarge)),
                if (queue.isNotEmpty)
                  TextButton(
                    onPressed: () => unawaited(clear(context)),
                    child:       Text(tr('清空')),
                  ),
                if (onClose != null)
                  IconButton(
                    tooltip: tr('收起播放队列'),
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NekoSpace.lg),
            child: Text(
              queue.isEmpty ? tr('队列为空') : '${queue.length} 首 · 拖动可调整顺序',
              style: text.bodySmall,
            ),
          ),
          const SizedBox(height: NekoSpace.sm),
          Expanded(
            child: queue.isEmpty
                ?       EmptyState(
                    icon: Icons.queue_music_rounded,
                    title: tr('还没有待播歌曲'),
                    description: tr('播放列表或在歌曲菜单中选择“加入播放队列”。'),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      NekoSpace.xs,
                      0,
                      NekoSpace.xs,
                      NekoSpace.lg,
                    ),
                    buildDefaultDragHandles: false,
                    itemCount: queue.length,
                    onReorderItem: (from, to) =>
                        unawaited(player.moveInQueue(from, to)),
                    itemBuilder: (context, index) =>
                        ReorderableDragStartListener(
                          key: ValueKey('queue-$index-${queue[index].path}'),
                          index: index,
                          child: actions.row(
                            context,
                            queue[index],
                            queueIndex: index,
                            onTap: () => unawaited(
                              player.play(List.of(player.queue), index),
                            ),
                          ),
                        ),
                  ),
          ),
        ],
      );
    },
  );
}
