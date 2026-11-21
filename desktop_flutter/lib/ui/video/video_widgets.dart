import 'package:flutter/material.dart';

import '../../i18n/tr.dart';
import '../../video/bili_client.dart';
import '../neko_theme.dart';

const _imageHeaders = {
  'Referer': 'https://www.bilibili.com/',
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
};

/// 统一的封面图：带 B 站需要的 Referer，加载失败退化成占位块。
class VideoCoverImage extends StatelessWidget {
  const VideoCoverImage({super.key, required this.url, this.fit = BoxFit.cover});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (url.isEmpty) return Container(color: colors.surfaceContainerHigh);
    return Image.network(
      url,
      fit: fit,
      headers: _imageHeaders,
      errorBuilder: (_, _, _) => Container(
        color: colors.surfaceContainerHigh,
        child: Icon(Icons.movie_outlined, color: colors.onSurfaceVariant.withValues(alpha: 0.6)),
      ),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : Container(color: colors.surfaceContainerHigh),
    );
  }
}

/// 封面 + 时长的角标。
class VideoCoverThumb extends StatelessWidget {
  const VideoCoverThumb({
    super.key,
    required this.video,
    this.width = 168,
    this.progress,
  });

  final BiliVideo video;
  final double width;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(NekoRadius.cover),
          child: Stack(
            fit: StackFit.expand,
            children: [
              VideoCoverImage(url: video.cover),
              if (video.durationSec > 0)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      formatDuration(video.durationSec),
                      style: const TextStyle(color: Colors.white, fontSize: 10.5, height: 1.2),
                    ),
                  ),
                ),
              if (progress != null && progress! > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: progress!.clamp(0.0, 1.0),
                    minHeight: 2.5,
                    backgroundColor: Colors.white.withValues(alpha: 0.28),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 列表行：左封面、右标题 + UP + 数据。
class VideoListRow extends StatelessWidget {
  const VideoListRow({
    super.key,
    required this.video,
    required this.onTap,
    this.progress,
    this.trailing,
    this.subtitle,
  });

  final BiliVideo video;
  final VoidCallback onTap;
  final double? progress;
  final Widget? trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(NekoRadius.control),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: NekoSpace.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VideoCoverThumb(video: video, width: 168, progress: progress),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500, height: 1.35),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    video.upName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle ??
                        '${formatCount(video.views)} ${tr('播放')} · '
                            '${formatCount(video.danmakuCount)} ${tr('弹幕')}',
                    style: text.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// 首页横向滚动的卡片。
class VideoRailCard extends StatelessWidget {
  const VideoRailCard({
    super.key,
    required this.video,
    required this.onTap,
    this.progress,
    this.width = 236,
  });

  final BiliVideo video;
  final VoidCallback onTap;
  final double? progress;
  final double width;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(NekoRadius.card),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VideoCoverThumb(video: video, width: width, progress: progress),
            const SizedBox(height: 8),
            Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(height: 1.35),
            ),
            const SizedBox(height: 4),
            Text(
              video.upName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelSmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分组标题 + 右侧可选操作。
class VideoSectionHeader extends StatelessWidget {
  const VideoSectionHeader({super.key, required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const Spacer(),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Text(action!, style: TextStyle(color: colors.onSurfaceVariant)),
          ),
      ],
    );
  }
}
