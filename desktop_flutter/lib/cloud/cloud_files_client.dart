import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../i18n/tr.dart';

/// 云存储 / 赞赏 / 森空岛绑定接口（桌面端）。
///
/// 请求发到 player.nekoh2o.top，带本站账号的 Bearer token；对象直传地址是
/// 雨云 ROS 域名，不带 token。
class CloudException implements Exception {
  const CloudException(this.code, this.message, {this.needSkland = false});
  final int code;
  final String message;
  final bool needSkland;
  @override
  String toString() => message;
}

class CloudFile {
  const CloudFile({
    required this.id,
    required this.name,
    required this.size,
    required this.category,
    required this.createdAt,
  });
  final String id;
  final String name;
  final int size;
  final String category;
  final int createdAt;

  factory CloudFile.fromJson(Map<String, dynamic> json) => CloudFile(
    id: '${json['id']}',
    name: '${json['name'] ?? ''}',
    size: (json['size'] as num?)?.toInt() ?? 0,
    category: '${json['category'] ?? ''}',
    createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
  );
}

class CloudQuota {
  const CloudQuota(this.storageBytes, this.trafficBytes, this.fileCount);
  final int storageBytes;
  final int trafficBytes;
  final int fileCount;
}

class CloudUsage {
  const CloudUsage(this.storageBytes, this.trafficBytes, this.filesCount);
  final int storageBytes;
  final int trafficBytes;
  final int filesCount;
}

class CloudOrder {
  const CloudOrder({
    required this.id,
    required this.tier,
    required this.months,
    required this.status,
    required this.amount,
    required this.createdAt,
  });
  final String id;
  final String tier;
  final int months;
  final String status;
  final num amount;
  final int createdAt;
}

class CloudTier {
  const CloudTier({
    required this.id,
    required this.label,
    required this.price,
    required this.storageBytes,
    required this.trafficBytes,
  });
  final String id;
  final String label;
  final num price;
  final int storageBytes;
  final int trafficBytes;
}

class SklandTicket {
  const SklandTicket(this.sid, this.url);
  final String sid;
  final String url;
}

class CloudFilesClient {
  CloudFilesClient({required String Function() token}) : _token = token;

  static const _base = 'https://player.nekoh2o.top';
  static const _account = 'https://account.nekoh2o.top';
  static const partSize = 5 * 1024 * 1024;

