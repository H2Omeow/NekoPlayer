import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/i18n/app_language.dart';
import 'package:nekoplayer_desktop/i18n/tr.dart';

void main() {
  tearDown(() => AppLanguage.debugOverride = 'zh-CN');

  test('explicit language tags win over system locales', () {
    expect(resolveLanguageTag('en', const [Locale('zh', 'CN')]), 'en');
    expect(resolveLanguageTag('ja', const [Locale('zh', 'TW')]), 'ja');
    expect(resolveLanguageTag('zh-TW', const [Locale('en')]), 'zh-TW');
  });

  test('system Chinese variants map to the right table', () {
    expect(resolveLanguageTag('system', const [Locale('zh', 'TW')]), 'zh-TW');
    expect(resolveLanguageTag('system', const [Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hant',
    )]), 'zh-TW');
    expect(resolveLanguageTag('system', const [Locale('zh', 'HK')]), 'zh-TW');
    expect(resolveLanguageTag('system', const [Locale('zh', 'CN')]), 'zh-CN');
    expect(resolveLanguageTag('system', const [Locale('en', 'US')]), 'en');
    expect(resolveLanguageTag('system', const [Locale('ja', 'JP')]), 'ja');
    expect(resolveLanguageTag('system', const [Locale('fr', 'FR')]), 'zh-CN');
  });

  test('unknown sources fall back to the source template', () {
    AppLanguage.debugOverride = 'en';
    expect(tr('这个键不存在 {value}', {'value': 3}), '这个键不存在 3');
  });

  test('placeholders are substituted from the translated table', () {
    AppLanguage.debugOverride = 'en';
    expect(
      tr('共 {count} 首', {'count': 12}),
      contains('12'),
    );
    AppLanguage.debugOverride = 'ja';
    expect(
      tr('共 {count} 首', {'count': 12}),
      contains('12'),
    );
  });
}
