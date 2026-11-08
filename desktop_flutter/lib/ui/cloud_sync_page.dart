import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../site_controller.dart';
import '../sync/cloud_sync_controller.dart';
import '../sync/sync_section.dart';
import 'neko_theme.dart';
import 'widgets/page_layout.dart';
import 'widgets/settings_list.dart';

/// NekoPlayer account and per-section cloud sync. Each data type shows its
/// local and cloud update time, can be uploaded or pulled on its own, and
/// has its own auto-sync switch.
class CloudSyncPage extends StatefulWidget {
  const CloudSyncPage({
    super.key,
    required this.controller,
    required this.site,
  });
  final CloudSyncController controller;
  final SiteController site;

  @override
  State<CloudSyncPage> createState() => _CloudSyncPageState();
}

class _CloudSyncPageState extends State<CloudSyncPage> {
  final selected = <SyncSection>{
    for (final section in SyncSection.values)
      if (section.isLibrary) section,
  };

  CloudSyncController get controller => widget.controller;
  SiteController get site => widget.site;

  @override
  void initState() {
    super.initState();
    if (controller.signedIn && !controller.busy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.refresh();
      });
    }
  }

  Future<bool> confirm(
    String title,
    String body,
    String action, {
    bool destructive = false,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    )
                  : null,
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  String names(Set<SyncSection> sections) =>
      sections.map((section) => section.label).join('、');

  Future<void> upload() async {
    final sections = Set.of(selected);
    final credentials = sections.contains(SyncSection.credentials);
    if (await confirm(
          '上传到云端？',
          '将用本机的「${names(sections)}」覆盖云端对应数据，云端多出的条目会被删除。'
              '${credentials ? '\n\n登录 Cookie 将上传至本站服务器，请确认这是你信任的设备。' : ''}',
          '上传',
        ) &&
        mounted) {
      await controller.upload(sections);
    }
  }

  Future<void> pull() async {
    final sections = Set.of(selected);
    final credentials = sections.contains(SyncSection.credentials);
    if (await confirm(
          '从云端拉取？',
          '将用云端的「${names(sections)}」覆盖本机对应数据，本机多出的条目会被删除。'
              '${credentials ? '\n\n本机的网易云 / 酷狗登录将被云端的登录替换。' : ''}',
          '拉取',
        ) &&
        mounted) {
      await controller.pull(sections);
    }
  }

  Future<void> importToken() async {
    final input = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入登录令牌'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: input,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '令牌或 nekoplayer://auth 回调链接',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('验证并导入'),
          ),
        ],
      ),
    );
    input.dispose();
    if (mounted && value != null) await site.importToken(value);
  }

  Future<void> logout() async {
    if (await confirm(
          '退出 NekoPlayer 账号？',
          '本机将不再同步；本机的音乐库与平台登录不会被删除。',
          '退出',
          destructive: true,
        ) &&
        mounted) {
      await site.logout();
    }
  }

  void login() =>
      site.login((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, site, site.accounts]),
    builder: (context, _) {
      final enabled =
          controller.signedIn && !controller.busy && selected.isNotEmpty;
      final text = Theme.of(context).textTheme;
      return DetailPage(
        title: '账号与云端同步',
        children: [
          _AccountCard(
            site: site,
            sync: controller,
            onLogin: login,
            onImportToken: importToken,
            onLogout: logout,
          ),
          if (site.message case final message?) ...[
            const SizedBox(height: NekoSpace.md),
            InlineNotice(
              message,
              action: site.busy
                  ? TextButton(
                      onPressed: site.cancelLogin,
                      child: const Text('取消'),
                    )
                  : null,
            ),
          ],
          const SizedBox(height: NekoSpace.xl),
          SettingsSection(
            title: '同步内容',
            description:
                '勾选的数据用于下方的手动操作。自动同步只处理单边改动；'
                '两端都改过时会标记冲突，等你选择方向。',
            children: [
              for (final section in SyncSection.values)
                _SectionTile(
                  section: section,
                  controller: controller,
                  selected: selected.contains(section),
                  onSelected: controller.busy
                      ? null
                      : (value) => setState(
                          () => value
                              ? selected.add(section)
                              : selected.remove(section),
                        ),
                ),
            ],
          ),
          if (controller.busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: NekoSpace.md),
          ],
          Wrap(
            spacing: NekoSpace.sm,
            runSpacing: NekoSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: enabled ? upload : null,
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('上传到云端'),
              ),
              FilledButton.tonalIcon(
                onPressed: enabled ? pull : null,
                icon: const Icon(Icons.cloud_download_outlined, size: 18),
                label: const Text('从云端拉取'),
              ),
              OutlinedButton.icon(
                onPressed: enabled
                    ? () => controller.merge(Set.of(selected))
                    : null,
                icon: const Icon(Icons.merge_type_rounded, size: 18),
                label: const Text('合并两端'),
              ),
            ],
          ),
          const SizedBox(height: NekoSpace.sm),
          Text(
            selected.isEmpty
                ? '先勾选要操作的数据。'
                : '已选 ${names(selected)}。上传 / 拉取会让对方与这一端完全一致（包括删除）；'
                      '合并保留两端的全部条目，适合第一次同步或处理冲突。',
            style: text.bodySmall,
          ),
          if (controller.error != null || controller.results.isNotEmpty) ...[
            const SizedBox(height: NekoSpace.xl),
            if (controller.error case final error?)
              Padding(
                padding: const EdgeInsets.only(bottom: NekoSpace.sm),
                child: InlineNotice(error, error: true),
              ),
            for (final result in controller.results)
              Padding(
                padding: const EdgeInsets.only(bottom: NekoSpace.sm),
                child: InlineNotice(
                  '${result.section.label}：${result.message}',
                  error: !result.ok,
                ),
              ),
          ],
          const SizedBox(height: NekoSpace.lg),
          Text('本地音频文件及其路径不会上传。', style: text.bodySmall),
        ],
      );
    },
  );
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.site,
    required this.sync,
    required this.onLogin,
    required this.onImportToken,
    required this.onLogout,
  });

  final SiteController site;
  final CloudSyncController sync;
  final VoidCallback onLogin;
  final VoidCallback onImportToken;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final user = site.user;
    final name = '${user?['nickname'] ?? user?['username'] ?? ''}';
    final signedIn = sync.signedIn;
    final busy = site.busy || sync.busy;
    final readable = site.accounts.readable;
    final title = !signedIn
        ? '未登录'
        : name.isEmpty
        ? '已保存登录凭据'
        : name;
    final subtitle = !signedIn
        ? '登录后，收藏、歌单、播放记录和平台登录可以在设备间同步。'
        : '上次检查云端：${describeTime(sync.lastCheckedAt, DateTime.now())}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(NekoSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: signedIn
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  foregroundColor: signedIn
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                  child: name.isEmpty
                      ? const Icon(Icons.person_rounded)
                      : Text(
                          name.characters.first.toUpperCase(),
                          style: text.titleLarge?.copyWith(
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                ),
                const SizedBox(width: NekoSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle, style: text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: NekoSpace.lg),
            Wrap(
              spacing: NekoSpace.sm,
              runSpacing: NekoSpace.sm,
              children: signedIn
                  ? [
                      OutlinedButton.icon(
                        onPressed: busy ? null : sync.refresh,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('刷新云端状态'),
                      ),
                      if (name.isEmpty)
                        TextButton(
                          onPressed: busy ? null : site.refresh,
                          child: const Text('验证账号'),
                        ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: colors.error,
                        ),
                        onPressed: busy ? null : onLogout,
                        child: const Text('退出登录'),
                      ),
                    ]
                  : [
                      FilledButton.icon(
                        onPressed: busy || !readable ? null : onLogin,
                        icon: const Icon(
                          Icons.open_in_browser_rounded,
                          size: 18,
                        ),
                        label: const Text('在浏览器中登录'),
                      ),
                      TextButton(
                        onPressed: busy || !readable ? null : onImportToken,
                        child: const Text('导入令牌'),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.section,
    required this.controller,
    required this.selected,
    required this.onSelected,
  });

  final SyncSection section;
  final CloudSyncController controller;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final state = controller.stateOf(section);
    final remote = controller.remote[section];
    final status = controller.statusOf(section);
    final now = DateTime.now();
    final checked = controller.remote.isNotEmpty;
    final cloud = !checked
        ? '未检查'
        : remote == null || !remote.hasData
        ? '暂无数据'
        : '${remote.count} 项 · ${describeTime(remote.updatedAt, now)}'
              '${remote.device.isEmpty ? '' : ' · ${remote.device}'}';
    final local =
        '${controller.localCount(section)} 项 · ${describeTime(state.localUpdatedAt, now)}';
    Widget side(IconData icon, String label, String value) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colors.onSurfaceVariant),
        const SizedBox(width: NekoSpace.xs),
        Flexible(child: Text('$label  $value', style: text.bodySmall)),
      ],
    );
    return InkWell(
      onTap: onSelected == null ? null : () => onSelected!(!selected),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          NekoSpace.sm,
          NekoSpace.md,
          NekoSpace.lg,
          NekoSpace.md,
        ),
        child: Row(
          children: [
            Checkbox(
              value: selected,
              onChanged: onSelected == null
                  ? null
                  : (value) => onSelected!(value ?? false),
            ),
            const SizedBox(width: NekoSpace.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: NekoSpace.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(section.label, style: text.bodyLarge),
                      _StatusBadge(status: status),
                    ],
                  ),
                  const SizedBox(height: NekoSpace.xs),
                  side(Icons.computer_rounded, '本机', local),
                  const SizedBox(height: 2),
                  side(Icons.cloud_outlined, '云端', cloud),
                  if (section == SyncSection.credentials) ...[
                    const SizedBox(height: NekoSpace.xs),
                    Text(
                      '包含网易云 / 酷狗的登录 Cookie，只在信任的设备上开启。',
                      style: text.bodySmall?.copyWith(color: colors.error),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: NekoSpace.md),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: state.autoSync,
                  onChanged: (value) => controller.setAuto(section, value),
                ),
                Text('自动同步', style: text.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (status) {
      SyncStatus.synced => colors.tertiary,
      SyncStatus.conflict => colors.error,
      SyncStatus.unknown => colors.outline,
      _ => colors.primary,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(NekoRadius.control),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          status.label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: color),
        ),
      ),
    );
  }
}