  final String Function() _token;

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
    String base = _base,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final uri = Uri.parse('$base$path');
      final request = await client.openUrl(method, uri);
      request.followRedirects = false;
      if (auth) {
        final value = _token();
        if (value.isEmpty) throw const CloudException(401, '请先登录 NekoPlayer 账号');
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $value');
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      if (text.isEmpty) {
        if (response.statusCode >= 400) {
          throw CloudException(response.statusCode, '请求失败（HTTP ${response.statusCode}）');
        }
        return {'code': 0};
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const CloudException(500, '响应格式异常');
      }
      final code = (decoded['code'] as num?)?.toInt() ?? 0;
      if (code != 0 || response.statusCode >= 400) {
        throw CloudException(
          code != 0 ? code : response.statusCode,
          '${decoded['msg'] ?? decoded['message'] ?? '请求失败'}',
          needSkland: decoded['needSkland'] == true,
        );
      }
      final data = decoded['data'];
      return data is Map<String, dynamic> ? data : decoded;
    } on SocketException {
      throw const CloudException(0, '无法连接服务器，请检查网络');
    } finally {
      client.close(force: true);
    }
  }

  Future<({List<CloudFile> files, CloudQuota? quota, CloudUsage? usage})> files() async {
    final body = await _json('GET', '/files');
    final data = body['data'];
    final files = <CloudFile>[
      if (data is List)
        for (final item in data)
          if (item is Map<String, dynamic>) CloudFile.fromJson(item),
    ];
    final quota = body['quota'];
    final usage = body['usage'];
    return (
      files: files,
      quota: quota is Map<String, dynamic>
          ? CloudQuota(
              (quota['storageBytes'] as num?)?.toInt() ?? 0,
              (quota['trafficBytes'] as num?)?.toInt() ?? 0,
              (quota['fileCount'] as num?)?.toInt() ?? 0,
            )
          : null,
      usage: usage is Map<String, dynamic>
          ? CloudUsage(
              (usage['storage_bytes'] as num?)?.toInt() ?? 0,
              (usage['traffic_bytes'] as num?)?.toInt() ?? 0,
              (usage['files_count'] as num?)?.toInt() ?? 0,
            )
          : null,
    );
  }

  Future<void> delete(String id) async {
    await _json('DELETE', '/files/$id');
  }

  Future<Map<String, dynamic>> share(String id, String mode, int days) =>
      _json('POST', '/files/$id/share', body: {'mode': mode, 'expiresDays': days});

  Future<List<CloudTier>> pricing() async {
    final body = await _json('GET', '/pricing', auth: false);
    final tiers = body['tiers'];
    return [
      if (tiers is List)
        for (final item in tiers)
          if (item is Map<String, dynamic>)
            CloudTier(
              id: '${item['id']}',
              label: '${item['label'] ?? ''}',
              price: (item['price'] as num?) ?? 0,
              storageBytes: (item['storageBytes'] as num?)?.toInt() ?? 0,
              trafficBytes: (item['trafficBytes'] as num?)?.toInt() ?? 0,
            ),
    ];
  }

  Future<List<CloudOrder>> myOrders() async {
    final body = await _json('GET', '/orders/mine');
    final data = body['data'] ?? body['orders'];
    return [
      if (data is List)
        for (final item in data)
          if (item is Map<String, dynamic>)
            CloudOrder(
              id: '${item['id']}',
              tier: '${item['tier']}',
              months: (item['months'] as num?)?.toInt() ?? 1,
              status: '${item['status']}',
              amount: (item['amount'] as num?) ?? 0,
              createdAt: (item['created_at'] as num?)?.toInt() ?? 0,
            ),
    ];
  }

  Future<String> createOrder(String tier, int months) async {
    final body = await _json('POST', '/orders', body: {'tier': tier, 'months': months});
    return '${body['id']}';
  }

  Future<void> uploadReceipt(String orderId, List<int> bytes, String mime) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('$_base/orders/$orderId/receipt'));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${_token()}');
      request.headers.contentType = MediaType('image', mime.split('/').last);
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode >= 400) {
        throw CloudException(response.statusCode, '凭证上传失败');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<SklandTicket> sklandStart() async {
    final body = await _json('POST', '/auth/skland/start', body: const {}, base: _account);
    return SklandTicket('${body['sid']}', '${body['url']}');
  }

  Future<String> sklandPoll(String sid) async {
    final body = await _json('GET', '/auth/skland/poll?sid=$sid', base: _account);
    return '${body['state']}';
  }

  /// 上传本地文件，小文件直传，大文件走 5MB 分片。
  Future<void> upload(
    String path,
    String name,
    String category, {
    void Function(double progress)? onProgress,
  }) async {
    final file = File(path);
    final size = await file.length();
    if (size <= partSize) {
      final body = await _json('POST', '/files/upload-url', body: {
        'name': name,
        'size': size,
        'category': category,
      });
      final fileId = '${body['fileId']}';
      await _putBytes('${body['uploadUrl']}', await file.readAsBytes(), 'application/octet-stream');
      onProgress?.call(0.95);
      await _json('POST', '/files/complete', body: {'fileId': fileId});
      onProgress?.call(1);
      return;
    }

    final init = await _json('POST', '/files/multipart', body: {
      'name': name,
      'size': size,
      'category': category,
    });
    final fileId = '${init['fileId']}';
    final partCount = (init['partCount'] as num).toInt();
    final chunkSize = (init['partSize'] as num?)?.toInt() ?? partSize;
    final parts = <Map<String, dynamic>>[];
    try {
      for (var index = 0; index < partCount; index++) {
        final start = index * chunkSize;
        final end = (start + chunkSize).clamp(0, size);
        final raf = await file.open();
        await raf.setPosition(start);
        final chunk = await raf.read(end - start);
        await raf.close();
        final part = await _json('GET', '/files/multipart/$fileId/part/${index + 1}');
        final etag = await _putBytes('${part['url']}', chunk, 'application/octet-stream');
        parts.add({'partNumber': index + 1, 'etag': etag});
        onProgress?.call((index + 1) / partCount * 0.95);
      }
      await _json('POST', '/files/multipart/$fileId/complete', body: {'parts': parts});
      onProgress?.call(1);
    } catch (error) {
      unawaited(_json('POST', '/files/multipart/$fileId/abort').catchError((_) => <String, dynamic>{}));
      rethrow;
    }
  }

  Future<String> _putBytes(String url, List<int> bytes, String mime) async {
    final client = HttpClient();
    try {
      final request = await client.putUrl(Uri.parse(url));
      request.headers.contentType = ContentType.parse(mime);
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode >= 400) {
        throw CloudException(response.statusCode, '上传失败（HTTP ${response.statusCode}）');
      }
      return response.headers.value('etag') ?? '';
    } finally {
      client.close(force: true);
    }
  }
}

String formatCloudBytes(int bytes) {
  if (bytes <= 0) return '0B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  return index == 0
      ? '${value.toStringAsFixed(0)}${units[index]}'
      : '${value.toStringAsFixed(value >= 100 ? 0 : 1)}${units[index]}';
}

String cloudDateLabel(int ms) {
  if (ms <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

String cloudOrderStatus(String status) => switch (status) {
  'pending' => tr('待审核'),
  'approved' => tr('已开通'),
  'rejected' => tr('已驳回'),
  _ => status,
};
