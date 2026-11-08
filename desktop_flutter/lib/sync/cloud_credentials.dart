import '../i18n/tr.dart';
import '../data/account_store.dart';

/// 云端 credentials 分区与本机账号之间的转换。
class CloudCredentials {
  const CloudCredentials({
    this.netease,
    this.kugou = const [null, null],
    this.platform,
    this.notes = const [],
  });

  /// null 表示云端没有可用的该平台登录，本机对应登录保持不变。
  final Map<String, String>? netease;
  final List<Map<String, String>?> kugou;
  final int? platform;
  final List<String> notes;

  bool get isEmpty =>
      netease == null && kugou.every((session) => session == null);

  factory CloudCredentials.parse(Map<String, dynamic> remote) {
    final notes = <String>[];
    Map<String, String>? parse(
      Object? raw,
      String name,
      bool Function(String) accept,
      String required,
    ) {
      if (raw == null || raw == '') return null;
      if (raw is! String) {
        notes.add(tr('{name}：云端 Cookie 格式异常，已跳过。', {'name': name}));
        return null;
      }
      final parsed = AccountStore.parseLenientCookies(raw, accept: accept);
      if ((parsed.values[required] ?? '').isEmpty) {
        notes.add(tr('{name}：云端 Cookie 中没有有效的 {field}，已跳过。', {
          'name': name,
          'field': required,
        }));
        return null;
      }
      if (parsed.skipped > 0) {
        notes.add(tr('{name}：已忽略 {count} 个不兼容字段。', {
          'name': name,
          'count': parsed.skipped,
        }));
      }
      return parsed.values;
    }

    final platform = remote['kgPlatform'] == 1 ? 1 : 0;
    final cookies = remote['kgCookies'];
    if (cookies != null && cookies is! List) {
      notes.add(tr('酷狗：云端账号槽位格式异常，已跳过。'));
    }
    final legacy = remote['kgToken'] is String
        ? (remote['kgToken'] as String).trim()
        : '';
    final kugou = <Map<String, String>?>[];
    for (var slot = 0; slot < 2; slot++) {
      final label = slot == 0 ? tr('酷狗原版') : tr('酷狗概念版');
      var raw = cookies is List && slot < cookies.length ? cookies[slot] : null;
      if ((raw == null || raw == '') && slot == platform && legacy.isNotEmpty) {
        raw = 'token=$legacy';
      }
      kugou.add(parse(raw, label, AccountStore.acceptKugouKey, 'token'));
    }
    final netease = parse(
      remote['ncCookie'],
      tr('网易云'),
      AccountStore.acceptNeteaseKey,
      'MUSIC_U',
    );
    final hasKugou = kugou.any((session) => session != null);
    return CloudCredentials(
      netease: netease,
      kugou: kugou,
      platform: hasKugou
          ? (kugou[platform] != null
                ? platform
                : kugou[0] != null
                ? 0
                : 1)
          : null,
      notes: notes,
    );
  }

  static String cookie(Map<String, String> values) =>
      values.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');

  static int localCount(AccountStore accounts) =>
      (accounts.neteaseLoggedIn ? 1 : 0) +
      [
        for (var slot = 0; slot < 2; slot++)
          if ((accounts.kugou(slot)['token'] ?? '').isNotEmpty) slot,
      ].length;

  /// 登录状态指纹：只含决定登录身份的字段，匿名会话与设备标识的变化不算修改。
  static String identity(AccountStore accounts) => [
    accounts.netease['MUSIC_U'] ?? '',
    for (var slot = 0; slot < 2; slot++)
      '${accounts.kugou(slot)['token'] ?? ''}|${accounts.kugou(slot)['userid'] ?? ''}',
    accounts.platform,
  ].join('\n');

  /// 上传内容。[remote] 非 null 时，本机没有登录的平台沿用云端内容（合并）。
  static Map<String, Object>? payload(
    AccountStore accounts, {
    Map<String, dynamic>? remote,
  }) {
    if (localCount(accounts) == 0 && remote == null) return null;
    final remoteCookies = remote?['kgCookies'] is List
        ? remote!['kgCookies'] as List
        : const [];
    String text(Object? value) => value is String ? value : '';
    final token = accounts.kugou()['token'] ?? '';
    return {
      'ncCookie': accounts.neteaseLoggedIn
          ? cookie(accounts.netease)
          : text(remote?['ncCookie']),
      'kgCookies': [
        for (var slot = 0; slot < 2; slot++)
          (accounts.kugou(slot)['token'] ?? '').isNotEmpty
              ? cookie(accounts.kugou(slot))
              : text(slot < remoteCookies.length ? remoteCookies[slot] : null),
      ],
      'kgPlatform': accounts.platform,
      'kgToken': token.isNotEmpty ? token : text(remote?['kgToken']),
    };
  }
}
