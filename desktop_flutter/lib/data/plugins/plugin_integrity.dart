import '../../i18n/tr.dart';
import 'dart:convert';

import 'package:crypto/crypto.dart';

void verifyPluginChecksum(String script, Object? expected) {
  if (expected == null) return;
  final digest = sha256.convert(utf8.encode(script));
  final valid =
      expected is String &&
      (RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(expected)
          ? digest.toString() == expected.toLowerCase()
          : expected == 'sha256-${base64Encode(digest.bytes)}');
  if (!valid) throw       FormatException(tr('音源脚本 SHA256 校验失败，已停止导入。'));
}
