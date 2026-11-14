import '../i18n/tr.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

import '../domain/online_music.dart';
import '../domain/music_plugin.dart';
import '../domain/library.dart' show encodeLyrics;
import 'account_store.dart';
import 'native_crypto.dart';
import 'catalog_transport.dart';
import 'builtin_music_plugin.dart';
import 'plugin_subscriptions.dart';
import 'plugins/script_music_catalog.dart';
import 'audio_cache.dart';
export 'catalog_transport.dart' show CatalogRequest, CatalogTransport;

class NativeMusicCatalog
    implements
        MusicCatalog,
        PluginMusicCatalog,
        SearchRecommendations,
        OnlineAudioSource,
        OnlineDownloadSource {
  NativeMusicCatalog({
    CatalogTransport? transport,
    int Function()? clock,
    AccountStore? accounts,
    this.initializeSessions = true,
    BuiltinMusicPlugin? musicPlugin,
    this.subscriptions,
    this.cache,
  }) : _transport = transport ?? sendCatalogRequest,
       accounts = accounts ?? AccountStore(),
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    plugin = musicPlugin ?? BuiltinMusicPlugin(transport: _transport);
  }

  final CatalogTransport _transport;
  final int Function() _clock;
  final AccountStore accounts;
  late final BuiltinMusicPlugin plugin;
  final PluginSubscriptions? subscriptions;
  static const _neteaseMagic = r'3go8&$8*3*3h0k(2)2';
  ScriptMusicCatalog get scripts => ScriptMusicCatalog(subscriptions!.runtime);

  String _lxPlatform(MusicPluginSource source, OnlineSong song) {
    final platform =
        song.provider.gateway ??
        (song.provider == MusicProvider.netease ? 'wy' : 'kg');
    return platform == 'tx' && !source.lxSources.containsKey(platform)
        ? 'qq'
        : platform;
  }

  MusicPluginSource? _lxOverride(OnlineSong song) {
    if (song.pluginSource?.scripted == true) return null;
    if (song.pluginSource != null || song.provider.gateway != null) {
      _pluginSource(song);
    }
    final platform =
        song.provider.gateway ??
        (song.provider == MusicProvider.netease ? 'wy' : 'kg');
    return subscriptions?.sources
        .where(
          (source) =>
              source.lx &&
              (source.lxSources.containsKey(platform) ||
                  platform == 'tx' && source.lxSources.containsKey('qq')),
        )
        .lastOrNull;
  }

  MusicPluginSource? _pluginSource(OnlineSong song) {
    final reference = song.pluginSource;
    if (subscriptions == null) return reference;
    final id = reference?.id ?? song.provider.sourceId;
    final current = subscriptions!.sources
        .where((source) => source.id == id)
        .firstOrNull;
    if (current == null) {
      throw MusicSearchException(tr('该音源订阅已停用或删除，请先在订阅管理中启用。'));
    }
    return current;
  }

  final bool initializeSessions;
  final AudioCache? cache;
  static const pageSize = 30;
  String get _mid {
    accounts.ensureDevice();
    return accounts.kugou()['KUGOU_API_MID']!;
  }

  static const levels = [
    'standard',
    'higher',
    'exhigh',
    'lossless',
    'hires',
    'jyeffect',
    'sky',
    'jymaster',
    'dolby',
  ];
  static const kgLevels = [
    '128',
    '320',
    'flac',
    'high',
    'viper_atmos',
    'viper_tape',
    'viper_clear',
    'super',
  ];
  final List<Future<void>?> _initializingKugou = [null, null];
  Future<void>? _initializingNetease;

  Future<void> initializeProvider(MusicProvider provider) async {
    if (provider == MusicProvider.netease) {
      if ((accounts.netease['MUSIC_U'] ?? accounts.netease['MUSIC_A'] ?? '')
          .isNotEmpty) {
        return;
      }
      await (_initializingNetease ??= _registerNetease());
    } else {
      final platform = accounts.platform;
      accounts.ensureDevice();
      if ((accounts.kugou()['dfid'] ?? '').isNotEmpty) return;
      await (_initializingKugou[platform] ??= _registerKugou());
      if (accounts.platform != platform) {
        throw MusicSearchException(tr('音乐平台已切换，请重新播放。'));
      }
    }
  }

  Future<void> _registerNetease() async {
    try {
      final device = accounts.neteaseDevice;
      const magic = _neteaseMagic;
      final xor = [
        for (var index = 0; index < device.length; index++)
          device.codeUnitAt(index) ^ magic.codeUnitAt(index % magic.length),
      ];
      final username = base64Encode(
        utf8.encode('$device ${base64Encode(md5.convert(xor).bytes)}'),
      );
      final result = await _request(
        _weapi('/api/register/anonimous', {'username': username}),
      );
      final cookies = _object(
        result['_cookies'],
      ).map((key, value) => MapEntry(key, _text(value)));
      if (_number(result['code']) != 200 ||
          (cookies['MUSIC_A'] ?? '').isEmpty) {
        throw MusicSearchException(tr('网易云访客会话初始化失败，请稍后重试或登录。'));
      }
      await accounts.update(netease: cookies);
    } finally {
      _initializingNetease = null;
    }
  }

  Future<void> _registerKugou() async {
    final platform = accounts.platform;
    try {
      accounts.ensureDevice();
      final session = accounts.kugou();
      final secret = NativeCrypto.randomText(6);
      final hash = md5.convert(utf8.encode(secret)).toString();
      final device = <String, dynamic>{
        'availableRamSize': 4983533568,
        'availableRomSize': 48114719,
        'availableSDSize': 48114717,
        'basebandVer': '',
        'batteryLevel': 100,
        'batteryStatus': 3,
        'brand': 'NekoPlayer',
        'buildSerial': 'unknown',
        'device': Platform.version.contains('arm64') ? 'aarch64' : 'amd64',
        'imei': session['KUGOU_API_GUID'],
        'imsi': '',
        'manufacturer': 'Desktop',
        'uuid': session['KUGOU_API_GUID'],
        for (final sensor in [
          'accelerometer',
          'gravity',
          'gyroscope',
          'light',
          'magnetic',
          'orientation',
          'pressure',
          'step_counter',
          'temperature',
        ]) ...{sensor: false, '${sensor}Value': ''},
      };
      final request = _gateway(
        '/risk/v2/r_register_dev',
        {
          'part': '1',
          'platid': '1',
          'p': NativeCrypto.rsa(
            jsonEncode({
              'aes': secret,
              'uid': int.tryParse(session['userid'] ?? '') ?? 0,
              'token': session['token'] ?? '',
            }),
            platform == 1 ? NativeCrypto.kugouLiteRsa : NativeCrypto.kugouRsa,
            pkcs: true,
          ),
        },
        host: 'userservice.kugou.com',
        rawBody: NativeCrypto.encrypt(
          jsonEncode(device),
          hash.substring(0, 16),
          hash.substring(16),
        ).base64,
      );
      final response = await _request(
        CatalogRequest(
          request.uri,
          headers: request.headers,
          body: request.body,
          decodeResponse: (bytes) => NativeCrypto.decrypt(
            bytes,
            hash.substring(0, 16),
            hash.substring(16),
          ),
        ),
      );
      final dfid = _text(_object(response['data'])['dfid'] ?? response['dfid']);
      if (_number(response['status']) != 1 || dfid.isEmpty) {
        throw MusicSearchException(
          tr('酷狗设备初始化失败（{code}），请重试。', {
            'code':
                _number(response['error_code'] ?? response['errcode']) ??
                _number(response['status']) ??
                -1,
          }),
        );
      }
      await accounts.update(
        kugou: {'dfid': dfid},
        platform: platform,
        selectPlatform: false,
      );
    } finally {
      _initializingKugou[platform] = null;
    }
  }

  CatalogRequest _weapi(String path, Map<String, dynamic> data) {
    final request = neteaseRequest(path, data);
    return CatalogRequest(
      Uri.https('music.163.com', path.replaceFirst('/api/', '/weapi/')),
      headers: request.headers,
      captureCookies: true,
      body: NativeCrypto.weapi({
        ...data,
        'e_r': false,
        'csrf_token': accounts.netease['__csrf'] ?? '',
      }),
    );
  }

  Future<LoginQr> createLoginQr(MusicProvider provider) async {
    if (provider == MusicProvider.netease) {
      final result = await _request(
        neteaseRequest('/api/login/qrcode/unikey', {'type': 3}),
      );
      final key = _text(result['unikey'] ?? _object(result['data'])['unikey']);
      if (_number(result['code']) != 200 || key.isEmpty) {
        throw MusicSearchException(tr('网易云未返回登录二维码。'));
      }
      return LoginQr(
        provider,
        key,
        Uri.https('music.163.com', '/login', {'codekey': key}),
        0,
      );
    }
    final platform = accounts.platform;
    accounts.ensureDevice(platform);
    final result = await _request(
      _gateway(
        '/v2/qrcode',
        {
          'appid': '1001',
          'type': '1',
          'plat': '4',
          'srcappid': '2919',
          'qrcode_txt':
              'https://h5.kugou.com/apps/loginQRCode/html/index.html?appid=${platform == 1 ? 3116 : 1005}&',
        },
        host: 'login-user.kugou.com',
        web: true,
      ),
    );
    final data = _object(result['data']);
    final key = _text(data['qrcode'] ?? data['key'] ?? data['unikey']);
    if (_number(result['status']) != 1 || key.isEmpty) {
      throw MusicSearchException(tr('酷狗未返回登录二维码。'));
    }
    return LoginQr(
      provider,
      key,
      Uri.https('h5.kugou.com', '/apps/loginQRCode/html/index.html', {
        'qrcode': key,
      }),
      platform,
    );
  }

  Future<LoginProgress> checkLoginQr(
    LoginQr qr, {
    bool Function()? accept,
  }) async {
    if (qr.provider == MusicProvider.netease) {
      final request = neteaseRequest('/api/login/qrcode/client/login', {
        'key': qr.key,
        'type': 3,
      });
      final result = await _request(
        CatalogRequest(
          request.uri,
          headers: request.headers,
          body: request.body,
          captureCookies: true,
        ),
      );
      switch (_number(result['code'])) {
        case 800:
          return LoginProgress.expired;
        case 801:
          return LoginProgress.waiting;
        case 802:
          return LoginProgress.scanned;
        case 803:
          final cookies = _object(
            result['_cookies'],
          ).map((key, value) => MapEntry(key, _text(value)));
          if ((cookies['MUSIC_U'] ?? '').isEmpty) {
            throw MusicSearchException(tr('网易云未返回有效登录凭据。'));
          }
          if (accept?.call() ?? true) await accounts.update(netease: cookies);
          return LoginProgress.authorized;
        default:
          throw MusicSearchException(tr('网易云扫码登录失败，请刷新二维码。'));
      }
    }
    if (qr.platform != accounts.platform) {
      throw MusicSearchException(tr('登录平台已切换，请刷新二维码。'));
    }
    final result = await _request(
      _gateway(
        '/v2/get_userinfo_qrcode',
        {
          'plat': '4',
          'appid': qr.platform == 1 ? '3116' : '1005',
          'srcappid': '2919',
          'qrcode': qr.key,
          'dev': accounts.kugou(qr.platform)['KUGOU_API_DEV']!,
        },
        host: 'login-user.kugou.com',
        web: true,
      ),
    );
    final data = _object(result['data']);
    if (_number(result['status']) != 1) {
      throw MusicSearchException(tr('酷狗扫码检查失败，请重试。'));
    }
    switch (_number(data['status'])) {
      case 0:
        return LoginProgress.expired;
      case 1:
        return LoginProgress.waiting;
      case 2:
        return LoginProgress.scanned;
      case 4:
        final token = _text(data['token']);
        final uid = _number(data['userid']) ?? 0;
        if (token.isEmpty ||
            ['null', 'undefined'].contains(token) ||
            uid <= 0) {
          throw MusicSearchException(tr('酷狗未返回有效登录凭据。'));
        }
        if (accept?.call() ?? true) {
          final device = {
            for (final entry in accounts.kugou(qr.platform).entries)
              if (entry.key.startsWith('KUGOU_API_') || entry.key == 'dfid')
                entry.key: entry.value,
          };
          await accounts.update(
            kugou: {
              ...device,
              for (final key in [
                'token',
                'userid',
                'vip_type',
                'vip_token',
                't1',
                'dfid',
              ])
                if (_text(data[key]).isNotEmpty) key: _text(data[key]),
            },
            platform: qr.platform,
            selectPlatform: false,
            replace: true,
          );
        }
        return LoginProgress.authorized;
      default:
        throw MusicSearchException(tr('酷狗扫码授权失败，请刷新二维码。'));
    }
  }

  CatalogRequest _gateway(
    String path,
    Map<String, String> query, {
    String router = '',
    Map<String, dynamic>? body,
    String? rawBody,
    String host = 'gateway.kugou.com',
    bool web = false,
    bool clear = false,
    bool sign = true,
  }) {
    accounts.ensureDevice();
    final session = accounts.kugou();
    final lite = accounts.platform == 1;
    final parameters = <String, String>{
      if (!clear) ...{
        'dfid': session['dfid'] ?? '-',
        'mid': _mid,
        'uuid': '-',
        'appid': lite ? '3116' : '1005',
        'clientver': lite ? '11440' : '20489',
        'clienttime': '${_clock() ~/ 1000}',
        if ((session['token'] ?? '').isNotEmpty) 'token': session['token']!,
        if ((session['userid'] ?? '0') != '0') 'userid': session['userid']!,
      },
      ...query,
    };
    final encoded = rawBody ?? (body == null ? '' : jsonEncode(body));
    final keys = parameters.keys.toList()..sort();
    final salt = web
        ? 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt'
        : lite
        ? 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA'
        : 'OIlwieks28dk2k092lksi2UIkp';
    if (sign) {
      parameters['signature'] = md5
          .convert(
            utf8.encode(
              '$salt${keys.map((key) => '$key=${parameters[key]}').join()}${web ? '' : encoded}$salt',
            ),
          )
          .toString();
    }
    return CatalogRequest(
      Uri.https(host, path).replace(
        query: parameters.entries
            .map(
              (entry) =>
                  '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
            )
            .join('&'),
      ),
      headers: {
        'User-Agent': 'Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi',
        'dfid': session['dfid'] ?? '-',
        'mid': _mid,
        'clienttime': '${_clock() ~/ 1000}',
        'kg-rc': '1',
        'kg-thash': '5d816a0',
        'kg-rec': '1',
        'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
        if (router.isNotEmpty) 'x-router': router,
        if (body != null) 'Content-Type': 'application/json; charset=UTF-8',
        if (rawBody != null)
          'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body == null && rawBody == null ? null : encoded,
    );
  }

  void _checkKugouAccount() {
    if (!accounts.kugouLoggedIn()) {
      throw MusicSearchException(tr('请先登录当前酷狗账号。'));
    }
  }

  String _kugouRsa(Map<String, dynamic> body) => NativeCrypto.rsa(
    jsonEncode(body),
    accounts.platform == 1 ? NativeCrypto.kugouLiteRsa : NativeCrypto.kugouRsa,
    padEnd: true,
  ).toUpperCase();

  void _checkMobile(String mobile) {
    if (!RegExp(r'^1[3-9][0-9]{9}$').hasMatch(mobile)) {
      throw MusicSearchException(tr('请输入有效的大陆手机号。'));
    }
  }

  Future<void> sendKugouCode(String mobile) async {
    _checkMobile(mobile);
    await initializeProvider(MusicProvider.kugou);
    final result = await _request(
      _gateway(
        '/v7/send_mobile_code',
        {},
        host: 'login-user.kugou.com',
        body: {'businessid': 5, 'mobile': mobile, 'plat': 3},
      ),
    );
    if (_number(result['status']) != 1 && _number(result['code']) != 200) {
      throw MusicSearchException(tr('酷狗未确认验证码发送成功，请稍后重试。'));
    }
  }

  Future<void> loginKugouMobile(
    String mobile,
    String code, {
    String? userId,
    bool Function()? accept,
  }) async {
    _checkMobile(mobile);
    if (!RegExp(r'^\d{4,8}$').hasMatch(code)) {
      throw MusicSearchException(tr('请输入 4–8 位短信验证码。'));
    }
    if (userId != null && (_number(userId) ?? 0) <= 0) {
      throw MusicSearchException(tr('所选账号 ID 无效。'));
    }
    await _loginKugou(
      mobile: mobile,
      code: code,
      userId: userId,
      accept: accept,
    );
  }

  Future<void> refreshKugouToken({bool Function()? accept}) async {
    _checkKugouAccount();
    await _loginKugou(accept: accept);
  }

  Future<void> _loginKugou({
    String? mobile,
    String? code,
    String? userId,
    bool Function()? accept,
  }) async {
    final platform = accounts.platform;
    final originalToken = accounts.kugou()['token'];
    await initializeProvider(MusicProvider.kugou);
    if (accounts.platform != platform) {
      throw MusicSearchException(tr('酷狗平台已切换，请重试。'));
    }
    final session = accounts.kugou();
    final lite = platform == 1;
    final now = _clock();
    final seconds = now ~/ 1000;
    final secret = NativeCrypto.randomText(16);
    final hash = md5.convert(utf8.encode(secret)).toString();
    String aes(String text, String key) =>
        NativeCrypto.encrypt(text, key, key.substring(key.length - 16)).base16;
    final body = <String, dynamic>{
      'plat': 1,
      'clienttime_ms': now,
      't1': lite
          ? aes(
              '${session['t1'] ?? ''}|$now',
              '5e4ef500e9597fe004bd09a46d8add98',
            )
          : 0,
      't2': lite
          ? aes(
              '${session['KUGOU_API_GUID']}|0f607264fc6318a92b9e13c65db7cd3c|${session['KUGOU_API_MAC']}|${session['KUGOU_API_DEV']}|$now',
              'fd14b35e3f81af3817a20ae7adae7020',
            )
          : 0,
      'pk': _kugouRsa({'clienttime_ms': now, 'key': secret}),
      'params': aes(
        jsonEncode(
          mobile == null
              ? <String, dynamic>{}
              : {'mobile': mobile, 'code': code},
        ),
        hash,
      ),
      if (lite) ...{
        'dfid': session['dfid'],
        'dev': session['KUGOU_API_DEV'],
        'gitversion': '5f0b7c4',
      } else
        't3': 'MCwwLDAsMCwwLDAsMCwwLDA=',
    };
    if (mobile != null) {
      final salt = lite
          ? 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA'
          : 'OIlwieks28dk2k092lksi2UIkp';
      body.addAll({
        'mobile':
            '${mobile.substring(0, 2)}*****${mobile.substring(mobile.length - 1)}',
        'support_multi': 1,
        'key': md5
            .convert(
              utf8.encode(
                '${lite ? 3116 : 1005}$salt${lite ? 11440 : 20489}$now',
              ),
            )
            .toString(),
        'userid': ?userId,
      });
    } else {
      final key = lite
          ? 'c24f74ca2820225badc01946dba4fdf7'
          : '90b8382a1bb4ccdcf063102053fd75b8';
      body.addAll({
        'p3': aes(
          jsonEncode({'clienttime': seconds, 'token': session['token']}),
          key,
        ),
        'userid': session['userid'],
        'dfid': session['dfid'],
      });
    }
    final request = _gateway(
      mobile == null ? '/v5/login_by_token' : '/v7/login_by_verifycode',
      {},
      host: mobile == null
          ? 'login-user.kugou.com'
          : 'loginserviceretry.kugou.com',
      body: body,
    );
    final result = await _request(
      CatalogRequest(
        request.uri,
        body: request.body,
        headers: {
          ...request.headers,
          if (mobile != null) ...{
            'support-calm': '1',
            'User-Agent': 'Android16-1070-11440-130-0-LOGIN-wifi',
          },
        },
      ),
    );
    if (_number(result['status']) != 1) {
      throw MusicSearchException(tr('酷狗未确认登录成功，请检查验证码、设备验证或登录凭据。'));
    }
    final data = <String, dynamic>{..._object(result['data'])};
    final secured = _text(data['secu_params']);
    if (secured.isNotEmpty) {
      if (secured.length > 32768 ||
          !RegExp(r'^(?:[a-fA-F0-9]{2})+$').hasMatch(secured)) {
        throw MusicSearchException(tr('酷狗登录响应格式异常。'));
      }
      final clear = NativeCrypto.decrypt(
        [
          for (var index = 0; index < secured.length; index += 2)
            int.parse(secured.substring(index, index + 2), radix: 16),
        ],
        hash,
        hash.substring(16),
      );
      try {
        data.addAll(_object(jsonDecode(clear)));
      } on FormatException {
        data['token'] = clear;
      }
    }
    if (_text(data['token']).isEmpty && mobile != null) {
      final choices = <String, KugouLoginChoice>{};
      for (final row
          in data.values
              .whereType<List>()
              .expand((rows) => rows)
              .whereType<Map<String, dynamic>>()) {
        final id = _text(row['userid']);
        if ((_number(id) ?? 0) > 0) {
          choices[id] = KugouLoginChoice(
            id,
            _text(row['nickname'] ?? row['username']),
          );
        }
      }
      if (choices.isNotEmpty) {
        throw KugouAccountSelection(choices.values.take(30).toList());
      }
    }
    if (_text(data['token']).isEmpty ||
        ['null', 'undefined'].contains(_text(data['token'])) ||
        (_number(data['userid']) ?? 0) <= 0) {
      throw MusicSearchException(tr('酷狗未返回有效登录凭据，原账号未修改。'));
    }
    if (accounts.platform != platform ||
        accounts.kugou()['token'] != originalToken ||
        !(accept?.call() ?? true)) {
      throw MusicSearchException(tr('登录操作已取消或账号已变化，未覆盖当前账号。'));
    }
    if (mobile == null && _text(data['userid']) != session['userid']) {
      throw MusicSearchException(tr('刷新结果的账号不匹配，未覆盖原凭据。'));
    }
    await accounts.update(
      kugou: {
        for (final entry in session.entries)
          if (entry.key.startsWith('KUGOU_API_') || entry.key == 'dfid')
            entry.key: entry.value,
        for (final key in ['token', 'userid', 'vip_type', 'vip_token', 't1'])
          if (_text(data[key]).isNotEmpty) key: _text(data[key]),
      },
      platform: platform,
      selectPlatform: false,
      replace: true,
    );
  }

  Future<Map<String, dynamic>> kugouAccountInfo({bool vip = false}) async {
    _checkKugouAccount();
    final seconds = _clock() ~/ 1000;
    final request = vip
        ? _gateway('/v1/get_union_vip', {
            'busi_type': 'concept',
          }, host: 'kugouvip.kugou.com')
        : _gateway(
            '/v3/get_my_info',
            {'plat': '1'},
            router: 'usercenter.kugou.com',
            body: {
              'visit_time': seconds,
              'usertype': 1,
              'p': _kugouRsa({
                'token': accounts.kugou()['token'],
                'clienttime': seconds,
              }),
              'userid': _number(accounts.kugou()['userid']),
            },
          );
    final result = await _request(request);
    if (_number(result['status']) != 1) {
      throw MusicSearchException(tr('酷狗账号信息读取失败，请检查登录状态。'));
    }
    final data = _object(result['data']);
    return _object(data[vip ? 'vip' : 'userinfo']).isEmpty
        ? data
        : _object(data[vip ? 'vip' : 'userinfo']);
  }

  Future<void> claimKugouDailyVip() async {
    _checkKugouAccount();
    if (accounts.platform != 1) {
      throw MusicSearchException(tr('每日听歌权益仅支持酷狗概念版账号。'));
    }
    final result = await _request(
      _gateway('/youth/v1/recharge/receive_vip_listen_song', {
        'source_id': '90139',
        'receive_day': '1',
      }, body: {}),
    );
    if (_number(result['status']) != 1 && _number(result['code']) != 200) {
      throw MusicSearchException(tr('平台未确认权益领取成功，请在官方客户端检查。'));
    }
  }

  Future<Map<String, dynamic>> _request(CatalogRequest request) async {
    try {
      return await _transport(request);
    } on TimeoutException {
      throw MusicSearchException(tr('音乐平台请求超时，请重试。'));
    } on IOException {
      throw MusicSearchException(tr('无法连接音乐平台，请检查网络。'));
    } on FormatException {
      throw MusicSearchException(tr('音乐平台响应格式异常。'));
    }
  }

  Future<Map<String, dynamic>> neteaseApi(
    String path,
    Map<String, dynamic> data, {
    bool weapi = false,
  }) => _request(weapi ? _weapi(path, data) : neteaseRequest(path, data));

  Future<Map<String, dynamic>> kugouApi(
    String path,
    Map<String, String> query, {
    String router = '',
    Map<String, dynamic>? body,
    String? rawBody,
    bool clear = false,
    bool sign = true,
    String host = 'gateway.kugou.com',
    Map<String, String> extraHeaders = const {},
  }) {
    final request = _gateway(
      path,
      query,
      router: router,
      body: body,
      rawBody: rawBody,
      clear: clear,
      sign: sign,
      host: host,
    );
    return _request(
      CatalogRequest(
        request.uri,
        body: request.body,
        headers: {...request.headers, ...extraHeaders},
      ),
    );
  }

  @override
  Future<ResolvedAudio> resolve(
    OnlineSong song, {
    String preferred = 'exhigh',
  }) async {
    final cached = await cache?.find(song, preferred);
    if (cached != null) return cached;
    final audio = await _resolve(song, preferred: preferred);
    cache?.remember(song, audio);
    return audio;
  }

  @override
  Future<ResolvedAudio> resolveDownload(OnlineSong song, String quality) =>
      _resolve(song, preferred: quality, download: true);

  Future<_NativeAudioChoices> _discoverNative(
    OnlineSong song, {
    required bool download,
    bool Function()? accept,
  }) async {
    if (initializeSessions) await initializeProvider(song.provider);
    if (accept?.call() == false) {
      throw MusicSearchException(tr('音质检查已取消。'));
    }
    final netease = song.provider == MusicProvider.netease;
    final platform = accounts.platform;
    final credential = netease
        ? accounts.netease['MUSIC_U'] ?? accounts.netease['MUSIC_A']
        : accounts.kugou()['token'];
    final userId = netease ? null : accounts.kugou()['userid'];
    void checkSession() {
      final active = netease
          ? accounts.netease['MUSIC_U'] ?? accounts.netease['MUSIC_A']
          : accounts.kugou()['token'];
      if ((!netease &&
              (accounts.platform != platform ||
                  accounts.kugou()['userid'] != userId)) ||
          active != credential) {
        throw MusicSearchException(tr('账号或平台已切换，请重新播放。'));
      }
    }

    final choices = <String, String>{};
    if (netease) {
      if (!RegExp(r'^\d+$').hasMatch(song.id)) {
        throw MusicSearchException(tr('歌曲编号无效，请重新搜索。'));
      }
      final detail = await _request(
        neteaseRequest('/api/song/music/detail/get', {'songId': song.id}),
      );
      if (_number(detail['code']) != 200) {
        throw MusicSearchException(tr('无法获取网易云音质信息。'));
      }
      final data = _object(detail['data']);
      const fields = ['l', 'm', 'h', 'sq', 'hr', 'je', 'sk', 'jm', 'db'];
      for (var index = 0; index < fields.length; index++) {
        if ((_number(_object(data[fields[index]])['size']) ?? 0) > 0) {
          choices[levels[index]] = '';
        }
      }
    } else {
      if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(song.hash)) {
        throw MusicSearchException(tr('歌曲缺少有效 hash，请重新搜索。'));
      }
      final detail = await _request(
        _gateway(
          '/v2/get_res_privilege/lite',
          {},
          router: 'media.store.kugou.com',
          body: {
            'appid': accounts.platform == 1 ? 3116 : 1005,
            'area_code': 1,
            'behavior': download ? 'download' : 'play',
            'clientver': accounts.platform == 1 ? 11440 : 20489,
            'need_hash_offset': 1,
            'relate': 1,
            'support_verify': 1,
            'resource': [
              {
                'type': 'audio',
                'page_id': 0,
                'hash': song.hash,
                'album_id': song.albumId.isEmpty ? '0' : song.albumId,
              },
            ],
            'qualities': kgLevels,
          },
        ),
      );
      if (_number(detail['status']) != 1) {
        throw MusicSearchException(tr('无法获取酷狗音质信息，请稍后重试。'));
      }
      final track =
          _items(detail['data']).firstOrNull ?? const <String, dynamic>{};
      for (final item in [track, ..._items(track['relate_goods'])]) {
        final quality = _text(item['quality']);
        final hash = _text(item['hash']).toLowerCase();
        if (kgLevels.contains(quality) &&
            _number(item['is_publish'] ?? item['publish']) == 1 &&
            (_number(_object(item['info'])['filesize']) ?? 0) > 0 &&
            RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(hash)) {
          choices[quality] = hash;
        }
      }
    }
    checkSession();
    return _NativeAudioChoices(choices, checkSession);
  }

  Future<List<AudioQuality>> downloadable(
    OnlineSong song, {
    bool Function()? accept,
  }) async {
    void checkAccepted() {
      if (accept?.call() == false) {
        throw MusicSearchException(tr('音质检查已取消。'));
      }
    }

    checkAccepted();
    final scriptSource = song.pluginSource?.scripted == true
        ? _pluginSource(song)
        : null;
    final lx = _lxOverride(song);
    final discovered = song.provider.gateway == null && lx == null
        ? await _discoverNative(song, download: true, accept: accept)
        : null;
    final result = <AudioQuality>[];
    final qualities = scriptSource == null
        ? lx == null
              ? AudioQuality.supported(song.provider)
              : scripts.lxQualities(lx, _lxPlatform(lx, song))
        : scripts.qualities(scriptSource, song);
    for (final quality in qualities) {
      checkAccepted();
      discovered?.checkSession();
      if (discovered != null && !discovered.choices.containsKey(quality.id)) {
        continue;
      }
      try {
        final audio = await _resolve(
          song,
          preferred: quality.id,
          download: true,
          discovered: discovered,
        );
        checkAccepted();
        discovered?.checkSession();
        if (audio.quality == quality.id) {
          result.add(
            AudioQuality(
              quality.id,
              quality.label,
              quality.rank,
              size: audio.size,
            ),
          );
        }
      } on AudioUnavailableException {
        checkAccepted();
        discovered?.checkSession();
      }
    }
    checkAccepted();
    result.sort((first, second) => second.rank.compareTo(first.rank));
    return result;
  }

  Future<ResolvedAudio> _resolve(
    OnlineSong song, {
    required String preferred,
    bool download = false,
    _NativeAudioChoices? discovered,
  }) async {
    if (song.pluginSource?.scripted == true) {
      final source = _pluginSource(song);
      if (source == null || subscriptions == null) {
        throw MusicSearchException(tr('请先重新安装该音源插件。'));
      }
      return scripts.resolve(source, song, preferred, exact: download);
    }
    final lx = _lxOverride(song);
    if (lx != null) {
      final result = await scripts.resolveLx(
        lx,
        _lxPlatform(lx, song),
        song,
        preferred,
        exact: download,
      );
      return ResolvedAudio(
        result.uri,
        download ? preferred : result.quality,
        size: result.size,
        format: result.format,
        headers: result.headers,
      );
    }
    if (song.provider.gateway != null) {
      return _resolvePlugin(song, preferred, download);
    }
    final available =
        discovered ?? await _discoverNative(song, download: download);
    final choices = available.choices;
    final checkSession = available.checkSession;
    checkSession();
    final netease = song.provider == MusicProvider.netease;
    if (!netease) {
      preferred =
          const {
            'standard': '128',
            'higher': '320',
            'exhigh': '320',
            'lossless': 'flac',
            'hires': 'high',
            'jyeffect': 'viper_clear',
            'sky': 'viper_atmos',
            'jymaster': 'super',
            'dolby': 'viper_atmos',
          }[preferred] ??
          preferred;
    }
    final ranks = netease ? levels : kgLevels;
    final ordered = choices.keys.toList()
      ..sort((first, second) {
        if (first == preferred) return -1;
        if (second == preferred) return 1;
        return ranks.indexOf(second).compareTo(ranks.indexOf(first));
      });
    if (download) ordered.removeWhere((quality) => quality != preferred);
    ResolvedAudio? fallback;
    for (final quality in ordered) {
      checkSession();
      Map<String, dynamic> data;
      if (netease) {
        final body = await _request(
          neteaseRequest(
            download
                ? '/api/song/enhance/download/url/v1'
                : '/api/song/enhance/player/url/v1',
            {
              if (download) 'id': song.id else 'ids': '[${song.id}]',
              'level': quality,
              'encodeType': 'flac',
              if (download || quality == 'sky') 'immerseType': 'c51',
            },
          ),
        );
        if ([401, 403, 429].contains(_number(body['code']))) {
          throw MusicSearchException(tr('音乐平台拒绝请求，请检查账号或稍后重试。'));
        }
        if (_number(body['code']) != 200) continue;
        data = body['data'] is Map<String, dynamic>
            ? _object(body['data'])
            : _items(body['data']).firstOrNull ?? const {};
        if ((data['code'] != null && _number(data['code']) != 200) ||
            data['freeTrialInfo'] != null) {
          continue;
        }
      } else {
        final hash = choices[quality]!;
        final body = await _request(
          _gateway('/v5/url', {
            'album_id': song.albumId.isEmpty ? '0' : song.albumId,
            'area_code': '1',
            'hash': hash,
            'ssa_flag': 'is_fromtrack',
            'version': '11430',
            'page_id': accounts.platform == 1 ? '967177915' : '151369488',
            'quality': quality,
            'album_audio_id': song.albumAudioId.isEmpty
                ? '0'
                : song.albumAudioId,
            'behavior': download ? 'download' : 'play',
            'pid': accounts.platform == 1 ? '411' : '2',
            'cmd': '26',
            'pidversion': '3001',
            'IsFreePart': '0',
            'ppage_id': accounts.platform == 1
                ? '356753938,823673182,967485191'
                : '463467626,350369493,788954147',
            'cdnBackup': '1',
            'module': '',
            'clientver': '11430',
            'key': md5
                .convert(
                  utf8.encode(
                    '$hash${accounts.platform == 1 ? '185672dd44712f60bb1736df5a377e82' : '57ae12eb6890223e355ccfcb74edf70d'}${accounts.platform == 1 ? 3116 : 1005}$_mid${accounts.kugou()['userid'] ?? '0'}',
                  ),
                )
                .toString(),
          }, router: 'trackercdn.kugou.com'),
        );
        if ([
          20018,
          20028,
        ].contains(_number(body['errcode'] ?? body['error_code']))) {
          throw MusicSearchException(tr('酷狗要求账号或设备验证，请在官方客户端验证后重试。'));
        }
        if (_number(body['status']) != 1) continue;
        data = body['data'] is Map<String, dynamic>
            ? _object(body['data'])
            : body;
        if ([
          'is_free_part',
          'isFreePart',
          'is_freepart',
          'is_free_part_url',
        ].any((key) => (_number(data[key]) ?? 0) > 0)) {
          continue;
        }
      }
      checkSession();
      var actual = _text(data[netease ? 'level' : 'quality']);
      if (netease && actual.isEmpty) {
        final bitrate = _number(data['br']) ?? 0;
        actual = switch (bitrate) {
          > 0 && <= 128000 => 'standard',
          > 128000 && <= 192000 => 'higher',
          > 192000 && <= 320000 => 'exhigh',
          _ => quality,
        };
      }
      if (actual.isNotEmpty && !ranks.contains(actual)) continue;
      final urls = [
        for (final key in ['url', 'play_url', 'backup_url', 'play_backup_url'])
          ...data[key] is List ? data[key] as List : [data[key]],
      ];
      for (final value in urls) {
        final uri = Uri.tryParse(_text(value));
        if (uri == null ||
            !['https', 'http'].contains(uri.scheme) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          continue;
        }
        final audio = ResolvedAudio(
          uri,
          actual.isEmpty ? quality : actual,
          size:
              _number(data['size'] ?? data['fileSize'] ?? data['filesize']) ??
              0,
          format: _text(data['type'] ?? data['extName'] ?? data['extname']),
          checksum: _text(data['md5']),
        );
        if (download && audio.quality != quality) continue;
        if (audio.quality == quality) return audio;
        if (fallback == null ||
            ranks.indexOf(audio.quality) > ranks.indexOf(fallback.quality)) {
          fallback = audio;
        }
        break;
      }
    }
    if (fallback != null) return fallback;
    throw AudioUnavailableException(tr('暂无当前账号可播放的完整音源；不播放试听片段。'));
  }

  @override
  Future<String> lyrics(OnlineSong song) async {
    final cached = await cache?.lyrics(song);
    if (cached != null) return cached;
    final content = await _fetchLyrics(song);
    cache?.rememberLyrics(song, content);
    return content;
  }

  Future<String> _fetchLyrics(OnlineSong song) async {
    if (song.pluginSource?.scripted == true) {
      final source = _pluginSource(song);
      if (source == null || subscriptions == null) {
        throw MusicSearchException(tr('请先重新安装该音源插件。'));
      }
      return scripts.lyrics(source, song);
    }
    final lx = _lxOverride(song);
    if (lx != null) {
      final content = await scripts.lxLyrics(lx, _lxPlatform(lx, song), song);
      if (content != null && content.isNotEmpty) return content;
    }
    if (song.provider.gateway != null) {
      final body = await plugin.lyrics(song, source: _pluginSource(song));
      return encodeLyrics(_text(body['lyric']), _text(body['tlyric']));
    }
    if (song.provider == MusicProvider.netease) {
      try {
        final body = await _request(
          neteaseRequest('/api/song/lyric/v1', {
            'id': song.id,
            'cp': false,
            'tv': 0,
            'lv': 0,
            'rv': 0,
            'kv': 0,
            'yv': 0,
            'ytv': 0,
            'yrv': 0,
          }),
        );
        if (_number(body['code']) == 200) {
          final timed = _text(_object(body['yrc'])['lyric']);
          final original = timed.trim().isNotEmpty
              ? timed
              : _text(_object(body['lrc'])['lyric']);
          if (original.trim().isNotEmpty) {
            return encodeLyrics(
              original,
              _text(_object(body['tlyric'])['lyric']),
            );
          }
        }
      } on MusicSearchException catch (_) {}
      final body = await _request(
        neteaseRequest('/api/song/lyric', {
          'id': song.id,
          'tv': -1,
          'lv': -1,
          'rv': -1,
          'kv': -1,
          '_nmclfl': 1,
        }),
      );
      if (_number(body['code']) != 200) {
        throw MusicSearchException(tr('网易云歌词读取失败。'));
      }
      final original = _text(_object(body['lrc'])['lyric']);
      final translated = _text(_object(body['tlyric'])['lyric']);
      return encodeLyrics(original, translated);
    }
    final body = await _request(
      _gateway(
        '/v1/search',
        {
          'album_audio_id': song.albumAudioId.isEmpty ? '0' : song.albumAudioId,
          'appid': '1005',
          'clientver': '20489',
          'duration': '0',
          'hash': song.hash,
          'keyword': '${song.title} ${song.artist}',
          'lrctxt': '1',
          'man': 'no',
        },
        host: 'lyrics.kugou.com',
        clear: true,
      ),
    );
    final candidate = _items(body['candidates']).firstOrNull;
    if (candidate == null) return '';
    final result = await _request(
      _gateway('/download', {
        'ver': '1',
        'client': 'android',
        'id': _text(candidate['id']),
        'accesskey': _text(candidate['accesskey']),
        'fmt': 'lrc',
        'charset': 'utf8',
      }, host: 'lyrics.kugou.com'),
    );
    return utf8.decode(base64Decode(_text(result['content'])));
  }

  @override
  Future<SearchPage> search(
    MusicProvider provider,
    String keyword,
    int page,
  ) async {
    keyword = keyword.trim();
    if (keyword.isEmpty || keyword.length > 200 || page < 1) {
      throw MusicSearchException(tr('请输入 1–200 字的关键词。'));
    }
    if (provider.gateway != null) {
      final source = subscriptions?.sources
          .where((item) => item.id == provider.sourceId)
          .firstOrNull;
      if (subscriptions != null && source == null) {
        throw MusicSearchException(tr('内置订阅已停用，请先在订阅管理中启用。'));
      }
      return _searchPlugin(provider, source, keyword, page);
    }
    try {
      final response = await _transport(
        provider == MusicProvider.netease
            ? _neteaseRequest(keyword, page)
            : _kugouRequest(keyword, page),
      );
      return provider == MusicProvider.netease
          ? _neteasePage(response, page)
          : _kugouPage(response, page);
    } on MusicSearchException {
      rethrow;
    } on TimeoutException {
      throw MusicSearchException(tr('搜索超时，请稍后重试。'));
    } on IOException {
      throw MusicSearchException(tr('无法连接音乐平台，请检查网络后重试。'));
    } on FormatException {
      throw MusicSearchException(tr('音乐平台响应格式异常，请稍后重试。'));
    }
  }

  static const _hotSearchLimit = 12;
  static const _suggestionLimit = 8;

  String? _recommendationPlatform(MusicProvider provider) =>
      provider.gateway ??
      switch (provider) {
        MusicProvider.netease => 'wy',
        MusicProvider.kugou => 'kg',
        _ => null,
      };

  /// Recommendations are an enhancement, not part of search: a disabled or
  /// scripted source simply yields no words instead of raising an error.
  ({bool enabled, MusicPluginSource? source}) _recommendationSource(
    MusicProvider provider,
    MusicPluginSource? source,
    String capability,
  ) {
    MusicPluginSource? resolved = source;
    if (resolved == null && provider.gateway != null && subscriptions != null) {
      resolved = subscriptions!.sources
          .where((item) => item.id == provider.sourceId)
          .firstOrNull;
      if (resolved == null) return (enabled: false, source: null);
    }
    if (resolved == null) return (enabled: true, source: null);
    if (resolved.scripted || !resolved.capabilities.contains(capability)) {
      return (enabled: false, source: null);
    }
    return (enabled: true, source: resolved);
  }

  @override
  Future<List<String>> hotSearches(
    MusicProvider provider, {
    MusicPluginSource? source,
  }) async {
    final platform = _recommendationPlatform(provider);
    final resolved = _recommendationSource(provider, source, 'hotSearch');
    if (platform == null || !resolved.enabled) return const [];
    try {
      final body = await plugin.request('music/hotSearch', {
        'platform': platform,
      }, source: resolved.source);
      if (_number(body['code']) != 200) return const [];
      return _recommendationWords(
        _items(body['list']).map((item) => _text(item['word'])),
        limit: _hotSearchLimit,
      );
    } on Exception {
      return const [];
    }
  }

  @override
  Future<List<String>> searchSuggestions(
    MusicProvider provider,
    String keyword, {
    MusicPluginSource? source,
  }) async {
    final value = keyword.trim();
    final platform = _recommendationPlatform(provider);
    final resolved = _recommendationSource(provider, source, 'suggest');
    if (platform == null ||
        value.isEmpty ||
        value.length > 200 ||
        !resolved.enabled) {
      return const [];
    }
    try {
      final body = await plugin.request('music/suggest', {
        'platform': platform,
        'keyword': value,
      }, source: resolved.source);
      if (_number(body['code']) != 200) return const [];
      final songs = _items(body['songs']).map((item) {
        final title = _text(item['title']).trim();
        final artist = _text(item['artist']).trim();
        return artist.isEmpty ? title : '$title $artist';
      });
      final singers = _items(
        body['singers'],
      ).map((item) => _text(item['name']));
      final albums = _items(body['albums']).map((item) => _text(item['name']));
      return _recommendationWords([
        ...songs,
        ...singers,
        ...albums,
      ], limit: _suggestionLimit);
    } on Exception {
      return const [];
    }
  }

  static List<String> _recommendationWords(
    Iterable<String> words, {
    required int limit,
  }) => words
      .map((word) => word.trim())
      .where((word) => word.isNotEmpty && word.length <= 200)
      .toSet()
      .take(limit)
      .toList(growable: false);

  @override
  Future<SearchPage> searchPlugin(
    MusicPluginSource source,
    String keyword,
    int page,
  ) {
    if (keyword.trim().isEmpty || keyword.length > 200 || page < 1) {
      throw MusicSearchException(tr('请输入 1–200 字的关键词。'));
    }
    final provider =
        MusicProvider.values
            .where((item) => item.gateway == source.platform)
            .firstOrNull ??
        MusicProvider.gatewayKugou;
    final reference =
        _pluginSource(
          OnlineSong(
            provider: provider,
            id: '',
            title: '',
            artist: '',
            pluginSource: source,
          ),
        ) ??
        source;
    if (!reference.capabilities.contains('search')) {
      throw MusicSearchException(tr('该插件不支持歌曲搜索。'));
    }
    if (reference.scripted) {
      if (subscriptions == null) {
        throw MusicSearchException(tr('音源脚本引擎未初始化。'));
      }
      return scripts.search(reference, keyword.trim(), page);
    }
    if (reference.platform == 'all') {
      return _searchAggregatePlugin(reference, keyword.trim(), page);
    }
    return _searchPlugin(provider, reference, keyword.trim(), page);
  }

  Future<SearchPage> _searchAggregatePlugin(
    MusicPluginSource source,
    String keyword,
    int page,
  ) async {
    final pages = <SearchPage>[];
    Object? failure;
    for (final platform in source.supportedPlatforms) {
      final provider = MusicProvider.values.firstWhere(
        (item) => item.gateway == platform,
      );
      try {
        pages.add(await _searchPlugin(provider, source, keyword, page));
      } on Exception catch (error) {
        failure = error;
      }
    }
    if (pages.isEmpty && failure != null) throw failure;
    return SearchPage(
      songs: pages.expand((entry) => entry.songs).toList(),
      hasMore: pages.any((entry) => entry.hasMore),
    );
  }

  Future<SearchPage> _searchPlugin(
    MusicProvider provider,
    MusicPluginSource? source,
    String keyword,
    int page,
  ) async {
    final body = await plugin.request('music/search', {
      'platform': provider.gateway!,
      'keyword': keyword,
      'page': '$page',
      'limit': '$pageSize',
    }, source: source);
    if (_number(body['code']) != 200) {
      throw MusicSearchException(tr('音源服务未返回搜索结果。'));
    }
    final songs = _items(body['data'])
        .map(
          (item) => OnlineSong(
            provider: provider,
            id: _text(item['id']).isNotEmpty
                ? _text(item['id'])
                : _text(item['songId']),
            title: _text(item['title']),
            artist: _text(item['artist']),
            album: _text(item['album']),
            albumAudioId: _text(item['album_audio_id']),
            artwork: _text(item['artwork']),
            pluginSource: source,
            pluginData: item,
          ),
        )
        .where((song) => song.id.isNotEmpty && song.title.isNotEmpty)
        .toList();
    return SearchPage(
      songs: songs,
      hasMore: songs.isNotEmpty && body['isEnd'] == false,
    );
  }

  CatalogRequest _neteaseRequest(String keyword, int page) {
    const path = '/api/search/get';
    return neteaseRequest(path, {
      's': keyword,
      'type': 1,
      'limit': pageSize,
      'offset': (page - 1) * pageSize,
    });
  }

  CatalogRequest neteaseRequest(String path, Map<String, dynamic> payload) {
    final cookies = <String, String>{
      'os': 'pc',
      'appver': '3.1.17.204416',
      'deviceId': accounts.neteaseDevice,
      'osver': 'Microsoft-Windows-10-Professional-build-19045-64bit',
      'channel': 'netease',
      '__remember_me': 'true',
      'ntes_kaola_ad': '1',
      '_ntes_nuid': accounts.neteaseDevice,
      ...accounts.netease,
    };
    if ((cookies['MUSIC_U'] ?? '').isNotEmpty) cookies.remove('MUSIC_A');
    final data = jsonEncode({
      ...payload,
      'e_r': false,
      'header': {
        ...cookies,
        'os': 'pc',
        'appver': '3.1.17.204416',
        'versioncode': '140',
        'buildver': '${_clock() ~/ 1000}',
        'resolution': '1920x1080',
        'requestId': '${_clock()}_0',
      },
    });
    final digest = md5.convert(
      utf8.encode('nobody${path}use${data}md5forencrypt'),
    );
    final encrypted = Encrypter(
      AES(Key.fromUtf8('e82ckenh8dichen8'), mode: AESMode.ecb),
    ).encrypt('$path-36cd479b6b5-$data-36cd479b6b5-$digest');
    final params = encrypted.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    return CatalogRequest(
      Uri.https(
        'interface.music.163.com',
        path.replaceFirst('/api/', '/eapi/'),
      ),
      headers: {
        'Referer': 'https://music.163.com/',
        'User-Agent': 'Mozilla/5.0',
        'Cookie': cookies.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join('; '),
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: Uri(queryParameters: {'params': params}).query,
    );
  }

  CatalogRequest _kugouRequest(String keyword, int page) {
    final now = '${_clock()}';
    final parameters = {
      'keyword': keyword,
      'page': '$page',
      'pagesize': '$pageSize',
      'platform': 'WebFilter',
      'appid': '1014',
      'srcappid': '2919',
      'clientver': '20000',
      'clienttime': now,
      'mid': now,
      'uuid': now,
      'dfid': '-',
    };
    final keys = parameters.keys.toList()..sort();
    final text = keys.map((key) => '$key=${parameters[key]}').join();
    const salt = 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt';
    parameters['signature'] = md5
        .convert(utf8.encode('$salt$text$salt'))
        .toString();
    return CatalogRequest(
      Uri.https('songsearch.kugou.com', '/song_search_v2', parameters),
      headers: {
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://www.kugou.com/',
      },
    );
  }

  // NetEase search reports only a picId for albums. The CDN path salt is
  // derived from the picId with the same key used by the anonymous login.
  static String _neteaseArtwork(Object? picId) {
    final id = _text(picId);
    if (id.isEmpty || (_number(id) ?? 0) == 0) return '';
    final xor = [
      for (var index = 0; index < id.length; index++)
        id.codeUnitAt(index) ^
            _neteaseMagic.codeUnitAt(index % _neteaseMagic.length),
    ];
    final salt = base64Encode(
      md5.convert(xor).bytes,
    ).replaceAll('/', '_').replaceAll('+', '-');
    return 'https://p1.music.126.net/$salt/$id.jpg';
  }

  SearchPage _neteasePage(Map<String, dynamic> body, int page) {
    if (body['code'] != 200) {
      throw MusicSearchException(tr('网易云暂未返回搜索结果，请稍后重试。'));
    }
    final result = _object(body['result']);
    final songs = _items(result['songs'])
        .map((song) {
          final artists = _items(song['artists'] ?? song['ar']);
          final album = _object(song['album'] ?? song['al']);
          final direct = _text(album['picUrl'] ?? album['blurPicUrl']);
          final artwork = direct.isNotEmpty
              ? (direct.startsWith('http://')
                    ? 'https://${direct.substring(7)}'
                    : direct)
              : _neteaseArtwork(album['picId'] ?? album['pic']);
          return OnlineSong(
            provider: MusicProvider.netease,
            id: _text(song['id']),
            title: _text(song['name']),
            artist: artists.map((artist) => _text(artist['name'])).join(' / '),
            album: _text(album['name']),
            artwork: artwork,
          );
        })
        .where((song) => song.id.isNotEmpty && song.title.isNotEmpty)
        .toList();
    final count = _number(result['songCount']);
    return SearchPage(
      songs: songs,
      hasMore:
          songs.isNotEmpty &&
          (count == null ? songs.length == pageSize : page * pageSize < count),
    );
  }

  SearchPage _kugouPage(Map<String, dynamic> body, int page) {
    if (_number(body['status']) != 1 ||
        (_number(body['error_code']) ?? 0) != 0) {
      throw MusicSearchException(tr('酷狗暂未返回搜索结果，请稍后重试。'));
    }
    final result = _object(body['data']);
    final songs = _items(result['lists'] ?? result['info'])
        .map((song) {
          final hash = _text(song['FileHash'] ?? song['hash']).toLowerCase();
          return OnlineSong(
            provider: MusicProvider.kugou,
            id: _text(song['Audioid'] ?? song['audio_id'] ?? hash),
            hash: hash,
            title: _clean(_text(song['SongName'] ?? song['songname'])),
            artist: _clean(_text(song['SingerName'] ?? song['singername'])),
            album: _clean(_text(song['AlbumName'] ?? song['album_name'])),
            artwork: _text(
              song['Image'] ?? song['img'] ?? song['album_img'],
            ).replaceAll('{size}', '400'),
            albumId: _text(song['AlbumID'] ?? song['album_id']),
            albumAudioId: _text(
              song['MixSongID'] ??
                  song['mixsongid'] ??
                  song['album_audio_id'] ??
                  song['ID'],
            ),
          );
        })
        .where(
          (song) =>
              RegExp(r'^[a-f0-9]{32}$').hasMatch(song.hash) &&
              song.title.isNotEmpty,
        )
        .toList();
    final count = _number(result['total']);
    return SearchPage(
      songs: songs,
      hasMore:
          songs.isNotEmpty &&
          (count == null ? songs.length == pageSize : page * pageSize < count),
    );
  }

  Future<ResolvedAudio> _resolvePlugin(
    OnlineSong song,
    String preferred,
    bool download,
  ) async {
    preferred =
        const {
          'standard': '128k',
          'higher': '192k',
          'exhigh': '320k',
          'lossless': 'flac',
          'hires': 'hires',
        }[preferred] ??
        preferred;
    final choices = <String>{
      preferred,
      if (!download) ...['hires', 'flac', '320k', '128k'],
    };
    for (final quality in choices) {
      final body = await plugin.request('music/url', {
        'source': song.provider.gateway!,
        'musicId': song.id,
        'quality': BuiltinMusicPlugin.quality(quality),
      }, source: _pluginSource(song));
      if (_number(body['code']) != 200 ||
          body['freeTrialInfo'] != null ||
          (_number(body['is_free_part']) ?? 0) > 0) {
        continue;
      }
      final uri = Uri.tryParse(_text(body['url']));
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        continue;
      }
      final returnedQuality = _text(body['quality']);
      final actual = returnedQuality.isEmpty
          ? quality
          : const {
                  'standard': '128k',
                  'higher': '192k',
                  'exhigh': '320k',
                  'lossless': 'flac',
                  'flac24bit': 'hires',
                }[returnedQuality] ??
                returnedQuality;
      if (!const ['128k', '192k', '320k', 'flac', 'hires'].contains(actual) ||
          download && actual != quality) {
        continue;
      }
      return ResolvedAudio(
        uri,
        actual,
        size: _number(body['size']) ?? 0,
        format: _text(body['format']),
        checksum: _text(body['md5']),
      );
    }
    throw AudioUnavailableException(tr('音源服务未返回可用的完整音频。'));
  }

  Future<SearchVideoPage> searchVideos(
    MusicProvider provider,
    String keyword,
    int page,
  ) async {
    keyword = keyword.trim();
    if (keyword.isEmpty || keyword.length > 200 || page < 1) {
      throw MusicSearchException(tr('请输入 1–200 字的关键词。'));
    }
    final body = await plugin.request('music/mv/search', {
      'platform': BuiltinMusicPlugin.platformFor(provider),
      'keyword': keyword,
      'page': '$page',
      'limit': '$pageSize',
    });
    if (_number(body['code']) != 200) {
      throw MusicSearchException(tr('内置插件未返回 MV 搜索结果，请稍后重试。'));
    }
    final videos = _items(body['data'])
        .map(
          (item) => MusicVideo(
            provider: provider,
            id: _text(item['id']),
            title: _text(item['title']),
            artist: _text(item['artist']),
            artwork: _text(item['artwork']),
          ),
        )
        .where((video) => video.id.isNotEmpty && video.title.isNotEmpty)
        .toList();
    return SearchVideoPage(videos, videos.isNotEmpty && body['isEnd'] == false);
  }

  Future<Uri> videoUrl(MusicVideo video) async {
    final platform = BuiltinMusicPlugin.platformFor(video.provider);
    final body = await plugin.request('music/mv/url', {
      'platform': platform,
      'id': video.id,
      'quality': BuiltinMusicPlugin.videoQuality(platform),
    });
    final uri = Uri.tryParse(_text(body['url']));
    if (_number(body['code']) != 200 ||
        uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw MusicSearchException(tr('MV 服务未返回可播放的视频。'));
    }
    return uri;
  }

  static Map<String, dynamic> _object(Object? value) =>
      value is Map<String, dynamic> ? value : const {};
  static List<Map<String, dynamic>> _items(Object? value) =>
      value is List ? value.whereType<Map<String, dynamic>>().toList() : [];
  static String _text(Object? value) => value?.toString() ?? '';
  static int? _number(Object? value) => int.tryParse(_text(value));
  static String _clean(String value) =>
      value.replaceAll(RegExp(r'</?em>', caseSensitive: false), '');
}

class _NativeAudioChoices {
  const _NativeAudioChoices(this.choices, this.checkSession);
  final Map<String, String> choices;
  final void Function() checkSession;
}
