import '../i18n/tr.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/account_store.dart';
import '../data/native_music_catalog.dart';
import '../domain/online_music.dart';
import 'kugou_account_page.dart';
import 'neko_theme.dart';
import 'widgets/settings_list.dart';

class AccountsPanel extends StatefulWidget {
  const AccountsPanel({super.key, required this.catalog});
  final NativeMusicCatalog catalog;

  @override
  State<AccountsPanel> createState() => _AccountsPanelState();
}

class _AccountsPanelState extends State<AccountsPanel> {
  bool busy = false;
  String? message;
  LoginQr? qr;
  int generation = 0;
  AccountStore get accounts => widget.catalog.accounts;

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  Future<void> action(Future<void> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await work();
    } catch (failure) {
      if (mounted) {
        setState(() {
          message = failure is MusicSearchException
              ? failure.message
              : failure is FormatException
              ? failure.message
              : tr('账号操作失败，请检查系统密钥环、网络与凭据格式。');
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> login(MusicProvider provider) async {
    final request = ++generation;
    await action(() async {
      final created = await widget.catalog.createLoginQr(provider);
      if (!mounted || request != generation) return;
      setState(() {
        qr = created;
        message = provider == MusicProvider.kugou && created.platform == 1
            ? tr('请使用{provider}概念版手机客户端扫码。', {
                'provider': provider.label,
              })
            : tr('请使用{provider}手机客户端扫码。', {
                'provider': provider.label,
              });
      });
    });
    if (!mounted || request != generation || qr == null) return;
    final active = qr!;
    final expires = DateTime.now().add(const Duration(minutes: 3));
    while (mounted &&
        request == generation &&
        DateTime.now().isBefore(expires)) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted || request != generation) return;
      try {
        final result = await widget.catalog.checkLoginQr(
          active,
          accept: () => mounted && request == generation,
        );
        if (!mounted || request != generation) return;
        setState(() {
          message = switch (result) {
            LoginProgress.waiting => tr('等待扫码…'),
            LoginProgress.scanned => tr('已扫码，请在手机上确认。'),
            LoginProgress.expired => tr('二维码已过期，请重新生成。'),
            LoginProgress.authorized => tr('登录成功，凭据已存入系统密钥环。'),
          };
          if (result == LoginProgress.expired ||
              result == LoginProgress.authorized) {
            qr = null;
          }
        });
        if (qr == null) return;
      } catch (failure) {
        if (mounted && request == generation) {
          setState(() {
            message = failure is MusicSearchException
                ? failure.message
                : tr('扫码检查失败，请重新生成二维码。');
            qr = null;
          });
        }
        return;
      }
    }
    if (mounted && request == generation) {
      setState(() {
        qr = null;
        message = tr('二维码已过期，请重新生成。');
      });
    }
  }

  Future<void> importCookie(MusicProvider provider) async {
    generation++;
    setState(() => qr = null);
    final input = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('导入{provider} Cookie', {'provider': provider.label})),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                    Text(tr('仅导入你自己的账号凭据。凭据保存在系统密钥环，不上传至本站。')),
              const SizedBox(height: 12),
              TextField(
                controller: input,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Cookie',
                  hintText: 'name=value; name=value',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:       Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child:       Text(tr('导入')),
          ),
        ],
      ),
    );
    input.dispose();
    if (!mounted || value == null) return;
    await action(() async {
      final cookies = AccountStore.parseCookies(value);
      if (provider == MusicProvider.netease) {
        if ((cookies['MUSIC_U'] ?? '').isEmpty) {
          throw       FormatException(tr('缺少 MUSIC_U 登录凭据。'));
        }
        await accounts.update(
          netease: {'deviceId': accounts.neteaseDevice, ...cookies},
          replace: true,
        );
      } else {
        if ((cookies['token'] ?? '').isEmpty ||
            (int.tryParse(cookies['userid'] ?? '') ?? 0) <= 0) {
          throw       FormatException(tr('缺少有效的 token 或 userid。'));
        }
        final device = {
          for (final entry in accounts.kugou().entries)
            if (entry.key.startsWith('KUGOU_API_') || entry.key == 'dfid')
              entry.key: entry.value,
        };
        await accounts.update(kugou: {...device, ...cookies}, replace: true);
      }
      if (mounted) setState(() => message = tr('凭据已导入；实际播放权限由音乐平台验证。'));
    });
  }

  Future<void> logout(MusicProvider provider) async {
    generation++;
    setState(() => qr = null);
    await action(() async {
      if (provider == MusicProvider.netease) {
        await accounts.update(
          netease: {'deviceId': accounts.neteaseDevice},
          replace: true,
        );
      } else {
        await accounts.update(
          kugou: {
            for (final entry in accounts.kugou().entries)
              if (entry.key.startsWith('KUGOU_API_') || entry.key == 'dfid')
                entry.key: entry.value,
          },
          replace: true,
        );
      }
      if (mounted) setState(() => message = tr('已清除本机登录凭据。'));
    });
  }

  Future<void> neteaseInfo() => action(() async {
    final original = accounts.netease['MUSIC_U'];
    if (!accounts.neteaseLoggedIn) {
      throw       MusicSearchException(tr('请先登录网易云账号。'));
    }
    final response = await widget.catalog.neteaseApi(
      '/api/nuser/account/get',
      {},
      weapi: true,
    );
    if (response['code'] != 200 || response['account'] is! Map) {
      throw       MusicSearchException(tr('网易云未确认账号有效，请重新登录。'));
    }
    if (!mounted || accounts.netease['MUSIC_U'] != original) return;
    final profile = response['profile'] is Map
        ? response['profile'] as Map
        : const {};
    final account = response['account'] as Map;
    accounts.setNickname(netease: profile['nickname']?.toString());
    setState(
      () => message = tr(
        '{nickname} · ID {id} · 会员类型 {vip}。实际可播音质由平台验证。',
        {
          'nickname': profile['nickname'] ?? tr('网易云用户'),
          'id': account['id'] ?? profile['userId'] ?? tr('未知'),
          'vip': profile['vipType'] ?? 0,
        },
      ),
    );
  });

  (bool, String) _status(MusicProvider provider) {
    if (provider == MusicProvider.netease) {
      final name = accounts.neteaseNickname;
      return accounts.neteaseLoggedIn
          ? (true, name == null ? tr('已登录') : tr('已登录 · {name}', {'name': name}))
          : (false, tr('未登录'));
    }
    final name = accounts.kugouNicknames[accounts.platform];
    if (accounts.kugouLoggedIn()) {
      return (true, name == null ? tr('已登录') : tr('已登录 · {name}', {'name': name}));
    }
    if (accounts.kugouTokenOnly()) {
      return (false, tr('凭据不完整：缺少 userid，可以播放，但账号功能不可用，请重新登录'));
    }
    return (false, tr('未登录'));
  }

  void _switchPlatform(int platform) {
    generation++;
    setState(() => qr = null);
    unawaited(action(() => accounts.update(platform: platform)));
  }

  Widget _provider(BuildContext context, MusicProvider provider) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final (signedIn, status) = _status(provider);
    final enabled = !busy && accounts.readable;
    final kugou = provider == MusicProvider.kugou;
    final activeQr = qr?.provider == provider ? qr : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(NekoSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: signedIn
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  foregroundColor: signedIn
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                  child: Text(
                    kugou ? tr('酷') : tr('网'),
                    style: text.titleSmall?.copyWith(color: null),
                  ),
                ),
                const SizedBox(width: NekoSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(provider.label, style: text.titleMedium),
                      Text(
                        status,
                        style: text.bodySmall?.copyWith(
                          color: signedIn ? colors.tertiary : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (kugou)
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments:       [
                      ButtonSegment(value: 0, label: Text(tr('原版'))),
                      ButtonSegment(value: 1, label: Text(tr('概念版'))),
                    ],
                    selected: {accounts.platform},
                    onSelectionChanged: busy
                        ? null
                        : (value) => _switchPlatform(value.single),
                  ),
              ],
            ),
            const SizedBox(height: NekoSpace.lg),
            Wrap(
              spacing: NekoSpace.sm,
              runSpacing: NekoSpace.sm,
              children: [
                (signedIn ? OutlinedButton.icon : FilledButton.icon)(
                  onPressed: enabled ? () => unawaited(login(provider)) : null,
                  icon: const Icon(Icons.qr_code_rounded, size: 18),
                  label: Text(signedIn ? tr('重新扫码登录') : tr('扫码登录')),
                ),
                TextButton(
                  onPressed: enabled
                      ? () => unawaited(importCookie(provider))
                      : null,
                  child:       Text(tr('导入 Cookie')),
                ),
                if (kugou)
                  TextButton(
                    onPressed: enabled
                        ? () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  KugouAccountPage(catalog: widget.catalog),
                            ),
                          )
                        : null,
                    child:       Text(tr('短信登录与权益')),
                  )
                else if (signedIn)
                  TextButton(
                    onPressed: busy ? null : neteaseInfo,
                    child:       Text(tr('验证账号与会员')),
                  ),
                if (signedIn || (kugou && accounts.kugouTokenOnly()))
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: colors.error),
                    onPressed: enabled
                        ? () => unawaited(logout(provider))
                        : null,
                    child:       Text(tr('退出')),
                  ),
              ],
            ),
            if (activeQr != null) ...[
              const SizedBox(height: NekoSpace.lg),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(NekoRadius.card),
                    child: ColoredBox(
                      color: Colors.white,
                      child: QrImageView(
                        data: activeQr.uri.toString(),
                        size: 184,
                        padding: const EdgeInsets.all(NekoSpace.md),
                      ),
                    ),
                  ),
                  const SizedBox(width: NekoSpace.xl),
                  Expanded(child: Text(message ?? '', style: text.bodyMedium)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: accounts,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!accounts.readable) ...[
                InlineNotice(
            tr('系统凭据库不可用或数据损坏。原数据已保护，暂不保存账号；Linux 请先解锁系统密钥环。'),
            error: true,
          ),
          const SizedBox(height: NekoSpace.lg),
        ],
        _provider(context, MusicProvider.netease),
        const SizedBox(height: NekoSpace.lg),
        _provider(context, MusicProvider.kugou),
        const SizedBox(height: NekoSpace.lg),
        if (busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: NekoSpace.md),
        ],
        if (message != null && qr == null) ...[
          InlineNotice(message!),
          const SizedBox(height: NekoSpace.md),
        ],
        Text(
          tr('账号只保存在本机的系统密钥环中；酷狗原版与概念版的登录相互独立。') + tr('如需在其他设备使用，可以在“账号与云端同步”中同步平台登录。'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}
