import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nekoplayer_desktop/data/app_data_export.dart';

void main() {
  test(
    'builds a portable backup and strips credentials and plugin secrets',
    () async {
      final values = <String, String?>{
        AppDataExporter.appearanceKey: jsonEncode({
          'version': 1,
          'theme': 'dark',
          'scale': 1.1,
          'token': 'appearance-token',
        }),
        AppDataExporter.languageKey: 'en',
        AppDataExporter.effectsKey: jsonEncode({
          'enabled': true,
          'password': 'effects-password',
        }),
        AppDataExporter.libraryKey: jsonEncode({
          'version': 1,
          'favorites': ['a'],
          'history': ['a'],
          'credentials': {'token': 'library-token'},
        }),
        AppDataExporter.pluginsKey: jsonEncode({
          'version': 1,
          'subscriptions': [
            {
              'url': 'https://example.com/subscription.json',
              'enabled': true,
              'sources': [
                {
                  'id': 'plugin-1',
                  'name': 'Example',
                  'script': 'secret-script',
                  'variables': {'token': 'plugin-token'},
                  'storage': {'cookie': 'plugin-cookie'},
                },
              ],
            },
          ],
        }),
      };

      final text = await AppDataExporter(
        read: (key) async => values[key],
        clock: () => DateTime.utc(2026, 11, 14, 12, 30),
        appVersionOverride: '1.2.5+25',
        platformOverride: 'linux',
      ).build();
      final body = jsonDecode(text) as Map<String, dynamic>;

      expect(body['format'], 'nekoplayer.data');
      expect(body['version'], 1);
      expect(body['appVersion'], '1.2.5+25');
      expect(body['platform'], 'linux');
      expect(body['exportedAt'], '2026-11-14T12:30:00.000Z');
      expect(body['settings']['language'], 'en');
      expect(body['settings']['appearance']['theme'], 'dark');
      expect(body['settings']['appearance'].containsKey('token'), isFalse);
      expect(body['settings']['audioEffects'].containsKey('password'), isFalse);
      expect(body['library']['favorites'], ['a']);
      expect(body['library'].containsKey('credentials'), isFalse);

      final source =
          body['plugins']['subscriptions'][0]['sources'][0]
              as Map<String, dynamic>;
      expect(source['id'], 'plugin-1');
      expect(source['name'], 'Example');
      expect(source.containsKey('script'), isFalse);
      expect(source.containsKey('variables'), isFalse);
      expect(source.containsKey('storage'), isFalse);
      for (final secret in [
        'appearance-token',
        'effects-password',
        'library-token',
        'secret-script',
        'plugin-token',
        'plugin-cookie',
      ]) {
        expect(text.contains(secret), isFalse, reason: secret);
      }
    },
  );

  test('keeps unreadable preference values instead of dropping them', () async {
    final text = await AppDataExporter(
      read: (key) async =>
          key == AppDataExporter.desktopKey ? 'not-json' : null,
      clock: () => DateTime.utc(2026),
    ).build();
    final body = jsonDecode(text) as Map<String, dynamic>;
    expect(body['desktop'], 'not-json');
    expect(body['library'], isNull);
  });
}
