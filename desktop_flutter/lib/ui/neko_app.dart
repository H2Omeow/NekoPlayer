import '../i18n/tr.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../appearance_controller.dart';
import '../data/account_music_repository.dart';
import '../data/catalog_browse_repository.dart';
import '../data/comments_repository.dart';
import '../data/library_store.dart';
import '../data/native_music_catalog.dart';
import '../desktop_integration.dart';
import '../deep_links.dart';
import '../domain/library.dart';
import '../domain/online_music.dart';
import '../dynamic_lyrics.dart';
import '../i18n/app_language.dart';
import '../player_controller.dart';
import '../search_controller.dart' as online;
import '../site_controller.dart';
import '../social_controller.dart';
import '../sync/account_verifier.dart';
import '../sync/cloud_sync_controller.dart';
import '../sync/sync_state_store.dart';
import 'account_music_page.dart';
import 'catalog_browse_page.dart';
import 'comments_page.dart';
import 'download_quality_dialog.dart';
import 'downloads_page.dart';
import 'library/home_page.dart';
import 'library/library_actions.dart';
import 'library/track_collection_page.dart';
import 'music_videos_page.dart';
import 'neko_theme.dart';
import 'now_playing/now_playing_page.dart';
import 'online_search_page.dart';
import 'plugin_subscriptions_page.dart';
import 'settings/settings_page.dart';
import 'shell/destinations.dart';
import 'shell/player_bar.dart';
import 'shell/queue_panel.dart';
import 'shell/sidebar.dart';
import 'social/social_page.dart';
import 'widgets/settings_list.dart';

export 'now_playing/now_playing_page.dart' show FullPlayer, LyricsView;
export 'shell/player_bar.dart';
export 'widgets/artwork.dart';
export 'widgets/empty_state.dart';

class NekoApp extends StatefulWidget {
  const NekoApp({
    super.key,
    required this.controller,
    required this.language,
    this.deepLinks,
  });

  final PlayerController controller;
  final AppLanguage language;
  final DeepLinkRouter? deepLinks;

  @override
  State<NekoApp> createState() => _NekoAppState();
}

class _NekoAppState extends State<NekoApp> {
  final appearance = AppearanceController();
  @override
  void initState() {
    super.initState();
    unawaited(appearance.initialize());
  }

  @override
  void dispose() {
    appearance.dispose();
    final source = widget.controller.onlineSource;
    if (source is NativeMusicCatalog) source.cache?.dispose();
    if (source is NativeMusicCatalog) source.subscriptions?.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([appearance, widget.language]),
    builder: (context, _) {
      final wallpaper =
          appearance.wallpaperEnabled && appearance.wallpaper != null;
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'NekoPlayer',
        locale: widget.language.locale,
        supportedLocales: const [
          Locale('zh', 'CN'),
          Locale('zh', 'TW'),
          Locale('en'),
          Locale('ja'),
        ],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        localeListResolutionCallback: (locales, supported) =>
            localeForTag(resolveLanguageTag(systemLanguageTag, locales ?? const [])),
        theme: nekoTheme(
          brightness: Brightness.light,
          controlAlpha: appearance.controls,
          wallpaper: wallpaper,
          customFont: appearance.fontFamily,
          reduceMotion: appearance.performanceUiEnabled,
        ),
        darkTheme: nekoTheme(
          controlAlpha: appearance.controls,
          wallpaper: wallpaper,
          customFont: appearance.fontFamily,
          reduceMotion: appearance.performanceUiEnabled,
        ),
        themeMode: appearance.theme,
        builder: (context, child) => AppearanceScope(
          controller: appearance,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(
                MediaQuery.textScalerOf(context).scale(1) * appearance.scale,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (wallpaper) ...[
                  ClipRect(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(
                        sigmaX: appearance.effectiveBlur(
                          appearance.blur,
                          MediaQuery.devicePixelRatioOf(context),
                        ),
                        sigmaY: appearance.effectiveBlur(
                          appearance.blur,
                          MediaQuery.devicePixelRatioOf(context),
                        ),
                      ),
                      child: Image.file(
                        File(appearance.wallpaper!),
                        cacheWidth: 1920,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: Theme.of(context).colorScheme.surface,
                        ),
                      ),
                    ),
                  ),
                  ColoredBox(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest
                        .withValues(alpha: appearance.mask),
                  ),
                ],
                child ?? const SizedBox(),
              ],
            ),
          ),
        ),
        home: PlayerShell(
          controller: widget.controller,
          deepLinks: widget.deepLinks,
          language: widget.language,
        ),
      );
    },
  );
}

