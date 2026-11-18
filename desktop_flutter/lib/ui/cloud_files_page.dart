import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../cloud/cloud_files_client.dart';
import '../data/account_store.dart';
import '../domain/social.dart';
import '../social_controller.dart';
import '../i18n/tr.dart';
import 'neko_theme.dart';
import 'widgets/page_layout.dart';
import 'widgets/settings_list.dart';

/// 云存储：文件、额度与赞赏。与 Android 端共用 player.nekoh2o.top 的接口。
class CloudFilesPage extends StatefulWidget {
  const CloudFilesPage({super.key, required this.accounts, this.social});
  final AccountStore accounts;
  final SocialController? social;

  @override
  State<CloudFilesPage> createState() => _CloudFilesPageState();
}

class _CloudFilesPageState extends State<CloudFilesPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  late final CloudFilesClient _client = CloudFilesClient(token: () => widget.accounts.siteToken);

  bool _loading = true;
  bool _needSkland = false;
  String? _error;
  List<CloudFile> _files = const [];
  CloudQuota? _quota;
  CloudUsage? _usage;
  double? _progress;

  List<CloudTier> _tiers = const [];
  List<CloudOrder> _orders = const [];
  bool _sponsorRequested = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _client.files();
      if (!mounted) return;
      setState(() {
        _files = result.files;
        _quota = result.quota;
        _usage = result.usage;
        _needSkland = false;
        _loading = false;
      });
    } on CloudException catch (error) {
      if (!mounted) return;
      setState(() {
        _needSkland = error.needSkland;
        _error = error.needSkland ? null : error.message;
        _loading = false;
      });
    }
  }

  Future<void> _loadSponsor() async {
    try {
      final tiers = await _client.pricing();
      final orders = await _client.myOrders();
      if (!mounted) return;
      setState(() {
        _tiers = tiers;
        _orders = orders;
      });
    } on CloudException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    }
  }

  Future<void> _pickAndUpload() async {
    final typeGroup = XTypeGroup(label: tr('所有文件'));
    final picked = await openFile(acceptedTypeGroups: [typeGroup]);
    if (picked == null) return;
    setState(() => _progress = 0);
    try {
      await _client.upload(
        picked.path,
        picked.name,
        _categoryOf(picked.name),
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      await _reload();
    } on CloudException catch (error) {
      if (!mounted) return;
      setState(() {
        _needSkland = error.needSkland;
        if (!error.needSkland) _error = error.message;
      });
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _share(CloudFile file) async {
    final choice = await showDialog<({String mode, int days})>(
      context: context,
      builder: (context) => _ShareDialog(file: file),
    );
    if (choice == null) return;
    try {
      final result = await _client.share(file.id, choice.mode, choice.days);
      final token = '${result['token']}';
      final link = 'https://player.nekoh2o.top/s/$token';
      await Clipboard.setData(ClipboardData(text: link));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('分享链接已复制：{link}', {'link': link})),
          action: widget.social == null
              ? null
              : SnackBarAction(
                  label: tr('发送给好友'),
                  onPressed: () => _sendToFriend(link, file.name),
                ),
        ),
      );
    } on CloudException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _sendToFriend(String link, String name) async {
    final social = widget.social;
    if (social == null) return;
    final peer = await showDialog<String>(
      context: context,
      builder: (context) => _FriendPickerDialog(social: social),
    );
    if (peer == null || peer.isEmpty || !mounted) return;
    try {
      await social.repository.sendMessage(
        to: peer,
        kind: 'text',
        text: '${tr('分享了一个文件给你：')}$name\n$link',
        clientId: 'cloud-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('已发送给好友'))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DetailPage(
      title: tr('云存储'),
      maxWidth: 900,
      actions: [
        IconButton(
          tooltip: tr('上传'),
          onPressed: _needSkland ? null : _pickAndUpload,
          icon: const Icon(Icons.cloud_upload_outlined),
        ),
        IconButton(
          tooltip: tr('刷新'),
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      children: [
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: tr('文件')),
            Tab(text: tr('额度')),
            Tab(text: tr('赞赏')),
          ],
        ),
        const SizedBox(height: NekoSpace.lg),
        if (_needSkland)
          _SklandGate(
            onBound: _reload,
            client: _client,
          )
        else if (_loading)
          const Padding(
            padding: EdgeInsets.all(NekoSpace.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: NekoSpace.md),
              child: Text(_error!, style: TextStyle(color: colors.error)),
            ),
          if (_progress != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${tr('上传中')} ${(_progress! * 100).toStringAsFixed(0)}%'),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: NekoSpace.lg),
              ],
            ),
          AnimatedBuilder(
            animation: _tabs,
            builder: (context, _) => switch (_tabs.index) {
              0 => _filesTab(colors),
              1 => _quotaTab(colors),
              _ => _sponsorTab(colors),
            },
          ),
        ],
      ],
    );
  }

  Widget _filesTab(ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _QuotaCard(quota: _quota, usage: _usage, colors: colors),
        const SizedBox(height: NekoSpace.lg),
        if (_files.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: NekoSpace.xl),
            child: Column(
              children: [
                Text(tr('还没有上传任何文件'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: NekoSpace.sm),
                Text(
                  tr('视频最多 50MB，图片 5MB，音乐 25MB，自定义文件 1GB'),
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: NekoSpace.lg),
                FilledButton.icon(
                  onPressed: _pickAndUpload,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(tr('上传文件')),
                ),
              ],
            ),
          )
        else
          for (final file in _files)
            SettingsSection(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: NekoSpace.lg),
                  leading: Icon(_iconFor(file.category)),
                  title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${formatCloudBytes(file.size)} · ${cloudDateLabel(file.createdAt)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: tr('分享'),
                        onPressed: () => _share(file),
                        icon: const Icon(Icons.share_outlined),
                      ),
                      IconButton(
                        tooltip: tr('删除'),
                        onPressed: () async {
                          await _client.delete(file.id);
                          await _reload();
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      ],
    );
  }

  Widget _quotaTab(ColorScheme colors) {
    final rows = <(String, String)>[
      (tr('总存储'), _quota == null ? '∞' : formatCloudBytes(_quota!.storageBytes)),
      (tr('月流量'), _quota == null ? '∞' : formatCloudBytes(_quota!.trafficBytes)),
      (tr('文件份数'), _quota == null || _quota!.fileCount <= 0 ? tr('不限') : '${_quota!.fileCount}'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _QuotaCard(quota: _quota, usage: _usage, colors: colors),
        const SizedBox(height: NekoSpace.lg),
        SettingsSection(
          title: tr('额度'),
          children: [
            for (final row in rows)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: NekoSpace.lg),
                title: Text(row.$1),
                trailing: Text(row.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: NekoSpace.xs, top: NekoSpace.sm),
          child: Text(
            tr('免费用户超过 180 天未登录会清理上传的文件（歌单、收藏、播放记录不受影响），清理前 7 天会在消息里提醒。分享和下载消耗分享者的流量，应用内下载减半。'),
            style: TextStyle(color: colors.onSurfaceVariant, height: 1.6),
          ),
        ),
      ],
    );
  }

  Widget _sponsorTab(ColorScheme colors) {
    if (!_sponsorRequested) {
      _sponsorRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSponsor());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('赞赏 NekoPlayer'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: NekoSpace.xs),
        Text(
          tr('赞赏后不限文件份数、单文件大小，存储 32.5G / 月流量 50G，且文件永不清理。支付后上传截图，人工核对后开通。'),
          style: TextStyle(color: colors.onSurfaceVariant, height: 1.6),
        ),
        const SizedBox(height: NekoSpace.lg),
        for (final tier in _tiers)
          SettingsSection(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: NekoSpace.lg),
                title: Text(tier.label),
                subtitle: Text('${formatCloudBytes(tier.storageBytes)} · ${formatCloudBytes(tier.trafficBytes)}/月'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('¥${tier.price}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: NekoSpace.md),
                    FilledButton(
                      onPressed: () => _createOrder(tier),
                      child: Text(tr('去赞赏')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        const SizedBox(height: NekoSpace.md),
        Text(tr('我的订单'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: NekoSpace.sm),
        if (_orders.isEmpty)
          Text(tr('还没有订单'), style: TextStyle(color: colors.onSurfaceVariant))
        else
          for (final order in _orders)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${order.tier} × ${order.months}'),
              subtitle: Text(cloudDateLabel(order.createdAt)),
              trailing: Text(cloudOrderStatus(order.status)),
            ),
      ],
    );
  }

  Future<void> _createOrder(CloudTier tier) async {
    try {
      final orderId = await _client.createOrder(tier.id, 1);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _ReceiptDialog(orderId: orderId, client: _client, onUploaded: _loadSponsor),
      );
    } on CloudException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  static IconData _iconFor(String category) => switch (category) {
    'video' => Icons.movie_outlined,
    'image' => Icons.image_outlined,
    'audio' => Icons.music_note_outlined,
    _ => Icons.insert_drive_file_outlined,
  };

  static String _categoryOf(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'mp4' || 'mkv' || 'webm' || 'mov' || 'avi' => 'video',
      'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'heic' => 'image',
      'mp3' || 'flac' || 'm4a' || 'wav' || 'ogg' || 'aac' => 'audio',
      _ => 'custom',
    };
  }
}

