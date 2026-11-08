import '../i18n/tr.dart';
import 'package:flutter/material.dart';

import '../domain/online_music.dart';

class DownloadQualityDialog extends StatefulWidget {
  const DownloadQualityDialog({
    super.key,
    required this.load,
    this.requiresConfirmation = false,
  });

  final Future<List<AudioQuality>> Function(bool Function() accept) load;
  final bool requiresConfirmation;

  @override
  State<DownloadQualityDialog> createState() => _DownloadQualityDialogState();
}

class _DownloadQualityDialogState extends State<DownloadQualityDialog> {
  List<AudioQuality> qualities = [];
  String? error;
  bool loading = true;
  bool checked = false;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    if (widget.requiresConfirmation) {
      loading = false;
    } else {
      load();
    }
  }

  Future<void> load() async {
    final request = ++generation;
    setState(() {
      loading = true;
      checked = true;
      error = null;
      qualities = [];
    });
    bool accept() => mounted && request == generation;
    try {
      final result = await widget.load(accept);
      if (accept()) setState(() => qualities = result);
    } on MusicSearchException catch (failure) {
      if (accept()) setState(() => error = failure.message);
    } catch (_) {
      if (accept()) setState(() => error = tr('音质检查失败，请检查网络与账号状态后重试。'));
    } finally {
      if (accept()) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return AlertDialog(
      title:       Text(tr('选择下载音质')),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('按当前账号逐项检查完整音源，不会下载音频。开始下载时会再次验证权限，不会用试听或低音质冒充。'),
              style: small,
            ),
            const SizedBox(height: 16),
            if (widget.requiresConfirmation) ...[
              Text(tr('惜缘音源会逐项请求音源接口，可能计入本站账号配额；只在你确认后发送，不会自动重试。'), style: small),
              const SizedBox(height: 16),
            ],
            if (loading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
                    Text(tr('正在检查可下载音质，可随时取消。')),
            ] else if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (checked && qualities.isEmpty)
                    Text(tr('当前账号没有已验证的可下载完整音质，请检查歌曲版权和账号权益。'))
            else
              for (final quality in qualities)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: const Icon(Icons.graphic_eq_rounded),
                  title: Text(quality.label),
                  subtitle: Text(
                    quality.size > 0
                        ? '${quality.id} · ${(quality.size / (1024 * 1024)).toStringAsFixed(1)} MiB'
                        : quality.id,
                  ),
                  trailing: const Icon(Icons.download_rounded),
                  onTap: () => Navigator.pop(context, quality.id),
                ),
          ],
        ),
      ),
      actions: [
        if (!checked)
          FilledButton(onPressed: load, child:       Text(tr('检查可下载音质'))),
        if (checked && !loading && (error != null || qualities.isEmpty))
          TextButton(onPressed: load, child:       Text(tr('重新检查'))),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:       Text(tr('取消')),
        ),
      ],
    );
  }
}
