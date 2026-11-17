import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// B 站视频模块的网络与数据层。
///
/// 桌面端直接走 B 站的公开 Web 接口，不依赖 JS 插件：
/// * 搜索 / 详情 / 相关推荐 / 热门走 `x/web-interface/*`；
/// * 取流走 `x/player/wbi/playurl`（`fnval=1` 拿 mp4 直链，mpv 可直接放）；
/// * 弹幕走 `x/v2/dm/web/seg.so`，返回 protobuf，这里手写解码（不引第三方）。
///
/// wbi 签名（`w_rid`）只在少数接口上强制，但带上更稳，所以统一加。

class BiliVideo {
  const BiliVideo({
    required this.bvid,
    required this.aid,
    required this.title,
    required this.cover,
    required this.upName,
    this.upFace = '',
    this.durationSec = 0,
    this.views = 0,
    this.danmakuCount = 0,
    this.pubdate = 0,
  });

  final String bvid;
  final int aid;
  final String title;
  final String cover;
  final String upName;
  final String upFace;
  final int durationSec;
  final int views;
  final int danmakuCount;
  final int pubdate;

  BiliVideo copyWith({String? title, String? cover}) => BiliVideo(
    bvid: bvid,
    aid: aid,
    title: title ?? this.title,
    cover: cover ?? this.cover,
    upName: upName,
    upFace: upFace,
    durationSec: durationSec,
    views: views,
    danmakuCount: danmakuCount,
    pubdate: pubdate,
  );
}

class BiliDetail {
  const BiliDetail({
    required this.video,
    required this.cid,
    required this.desc,
    required this.tname,
  });

  final BiliVideo video;
  final int cid;
  final String desc;
  final String tname;
}

class BiliDanmaku {
  const BiliDanmaku({
    required this.progressMs,
    required this.mode,
    required this.fontSize,
    required this.color,
    required this.content,
    this.weight = 1,
  });

  final int progressMs;
  final int mode;
  final int fontSize;
  final int color;
  final String content;
  final int weight;
}

class BiliPlaySource {
  const BiliPlaySource({
    required this.url,
    required this.quality,
    required this.label,
    required this.acceptQuality,
    required this.acceptLabels,
  });

  final String url;
  final int quality;
  final String label;
  final List<int> acceptQuality;
  final List<String> acceptLabels;
}

class BiliAccount {
  const BiliAccount({
    this.mid = 0,
    this.name = '',
    this.face = '',
    this.isLogin = false,
  });

  final int mid;
  final String name;
  final String face;
  final bool isLogin;

  static const guest = BiliAccount();
}

class BiliQrTicket {
  const BiliQrTicket(this.key, this.url);
  final String key;
  final String url;
}

enum BiliQrState { waiting, scanned, success, expired }

class BiliQrPoll {
  const BiliQrPoll(this.state, {this.message = ''});
  final BiliQrState state;
  final String message;
}

class BiliException implements Exception {
  const BiliException(this.message, [this.code = -1]);
  final String message;
  final int code;

  @override
  String toString() => message;
}

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/// 登录态：Cookie 存在 SharedPreferences 里（明文，仅本机）。
class BiliSession {
  BiliSession._();
  static final BiliSession instance = BiliSession._();

  static const _keyCookie = 'bili_cookie';
  static const _keyMid = 'bili_mid';
  static const _keyName = 'bili_name';
  static const _keyFace = 'bili_face';

  SharedPreferences? _prefs;
  BiliAccount account = BiliAccount.guest;
  final _changes = StreamController<BiliAccount>.broadcast();

