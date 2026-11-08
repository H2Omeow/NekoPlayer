import 'dart:async';

import 'package:flutter/material.dart';

import '../data/native_music_catalog.dart';
import '../domain/online_music.dart';
import 'neko_theme.dart';
import 'widgets/page_layout.dart';
import 'widgets/settings_list.dart';

class KugouAccountPage extends StatefulWidget {
  const KugouAccountPage({super.key, required this.catalog});
  final NativeMusicCatalog catalog;
  @override
  State<KugouAccountPage> createState() => _KugouAccountPageState();
}

class _KugouAccountPageState extends State<KugouAccountPage> {
  final phone = TextEditingController();
  final code = TextEditingController();
  bool busy = false;
  String? message;
  String? nickname;
  String? vip;
  List<KugouLoginChoice> choices = [];
  DateTime? sentAt;
  Timer? timer;
  int generation = 0;
  late int platform;
  late String? token;

  @override
  void initState() {
    super.initState();
    platform = widget.catalog.accounts.platform;
    token = widget.catalog.accounts.kugou()['token'];
    widget.catalog.accounts.addListener(accountChanged);
  }

  void accountChanged() {
    final accounts = widget.catalog.accounts;
    if (platform == accounts.platform && token == accounts.kugou()['token']) {
      return;
    }
    generation++;
    platform = accounts.platform;
    token = accounts.kugou()['token'];
    if (mounted) {
      setState(() {
        nickname = null;
        vip = null;
        choices = [];
      });
    }
  }

  Future<void> action(Future<void> Function(int request) work) async {
    if (busy) return;
    final request = ++generation;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await work(request);
    } catch (failure) {
      if (mounted && request == generation) {
        setState(() {
          if (failure is KugouAccountSelection) {
            choices = failure.accounts;
            message = '该手机号关联多个账号，请选择要登录的账号。';
          } else {
            message = failure is MusicSearchException
                ? failure.message
                : '账号操作失败，请检查网络、设备验证和系统密钥环。';
          }
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> send() => action((request) async {
    await widget.catalog.sendKugouCode(phone.text.trim());
    if (!mounted || request != generation) return;
    setState(() {
      sentAt = DateTime.now();
      message = '平台已确认验证码发送，请检查短信。';
    });
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
      if (remaining == 0) timer?.cancel();
    });
  });

  int get remaining => sentAt == null
      ? 0
      : (60 - DateTime.now().difference(sentAt!).inSeconds).clamp(0, 60);

  Future<void> login([String? userId]) => action((request) async {
    await widget.catalog.loginKugouMobile(
      phone.text.trim(),
      code.text.trim(),
      userId: userId,
      accept: () => mounted && request == generation,
    );
    if (mounted) {
      setState(() {
        choices = [];
        code.clear();
        message = '已保存平台确认的登录凭据。';
      });
    }
  });

  Future<void> info() => action((request) async {
    final user = await widget.catalog.kugouAccountInfo();
    final membership = await widget.catalog.kugouAccountInfo(vip: true);
    if (!mounted || request != generation) return;
    final rawEnd =
        int.tryParse(
          '${membership['end_time'] ?? membership['vip_end_time'] ?? 0}',
        ) ??
        0;
    String expiry = '未提供有效期';
    if (rawEnd > 0 && rawEnd < 9999999999999) {
      final end = DateTime.fromMillisecondsSinceEpoch(
        rawEnd > 100000000000 ? rawEnd : rawEnd * 1000,
      ).toLocal();
      expiry =
          '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';
    }
    setState(() {
      nickname =
          '${user['nickname'] ?? user['nick_name'] ?? user['username'] ?? '酷狗用户'}';
      vip =
          '会员类型 ${membership['vip_type'] ?? membership['vip_level'] ?? 0} · $expiry';
      message = '账号信息已更新；可播音质仍由播放接口验证。';
    });
  });

  Future<void> claim() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('领取概念版听歌权益？'),
        content: const Text('将使用当前概念版账号向官方接口发送一次领取请求。不会自动重复领取，也不保证账号满足领取条件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认领取'),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true) return;
    await action((request) async {
      await widget.catalog.claimKugouDailyVip();
      if (mounted && request == generation) {
        setState(() => message = '平台已确认领取请求成功；具体权益请在官方客户端检查。');
      }
    });
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    widget.catalog.accounts.removeListener(accountChanged);
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = widget.catalog.accounts.kugouLoggedIn();
    return DetailPage(
      title: platform == 0 ? '酷狗账号 · 原版' : '酷狗账号 · 概念版',
      children: [
        SettingsSection(
          title: '短信登录',
          description: '只有点击发送时才会联系官方短信接口，不会自动发送或重试；发送需要通过平台设备验证。',
          children: [
            Padding(
              padding: const EdgeInsets.all(NekoSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: phone,
                          enabled: !busy,
                          keyboardType: TextInputType.phone,
                          maxLength: 11,
                          onChanged: (_) => setState(() => choices = []),
                          decoration: const InputDecoration(
                            hintText: '大陆手机号',
                            prefixIcon: Icon(Icons.phone_iphone_rounded),
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: NekoSpace.sm),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: busy || remaining > 0 ? null : send,
                          child: Text(
                            remaining > 0 ? '$remaining 秒后重发' : '发送验证码',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: NekoSpace.md),
                  TextField(
                    controller: code,
                    enabled: !busy,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    onSubmitted: busy ? null : (_) => login(),
                    decoration: const InputDecoration(
                      hintText: '短信验证码',
                      prefixIcon: Icon(Icons.password_rounded),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: NekoSpace.lg),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed: busy ? null : login,
                      child: const Text('登录'),
                    ),
                  ),
                ],
              ),
            ),
            for (final choice in choices)
              SettingsTile(
                icon: Icons.account_circle_outlined,
                title: choice.name.isEmpty ? '账号 ${choice.id}' : choice.name,
                subtitle: 'ID ${choice.id}',
                onTap: busy ? null : () => login(choice.id),
              ),
          ],
        ),
        SettingsSection(
          title: '账号与权益',
          description: loggedIn ? null : '登录后可用。',
          children: [
            SettingsTile(
              icon: Icons.workspace_premium_outlined,
              title: '读取账号与会员状态',
              subtitle: nickname == null ? null : '$nickname · $vip',
              enabled: !busy && loggedIn,
              onTap: info,
            ),
            SettingsTile(
              icon: Icons.refresh_rounded,
              title: '刷新登录凭据',
              enabled: !busy && loggedIn,
              onTap: () => action((request) async {
                await widget.catalog.refreshKugouToken(
                  accept: () => mounted && request == generation,
                );
                if (mounted) {
                  setState(() => message = '登录凭据已通过平台确认并刷新。');
                }
              }),
            ),
            if (platform == 1)
              SettingsTile(
                icon: Icons.redeem_rounded,
                title: '领取每日听歌权益',
                subtitle: '手动领取，不会自动执行',
                enabled: !busy && loggedIn,
                onTap: claim,
              ),
          ],
        ),
        if (busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: NekoSpace.lg),
        ],
        if (message case final value?) InlineNotice(value),
      ],
    );
  }
}
