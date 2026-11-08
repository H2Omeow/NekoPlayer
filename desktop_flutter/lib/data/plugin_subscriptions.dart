import '../i18n/tr.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/music_plugin.dart';
import 'library_store.dart';
import 'plugins/plugin_loader.dart';
import 'plugins/plugin_integrity.dart';
import 'plugins/plugin_runtime.dart';
export 'plugins/plugin_loader.dart' show parsePluginMeta;

typedef PluginTextLoader = Future<String> Function(Uri uri);

class MusicSubscription {
  const MusicSubscription({
    required this.url,
    required this.sources,
    this.enabled = true,
    this.builtin = false,
  });
  final Uri url;
  final List<MusicPluginSource> sources;
  final bool enabled;
  final bool builtin;

  MusicSubscription withEnabled(bool value) => MusicSubscription(
    url: url,
    sources: sources,
    enabled: value,
    builtin: builtin,
  );

  Map<String, dynamic> toJson() => {
    'url': '$url',
    'enabled': enabled,
    'builtin': builtin,
    'sources': sources.map((source) => source.toJson()).toList(),
  };
}

class PluginSubscriptions extends ChangeNotifier {
  PluginSubscriptions({
    this.store,
    PluginTextLoader? loader,
    Future<String> Function()? bundled,
    PluginScriptRuntime? runtime,
  }) : _loader = loader ?? loadPluginText,
       runtime = runtime ?? NativePluginRuntime(),
       _bundled =
           bundled ??
           (() =>
               rootBundle.loadString('assets/music_plugins/animemusic.json'));

  final LibraryStore? store;
  final PluginScriptRuntime runtime;
  final PluginTextLoader _loader;
  final Future<String> Function() _bundled;
  List<MusicSubscription> _subscriptions = [];
  List<MusicSubscription> get subscriptions =>
      List.unmodifiable(_subscriptions);
  List<MusicPluginSource> get sources => {
    for (final subscription in _subscriptions.where((item) => item.enabled))
      for (final source in subscription.sources) source.id: source,
  }.values.toList();
  bool readable = true;
  bool busy = false;
  String? error;
  bool _disposed = false;

  Future<void> initialize() async {
    try {
      final manifest = jsonDecode(await _bundled()) as Map<String, dynamic>;
      final builtin = MusicSubscription(
        url: pluginHttpsUri(manifest['subscription'] as String),
        builtin: true,
        sources: [
          for (final meta
              in (manifest['plugins'] as List).cast<Map<String, dynamic>>())
            MusicPluginSource.fromMeta(
              meta,
              pluginHttpsUri(meta['update'] as String),
              builtin: true,
            ),
        ],
      );
      _subscriptions = [builtin];
      final raw = await store?.read();
      if (raw != null) {
        final body = jsonDecode(raw) as Map<String, dynamic>;
        if (body['version'] != 1 || body['subscriptions'] is! List) {
          throw       FormatException(tr('订阅配置格式无效。'));
        }
        final restored = <MusicSubscription>[];
        for (final item
            in (body['subscriptions'] as List).cast<Map<String, dynamic>>()) {
          final url = subscriptionUri(item['url'] as String);
          final isBuiltin = url == builtin.url;
          restored.add(
            MusicSubscription(
              url: url,
              enabled: item['enabled'] as bool,
              builtin: isBuiltin,
              sources: [
                for (final row
                    in (item['sources'] as List).cast<Map<String, dynamic>>())
                  MusicPluginSource.fromJson({...row, 'builtin': isBuiltin}),
              ],
            ),
          );
        }
        if (!restored.any((item) => item.builtin)) restored.insert(0, builtin);
        if (restored.length > 64 ||
            restored.map((item) => item.url).toSet().length !=
                restored.length) {
          throw       FormatException(tr('订阅数量或标识无效。'));
        }
        _subscriptions = restored;
      }
    } catch (_) {
      readable = false;
      error = tr('订阅配置读取失败，未覆盖原文件。');
    }
    if (!_disposed) notifyListeners();
  }

  Future<MusicSubscription> preview(Uri url) async {
    final safe = subscriptionUri('$url');
    final text = await _loader(safe);
    return previewText(text, safe);
  }

