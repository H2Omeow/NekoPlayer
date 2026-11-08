import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'data/audio_cache.dart';

import 'data/library_store.dart';
import 'diagnostics/crash_guard.dart';
import 'diagnostics/crash_log.dart';
import 'data/native_music_catalog.dart';
import 'data/account_store.dart';
import 'data/plugin_subscriptions.dart';
import 'data/plugins/plugin_runtime.dart';
import 'deep_links.dart';
import 'download_controller.dart';
import 'playback/effects_playback_engine.dart';
import 'player_controller.dart';
import 'ui/neko_app.dart';
import 'ui/bundled_fonts.dart';
import 'ui/diagnostics_page.dart';
import 'ui/neko_theme.dart';

void main(List<String> arguments) =>
    CrashGuard.run(() => _start(arguments));

Future<void> _start(List<String> arguments) async {
  final deepLinks = await DeepLinkRouter.start(arguments);
  // 第二个实例已把深链转发给正在运行的窗口，直接退出。
  if (deepLinks == null) return;
  registerBundledFontLicense();
  try {
    MediaKit.ensureInitialized();
    final accounts = AccountStore(storage: SecureCredentialStorage());
    await accounts.initialize();
    AudioCache? cache;
    try {
      final directory = await getApplicationCacheDirectory();
      cache = AudioCache(
        directory: Directory('${directory.path}/audio-v1'),
        store: PreferencesCacheStore(SharedPreferencesAsync()),
      );
      await cache.initialize();
    } catch (failure, stack) {
      CrashLog.error(
        'startup',
        'Audio cache unavailable',
        error: failure,
        stack: stack,
      );
    }
    final subscriptions = PluginSubscriptions(
      store: PreferencesPluginStore(SharedPreferencesAsync()),
      runtime: NativePluginRuntime(
        store: PreferencesPluginStorage(SharedPreferencesAsync()),
      ),
    );
    await subscriptions.initialize();
    final onlineSource = NativeMusicCatalog(
      accounts: accounts,
      cache: cache,
      subscriptions: subscriptions,
    );
    final downloads = DownloadController(
      source: onlineSource,
      store: PreferencesDownloadStore(SharedPreferencesAsync()),
    );
    await downloads.initialize();
    final engine = EffectsPlaybackEngine(onlineSource: onlineSource);
    await engine.initializeEffects();
    final controller = PlayerController(
      engine: engine,
      onlineSource: onlineSource,
      downloads: downloads,
      store: PreferencesLibraryStore(SharedPreferencesAsync()),
    );
    await controller.initialize();
    runApp(NekoApp(controller: controller, deepLinks: deepLinks));
  } catch (failure, stack) {
    CrashLog.error(
      'startup',
      'Player core initialization failed',
      error: failure,
      stack: stack,
    );
    runApp(
      MaterialApp(
        theme: nekoTheme(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SelectableText(
                    '播放内核初始化失败。\nLinux 请安装与你的系统架构匹配的 libmpv 和 GTK 3；Windows 请检查安装包中的播放依赖。',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    '错误详情已写入日志：${CrashGuard.logPath ?? defaultLogRoot().path}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) => OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const DiagnosticsPage(),
                        ),
                      ),
                      icon: const Icon(Icons.bug_report_outlined),
                      label: const Text('查看崩溃日志'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
