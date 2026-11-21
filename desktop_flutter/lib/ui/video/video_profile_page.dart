import 'package:flutter/material.dart';

import '../../i18n/tr.dart';
import '../../video/bili_client.dart';
import '../../video/video_settings.dart';
import '../neko_theme.dart';
import 'video_widgets.dart';

/// 「我的」页：账号、观看历史、云存储与设置入口。
class VideoProfilePage extends StatelessWidget {
  const VideoProfilePage({
    super.key,
    required this.client,
    required this.store,
    required this.onOpenVideo,
    this.onOpenCloud,
    this.onOpenDanmakuSettings,
    this.onOpenPlayerSettings,
  });

  final BiliClient client;
  final VideoSettingsStore store;
  final void Function(BiliVideo video) onOpenVideo;
  final VoidCallback? onOpenCloud;
  final VoidCallback? onOpenDanmakuSettings;
  final VoidCallback? onOpenPlayerSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: NekoPalette.of(context).canvas,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final history = store.watchHistory;
            return ListView(
              padding: const EdgeInsets.fromLTRB(NekoSpace.xl, NekoSpace.md, NekoSpace.xl, NekoSpace.xl),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back),
                      tooltip: tr('返回'),
                    ),
                    Text(tr('我的'), style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
                const SizedBox(height: NekoSpace.lg),
                _AccountCard(onChanged: () {}),
                const SizedBox(height: NekoSpace.xl),
                if (onOpenCloud != null)
                  _EntryTile(
                    icon: Icons.cloud_outlined,
                    title: tr('云存储'),
                    subtitle: tr('上传文件、分享链接、查看额度与赞赏'),
                    onTap: onOpenCloud!,
                  ),
                if (onOpenDanmakuSettings != null)
                  _EntryTile(
                    icon: Icons.comment_outlined,
                    title: tr('弹幕设置'),
                    subtitle: tr('字号、速度、透明度、显示区域'),
                    onTap: onOpenDanmakuSettings!,
                  ),
                if (onOpenPlayerSettings != null)
                  _EntryTile(
                    icon: Icons.settings_outlined,
                    title: tr('播放设置'),
                    subtitle: tr('默认清晰度、倍速、续播'),
                    onTap: onOpenPlayerSettings!,
                  ),
                const SizedBox(height: NekoSpace.xl),
                VideoSectionHeader(
                  title: tr('观看历史'),
                  action: history.isEmpty ? null : tr('清空'),
                  onAction: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(tr('清空观看历史？')),
                        content: Text(tr('清空后无法恢复，已上传的文件不受影响。')),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr('取消'))),
                          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(tr('清空'))),
                        ],
                      ),
                    );
                    if (confirmed == true) store.clearHistory();
                  },
                ),
                if (history.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: NekoSpace.xl),
                    child: Text(
                      tr('还没有观看记录'),
                      style: TextStyle(color: colors.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  for (final entry in history)
                    VideoListRow(
                      video: BiliVideo(
                        bvid: entry.bvid,
                        aid: 0,
                        title: entry.title,
                        cover: entry.cover,
                        upName: entry.upName,
                        upFace: '',
                        durationSec: entry.durationSec,
                        views: 0,
                        danmakuCount: 0,
                        pubdate: 0,
                      ),
                      progress: entry.progress,
                      subtitle: entry.positionMs > 0
                          ? '${tr('已观看')} ${formatDuration(entry.positionMs ~/ 1000)} / '
                              '${formatDuration(entry.durationSec)}'
                          : null,
                      onTap: () => onOpenVideo(
                        BiliVideo(
                          bvid: entry.bvid,
                          aid: 0,
                          title: entry.title,
                          cover: entry.cover,
                          upName: entry.upName,
                          upFace: '',
                          durationSec: entry.durationSec,
                          views: 0,
                          danmakuCount: 0,
                          pubdate: 0,
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: tr('删除记录'),
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => store.removeWatch(entry.bvid),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.onChanged});

  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return StreamBuilder<BiliAccount>(
      stream: BiliSession.instance.changes,
      initialData: BiliSession.instance.account,
      builder: (context, snapshot) {
        final account = snapshot.data ?? BiliAccount.guest;
        return Container(
          padding: const EdgeInsets.all(NekoSpace.lg),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(NekoRadius.card),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: colors.surfaceContainerHighest,
                foregroundImage: account.face.isEmpty ? null : NetworkImage(account.face),
                child: Text(account.isLogin && account.name.isNotEmpty ? account.name.substring(0, 1) : 'B'),
              ),
              const SizedBox(width: NekoSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.isLogin ? account.name : tr('未登录'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      account.isLogin ? 'UID ${account.mid}' : tr('登录后可发送弹幕、点赞收藏'),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (account.isLogin)
                OutlinedButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(tr('退出登录？')),
                        content: Text(tr('退出后需要重新扫码才能发送弹幕和同步数据。')),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr('取消'))),
                          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(tr('退出'))),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await BiliSession.instance.logout();
                      onChanged();
                    }
                  },
                  child: Text(tr('退出登录')),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: NekoSpace.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(NekoRadius.control),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: NekoSpace.lg, vertical: NekoSpace.md),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(NekoRadius.control),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colors.onSurfaceVariant),
              const SizedBox(width: NekoSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 2),
                    Text(subtitle, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
