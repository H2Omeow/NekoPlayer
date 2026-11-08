import 'dart:async';

import 'package:nekoplayer_desktop/i18n/app_language.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Existing UI tests assert Simplified Chinese labels.
  AppLanguage.debugOverride = 'zh-CN';
  await testMain();
}