class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.quota, required this.usage, required this.colors});
  final CloudQuota? quota;
  final CloudUsage? usage;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final storageTotal = quota?.storageBytes ?? 0;
    final trafficTotal = quota?.trafficBytes ?? 0;
    final storageUsed = usage?.storageBytes ?? 0;
    final trafficUsed = usage?.trafficBytes ?? 0;
    return Container(
      padding: const EdgeInsets.all(NekoSpace.lg),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(NekoRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bar(tr('存储'), storageUsed, storageTotal),
          const SizedBox(height: NekoSpace.md),
          _bar(tr('本月流量'), trafficUsed, trafficTotal),
          const SizedBox(height: NekoSpace.sm),
          Text('${tr('文件数')} ${usage?.filesCount ?? 0}', style: TextStyle(color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _bar(String label, int used, int total) {
    final value = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text('${formatCloudBytes(used)} / ${total > 0 ? formatCloudBytes(total) : '∞'}'),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(value: value, minHeight: 6),
        ),
      ],
    );
  }
}

class _FriendPickerDialog extends StatefulWidget {
  const _FriendPickerDialog({required this.social});
  final SocialController social;

  @override
  State<_FriendPickerDialog> createState() => _FriendPickerDialogState();
}

class _FriendPickerDialogState extends State<_FriendPickerDialog> {
  late Future<List<SocialConversation>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.social.repository.conversations();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('发送给好友')),
    content: SizedBox(
      width: 360,
      height: 320,
      child: FutureBuilder<List<SocialConversation>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data ?? const <SocialConversation>[];
          if (rows.isEmpty) {
            return Center(child: Text(tr('还没有可以发消息的好友。')));
          }
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: Text(row.peer?.displayName ?? tr('用户')),
                onTap: () => Navigator.of(context).pop(row.peerId),
              );
            },
          );
        },
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('取消'))),
    ],
  );
}

