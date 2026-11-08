import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/plugin_subscriptions.dart';
import '../domain/music_plugin.dart';
import 'neko_theme.dart';
import 'widgets/page_layout.dart';
import 'widgets/settings_list.dart';

class PluginSubscriptionsPage extends StatefulWidget {
  const PluginSubscriptionsPage({super.key, required this.subscriptions});
  final PluginSubscriptions subscriptions;

  @override
  State<PluginSubscriptionsPage> createState() =>
      _PluginSubscriptionsPageState();
}

class _PluginSubscriptionsPageState extends State<PluginSubscriptionsPage> {
  final input = TextEditingController();
  bool loading = false;
  String? error;

  Future<void> preview(
    String value, {
    MusicSubscription? previous,
    String? text,
  }) async {
    if (loading || widget.subscriptions.busy) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final uri = subscriptionUri(value);
      if (uri.scheme == 'file' &&
          await File.fromUri(uri).length() > 5 * 1024 * 1024) {
        throw const FormatException('文件超过 5 MiB。');
      }
      final content =
          text ??
          (uri.scheme == 'file'
              ? await File.fromUri(uri).readAsString()
              : null);
      final subscription = content == null
          ? await widget.subscriptions.preview(uri)
          : await widget.subscriptions.previewText(content, uri);
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(previous == null ? '添加音源订阅' : '更新音源订阅'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${subscription.url.host} · ${subscription.sources.length} 个音源',
                  ),
                  const SizedBox(height: 12),
                  for (final source in subscription.sources)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(source.name),
                      subtitle: Text(
                        '${source.format} · ${source.author} · ${source.version}\n${source.url}',
                      ),
                      isThreeLine: true,
                    ),
                  const Text(
                    '音源会处理搜索词和歌曲信息，请只添加可信来源。LX 解析音源会用于对应平台的搜索结果；同平台有多个时，使用最后启用的订阅。',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      );
      if (!mounted || accepted != true) return;
      await widget.subscriptions.save(
        subscription.withEnabled(previous?.enabled ?? true),
      );
      if (mounted) input.clear();
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is FormatException
              ? failure.message
              : '订阅加载或保存失败，请检查网络和链接。',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> change(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (_) {
      if (mounted) setState(() => error = '订阅配置保存失败，原配置保持不变。');
    }
  }

  Future<void> importFile() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: '音源 / 订阅', extensions: ['js', 'json']),
      ],
    );
    if (file == null || !mounted) return;
    if (await file.length() > 5 * 1024 * 1024) {
      if (mounted) setState(() => error = '文件超过 5 MiB。');
      return;
    }
    await preview(
      Uri.file(file.path).toString(),
      text: await file.readAsString(),
    );
  }

  Future<void> configure(MusicPluginSource source) async {
    final controller = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(source.variables),
    );
    String? validation;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('${source.name} · 变量'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final variable in source.userVariables)
                  Text(
                    '${variable['key'] ?? ''}：${variable['name'] ?? ''} ${variable['hint'] ?? ''}',
                  ),
                TextField(
                  controller: controller,
                  minLines: 4,
                  maxLines: 10,
                  decoration: InputDecoration(
                    labelText: '变量 JSON 对象',
                    errorText: validation,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final values =
                      jsonDecode(controller.text) as Map<String, dynamic>;
                  if (values.values.any((value) => value is! String)) {
                    throw const FormatException();
                  }
                  Navigator.pop(context, values.cast<String, String>());
                } catch (_) {
                  update(() => validation = '请输入值为字符串的 JSON 对象。');
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result != null) {
      await change(() => widget.subscriptions.configure(source, result));
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.subscriptions,
    builder: (context, _) {
      final store = widget.subscriptions;
      final disabled = loading || store.busy || !store.readable;
      final text = Theme.of(context).textTheme;
      final colors = Theme.of(context).colorScheme;
      return DetailPage(
        title: '音源与插件订阅',
        children: [
          Text(
            '支持 Animemusic、MusicFree、BakaMusic 和 LX / 洛雪脚本，可以导入订阅链接或本地文件。',
            style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: NekoSpace.lg),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: input,
                  enabled: !disabled,
                  decoration: const InputDecoration(
                    hintText: 'HTTPS 订阅或插件链接',
                    prefixIcon: Icon(Icons.link_rounded),
                  ),
                  onSubmitted: disabled ? null : preview,
                ),
              ),
              const SizedBox(width: NekoSpace.sm),
              FilledButton(
                onPressed: disabled ? null : () => preview(input.text),
                child: const Text('添加'),
              ),
              const SizedBox(width: NekoSpace.xs),
              IconButton(
                tooltip: '从文件导入',
                onPressed: disabled ? null : importFile,
                icon: const Icon(Icons.file_open_outlined),
              ),
            ],
          ),
          const SizedBox(height: NekoSpace.lg),
          if (loading || store.busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: NekoSpace.lg),
          ],
          if (error ?? store.error case final message?) ...[
            InlineNotice(message, error: true),
            const SizedBox(height: NekoSpace.lg),
          ],
          for (final subscription in store.subscriptions)
            Padding(
              padding: const EdgeInsets.only(bottom: NekoSpace.md),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NekoSpace.xl,
                    NekoSpace.lg,
                    NekoSpace.md,
                    NekoSpace.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  subscription.builtin
                                      ? '内置 · 惜缘惜梦'
                                      : subscription.url.scheme == 'file'
                                      ? subscription.url.pathSegments.last
                                      : subscription.url.host,
                                  style: text.titleMedium,
                                ),
                                Text(
                                  '${subscription.sources.length} 个音源',
                                  style: text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: subscription.enabled,
                            onChanged: disabled
                                ? null
                                : (enabled) => change(
                                    () =>
                                        store.setEnabled(subscription, enabled),
                                  ),
                          ),
                          PopupMenuButton<VoidCallback>(
                            tooltip: '更多',
                            enabled: !disabled,
                            icon: const Icon(Icons.more_horiz_rounded),
                            onSelected: (action) => action(),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: () => preview(
                                  '${subscription.url}',
                                  previous: subscription,
                                ),
                                child: const Text('检查更新'),
                              ),
                              if (!subscription.builtin)
                                PopupMenuItem(
                                  value: () =>
                                      change(() => store.remove(subscription)),
                                  child: Text(
                                    '删除订阅',
                                    style: TextStyle(color: colors.error),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      if (!subscription.builtin)
                        SelectableText(
                          '${subscription.url}',
                          maxLines: 1,
                          style: text.labelSmall,
                        ),
                      const SizedBox(height: NekoSpace.md),
                      Wrap(
                        spacing: NekoSpace.sm,
                        runSpacing: NekoSpace.sm,
                        children: [
                          for (final source in subscription.sources)
                            ActionChip(
                              avatar: source.scripted
                                  ? const Icon(Icons.tune_rounded)
                                  : null,
                              tooltip: source.scripted ? '设置变量' : null,
                              label: Text('${source.name} · ${source.version}'),
                              onPressed: disabled || !source.scripted
                                  ? null
                                  : () => configure(source),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
