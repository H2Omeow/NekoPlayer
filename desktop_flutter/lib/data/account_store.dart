import '../i18n/tr.dart';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class CredentialStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class SecureCredentialStorage implements CredentialStorage {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const key = 'nekoplayer.flutter.accounts.v1';

  @override
  Future<String?> read() => _storage.read(key: key);
  @override
  Future<void> write(String value) => _storage.write(key: key, value: value);
}

class AccountStore extends ChangeNotifier {
  AccountStore({this.storage});

  final CredentialStorage? storage;
  Map<String, String> _netease = {};
  List<Map<String, String>> _kugou = [{}, {}];
  int _platform = 0;
  String _siteToken = '';
  String get siteToken => _siteToken;
  bool readable = true;
  Future<void> _writes = Future.value();

  int get platform => _platform;
  Map<String, String> get netease => Map.unmodifiable(_netease);
  Map<String, String> kugou([int? platform]) =>
      Map.unmodifiable(_kugou[platform ?? _platform]);
  bool get neteaseLoggedIn => (_netease['MUSIC_U'] ?? '').isNotEmpty;
  bool kugouLoggedIn([int? platform]) {
    final session = kugou(platform);
    return (session['token'] ?? '').isNotEmpty &&
        (int.tryParse(session['userid'] ?? '') ?? 0) > 0;
  }

  // 只有 token、没有 userid：能播放，但账号信息等接口不可用。
  bool kugouTokenOnly([int? platform]) {
    final session = kugou(platform);
    return (session['token'] ?? '').isNotEmpty && !kugouLoggedIn(platform);
  }

  // 校验账号后得到的昵称，仅保存在内存中，凭据变化时清除。
  String? neteaseNickname;
  final List<String?> kugouNicknames = [null, null];

  void setNickname({String? netease, int? kugouSlot, String? kugou}) {
    if (netease != null) neteaseNickname = netease;
    if (kugouSlot != null) kugouNicknames[kugouSlot] = kugou;
    notifyListeners();
  }