class _ShareDialog extends StatefulWidget {
  const _ShareDialog({required this.file});
  final CloudFile file;

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  String mode = 'app';
  int days = 7;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${tr('分享')} ${widget.file.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('分享方式')),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'app', label: Text(tr('应用内（流量减半）'))),
              ButtonSegment(value: 'direct', label: Text(tr('直链（免登录）'))),
            ],
            selected: {mode},
            onSelectionChanged: (value) => setState(() => mode = value.first),
          ),
          const SizedBox(height: NekoSpace.md),
          Text(tr('有效期')),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1 天')),
              ButtonSegment(value: 7, label: Text('7 天')),
              ButtonSegment(value: 30, label: Text('30 天')),
            ],
            selected: {days},
            onSelectionChanged: (value) => setState(() => days = value.first),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('取消'))),
        FilledButton(
          onPressed: () => Navigator.pop(context, (mode: mode, days: days)),
          child: Text(tr('生成链接')),
        ),
      ],
    );
  }
}

class _ReceiptDialog extends StatefulWidget {
  const _ReceiptDialog({required this.orderId, required this.client, required this.onUploaded});
  final String orderId;
  final CloudFilesClient client;
  final VoidCallback onUploaded;

  @override
  State<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<_ReceiptDialog> {
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('上传支付凭证')),
      content: Text(tr('支付后把截图传上来，核对通过会立即开通，通常几分钟到几小时。')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('稍后'))),
        FilledButton(
          onPressed: busy ? null : _pick,
          child: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tr('选择截图')),
        ),
      ],
    );
  }

  Future<void> _pick() async {
    final picked = await openFile(acceptedTypeGroups: [XTypeGroup(label: tr('图片'), extensions: const ['png', 'jpg', 'jpeg'])]);
    if (picked == null) return;
    setState(() => busy = true);
    try {
      final bytes = await File(picked.path).readAsBytes();
      await widget.client.uploadReceipt(widget.orderId, bytes, 'image/png');
      widget.onUploaded();
      if (mounted) Navigator.pop(context);
    } on CloudException catch (error) {
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _SklandGate extends StatelessWidget {
  const _SklandGate({required this.onBound, required this.client});
  final Future<void> Function() onBound;
  final CloudFilesClient client;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NekoSpace.xl),
      child: Column(
        children: [
          const Icon(Icons.shield_outlined, size: 40),
          const SizedBox(height: NekoSpace.md),
          Text(tr('云存储需要绑定森空岛账号'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: NekoSpace.sm),
          Text(
            tr('绑定后用于确认账号归属，不会读取你的游戏数据。'),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: NekoSpace.lg),
          FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => _SklandBindDialog(client: client, onBound: onBound),
            ),
            child: Text(tr('去绑定')),
          ),
        ],
      ),
    );
  }
}