  Stream<BiliAccount> get changes => _changes.stream;

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    account = BiliAccount(
      mid: _prefs!.getInt(_keyMid) ?? 0,
      name: _prefs!.getString(_keyName) ?? '',
      face: _prefs!.getString(_keyFace) ?? '',
      isLogin: (_prefs!.getString(_keyCookie) ?? '').isNotEmpty,
    );
    _changes.add(account);
  }

  String get cookieHeader => _prefs?.getString(_keyCookie) ?? '';

  String cookieValue(String key) {
    for (final part in cookieHeader.split(';')) {
      final trimmed = part.trim();
      final at = trimmed.indexOf('=');
      if (at <= 0) continue;
      if (trimmed.substring(0, at) == key) return trimmed.substring(at + 1);
    }
    return '';
  }

  String get csrf => cookieValue('bili_jct');

  Future<void> saveAccount(BiliAccount next) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_keyMid, next.mid);
    await _prefs!.setString(_keyName, next.name);
    await _prefs!.setString(_keyFace, next.face);
    account = next;
    _changes.add(account);
  }

  /// 扫码成功后由 Set-Cookie 拼出来，或由用户手动粘贴。
  Future<void> mergeCookies(Map<String, String> cookies) async {
    _prefs ??= await SharedPreferences.getInstance();
    final merged = <String, String>{
      for (final part in cookieHeader.split(';'))
        if (part.trim().contains('='))
          part.trim().substring(0, part.trim().indexOf('=')): part
              .trim()
              .substring(part.trim().indexOf('=') + 1),
      ...cookies,
    };
    final header = merged.entries.map((e) => '${e.key}=${e.value}').join('; ');
    await _prefs!.setString(_keyCookie, header);
    account = BiliAccount(
      mid: int.tryParse(merged['DedeUserID'] ?? '') ?? account.mid,
      name: account.name,
      face: account.face,
      isLogin: header.isNotEmpty,
    );
    _changes.add(account);
  }

  Future<void> importCookie(String raw) async {
    _prefs ??= await SharedPreferences.getInstance();
    final cleaned = raw
        .replaceAll('\n', ';')
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.contains('='))
        .join('; ');
    await _prefs!.setString(_keyCookie, cleaned);
    account = BiliAccount(
      mid: int.tryParse(cookieValue('DedeUserID')) ?? 0,
      name: account.name,
      face: account.face,
      isLogin: cleaned.isNotEmpty,
    );
    _changes.add(account);
  }

  Future<void> logout() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove(_keyCookie);
    await _prefs!.remove(_keyMid);
    await _prefs!.remove(_keyName);
    await _prefs!.remove(_keyFace);
    account = BiliAccount.guest;
    _changes.add(account);
  }
}

/// wbi 签名的固定置换表。
const _mixinKeyEncTab = <int>[
  46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, //
  27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
  37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
  22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
];