/// The main window: sidebar, content panel with its own navigation stack,
/// optional queue panel and the transport bar.
class PlayerShell extends StatefulWidget {
  PlayerShell({
    super.key,
    required this.controller,
    this.deepLinks,
    AppLanguage? language,
  }) : language = language ?? AppLanguage();

  final PlayerController controller;
  final DeepLinkRouter? deepLinks;
  final AppLanguage language;

  @override
  State<PlayerShell> createState() => _PlayerShellState();
}

class _PlayerShellState extends State<PlayerShell> {
  late final dynamicLyrics = DynamicLyricsServer(
    snapshot: () => dynamicLyricsSnapshot(
      track: controller.current,
      lyrics: controller.lyrics,
      position: controller.position,
      duration: controller.duration,
      playing: controller.engine.playing,
      rate: controller.rate,
      showTranslation: controller.showTranslation,
    ),
  );
  late final NativeMusicCatalog catalog;
  late final online.SearchController onlineSearch;
  late final SiteController site;
  late final SocialController social;
  late final CloudSyncController cloudSync;
  late final DesktopIntegration integration;
  late final LibraryActions actions;
  final contentNavigator = GlobalKey<NavigatorState>();
  bool _profileOpen = false;

  Destination destination = const Destination(Section.home);
  bool queueOpen = false;
  bool importing = false;

