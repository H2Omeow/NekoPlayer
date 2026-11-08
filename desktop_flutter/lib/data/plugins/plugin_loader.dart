import '../../i18n/tr.dart';
import 'dart:convert';

import '../../domain/music_plugin.dart';
import 'plugin_runtime.dart';

class PluginLoader {
  PluginLoader(this.runtime);
  final PluginScriptRuntime runtime;

  Future<MusicPluginSource> inspect(
    String script,
    Uri url, {
    bool builtin = false,
    String? format,
  }) async {
    if (utf8.encode(script).length > 5 * 1024 * 1024) {
      throw       FormatException(tr('音源脚本超过 5 MiB。'));
    }
    if (RegExp(r'\b(?:const|let|var)\s+META\s*=').hasMatch(script)) {
      Map<String, dynamic>? meta;
      try {
        meta = parsePluginMeta(script);
      } on FormatException catch (_) {}
      if (meta?['format'] == 'animemusic/1') {
        return MusicPluginSource.fromMeta(meta!, url, builtin: builtin);
      }
    }
    final meta = await runtime.inspect(script, url, format: format);
    return MusicPluginSource.fromScript(meta, url, script);
  }
}

Map<String, dynamic> parsePluginMeta(String script) {
  final assignment = RegExp(
    r'\b(?:const|let|var)\s+META\s*=\s*',
  ).firstMatch(script);
  if (assignment == null ||
      assignment.end >= script.length ||
      script[assignment.end] != '{') {
    throw       FormatException(tr('插件缺少有效 META。'));
  }
  var depth = 0;
  var quoted = false;
  var escaped = false;
  for (var index = assignment.end; index < script.length; index++) {
    final character = script[index];
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (character == r'\') {
        escaped = true;
      } else if (character == '"') {
        quoted = false;
      }
    } else if (character == '"') {
      quoted = true;
    } else if (character == '{') {
      depth++;
    } else if (character == '}' && --depth == 0) {
      final meta = jsonDecode(script.substring(assignment.end, index + 1));
      if (meta is Map<String, dynamic>) return meta;
      break;
    }
  }
  throw FormatException(tr('插件 META 必须是完整的 JSON 对象。'));
}
