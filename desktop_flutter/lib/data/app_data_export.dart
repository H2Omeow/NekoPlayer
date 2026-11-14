import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/app_info.dart' show appVersion;

/// Builds a portable JSON backup of the desktop app's local data.
///
/// The export intentionally leaves out account credentials, the secure plugin
/// storage (which may hold tokens) and all audio files. Plugin scripts and
/// user-supplied variables are stripped too, while subscription URLs and
/// library/settings data are kept.
class AppDataExporter {
  AppDataExporter({
    Future<String?> Function(String key)? read,
    DateTime Function()? clock,
    String? appVersionOverride,
    String? platformOverride,
  }) : _read = read ?? ((key) => SharedPreferencesAsync().getString(key)),
       _clock = clock ?? DateTime.now,
       _version = appVersionOverride ?? appVersion,
       _platform = platformOverride ?? Platform.operatingSystem;

  final Future<String?> Function(String key) _read;
  final DateTime Function() _clock;
  final String _version;
  final String _platform;

  static const appearanceKey = 'nekoplayer.flutter.appearance.v1';
  static const languageKey = 'nekoplayer.language.v1';
  static const effectsKey = 'nekoplayer.flutter.effects.v1';
  static const libraryKey = 'nekoplayer.flutter.library.v1';
  static const downloadsKey = 'nekoplayer.flutter.downloads.v1';
  static const cacheKey = 'nekoplayer.flutter.cache.v1';
  static const desktopKey = 'nekoplayer.flutter.desktop.v1';
  static const pluginsKey = 'nekoplayer.flutter.plugins.v1';

  Future<String> build() async {
    final body = <String, dynamic>{
      'format': 'nekoplayer.data',
      'version': 1,
      'appVersion': _version,
      'platform': _platform,
      'exportedAt': _clock().toIso8601String(),
      'notes': '登录凭据、插件密钥、脚本和音频文件不会包含在此导出中。',
      'settings': {
        'appearance': _sanitize(_decode(await _read(appearanceKey))),
        'language': await _read(languageKey),
        'audioEffects': _sanitize(_decode(await _read(effectsKey))),
      },
      'library': _sanitize(_decode(await _read(libraryKey))),
      'downloads': _sanitize(_decode(await _read(downloadsKey))),
      'cache': _sanitize(_decode(await _read(cacheKey))),
      'desktop': _sanitize(_decode(await _read(desktopKey))),
      'plugins': _sanitize(_decode(await _read(pluginsKey))),
    };
    return const JsonEncoder.withIndent('  ').convert(body);
  }

  static dynamic _decode(String? raw) {
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      // Keep unreadable values visible instead of silently dropping user data.
      return raw;
    }
  }

  static const _sensitiveKeys = {
    'script',
    'variables',
    'storage',
    'token',
    'cookie',
    'cookies',
    'authorization',
    'password',
    'secret',
    'credential',
    'credentials',
    'site_token',
    'apikey',
    'api_key',
  };

  static bool _sensitive(String key) {
    final lower = key.toLowerCase();
    return _sensitiveKeys.contains(lower) ||
        lower.contains('token') ||
        lower.contains('secret') ||
        lower.contains('password') ||
        lower.contains('credential');
  }

  static dynamic _sanitize(dynamic value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          if (!_sensitive('${entry.key}'))
            '${entry.key}': _sanitize(entry.value),
      };
    }
    if (value is List) return value.map(_sanitize).toList();
    return value;
  }
}