  PlayerController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    catalog = controller.onlineSource is NativeMusicCatalog
        ? controller.onlineSource as NativeMusicCatalog
        : NativeMusicCatalog();
    onlineSearch = online.SearchController(catalog);
    catalog.subscriptions?.addListener(subscriptionChanged);
    site = SiteController(accounts: catalog.accounts, player: controller);
    social = SocialController(
      accounts: catalog.accounts,
      client: site.client,
      player: controller,
      onSnack: snack,
      onNotify: (title, body, uri) =>
          unawaited(integration.notify(title, body, uri)),
    );
    cloudSync = CloudSyncController(
      site: site,
      player: controller,
      store: PreferencesSyncStore(SharedPreferencesAsync()),
      verifier: catalogVerifier(catalog),
    );
    unawaited(cloudSync.start());
    integration = DesktopIntegration(
      controller,
      settingsLoader: () async =>
          PreferencesDesktopStore(SharedPreferencesAsync()),
    );
    integration.onUri = (uri) => widget.deepLinks?.open(uri);
    unawaited(integration.initialize());
    widget.language.addListener(languageChanged);
    actions = LibraryActions(
      player: controller,
      onComments: openComments,
      onShare: openShareTrack,
      onDownload: controller.downloads == null
          ? null
          : (song) => unawaited(downloadSong(song)),
    );
    site.addListener(siteChanged);
    social.addListener(socialChanged);
    widget.deepLinks?.addListener(deepLinkChanged);
    if (site.user != null) social.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => deepLinkChanged());
  }

  void siteChanged() {
    if (site.user != null) {
      social.start();
      // A chat/user deep link received before login stays pending; retry it
      // once the account becomes available.
      WidgetsBinding.instance.addPostFrameCallback((_) => deepLinkChanged());
    } else {
      social.stop();
    }
    if (mounted) setState(() {});
  }

  void socialChanged() {
    if (!mounted) return;
    setState(() {});
    final profile = social.profile;
    if (profile != null && !_profileOpen) {
      _profileOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || social.profile == null) {
          _profileOpen = false;
          return;
        }
        await showSocialProfileDialog(context, social);
        _profileOpen = false;
      });
    }
  }

  void deepLinkChanged() {
    final link = widget.deepLinks?.link;
    if (link == null) return;
    if (link.shareToken != null) {
      unawaited(social.openShareToken(link.shareToken!));
      widget.deepLinks?.consume();
      return;
    }
    void openSocial() {
      navigate(const Destination(Section.social));
    }

    openSocial();
    if (link.chatPeer != null) {
      if (site.user != null) {
        unawaited(social.openChat(link.chatPeer!));
        widget.deepLinks?.consume();
      }
    } else if (link.userId != null) {
      if (site.user != null) {
        unawaited(social.loadProfile(link.userId!));
        widget.deepLinks?.consume();
      }
    } else {
      widget.deepLinks?.consume();
    }
  }

  Future<void> openShareTrack(Track track) async {
    if (track.online == null) {
      snack(tr('本地文件不能生成分享链接。'));
      return;
    }
    final isCurrent = controller.current?.path == track.path;
    final lyric = isCurrent && controller.lyricIndex >= 0 &&
            controller.lyricIndex < controller.lyrics.length
        ? controller.lyrics[controller.lyricIndex].text
        : '';
    await showSongShareDialog(
      context,
      social: social,
      track: track,
      isCurrent: isCurrent,
      lyric: lyric,
      position: controller.position,
      duration: controller.duration,
    );
  }

  @override
  void dispose() {
    widget.language.removeListener(languageChanged);
    widget.deepLinks?.removeListener(deepLinkChanged);
    site.removeListener(siteChanged);
    social.removeListener(socialChanged);
    social.dispose();
    unawaited(dynamicLyrics.dispose());
    integration.dispose();
    catalog.subscriptions?.removeListener(subscriptionChanged);
    onlineSearch.dispose();
    cloudSync.dispose();
    site.dispose();
    super.dispose();
  }

  void languageChanged() => unawaited(integration.refreshTrayLabels());

  void subscriptionChanged() {
    final selected = onlineSearch.pluginSource;
    if (selected != null &&
        !catalog.subscriptions!.sources.any(
          (source) => source.id == selected.id,
        )) {
      onlineSearch.selectProvider(MusicProvider.netease);
    }
  }

  void navigate(Destination next) {
    if (next == destination) {
      contentNavigator.currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => destination = next);
  }

  void snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void pushContent(Widget page) => contentNavigator.currentState?.push(
    MaterialPageRoute<void>(builder: (_) => page),
  );

  void openComments(OnlineSong song) => pushContent(
    CommentsPage(repository: CommentsRepository(catalog), song: song),
  );

  Future<void> importMusic() async {
    if (importing) return;
    setState(() => importing = true);
    try {
      final files = await openFiles(
        acceptedTypeGroups: [
          XTypeGroup(label: tr('音乐文件'), extensions: PlayerController.extensions),
        ],
      );
      if (!mounted) return;
      await controller.importFiles(files.map((file) => file.path).toList());
      if (mounted && files.isNotEmpty) {
        navigate(const Destination(Section.all));
        snack(tr('已导入 {count} 个文件', {'count': files.length}));
      }
    } catch (_) {
      snack(tr('文件选择未完成，请重试。'));
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> downloadSong(OnlineSong song) async {
    final downloads = controller.downloads;
    if (downloads == null) return;
    try {
      final session = AccountMusicRepository(catalog).sessionKey;
      final siteToken = catalog.accounts.siteToken;
      void checkSession() {
        if (session != AccountMusicRepository(catalog).sessionKey ||
            siteToken != catalog.accounts.siteToken) {
          throw       MusicSearchException(tr('账号已切换，请重新选择歌曲并检查音质。'));
        }
      }

      final quality = await showDialog<String>(
        context: context,
        builder: (context) => DownloadQualityDialog(
          load: (accept) => catalog.downloadable(song, accept: accept),
          requiresConfirmation: song.provider.gateway != null,
        ),
      );
      if (!mounted || quality == null) return;
      checkSession();
      final directory =
          AppearanceScope.maybeOf(context)?.downloadDirectory ??
          await getDirectoryPath(confirmButtonText: tr('下载到此文件夹'));
      if (!mounted || directory == null) return;
      checkSession();
      await downloads.enqueue(song, directory, quality);
      snack(downloads.error ?? tr('已加入下载队列'));
    } on MusicSearchException catch (failure) {
      snack(failure.message);
    } catch (_) {
      snack(tr('无法创建下载任务，请检查目录权限。'));
    }
  }

  Future<void> createPlaylist() async {
    final input = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title:       Text(tr('新建歌单')),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: input,
            autofocus: true,
            maxLength: 80,
            decoration:       InputDecoration(hintText: tr('歌单名称')),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) Navigator.pop(context, value);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:       Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () {
              if (input.text.trim().isNotEmpty) {
                Navigator.pop(context, input.text);
              }
            },
            child:       Text(tr('创建')),
          ),
        ],
      ),
    );
    if (result != null) {
      final id = controller.createPlaylist(result);
      if (id != null) navigate(Destination(Section.playlist, id));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
  }

  void openPlayer() {
    if (controller.current == null) return;
    final reduceMotion =
        AppearanceScope.maybeOf(context)?.performanceUiEnabled ?? false;
    unawaited(
      Navigator.of(context).push(
        PageRouteBuilder<void>(
          transitionDuration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 350),
          reverseTransitionDuration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 250),
          pageBuilder: (_, _, _) => FullPlayer(
            controller: controller,
            onShare: openShareTrack,
            onDynamicLyrics: openDynamicLyrics,
            dynamicLyricsUri: dynamicLyrics.start,
            onComments: (song) {
              Navigator.of(context).popUntil((route) => route.isFirst);
              openComments(song);
            },
            onDownload: controller.downloads == null
                ? null
                : (song) => unawaited(downloadSong(song)),
          ),
          transitionsBuilder: reduceMotion
              ? (_, _, _, child) => child
              : (_, animation, _, child) {
                  final curved = CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  );
                  return FadeTransition(
                    opacity: curved,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.06),
                        end: Offset.zero,
                      ).animate(curved),
                      child: child,
                    ),
                  );
                },
        ),
      ),
    );
  }

  Future<void> openDynamicLyrics() async {
    try {
      final appearance = AppearanceScope.maybeOf(context);
      final base = await dynamicLyrics.start();
      final uri = lyricsUriWithQuality(
        base,
        appearance?.lyricsQuery ?? const {},
      );
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError(tr('无法打开浏览器'));
      }
    } catch (_) {
      snack(tr('无法打开浏览器，普通歌词仍可使用。'));
    }
  }

  Widget searchPage() => OnlineSearchPage(
    controller: onlineSearch,
    subscriptions: catalog.subscriptions,
    onSubscriptions: catalog.subscriptions == null
        ? null
        : () => pushContent(
            PluginSubscriptionsPage(subscriptions: catalog.subscriptions!),
          ),
    onEnqueue: (song) => controller.enqueue(Track.fromOnline(song)),
    onFavorite: (song) => controller.toggleFavorite(Track.fromOnline(song)),
    isFavorite: (song) => controller.favorites.contains(song.key),
    actionsFor: (context, song) =>
        actions.actionsFor(context, Track.fromOnline(song)),
    isPlaying: (song) => controller.current?.path == song.key,
    onBrowse: () => pushContent(
      CatalogBrowsePage(
        repository: CatalogBrowseRepository(catalog),
        player: controller,
        onComments: openComments,
        onDownload: controller.downloads == null
            ? null
            : (song) => unawaited(downloadSong(song)),
      ),
    ),
    onAccountLibrary: () => navigate(const Destination(Section.platform)),
    onVideos: () => pushContent(
      MusicVideosPage(
        catalog: catalog,
        provider: onlineSearch.provider,
        volume: controller.volume,
        pauseMusic: controller.pause,
      ),
    ),
    onPlay: (songs, index) =>
        unawaited(controller.play(songs.map(Track.fromOnline).toList(), index)),
  );

  Widget rootPage() => switch (destination.section) {
    Section.home => HomePage(
      player: controller,
      onOpenPlayer: openPlayer,
      onOpenPlaylist: (id) => navigate(Destination(Section.playlist, id)),
      onCreatePlaylist: createPlaylist,
      onDiscover: () => navigate(const Destination(Section.discover)),
      onImport: importMusic,
      onFavorites: () => navigate(const Destination(Section.favorites)),
      onRecent: () => navigate(const Destination(Section.recent)),
    ),
    Section.discover => searchPage(),
    Section.social => SocialPage(
      site: site,
      social: social,
      player: controller,
      onLogin: () => navigate(const Destination(Section.settings)),
      onOpenShare: (track) => unawaited(openShareTrack(track)),
    ),
    Section.library => LibraryOverviewPage(
      player: controller,
      onSelect: (next) => pushContent(collectionPage(next)),
      onCreatePlaylist: createPlaylist,
      showDownloads: controller.downloads != null,
    ),
    Section.settings => SettingsPage(
      player: controller,
      catalog: catalog,
      site: site,
      cloudSync: cloudSync,
      integration: integration,
      language: widget.language,
    ),
    _ => collectionPage(destination),
  };

  Widget collectionPage(Destination target) => switch (target.section) {
    Section.favorites => TrackCollectionPage(
      kind: CollectionKind.favorites,
      actions: actions,
    ),
    Section.recent => TrackCollectionPage(
      kind: CollectionKind.recent,
      actions: actions,
    ),
    Section.playlist => TrackCollectionPage(
      key: ValueKey('playlist-${target.playlistId}'),
      kind: CollectionKind.playlist,
      playlistId: target.playlistId,
      actions: actions,
      onPlaylistDeleted: () => navigate(const Destination(Section.home)),
    ),
    Section.downloads when controller.downloads != null => DownloadsPage(
      controller: controller.downloads!,
      onImport: (task) => controller.importDownload(task),
      onPlay: (task) => controller.importDownload(task, play: true),
    ),
    Section.platform => AccountMusicPage(
      repository: AccountMusicRepository(catalog),
      player: controller,
      onComments: openComments,
      onDownload: controller.downloads == null
          ? null
          : (song) => unawaited(downloadSong(song)),
    ),
    _ => TrackCollectionPage(
      kind: CollectionKind.local,
      actions: actions,
      importing: importing,
      onImport: importMusic,
    ),
  };

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
          unawaited(importMusic()),
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
          navigate(const Destination(Section.discover)),
      const SingleActivator(LogicalKeyboardKey.space, control: true): () =>
          unawaited(controller.toggle()),
      const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): () =>
          unawaited(controller.next()),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): () =>
          unawaited(controller.previous()),
    },
    child: Focus(
      autofocus: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final compact = width < 720;
          final collapsed = width < 1100;
          final sideQueue = queueOpen && width >= 1100;
          final palette = NekoPalette.of(context);
          final content = _ContentPanel(
            navigatorKey: contentNavigator,
            destination: destination,
            page: rootPage(),
            error: controller.error,
            onDismissError: controller.dismissError,
          );
          final bar = PlayerBar(
            controller: controller,
            onOpenPlayer: openPlayer,
            onShare: openShareTrack,
            integration: integration,
            queueOpen: queueOpen,
            onToggleQueue: () {
              if (width >= 1100) {
                setState(() => queueOpen = !queueOpen);
              } else {
                unawaited(
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    constraints: const BoxConstraints(maxWidth: 560),
                    builder: (context) => SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.75,
                      child: QueuePanel(actions: actions),
                    ),
                  ),
                );
              }
            },
          );
          if (compact) {
            return Scaffold(
              backgroundColor: palette.canvas,
              body: SafeArea(
                child: Column(
                  children: [
                    Expanded(child: _Panel(margin: false, child: content)),
                    bar,
                  ],
                ),
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: switch (destination.section) {
                  Section.home => 0,
                  Section.discover => 1,
                  Section.social => 2,
                  Section.settings => 4,
                  _ => 3,
                },
                onDestinationSelected: (index) => navigate(
                  Destination(
                    [
                      Section.home,
                      Section.discover,
                      Section.social,
                      Section.library,
                      Section.settings,
                    ][index],
                  ),
                ),
                destinations: [
                  for (final section in [
                    Section.home,
                    Section.discover,
                    Section.social,
                    Section.library,
                    Section.settings,
                  ])
                    NavigationDestination(
                      icon: Badge(
                        isLabelVisible: section == Section.social && social.unread > 0,
                        label: Text('${social.unread}'),
                        child: Icon(section.icon),
                      ),
                      selectedIcon: Badge(
                        isLabelVisible: section == Section.social && social.unread > 0,
                        label: Text('${social.unread}'),
                        child: Icon(section.selectedIcon),
                      ),
                      label: section.label,
                    ),
                ],
              ),
            );
          }
          return Scaffold(
            backgroundColor: palette.canvas,
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        NekoSpace.sm,
                        NekoSpace.sm,
                        NekoSpace.sm,
                        0,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: collapsed ? 72 : 248,
                            child: _Panel(
                              child: Sidebar(
                                player: controller,
                                selected: destination,
                                onSelect: navigate,
                                onCreatePlaylist: createPlaylist,
                                collapsed: collapsed,
                                showDownloads: controller.downloads != null,
                                showPlatform: true,
                                socialUnread: social.unread,
                                accountLabel: site.user == null
                                    ? null
                                    : '${site.user!['nickname'] ?? site.user!['username'] ?? ''}',
                              ),
                            ),
                          ),
                          const SizedBox(width: NekoSpace.sm),
                          Expanded(child: _Panel(child: content)),
                          if (sideQueue) ...[
                            const SizedBox(width: NekoSpace.sm),
                            SizedBox(
                              width: 340,
                              child: _Panel(
                                child: QueuePanel(
                                  actions: actions,
                                  onClose: () =>
                                      setState(() => queueOpen = false),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  bar,
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.margin = true});
  final Widget child;
  final bool margin;

  @override
  Widget build(BuildContext context) => Material(
    color: NekoPalette.of(context).panel,
    borderRadius: margin ? BorderRadius.circular(NekoRadius.panel) : null,
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _ContentPanel extends StatelessWidget {
  const _ContentPanel({
    required this.navigatorKey,
    required this.destination,
    required this.page,
    required this.error,
    required this.onDismissError,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Destination destination;
  final Widget page;
  final String? error;
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NekoSpace.lg,
            NekoSpace.lg,
            NekoSpace.lg,
            0,
          ),
          child: InlineNotice(
            error!,
            error: true,
            action: TextButton(
              onPressed: onDismissError,
              child:       Text(tr('知道了')),
            ),
          ),
        ),
      Expanded(
        child: HeroControllerScope.none(
          child: Navigator(
            key: navigatorKey,
            pages: [
              MaterialPage<void>(key: ValueKey(destination), child: page),
            ],
            onDidRemovePage: (_) {},
          ),
        ),
      ),
    ],
  );
}

/// The library tab on narrow windows, where the sidebar is not shown.
class LibraryOverviewPage extends StatelessWidget {
  const LibraryOverviewPage({
    super.key,
    required this.player,
    required this.onSelect,
    required this.onCreatePlaylist,
    this.showDownloads = false,
  });

  final PlayerController player;
  final ValueChanged<Destination> onSelect;
  final VoidCallback onCreatePlaylist;
  final bool showDownloads;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: player,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(NekoSpace.lg),
      children: [
        Text(tr('音乐库'), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: NekoSpace.lg),
        SettingsSection(
          children: [
            for (final (section, count) in [
              (Section.favorites, '${player.favorites.length}'),
              (Section.recent, null),
              (Section.all, '${player.tracks.length}'),
              if (showDownloads) (Section.downloads, null),
              (Section.platform, null),
            ])
              SettingsTile(
                icon: section.icon,
                title: section.label,
                value: count,
                onTap: () => onSelect(Destination(section)),
              ),
          ],
        ),
        SettingsSection(
          title: tr('歌单'),
          children: [
            for (final playlist in player.playlists)
              SettingsTile(
                icon: Icons.queue_music_rounded,
                title: playlist.name,
                value: tr('{count} 首', {'count': playlist.paths.length}),
                onTap: () =>
                    onSelect(Destination(Section.playlist, playlist.id)),
              ),
            SettingsTile(
              icon: Icons.add_rounded,
              title: tr('新建歌单'),
              onTap: onCreatePlaylist,
            ),
          ],
        ),
      ],
    ),
  );
}
