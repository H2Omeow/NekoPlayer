import '../i18n/tr.dart';
import 'package:flutter/material.dart';

import '../download_controller.dart';
import 'neko_theme.dart';
import 'widgets/artwork.dart';
import 'widgets/empty_state.dart';
import 'widgets/page_layout.dart';
import 'widgets/settings_list.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({
    super.key,
    required this.controller,
    required this.onImport,
    required this.onPlay,
  });
  final DownloadController controller;
  final Future<void> Function(DownloadTask task) onImport;
  final Future<void> Function(DownloadTask task) onPlay;

  Future<void> deleteFiles(BuildContext context, DownloadTask task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title:       Text(tr('删除已下载的文件？')),
        content: Text(
          tr('将删除这项任务创建的音频{lyrics}，不只是移除记录。\n\n{path}\n\n正在播放的文件可能被系统占用。', {
            'lyrics': task.lyricsOwned ? tr('及歌词') : '',
            'path': task.path ?? '',
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:       Text(tr('取消')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child:       Text(tr('删除文件')),
          ),
        ],
      ),
    );
    if (context.mounted && confirm == true) {
      await controller.remove(task, deleteFiles: true);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => DetailPage(
      title: tr('下载管理'),
      children: [
        if (controller.error case final error?) ...[
          InlineNotice(error, error: true),
          const SizedBox(height: NekoSpace.lg),
        ],
        if (controller.tasks.isEmpty)
                Padding(
            padding: EdgeInsets.symmetric(vertical: NekoSpace.xxl),
            child: EmptyState(
              icon: Icons.download_rounded,
              title: tr('还没有下载任务'),
              description: tr('在歌曲的“⋯”菜单中选择“下载”。'),
            ),
          )
        else
          SettingsSection(
            description:
                tr('一次只下载一首以降低占用，支持暂停和断点续传。') + tr('下载权限单独验证，不会用试听或播放链接代替。'),
            children: [
              for (final task in controller.tasks)
                _DownloadTile(
                  task: task,
                  controller: controller,
                  onPlay: () => onPlay(task),
                  onImport: () => onImport(task),
                  onDeleteFiles: () => deleteFiles(context, task),
                ),
            ],
          ),
      ],
    ),
  );
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({
    required this.task,
    required this.controller,
    required this.onPlay,
    required this.onImport,
    required this.onDeleteFiles,
  });

  final DownloadTask task;
  final DownloadController controller;
  final VoidCallback onPlay;
  final VoidCallback onImport;
  final VoidCallback onDeleteFiles;

  static String megabytes(int bytes) =>
      '${(bytes / 1048576).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final done = task.phase == DownloadPhase.completed && task.path != null;
    final running = task.phase == DownloadPhase.downloading;
    final status = switch (task.phase) {
      DownloadPhase.queued => tr('排队中'),
      DownloadPhase.downloading => tr('下载中'),
      DownloadPhase.paused => tr('已暂停'),
      DownloadPhase.failed => tr('失败'),
      DownloadPhase.completed => tr('已完成'),
    };
    final size = task.total == null
        ? megabytes(task.received)
        : done
        ? megabytes(task.total!)
        : '${megabytes(task.received)} / ${megabytes(task.total!)}';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NekoSpace.lg,
        vertical: NekoSpace.md,
      ),
      child: Row(
        children: [
          Artwork(size: 44, url: task.song.artwork, label: task.song.title),
          const SizedBox(width: NekoSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyLarge,
                ),
                Text(
                  '${task.song.artist} · ${task.song.provider.label} · ${task.quality} · $status · $size',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: task.phase == DownloadPhase.failed
                        ? colors.error
                        : null,
                  ),
                ),
                if (running) ...[
                  const SizedBox(height: NekoSpace.xs),
                  LinearProgressIndicator(
                    value: task.total == null || task.total == 0
                        ? null
                        : (task.received / task.total!).clamp(0, 1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ],
                if (task.error case final error?)
                  Text(
                    error,
                    style: text.bodySmall?.copyWith(color: colors.error),
                  ),
                if (done)
                  Tooltip(
                    message: task.path!,
                    child: Text(
                      task.path!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelSmall,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: NekoSpace.sm),
          if (running || task.phase == DownloadPhase.queued)
            IconButton(
              tooltip: tr('暂停'),
              onPressed: () => controller.pause(task),
              icon: const Icon(Icons.pause_rounded),
            ),
          if (task.phase == DownloadPhase.paused ||
              task.phase == DownloadPhase.failed)
            IconButton(
              tooltip: task.phase == DownloadPhase.failed
                  ? tr('重试')
                  : tr('继续'),
              onPressed: () => controller.resume(task),
              icon: Icon(
                task.phase == DownloadPhase.failed
                    ? Icons.refresh_rounded
                    : Icons.play_arrow_rounded,
              ),
            ),
          if (done)
            IconButton(
              tooltip: tr('播放'),
              onPressed: onPlay,
              icon: const Icon(Icons.play_circle_outline_rounded),
            ),
          PopupMenuButton<VoidCallback>(
            tooltip: tr('更多'),
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              if (done)
                PopupMenuItem(value: onImport, child:       Text(tr('加入音乐库'))),
              if (done)
                PopupMenuItem(
                  value: onDeleteFiles,
                  enabled: !controller.isActive(task),
                  child: Text(tr('删除下载文件'), style: TextStyle(color: colors.error)),
                ),
              PopupMenuItem(
                value: () => controller.remove(task),
                child: Text(running ? tr('取消下载') : tr('移除记录')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