class _SklandBindDialog extends StatefulWidget {
  const _SklandBindDialog({required this.client, required this.onBound});
  final CloudFilesClient client;
  final Future<void> Function() onBound;

  @override
  State<_SklandBindDialog> createState() => _SklandBindDialogState();
}

class _SklandBindDialogState extends State<_SklandBindDialog> {
  SklandTicket? ticket;
  String state = 'loading';
  String message = '';
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final value = await widget.client.sklandStart();
      if (!mounted) return;
      setState(() {
        ticket = value;
        state = 'waiting';
      });
      timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    } on CloudException catch (error) {
      if (!mounted) return;
      setState(() {
        state = 'error';
        message = error.message;
      });
    }
  }

  Future<void> _poll() async {
    final value = ticket;
    if (value == null) return;
    try {
      final next = await widget.client.sklandPoll(value.sid);
      if (!mounted) return;
      setState(() => state = next);
      if (next == 'ok') {
        timer?.cancel();
        await widget.onBound();
        if (mounted) Navigator.pop(context);
      } else if (next == 'expired' || next == 'login_required') {
        timer?.cancel();
      }
    } on CloudException catch (error) {
      if (!mounted) return;
      setState(() => message = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      'scanned' => tr('已扫码，请在手机上确认'),
      'expired' => tr('二维码已失效，请重新打开'),
      'login_required' => tr('请先登录 NekoPlayer 账号'),
      'ok' => tr('绑定成功'),
      'error' => message.isEmpty ? tr('森空岛暂时不可用') : message,
      _ => tr('打开森空岛 App 扫码'),
    };
    return AlertDialog(
      title: Text(tr('绑定森空岛')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ticket != null)
            QrImageView(data: ticket!.url, size: 200, backgroundColor: Colors.white)
          else
            const SizedBox(width: 200, height: 200, child: Center(child: CircularProgressIndicator())),
          const SizedBox(height: NekoSpace.md),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('关闭'))),
      ],
    );
  }
}
