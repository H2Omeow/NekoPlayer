import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/site_client.dart';
import 'domain/online_music.dart';

enum PlayerBackground { solid, cover, wallpaper }

class AppearanceController extends ChangeNotifier {
  ThemeMode theme = ThemeMode.dark;
  double scale = 1;
  bool wallpaperEnabled = false;
  String? wallpaper;
  double mask = .8;
  double blur = 0;
  double controls = 1;
  PlayerBackground playerBackground = PlayerBackground.cover;
  double playerMask = .85;
  double playerBlur = 12;
  String? downloadDirectory;
  bool readable = true;
  bool busy = false;
  String? error;
  bool _disposed = false;
  int _wallpaperGeneration = 0;
  HttpClient? _wallpaperClient;
  Future<void> _writes = Future.value();

  Future<void> initialize() async {
    try {
      final raw = await SharedPreferencesAsync().getString(
        'nekoplayer.flutter.appearance.v1',
      );
      if (raw == null) return;
      final body = jsonDecode(raw) as Map<String, dynamic>;
      if (body['version'] != 1) throw const FormatException();
      theme = ThemeMode.values.byName(body['theme'] as String);
      scale = (body['scale'] as num).toDouble().clamp(.85, 1.4);
      mask = (body['mask'] as num).toDouble().clamp(.35, .95);
      blur = (body['blur'] as num).toDouble().clamp(0, 20);
      controls = (body['controls'] as num).toDouble().clamp(.2, 1);
      playerBackground = PlayerBackground.values.byName(
        body['playerBackground'] as String? ?? 'cover',
      );
      playerMask = (body['playerMask'] as num? ?? .85).toDouble().clamp(
        .35,
        .95,
      );
      playerBlur = (body['playerBlur'] as num? ?? 12).toDouble().clamp(0, 20);
      if ([
        scale,
        mask,
        blur,
        controls,
        playerMask,
        playerBlur,
      ].any((value) => !value.isFinite)) {
        throw const FormatException();
      }
      wallpaper = body['wallpaper'] as String?;
      wallpaperEnabled = body['wallpaperEnabled'] == true;
      downloadDirectory = body['downloadDirectory'] as String?;
    } catch (_) {
      theme = ThemeMode.dark;
      scale = 1;
      mask = .8;
      blur = 0;
      controls = 1;
      playerBackground = PlayerBackground.cover;
      playerMask = .85;
      playerBlur = 12;
      wallpaper = null;
      wallpaperEnabled = false;
      downloadDirectory = null;
      readable = false;
      error = '外观设置读取失败，已保留原数据；本次修改不会覆盖它。';
    }
    if (!_disposed) notifyListeners();
  }