  static String randomHex(int bytes) {
    final random = Random.secure();
    return List.generate(
      bytes,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  String get neteaseDevice =>
      _netease.putIfAbsent('deviceId', () => randomHex(26).toUpperCase());

  void ensureDevice([int? selected]) {
    final session = _kugou[selected ?? _platform];
    final guid = session.putIfAbsent('KUGOU_API_GUID', () => randomHex(16));
    session.putIfAbsent(
      'KUGOU_API_MID',
      () => BigInt.parse(
        md5.convert(utf8.encode(guid)).toString(),
        radix: 16,
      ).toString(),
    );
    session.putIfAbsent('KUGOU_API_DEV', () => randomHex(16).toUpperCase());
    session.putIfAbsent('KUGOU_API_MAC', () => '02:00:00:00:00:00');
  }

  Future<void> initialize() async {
    try {
      final encoded = await storage?.read();
      if (encoded != null) {
        final body = jsonDecode(encoded) as Map<String, dynamic>;
        if (body['version'] != 1) {
          throw const FormatException('Unknown account format');
        }
        final netease = Map<String, String>.from(body['netease'] as Map);
        final kugou = (body['kugou'] as List)
            .map((value) => Map<String, String>.from(value as Map))
            .toList();
        final platform = body['platform'] as int;
        final siteToken = body['siteToken'] as String? ?? '';
        validateSiteToken(siteToken, allowEmpty: true);
        if (kugou.length != 2 || platform < 0 || platform > 1) {
          throw const FormatException('Invalid account slots');
        }
        _validate(netease);
        for (final session in kugou) {
          _validate(session);
        }
        _netease = netease;
        _kugou = kugou;
        _platform = platform;
        _siteToken = siteToken;
      }
    } catch (_) {
      readable = false;
    }
    ensureDevice(0);
    ensureDevice(1);
  }

  static Map<String, String> parseCookies(String raw) {
    if (raw.length > 16384 || raw.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw       FormatException(tr('Cookie 必须为单行文本且不超过 16KB。'));
    }
    final result = <String, String>{};
    for (final part
        in raw
            .replaceFirst(RegExp(r'^Cookie:\s*', caseSensitive: false), '')
            .split(';')) {
      if (part.trim().isEmpty) continue;
      final separator = part.indexOf('=');
      if (separator <= 0) throw       FormatException(tr('Cookie 格式无效。'));
      final name = part.substring(0, separator).trim();
      if (result.containsKey(name)) {
        throw       FormatException(tr('Cookie 包含重复字段。'));
      }
      result[name] = part.substring(separator + 1).trim();
    }
    _validate(result);
    return result;
  }

  static const neteaseCloudKeys = {
    'MUSIC_U',
    'MUSIC_A',
    'MUSIC_R_T',
    'MUSIC_A_T',
    '__csrf',
    '__remember_me',
    'deviceId',
    'sDeviceId',
    'os',
    'osver',
    'appver',
    'buildver',
    'channel',
    'mobilename',
    'resolution',
    'NMTID',
    'WEVNSM',
    'WNMCID',
    '_ntes_nuid',
    '_ntes_nnid',
    'NTES_P_UTID',
    'WM_TID',
    'ntes_utid',
  };
  static const kugouCloudKeys = {
    'token',
    'userid',
    'vip_type',
    'vip_token',
    't1',
    'dfid',
    'mid',
  };

  static bool acceptNeteaseKey(String key) => neteaseCloudKeys.contains(key);
  static bool acceptKugouKey(String key) =>
      kugouCloudKeys.contains(key) || key.startsWith('KUGOU_API_');

  /// 云端 Cookie 的宽松解析：跳过无效、重复之外的字段与不在白名单中的字段，
  /// 而不是整体拒绝；其他端写入的 JSESSIONID-WYYY 之类字段不应影响登录。
  static ({Map<String, String> values, int skipped}) parseLenientCookies(
    String raw, {
    required bool Function(String key) accept,
  }) {
    final values = <String, String>{};
    var skipped = 0;
    if (raw.length > 65536) return (values: values, skipped: 1);
    for (final part
        in raw
            .replaceFirst(RegExp(r'^Cookie:\s*', caseSensitive: false), '')
            .split(RegExp(r'[;\r\n]'))) {
      if (part.trim().isEmpty) continue;
      final separator = part.indexOf('=');
      final name = separator <= 0 ? '' : part.substring(0, separator).trim();
      final value = separator <= 0 ? '' : part.substring(separator + 1).trim();
      if (name.isEmpty ||
          !accept(name) ||
          !RegExp(r'^[A-Za-z0-9_]+$').hasMatch(name) ||
          value.contains(RegExp(r'[\x00-\x20\x7f-\uffff]')) ||
          (['MUSIC_U', 'token'].contains(name) &&
              ['', 'null', 'undefined'].contains(value))) {
        skipped++;
        continue;
      }
      values[name] = value;
    }
    return (values: values, skipped: skipped);
  }

  static void validateSiteToken(String token, {bool allowEmpty = false}) {
    if (allowEmpty && token.isEmpty) return;
    if (token.length < 16 ||
        token.length > 16384 ||
        token.contains(RegExp(r'[^\x21-\x7e]'))) {
      throw       FormatException(tr('本站令牌格式无效。'));
    }
  }

  static void _validate(Map<String, String> values) {
    for (final entry in values.entries) {
      if (['MUSIC_U', 'token'].contains(entry.key) &&
          ['null', 'undefined'].contains(entry.value)) {
        throw       FormatException(tr('登录凭据无效。'));
      }
      if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(entry.key) ||
          entry.value.contains(RegExp(r'[;\x00-\x20\x7f-\uffff]'))) {
        throw       FormatException(tr('Cookie 包含无效字符。'));
      }
    }
  }

  Future<void> update({
    Map<String, String>? netease,
    Map<String, String>? kugou,
    int? platform,
    bool replace = false,
    bool selectPlatform = true,
    String? siteToken,
    String? expectedSiteToken,
  }) {
    final command = _writes.then((_) async {
      if (!readable) throw StateError(tr('系统凭据库不可用或原数据损坏；为保护账号，未覆盖原数据。'));
      if (expectedSiteToken != null && expectedSiteToken != _siteToken) {
        throw       FormatException(tr('本站账号已切换，已取消旧账号操作。'));
      }
      if (platform != null && (platform < 0 || platform > 1)) {
        throw const FormatException('Invalid platform');
      }
      if (netease != null) _validate(netease);
      if (kugou != null) _validate(kugou);
      if (siteToken != null) validateSiteToken(siteToken, allowEmpty: true);
      final nextNetease = netease == null
          ? _netease
          : {if (!replace) ..._netease, ...netease};
      final nextKugou = [
        for (final session in _kugou) Map<String, String>.of(session),
      ];
      final selected = platform ?? _platform;
      if (kugou != null) {
        nextKugou[selected] = {if (!replace) ...nextKugou[selected], ...kugou};
      }
      await _commit(
        nextNetease,
        nextKugou,
        selectPlatform ? selected : _platform,
        siteToken ?? _siteToken,
      );
    });
    _writes = command.catchError((Object _) {});
    return command;
  }

  Future<void> importMissingSessions({
    required Map<String, String> netease,
    required List<Map<String, String>> kugou,
    required int preferredPlatform,
    required String expectedSiteToken,
  }) {
    final incomingNetease = Map<String, String>.of(netease);
    final incomingKugou = [
      for (final session in kugou) Map<String, String>.of(session),
    ];
    final command = _writes.then((_) async {
      if (!readable) throw StateError(tr('系统凭据库不可用或原数据损坏；为保护账号，未覆盖原数据。'));
      if (expectedSiteToken != _siteToken) {
        throw       FormatException(tr('本站账号已切换，已取消旧账号操作。'));
      }
      if (incomingKugou.length != 2 ||
          preferredPlatform < 0 ||
          preferredPlatform > 1) {
        throw       FormatException(tr('云端账号平台无效。'));
      }
      _validate(incomingNetease);
      for (final session in incomingKugou) {
        _validate(session);
      }
      final hasLocalKugou = [
        for (var platform = 0; platform < 2; platform++)
          kugouLoggedIn(platform),
      ].any((complete) => complete);
      final nextNetease = neteaseLoggedIn
          ? _netease
          : {..._netease, ...incomingNetease};
      final nextKugou = [
        for (var platform = 0; platform < 2; platform++)
          {
            ..._kugou[platform],
            if (!kugouLoggedIn(platform)) ...incomingKugou[platform],
          },
      ];
      await _commit(
        nextNetease,
        nextKugou,
        hasLocalKugou ? _platform : preferredPlatform,
        _siteToken,
      );
    });
    _writes = command.catchError((Object _) {});
    return command;
  }

  /// 用云端登录替换本机对应平台的登录；为 null 的平台保持不变。
  Future<void> replaceSessions({
    Map<String, String>? netease,
    List<Map<String, String>?>? kugou,
    int? platform,
    required String expectedSiteToken,
  }) {
    final incomingNetease = netease == null ? null : Map.of(netease);
    final incomingKugou = kugou == null
        ? null
        : [for (final item in kugou) item == null ? null : Map.of(item)];
    final command = _writes.then((_) async {
      if (!readable) throw StateError(tr('系统凭据库不可用或原数据损坏；为保护账号，未覆盖原数据。'));
      if (expectedSiteToken != _siteToken) {
        throw       FormatException(tr('本站账号已切换，已取消旧账号操作。'));
      }
      if ((incomingKugou != null && incomingKugou.length != 2) ||
          (platform != null && (platform < 0 || platform > 1))) {
        throw       FormatException(tr('云端账号平台无效。'));
      }
      if (incomingNetease != null) _validate(incomingNetease);
      for (final session in incomingKugou ?? const <Map<String, String>?>[]) {
        if (session != null) _validate(session);
      }
      final nextNetease = incomingNetease == null
          ? _netease
          : {
              if (_netease['deviceId'] != null)
                'deviceId': _netease['deviceId']!,
              ...incomingNetease,
            };
      final nextKugou = [
        for (var slot = 0; slot < 2; slot++)
          incomingKugou?[slot] == null
              ? _kugou[slot]
              : {
                  // 云端没有设备标识时沿用本机的，避免与 dfid 脱节。
                  if (!incomingKugou![slot]!.containsKey('KUGOU_API_GUID'))
                    for (final entry in _kugou[slot].entries)
                      if (entry.key.startsWith('KUGOU_API_') ||
                          entry.key == 'dfid')
                        entry.key: entry.value,
                  ...incomingKugou[slot]!,
                },
      ];
      await _commit(nextNetease, nextKugou, platform ?? _platform, _siteToken);
    });
    _writes = command.catchError((Object _) {});
    return command;
  }

  Future<void> _commit(
    Map<String, String> netease,
    List<Map<String, String>> kugou,
    int platform,
    String siteToken,
  ) async {
    final encoded = jsonEncode({
      'version': 1,
      'netease': netease,
      'kugou': kugou,
      'platform': platform,
      'siteToken': siteToken,
    });
    await storage?.write(encoded);
    if (netease['MUSIC_U'] != _netease['MUSIC_U']) neteaseNickname = null;
    for (var slot = 0; slot < 2; slot++) {
      if (kugou[slot]['token'] != _kugou[slot]['token'] ||
          kugou[slot]['userid'] != _kugou[slot]['userid']) {
        kugouNicknames[slot] = null;
      }
    }
    _netease = Map.of(netease);
    _kugou = kugou;
    _platform = platform;
    _siteToken = siteToken;
    ensureDevice(0);
    ensureDevice(1);
    notifyListeners();
  }
}
