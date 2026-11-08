import '../i18n/tr.dart';
import 'dart:convert';

import 'package:crypto/crypto.dart';

Uri pluginHttpsUri(String value) {
  var uri = Uri.tryParse(value.trim());
  if (uri?.host == 'animemusic.bzxhkj.com' && uri?.scheme == 'http') {
    uri = uri!.replace(scheme: 'https');
  }
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      uri.toString().length > 4096) {
    throw       FormatException(tr('插件地址必须是无账号密码的 HTTPS 链接。'));
  }
  return uri;
}

class MusicPluginSource {
  const MusicPluginSource({
    required this.id,
    required this.url,
    required this.api,
    required this.platform,
    required this.name,
    required this.version,
    required this.author,
    required this.capabilities,
    this.builtin = false,
    this.format = 'animemusic/1',
    this.script = '',
    this.qualities = const [],
    this.lxSources = const {},
    this.variables = const {},
    this.userVariables = const [],
    this.supportedPlatforms = const [],
  });

  final String id;
  final Uri url;
  final Uri api;
  final String platform;
  final String name;
  final String version;
  final String author;
  final List<String> capabilities;
  final bool builtin;
  final String format;
  final String script;
  final List<String> qualities;
  final Map<String, dynamic> lxSources;
  final Map<String, String> variables;
  final List<Map<String, dynamic>> userVariables;
  final List<String> supportedPlatforms;
  bool get scripted => format != 'animemusic/1';
  bool get lx => format == 'lx';

  static String externalId(Uri url) =>
      'plugin-${sha256.convert(utf8.encode(url.toString()))}';

  factory MusicPluginSource.fromScript(
    Map<String, dynamic> meta,
    Uri url,
    String script, {
    Map<String, String> variables = const {},
    bool reference = false,
  }) {
    final format = meta['format'];
    final platform = '${meta['platform'] ?? ''}'.trim();
    final name = '${meta['name'] ?? platform}'.trim();
    if (!const {'musicfree', 'baka', 'lx'}.contains(format) ||
        platform.isEmpty ||
        platform.length > 128 ||
        name.isEmpty ||
        name.length > 200 ||
        (!reference && script.isEmpty) ||
        utf8.encode(script).length > 5 * 1024 * 1024 ||
        meta['capabilities'] is! List ||
        (meta['capabilities'] as List).any((value) => value is! String)) {
      throw       FormatException(tr('音源脚本元信息无效。'));
    }
    if (url.scheme != 'file') pluginHttpsUri('$url');
    return MusicPluginSource(
      id: externalId(url),
      url: url,
      api: url,
      platform: platform,
      name: name,
      version: '${meta['version'] ?? ''}',
      author: '${meta['author'] ?? ''}',
      capabilities: List<String>.unmodifiable(meta['capabilities'] as List),
      format: format as String,
      script: script,
      qualities: List<String>.unmodifiable(
        (meta['qualities'] as List? ?? []).whereType<String>(),
      ),
      lxSources: Map<String, dynamic>.unmodifiable(
        meta['sources'] as Map? ?? {},
      ),
      variables: Map.unmodifiable(variables),
      userVariables: (meta['userVariables'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
    );
  }

  factory MusicPluginSource.fromMeta(
    Map<String, dynamic> meta,
    Uri url, {
    bool builtin = false,
  }) {
    final platform = '${meta['platform'] ?? ''}';
    final name = '${meta['name'] ?? ''}'.trim();
    final capabilities = meta['capabilities'];
    final api = pluginHttpsUri('${meta['api'] ?? ''}');
    if (meta['format'] != 'animemusic/1' ||
        !(platforms.contains(platform) || platform == 'all') ||
        name.isEmpty ||
        name.length > 200 ||
        api.hasQuery ||
        capabilities is! List ||
        capabilities.any((value) => value is! String)) {
      throw       FormatException(tr('只支持具有有效 META 信息的 animemusic/1 音源插件。'));
    }
    final supported = (meta['platforms'] as List? ?? [])
        .whereType<String>()
        .toList();
    if (platform == 'all' &&
        (supported.isEmpty ||
            supported.any((item) => !platforms.contains(item)))) {
      throw       FormatException(tr('聚合音源必须声明有效的平台列表。'));
    }
    final normalizedUrl = url.scheme == 'file'
        ? url
        : pluginHttpsUri(url.toString());
    return MusicPluginSource(
      id: builtin ? 'animemusic-$platform' : externalId(normalizedUrl),
      url: normalizedUrl,
      api: api.replace(
        path: api.path.endsWith('.php')
            ? api.path
            : '${api.path.replaceAll(RegExp(r'/+$'), '')}/index.php',
      ),
      platform: platform,
      name: name,
      version: '${meta['version'] ?? ''}',
      author: '${meta['author'] ?? ''}',
      capabilities: List<String>.unmodifiable(capabilities),
      builtin: builtin,
      qualities: List<String>.unmodifiable(
        (meta['qualities'] as List? ?? []).whereType<String>(),
      ),
      supportedPlatforms: List.unmodifiable(supported),
    );
  }

  factory MusicPluginSource.fromJson(
    Map<String, dynamic> json, {
    bool reference = false,
  }) {
    final source = json['format'] != 'animemusic/1'
        ? MusicPluginSource.fromScript(
            json,
            Uri.parse(json['url'] as String),
            json['script'] as String? ?? '',
            reference: reference,
            variables: (json['variables'] as Map? ?? {}).map(
              (key, value) => MapEntry('$key', '$value'),
            ),
          )
        : MusicPluginSource.fromMeta(
            json,
            Uri.parse(json['url'] as String),
            builtin: json['builtin'] == true,
          );
    if (source.id != json['id']) {
      throw       FormatException(tr('插件标识与来源不一致。'));
    }
    return source;
  }

  Map<String, dynamic> toJson({bool includeScript = true}) => {
    'format': format,
    'id': id,
    'url': '$url',
    'api': '$api',
    'platform': platform,
    'name': name,
    'version': version,
    'author': author,
    'capabilities': capabilities,
    'builtin': builtin,
    'qualities': qualities,
    if (supportedPlatforms.isNotEmpty) 'platforms': supportedPlatforms,
    if (scripted) ...{
      if (includeScript) 'script': script,
      'sources': lxSources,
      if (includeScript) 'variables': variables,
      'userVariables': userVariables,
    },
  };

  MusicPluginSource withVariables(Map<String, String> next) =>
      MusicPluginSource.fromJson({...toJson(), 'variables': next});

  static const platforms = {'kg', 'kw', 'wy', 'tx', 'mg', 'bilibili', 'qishui'};
}