  void update({
    ThemeMode? themeMode,
    double? textScale,
    bool? showWallpaper,
    String? wallpaperPath,
    bool clearWallpaper = false,
    double? darkness,
    double? blurRadius,
    double? controlAlpha,
    PlayerBackground? playerMode,
    double? playerDarkness,
    double? playerBlurRadius,
    String? downloads,
    bool resetDownloads = false,
  }) {
    if (_disposed) return;
    if (clearWallpaper || wallpaperPath != null || showWallpaper != null) {
      _wallpaperGeneration++;
      _wallpaperClient?.close(force: true);
    }
    theme = themeMode ?? theme;
    playerBackground = playerMode ?? playerBackground;
    if (playerDarkness != null && playerDarkness.isFinite) {
      playerMask = playerDarkness.clamp(.35, .95);
    }
    if (playerBlurRadius != null && playerBlurRadius.isFinite) {
      playerBlur = playerBlurRadius.clamp(0, 20);
    }
    if (textScale != null && textScale.isFinite) {
      scale = textScale.clamp(.85, 1.4);
    }
    if (darkness != null && darkness.isFinite) mask = darkness.clamp(.35, .95);
    if (blurRadius != null && blurRadius.isFinite) {
      blur = blurRadius.clamp(0, 20);
    }
    if (controlAlpha != null && controlAlpha.isFinite) {
      controls = controlAlpha.clamp(.2, 1);
    }
    wallpaper = clearWallpaper ? null : wallpaperPath ?? wallpaper;
    wallpaperEnabled = clearWallpaper
        ? false
        : showWallpaper ?? wallpaperEnabled;
    downloadDirectory = resetDownloads ? null : downloads ?? downloadDirectory;
    if (readable) {
      final encoded = jsonEncode({
        'version': 1,
        'theme': theme.name,
        'scale': scale,
        'mask': mask,
        'blur': blur,
        'controls': controls,
        'playerBackground': playerBackground.name,
        'playerMask': playerMask,
        'playerBlur': playerBlur,
        'wallpaper': wallpaper,
        'wallpaperEnabled': wallpaperEnabled,
        'downloadDirectory': downloadDirectory,
      });
      _writes = _writes
          .then(
            (_) => SharedPreferencesAsync().setString(
              'nekoplayer.flutter.appearance.v1',
              encoded,
            ),
          )
          .catchError((Object _) {
            error = '设置已应用，但保存失败。';
            if (!_disposed) notifyListeners();
          });
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> localWallpaper(String path) async {
    final file = File(path);
    if (!await file.exists() || await file.length() > 16 * 1024 * 1024) {
      throw const MusicSearchException('壁纸文件不可读或超过 16MB。');
    }
    update(wallpaperPath: path, showWallpaper: true);
  }

  Future<void> randomWallpaper({SiteClient? site}) async {
    if (busy || _disposed) return;
    final generation = ++_wallpaperGeneration;
    busy = true;
    error = null;
    notifyListeners();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    _wallpaperClient = client;
    File? downloaded;
    bool timedOut = false;
    final deadline = Timer(const Duration(seconds: 30), () {
      timedOut = true;
      client.close(force: true);
    });
    try {
      final images = await (site ?? SiteClient()).wallpapers().timeout(
        const Duration(seconds: 30),
      );
      if (_disposed || generation != _wallpaperGeneration) return;
      if (timedOut) throw TimeoutException('Wallpaper deadline exceeded');
      if (images.isEmpty) throw const MusicSearchException('本站暂时没有横屏壁纸。');
      final candidates = List.of(images)..shuffle(Random.secure());
      List<int>? bytes;
      MusicSearchException? rejected;
      for (final uri in candidates.take(3)) {
        try {
          bytes = await _downloadWallpaper(client, uri);
          break;
        } on MusicSearchException catch (failure) {
          rejected = failure;
        }
      }
      if (bytes == null) throw rejected!;
      if (_disposed || generation != _wallpaperGeneration) return;
      if (timedOut) throw TimeoutException('Wallpaper deadline exceeded');
      final cache = await getApplicationCacheDirectory();
      final directory = Directory('${cache.path}/nekoplayer-wallpapers');
      final type = await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw const MusicSearchException('壁纸缓存目录不可用，已保留原背景。');
      }
      await directory.create(recursive: true);
      final file = File(
        '${directory.path}/wallpaper-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}.image',
      );
      downloaded = file;
      await file.writeAsBytes(bytes, flush: true);
      if (_disposed || generation != _wallpaperGeneration) return;
      if (timedOut) throw TimeoutException('Wallpaper deadline exceeded');
      update(wallpaperPath: file.path, showWallpaper: true);
      await _cleanWallpapers(directory);
    } catch (failure) {
      if (!_disposed && generation == _wallpaperGeneration) {
        error = failure is MusicSearchException
            ? failure.message
            : '壁纸加载失败，已保留原背景。';
      }
    } finally {
      deadline.cancel();
      client.close(force: true);
      if (identical(_wallpaperClient, client)) _wallpaperClient = null;
      if (downloaded != null && downloaded.path != wallpaper) {
        try {
          await downloaded.delete();
        } on FileSystemException {
          if (!_disposed) error ??= '未使用的壁纸缓存暂时无法清理。';
        }
      }
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<List<int>> _downloadWallpaper(HttpClient client, Uri uri) async {
    const limit = 16 * 1024 * 1024;
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 ||
        response.contentLength > limit ||
        !(response.headers.contentType?.mimeType.startsWith('image/') ??
            false)) {
      await response.drain<void>().catchError((_) {});
      throw const MusicSearchException('壁纸服务返回的内容无效。');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      if (bytes.length + chunk.length > limit) {
        throw const MusicSearchException('壁纸超过 16MB，已停止加载。');
      }
      bytes.addAll(chunk);
    }
    return bytes;
  }

  Future<void> _cleanWallpapers(Directory directory) async {
    try {
      var visited = 0;
      await for (final entry in directory.list(followLinks: false)) {
        if (++visited > 128 || _disposed) break;
        final name = entry.uri.pathSegments.last;
        if (entry is File &&
            entry.path != wallpaper &&
            RegExp(r'^wallpaper-\d+-\d+\.image$').hasMatch(name)) {
          await entry.delete();
        }
      }
    } on FileSystemException {
      if (!_disposed) error ??= '旧壁纸缓存暂时无法清理，当前背景仍可使用。';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _wallpaperGeneration++;
    _wallpaperClient?.close(force: true);
    super.dispose();
  }
}

class AppearanceScope extends InheritedNotifier<AppearanceController> {
  const AppearanceScope({
    super.key,
    required AppearanceController controller,
    required super.child,
  }) : super(notifier: controller);
  static AppearanceController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()?.notifier;
}