class BiliClient {
  BiliClient({HttpClient? client}) : _client = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 12));

  final HttpClient _client;
  final BiliSession _session = BiliSession.instance;

  String _mixinKey = '';
  DateTime _mixinFetched = DateTime.fromMillisecondsSinceEpoch(0);

  Map<String, String> get _baseHeaders => {
    'User-Agent': _userAgent,
    'Referer': 'https://www.bilibili.com/',
    'Origin': 'https://www.bilibili.com',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9',
  };

  Map<String, String> get _cookieHeaders {
    final cookie = _session.cookieHeader;
    return cookie.isEmpty ? const {} : {'Cookie': cookie};
  }

  Future<void> refreshAccount() async {
    try {
      final nav = await _getJson('https://api.bilibili.com/x/web-interface/nav', signed: false);
      final data = nav['data'];
      if (data is Map) {
        await _session.saveAccount(
          BiliAccount(
            mid: (data['mid'] as num?)?.toInt() ?? 0,
            name: (data['uname'] as String?) ?? '',
            face: normalizeUrl((data['face'] as String?) ?? ''),
            isLogin: data['isLogin'] == true,
          ),
        );
      }
    } catch (_) {
      // 游客态拉 nav 失败不影响浏览
    }
  }

  Future<List<BiliVideo>> search(String keyword, {int page = 1, String order = 'totalrank'}) async {
    if (keyword.trim().isEmpty) return const [];
    final url =
        'https://api.bilibili.com/x/web-interface/wbi/search/type'
        '?search_type=video&keyword=${Uri.encodeQueryComponent(keyword)}'
        '&page=$page&order=$order';
    final body = await _getJson(url, signed: true);
    final data = body['data'];
    if (data is! Map) throw const BiliException('搜索无结果');
    final result = data['result'];
    if (result is! List) return const [];
    return result
        .whereType<Map>()
        .map(_videoFromSearch)
        .where((v) => v.bvid.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<BiliVideo>> popular({int page = 1}) async {
    final uri = Uri.parse('https://api.bilibili.com/x/web-interface/popular?ps=20&pn=$page');
    final body = await _getJson(uri.toString(), signed: false);
    final list = body['data']?['list'];
    if (list is! List) return const [];
    return list.whereType<Map>().map(_videoFromSearch).toList(growable: false);
  }

  Future<BiliDetail> detail(String bvid) async {
    final body = await _getJson(
      'https://api.bilibili.com/x/web-interface/wbi/view?bvid=$bvid',
      signed: true,
    );
    final data = body['data'];
    if (data is! Map) throw const BiliException('视频信息获取失败');
    final owner = data['owner'] as Map?;
    final stat = data['stat'] as Map?;
    final video = BiliVideo(
      bvid: (data['bvid'] as String?) ?? bvid,
      aid: (data['aid'] as num?)?.toInt() ?? 0,
      title: cleanTitle((data['title'] as String?) ?? ''),
      cover: normalizeUrl((data['pic'] as String?) ?? ''),
      upName: (owner?['name'] as String?) ?? '',
      upFace: normalizeUrl((owner?['face'] as String?) ?? ''),
      durationSec: (data['duration'] as num?)?.toInt() ?? 0,
      views: (stat?['view'] as num?)?.toInt() ?? 0,
      danmakuCount: (stat?['danmaku'] as num?)?.toInt() ?? 0,
      pubdate: (data['pubdate'] as num?)?.toInt() ?? 0,
    );
    return BiliDetail(
      video: video,
      cid: (data['cid'] as num?)?.toInt() ?? 0,
      desc: (data['desc'] as String?) ?? '',
      tname: (data['tname'] as String?) ?? '',
    );
  }

  Future<List<BiliVideo>> related(String bvid) async {
    final body = await _getJson(
      'https://api.bilibili.com/x/web-interface/archive/related?bvid=$bvid',
      signed: false,
    );
    final list = body['data'];
    if (list is! List) return const [];
    return list.whereType<Map>().map(_videoFromSearch).toList(growable: false);
  }

  Future<BiliPlaySource> playUrl(String bvid, int cid, {int qn = 80}) async {
    final body = await _getJson(
      'https://api.bilibili.com/x/player/wbi/playurl'
      '?bvid=$bvid&cid=$cid&qn=$qn&fnval=1&fnver=0&fourk=1',
      signed: true,
    );
    final data = body['data'];
    if (data is! Map) throw const BiliException('取播放地址失败（可能需要登录或视频受限）');
    final durl = data['durl'];
    String url = '';
    if (durl is List && durl.isNotEmpty && durl.first is Map) {
      url = normalizeUrl(((durl.first as Map)['url'] as String?) ?? '');
    }
    if (url.isEmpty) throw const BiliException('该视频暂无可用直链');
    final quality = (data['quality'] as num?)?.toInt() ?? qn;
    final accepts = (data['accept_quality'] as List?)?.map((e) => (e as num).toInt()).toList() ?? const <int>[];
    final labels = (data['accept_description'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    return BiliPlaySource(
      url: url,
      quality: quality,
      label: qualityLabel(quality),
      acceptQuality: accepts,
      acceptLabels: labels,
    );
  }

  Future<List<BiliDanmaku>> danmaku(int cid, int aid, {int segment = 1}) async {
    final uri = Uri.parse(
      'https://api.bilibili.com/x/v2/dm/web/seg.so'
      '?type=1&oid=$cid&pid=$aid&segment_index=$segment',
    );
    final bytes = await _getBytes(uri.toString());
    return parseDanmaku(bytes);
  }

  /// 6 分钟一段，整片最多拉 60 段。
  Future<List<BiliDanmaku>> allDanmaku(int cid, int aid, int durationSec) async {
    final segments = ((durationSec + 359) ~/ 360).clamp(1, 60);
    final out = <BiliDanmaku>[];
    for (var i = 1; i <= segments; i++) {
      try {
        out.addAll(await danmaku(cid, aid, segment: i));
      } catch (_) {
        // 单段失败忽略，别让整片弹幕都消失
      }
    }
    out.sort((a, b) => a.progressMs.compareTo(b.progressMs));
    return out;
  }

  Future<BiliQrTicket> qrGenerate() async {
    final body = await _getJson(
      'https://passport.bilibili.com/x/passport-login/web/qrcode/generate',
      signed: false,
    );
    final data = body['data'];
    if (data is! Map) throw const BiliException('二维码生成失败');
    return BiliQrTicket(
      (data['qrcode_key'] as String?) ?? '',
      (data['url'] as String?) ?? '',
    );
  }

  Future<BiliQrPoll> qrPoll(String key) async {
    final uri = Uri.parse(
      'https://passport.bilibili.com/x/passport-login/web/qrcode/poll'
      '?qrcode_key=$key&source=main-fe-header',
    );
    final response = await _send(uri, signed: false);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as Map?;
    final code = (data?['code'] as num?)?.toInt() ?? -1;
    switch (code) {
      case 0:
        final cookies = <String, String>{};
        for (final cookie in response.cookies) {
          cookies[cookie.name] = cookie.value;
        }
        if (cookies.isNotEmpty) {
          await _session.mergeCookies(cookies);
          await refreshAccount();
        }
        return const BiliQrPoll(BiliQrState.success);
      case 86101:
        return const BiliQrPoll(BiliQrState.waiting, message: '等待扫码');
      case 86090:
        return const BiliQrPoll(BiliQrState.scanned, message: '已扫码，请在手机上确认');
      case 86038:
        return const BiliQrPoll(BiliQrState.expired, message: '二维码已失效');
      default:
        return BiliQrPoll(BiliQrState.expired, message: '登录失败（$code）');
    }
  }

  Future<bool> postDanmaku({
    required int cid,
    required int aid,
    required String content,
    required int progressMs,
    int mode = 1,
    int fontSize = 25,
    int color = 0xFFFFFF,
  }) async {
    final csrf = _session.csrf;
    if (csrf.isEmpty) return false;
    final body = {
      'type': '1',
      'oid': '$cid',
      'msg': content,
      'progress': '$progressMs',
      'mode': '$mode',
      'fontsize': '$fontSize',
      'color': '$color',
      'csrf': csrf,
    };
    final response = await _send(
      Uri.parse('https://api.bilibili.com/x/v2/dm/post'),
      signed: false,
      method: 'POST',
      form: body,
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['code'] == 0;
  }

  // ==================== 内部 ====================

  BiliVideo _videoFromSearch(Map raw) {
    final aid = (raw['aid'] as num?)?.toInt() ??
        (raw['id'] as num?)?.toInt() ??
        0;
    final duration = raw['duration'];
    return BiliVideo(
      bvid: (raw['bvid'] as String?) ?? '',
      aid: aid,
      title: cleanTitle((raw['title'] as String?) ?? ''),
      cover: normalizeUrl((raw['pic'] as String?) ?? ''),
      upName: (raw['author'] as String?) ?? (raw['owner']?['name'] as String?) ?? '',
      durationSec: duration is num ? duration.toInt() : parseDuration(duration?.toString() ?? ''),
      views: (raw['play'] as num?)?.toInt() ?? 0,
      danmakuCount: (raw['video_review'] as num?)?.toInt() ?? 0,
      pubdate: (raw['pubdate'] as num?)?.toInt() ?? 0,
    );
  }

  Future<Map<String, dynamic>> _getJson(String url, {required bool signed}) async {
    final uri = Uri.parse(url);
    final finalUri = signed ? await _signed(uri) : uri;
    final response = await _send(finalUri, signed: false);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final code = (body['code'] as num?)?.toInt() ?? 0;
    if (code != 0 && code != -101) {
      throw BiliException((body['message'] as String?) ?? '请求失败（$code）', code);
    }
    return body;
  }

  Future<List<int>> _getBytes(String url) async {
    final response = await _send(Uri.parse(url), signed: false, binary: true);
    return response.bytes;
  }

  Future<_BiliResponse> _send(
    Uri uri, {
    required bool signed,
    String method = 'GET',
    Map<String, String>? form,
    bool binary = false,
  }) async {
    final request = await _client.openUrl(method, uri);
    request.followRedirects = false;
    _baseHeaders.forEach(request.headers.set);
    _cookieHeaders.forEach(request.headers.set);
    if (form != null) {
      final payload = form.entries
          .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      request.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
      request.write(payload);
    }
    final response = await request.close();
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > 8 * 1024 * 1024) throw const BiliException('响应过大');
    }
    if (response.statusCode != 200 && !binary) {
      throw BiliException('HTTP ${response.statusCode}');
    }
    return _BiliResponse(
      body: binary ? '' : utf8.decode(bytes, allowMalformed: true),
      bytes: bytes,
      cookies: response.cookies,
    );
  }

  Future<Uri> _signed(Uri uri) async {
    final key = await _ensureMixinKey();
    if (key.isEmpty) return uri;
    final params = <String, String>{
      for (final entry in uri.queryParameters.entries) entry.key: entry.value,
    };
    params['wts'] = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final sorted = params.keys.toList()..sort();
    final query = sorted
        .map((k) => '$k=${Uri.encodeQueryComponent(params[k]!)}')
        .join('&');
    final rid = md5.convert(utf8.encode('$query$key')).toString();
    return uri.replace(query: '$query&w_rid=$rid');
  }

  Future<String> _ensureMixinKey() async {
    if (_mixinKey.isNotEmpty &&
        DateTime.now().difference(_mixinFetched) < const Duration(hours: 6)) {
      return _mixinKey;
    }
    try {
      final body = await _getJson('https://api.bilibili.com/x/web-interface/nav', signed: false);
      final wbi = body['data']?['wbi_img'];
      if (wbi is! Map) return _mixinKey;
      final img = keyFromUrl((wbi['img_url'] as String?) ?? '');
      final sub = keyFromUrl((wbi['sub_url'] as String?) ?? '');
      final raw = '$img$sub';
      if (raw.length < 64) return _mixinKey;
      final buffer = StringBuffer();
      for (var i = 0; i < 32; i++) {
        buffer.write(raw[_mixinKeyEncTab[i]]);
      }
      _mixinKey = buffer.toString();
      _mixinFetched = DateTime.now();
      return _mixinKey;
    } catch (_) {
      return _mixinKey;
    }
  }
}

class _BiliResponse {
  const _BiliResponse({required this.body, required this.bytes, required this.cookies});
  final String body;
  final List<int> bytes;
  final List<Cookie> cookies;
}

String keyFromUrl(String url) {
  final file = url.split('/').last;
  final dot = file.indexOf('.');
  return dot < 0 ? file : file.substring(0, dot);
}

String normalizeUrl(String raw) {
  if (raw.isEmpty) return raw;
  if (raw.startsWith('//')) return 'https:$raw';
  return raw;
}

/// 搜索结果的标题里带 `<em class="keyword">` 高亮标签，去掉。
String cleanTitle(String raw) => raw
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');

int parseDuration(String raw) {
  if (raw.isEmpty) return 0;
  final parts = raw.split(':').map((e) => int.tryParse(e.trim()) ?? 0).toList();
  return switch (parts.length) {
    3 => parts[0] * 3600 + parts[1] * 60 + parts[2],
    2 => parts[0] * 60 + parts[1],
    1 => parts[0],
    _ => 0,
  };
}

String formatDuration(int seconds) {
  if (seconds <= 0) return '00:00';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

String qualityLabel(int qn) => switch (qn) {
  127 => '8K',
  126 => '杜比视界',
  125 => 'HDR',
  120 => '4K',
  116 => '1080P60',
  112 => '1080P+',
  80 => '1080P',
  74 => '720P60',
  64 => '720P',
  32 => '480P',
  16 => '360P',
  _ => '${qn}P',
};

String formatCount(int value) {
  if (value >= 100000000) return '${(value / 100000000).toStringAsFixed(1)}亿';
  if (value >= 10000) return '${(value / 10000).toStringAsFixed(1)}万';
  return '$value';
}

// ==================== 弹幕 protobuf 解码 ====================

List<BiliDanmaku> parseDanmaku(List<int> bytes) {
  final out = <BiliDanmaku>[];
  final reader = _ProtoReader(bytes);
  while (!reader.done) {
    final tag = reader.varint();
    final field = tag >> 3;
    final wire = tag & 7;
    if (field == 1 && wire == 2) {
      final parsed = _parseDanmakuElem(reader.lengthDelimited());
      if (parsed != null && parsed.content.isNotEmpty) out.add(parsed);
    } else {
      reader.skip(wire);
    }
  }
  return out;
}

BiliDanmaku? _parseDanmakuElem(List<int> bytes) {
  var progress = 0;
  var mode = 1;
  var fontSize = 25;
  var color = 0xFFFFFF;
  var weight = 1;
  var content = '';
  final reader = _ProtoReader(bytes);
  while (!reader.done) {
    final tag = reader.varint();
    final field = tag >> 3;
    final wire = tag & 7;
    switch (field) {
      case 2:
        progress = reader.varint();
      case 3:
        mode = reader.varint();
      case 4:
        fontSize = reader.varint();
      case 5:
        color = reader.varint();
      case 7:
        content = utf8.decode(reader.lengthDelimited(), allowMalformed: true);
      case 9:
        weight = reader.varint();
      default:
        reader.skip(wire);
    }
  }
  if (mode >= 7 && mode <= 9) return null; // 高级/代码弹幕本期不支持
  return BiliDanmaku(
    progressMs: progress,
    mode: mode,
    fontSize: fontSize,
    color: color,
    content: content,
    weight: weight,
  );
}

class _ProtoReader {
  _ProtoReader(this.bytes);

  final List<int> bytes;
  int offset = 0;

  bool get done => offset >= bytes.length;

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (offset >= bytes.length) throw const FormatException('truncated varint');
      final byte = bytes[offset++];
      result |= (byte & 0x7F) << shift;
      if (byte & 0x80 == 0) return result;
      shift += 7;
      if (shift > 63) throw const FormatException('varint too long');
    }
  }

  /// 读一个 length-delimited 字段的载荷（先读长度，再切片）。
  List<int> lengthDelimited() {
    final length = varint();
    final start = offset;
    offset += length;
    if (offset > bytes.length) throw const FormatException('truncated bytes');
    return bytes.sublist(start, offset);
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        offset += 8;
      case 2:
        final length = varint();
        offset += length;
      case 5:
        offset += 4;
      default:
        throw FormatException('unsupported wire type $wire');
    }
    if (offset > bytes.length) throw const FormatException('truncated');
  }
}
