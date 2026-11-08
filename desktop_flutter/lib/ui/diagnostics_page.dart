import '../i18n/tr.dart';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../diagnostics/crash_guard.dart';
import '../diagnostics/crash_log.dart';
import '../diagnostics/diagnostics_store.dart';
import '../diagnostics/session_marker.dart';
import 'neko_theme.dart';
import 'widgets/empty_state.dart';
import 'widgets/page_layout.dart';
import 'widgets/settings_list.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key, this.store, this.report});
  final DiagnosticsStore? store;
  final SessionReport? report;
  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  late final DiagnosticsStore store =
      widget.store ??
      DiagnosticsStore(CrashLog.current?.root ?? defaultLogRoot());
  late final SessionReport report = widget.report ?? CrashGuard.report;
  List<DiagnosticFile> files = const [];
  DiagnosticFile? selected;
  String content = '';
  String? notice;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final next = store.list();
    final keep = selected == null
        ? null
        : next.where((entry) => entry.file.path == selected!.file.path);
    final target = keep != null && keep.isNotEmpty
        ? keep.first
        : (next.isEmpty ? null : next.first);
    if (!mounted) return;
    setState(() {
      files = next;
      selected = target;
      if (target == null) content = '';
    });
    if (target != null) await show(target);
  }

  Future<void> show(DiagnosticFile entry) async {
    setState(() => selected = entry);
    String text;
    try {
      text = await store.read(entry);
    } catch (_) {
      text = tr('无法读取该文件。');
    }
    if (mounted && selected == entry) setState(() => content = text);
  }

  Future<void> action(Future<String?> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      notice = null;
    });
    try {
      final message = await work();
      if (mounted) setState(() => notice = message);
    } catch (_) {
      if (mounted) setState(() => notice = tr('操作未完成，请检查文件权限和磁盘空间。'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export() => action(() async {
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 19)
        .replaceAll(RegExp(r'[-:]'), '')
        .replaceAll('T', '-');
    final location = await getSaveLocation(
      suggestedName: 'nekoplayer-diagnostics-$stamp.txt',
      acceptedTypeGroups:       [
        XTypeGroup(label: tr('文本'), extensions: ['txt']),
      ],
    );
    if (location == null) return null;
    await File(location.path).writeAsString(await store.exportText());
    return tr('诊断信息已导出：{path}', {'path': location.path});
  });

  Future<void> openFolder() => action(() async {
    store.root.createSync(recursive: true);
    final opened = await launchUrl(Uri.file(store.root.path));
    return opened ? null : tr('无法打开文件夹：{path}', {'path': store.root.path});
  });

  Future<void> clear() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title:       Text(tr('清除所有日志？')),
        content:       Text(tr('将删除全部运行日志和崩溃转储，无法恢复。建议先导出诊断信息。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:       Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child:       Text(tr('清除')),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true) return;
    await action(() async {
      final removed = store.clear();
      CrashLog.current?.reset();
      return tr('已清除 {count} 个文件。', {'count': removed});
    });
    await refresh();
  }

  Widget _fileList(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: NekoSpace.xs),
        children: [
          for (final entry in files)
            ListTile(
              dense: true,
              selected: entry == selected,
              leading: Icon(
                entry.crash
                    ? Icons.error_outline_rounded
                    : Icons.description_outlined,
                color: entry.crash ? colors.error : null,
              ),
              title: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${entry.crash ? '${tr('崩溃')} · ' : ''}'
                '${entry.modified.toLocal().toString().substring(0, 19)}',
                style: text.labelSmall,
              ),
              onTap: () => show(entry),
            ),
        ],
      ),
    );
  }

  Widget _viewer(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    clipBehavior: Clip.antiAlias,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(NekoSpace.lg),
      child: SelectableText(
        content,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: ['Consolas', 'DejaVu Sans Mono'],
          fontSize: 12,
          height: 1.5,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final gutter = pageGutter(context);
    final narrow = MediaQuery.sizeOf(context).width < 900;
    return Scaffold(
      appBar: AppBar(
        title:       Text(tr('崩溃日志与诊断')),
        actions: [
          IconButton(
            tooltip: tr('刷新'),
            onPressed: busy ? null : refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: NekoSpace.sm),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(gutter, NekoSpace.sm, gutter, gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (report.uncleanShutdown) ...[
              InlineNotice(
                tr('上次运行没有正常退出{started}。{detail}', {
                  'started': report.previousStart == null
                      ? ''
                      : tr('（启动于 {time}）', {
                          'time': report.previousStart!
                              .toString()
                              .substring(0, 19),
                        }),
                  'detail': report.crashFiles.isEmpty
                      ? tr('没有发现崩溃转储，可能是被系统结束或断电。')
                      : tr('发现 {count} 个崩溃文件，请导出诊断信息后反馈。', {
                          'count': report.crashFiles.length,
                        }),
                }),
                error: true,
              ),
              const SizedBox(height: NekoSpace.lg),
            ],
            Wrap(
              spacing: NekoSpace.sm,
              runSpacing: NekoSpace.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : export,
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label:       Text(tr('导出诊断信息')),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : openFolder,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label:       Text(tr('打开日志文件夹')),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: busy || files.isEmpty ? null : clear,
                  child:       Text(tr('清除日志')),
                ),
              ],
            ),
            const SizedBox(height: NekoSpace.sm),
            SelectableText(store.root.path, style: text.bodySmall),
            if (notice case final message?) ...[
              const SizedBox(height: NekoSpace.md),
              InlineNotice(message),
            ],
            const SizedBox(height: NekoSpace.lg),
            Expanded(
              child: files.isEmpty
                  ?       EmptyState(
                      icon: Icons.task_alt_rounded,
                      title: tr('暂无日志'),
                      description: tr('运行日志和崩溃记录会保存在这里。'),
                    )
                  : narrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: 180, child: _fileList(context)),
                        const SizedBox(height: NekoSpace.md),
                        Expanded(child: _viewer(context)),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 280, child: _fileList(context)),
                        const SizedBox(width: NekoSpace.md),
                        Expanded(child: _viewer(context)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