  Future<MusicSubscription> previewText(String text, Uri safe) async {
    if (utf8.encode(text).length > 5 * 1024 * 1024) {
      throw       FormatException(tr('订阅或插件超过 5 MiB。'));
    }
    safe = subscriptionUri('$safe');
    final inspector = PluginLoader(runtime);
    Object? body;
    try {
      body = jsonDecode(text);
    } on FormatException catch (_) {
      final source = await inspector.inspect(text, safe);
      return MusicSubscription(url: safe, sources: [source]);
    }
    final plugins = body is Map ? body['plugins'] : body;
    if (plugins is! List || plugins.isEmpty || plugins.length > 32) {
      throw       FormatException(tr('订阅必须包含 1–32 个插件条目。'));
    }
    final isBuiltin = safe == builtinSubscriptionUrl;
    final sources = <String, MusicPluginSource>{};
    var scriptBytes = 0;
    for (final item in plugins) {
      final entry = item is String ? {'url': item} : item;
      if (entry is! Map) {
        throw       FormatException(tr('订阅中的插件链接无效。'));
      }
      final location = entry['url'] ?? entry['srcUrl'] ?? entry['update'];
      if (location is! String) throw       FormatException(tr('订阅中的插件链接无效。'));
      final scriptUrl = pluginHttpsUri('${safe.resolve(location)}');
      final native =
          entry['format'] == 'animemusic/1' && entry['api'] is String;
      final script = native ? '' : await _loader(scriptUrl);
      if (!native) verifyPluginChecksum(script, entry['sha256']);
      scriptBytes += utf8.encode(script).length;
      if (scriptBytes > 16 * 1024 * 1024) {
        throw       FormatException(tr('订阅脚本总大小超过 16 MiB。'));
      }
      final source = native
          ? MusicPluginSource.fromMeta(
              Map<String, dynamic>.from(entry),
              scriptUrl,
              builtin: isBuiltin,
            )
          : await inspector.inspect(
              script,
              scriptUrl,
              builtin: isBuiltin,
              format: entry['format'] == 'auto'
                  ? null
                  : entry['format'] as String?,
            );
      if (sources.containsKey(source.id)) {
        throw       FormatException(tr('订阅包含重复的插件标识。'));
      }
      sources[source.id] = source;
    }
    return MusicSubscription(
      url: safe,
      sources: List.unmodifiable(sources.values),
      builtin: isBuiltin,
    );
  }

  Future<void> save(MusicSubscription subscription) => _change([
    for (final existing in _subscriptions)
      if (existing.url != subscription.url) existing,
    MusicSubscription(
      url: subscription.url,
      builtin: subscription.builtin,
      enabled: subscription.enabled,
      sources: [
        for (final source in subscription.sources)
          if (source.scripted)
            source.withVariables(
              _subscriptions
                      .expand((entry) => entry.sources)
                      .where((entry) => entry.id == source.id)
                      .firstOrNull
                      ?.variables ??
                  source.variables,
            )
          else
            source,
      ],
    ),
  ]);

  Future<void> configure(
    MusicPluginSource source,
    Map<String, String> variables,
  ) => _change([
    for (final subscription in _subscriptions)
      MusicSubscription(
        url: subscription.url,
        builtin: subscription.builtin,
        enabled: subscription.enabled,
        sources: [
          for (final item in subscription.sources)
            item.id == source.id ? item.withVariables(variables) : item,
        ],
      ),
  ]);

  Future<void> setEnabled(MusicSubscription subscription, bool enabled) =>
      _change([
        for (final existing in _subscriptions)
          existing.url == subscription.url
              ? existing.withEnabled(enabled)
              : existing,
      ]);

  Future<void> remove(MusicSubscription subscription) {
    if (subscription.builtin) throw StateError(tr('内置订阅只能停用，不能删除。'));
    return _change([
      for (final existing in _subscriptions)
        if (existing.url != subscription.url) existing,
    ]);
  }

  Future<void> _change(List<MusicSubscription> next) async {
    if (!readable || busy || _disposed) throw StateError(tr('订阅配置暂不可写入。'));
    if (next.length > 64) throw       FormatException(tr('最多支持 64 个订阅。'));
    busy = true;
    notifyListeners();
    try {
      await store?.write(
        jsonEncode({
          'version': 1,
          'subscriptions': next.map((item) => item.toJson()).toList(),
        }),
      );
      if (!_disposed) _subscriptions = next;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final builtinSubscriptionUrl = Uri.parse(
  'https://animemusic.bzxhkj.com/animemusic/subscription.json',
);

Uri subscriptionUri(String value) {
  var uri = Uri.tryParse(value);
  if (uri?.scheme == 'file' &&
      uri!.host.isEmpty &&
      uri.userInfo.isEmpty &&
      uri.path.startsWith('/') &&
      !uri.hasQuery &&
      !uri.hasFragment) {
    return uri;
  }
  uri = pluginHttpsUri(value);
  if (uri.toString() == '$builtinSubscriptionUrl/') {
    return builtinSubscriptionUrl;
  }
  return uri;
}

Future<String> loadPluginText(Uri uri) async {
  var current = pluginHttpsUri('$uri');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    return await (() async {
      for (var redirect = 0; redirect <= 3; redirect++) {
        final request = await client.getUrl(current);
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'NekoPlayer/plugin-subscription',
        );
        final response = await request.close();
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) throw FormatException(tr('订阅重定向缺少地址。'));
          current = pluginHttpsUri('${current.resolve(location)}');
          continue;
        }
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException(tr('订阅读取失败（HTTP {status}）', {'status': response.statusCode}));
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 5 * 1024 * 1024) {
            throw       FormatException(tr('订阅或插件超过 5 MiB，已停止读取。'));
          }
          bytes.addAll(chunk);
        }
        return utf8.decode(bytes);
      }
      throw       FormatException(tr('订阅重定向次数过多。'));
    })().timeout(const Duration(seconds: 20));
  } finally {
    client.close(force: true);
  }
}
