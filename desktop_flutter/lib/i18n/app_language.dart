import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const supportedLanguageTags = ['zh-CN', 'zh-TW', 'en', 'ja'];
const systemLanguageTag = 'system';

Locale? localeForTag(String tag) => switch (tag) {
  'zh-CN' => const Locale('zh', 'CN'),
  'zh-TW' => const Locale('zh', 'TW'),
  'en' => const Locale('en'),
  'ja' => const Locale('ja'),
  _ => null,
};

String resolveLanguageTag(String saved, List<Locale> systemLocales) {
  if (supportedLanguageTags.contains(saved)) return saved;
  for (final locale in systemLocales) {
    final language = locale.languageCode.toLowerCase();
    if (language == 'zh') {
      final script = locale.scriptCode?.toLowerCase();
      final country = locale.countryCode?.toLowerCase();
      return script == 'hant' || country == 'tw' || country == 'hk' || country == 'mo'
          ? 'zh-TW'
          : 'zh-CN';
    }
    if (language == 'en') return 'en';
    if (language == 'ja') return 'ja';
  }
  return 'zh-CN';
}

/// Persisted UI language. `system` means follow the platform locale.
class AppLanguage extends ChangeNotifier {
  AppLanguage({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync() {
    instance = this;
  }

  static const storageKey = 'nekoplayer.language.v1';
  static AppLanguage? instance;

  /// Widget tests set this to keep existing Chinese assertions stable.
  static String? debugOverride;

  final SharedPreferencesAsync _preferences;
  String _tag = systemLanguageTag;
  String _effective = 'zh-CN';
  List<Locale> _systemLocales = const [Locale('zh', 'CN')];

  String get tag => _tag;
  String get effectiveTag => debugOverride ?? _effective;
  Locale? get locale => localeForTag(_effective);

  static String get currentTag =>
      debugOverride ?? instance?._effective ?? 'zh-CN';

  Future<void> initialize() async {
    _systemLocales = WidgetsBinding.instance.platformDispatcher.locales;
    try {
      _tag = await _preferences.getString(storageKey) ?? systemLanguageTag;
    } catch (_) {
      _tag = systemLanguageTag;
    }
    if (_tag != systemLanguageTag && !supportedLanguageTags.contains(_tag)) {
      _tag = systemLanguageTag;
    }
    _effective = resolveLanguageTag(_tag, _systemLocales);
    notifyListeners();
  }

  Future<void> setTag(String value) async {
    final normalized =
        value == systemLanguageTag || supportedLanguageTags.contains(value)
        ? value
        : systemLanguageTag;
    _tag = normalized;
    _effective = resolveLanguageTag(normalized, _systemLocales);
    notifyListeners();
    try {
      await _preferences.setString(storageKey, normalized);
    } catch (_) {
      // The in-memory switch still applies if persistence is unavailable.
    }
  }
}
