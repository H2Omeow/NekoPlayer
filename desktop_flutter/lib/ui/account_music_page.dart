import 'package:flutter/material.dart';

import '../data/account_library_sync.dart';
import '../data/account_music_repository.dart';
import '../domain/library.dart';
import '../domain/online_music.dart';
import '../player_controller.dart';
import 'library/library_actions.dart';
import 'neko_theme.dart';
import 'widgets/artwork.dart';
import 'widgets/empty_state.dart';
import 'widgets/page_layout.dart';
import 'widgets/settings_list.dart';

class AccountMusicPage extends StatefulWidget {
  const AccountMusicPage({
    super.key,
    required this.repository,
    required this.player,
    required this.onComments,
    this.onDownload,
    this.songLoader,
    this.title,
    this.collectionId,
  });
  final AccountMusicRepository repository;
  final PlayerController player;
  final void Function(OnlineSong) onComments;
  final void Function(OnlineSong)? onDownload;
  final Future<AccountPage<OnlineSong>> Function(int)? songLoader;
  final String? title;
  final String? collectionId;

  @override
  State<AccountMusicPage> createState() => _AccountMusicPageState();
}

class _AccountMusicPageState extends State<AccountMusicPage> {
  MusicProvider provider = MusicProvider.netease;
  AccountCollection collection = AccountCollection.playlists;
  AccountPlaylist? selected;
  List<AccountPlaylist> playlists = [];
  List<OnlineSong> songs = [];
  int page = 0;
  int generation = 0;
  bool busy = false;
  bool more = false;
  String? error;
  late String session;
  late final AccountLibrarySync sync;

  @override
  void initState() {
    super.initState();
    sync = AccountLibrarySync(
      sessionKey: () => widget.repository.sessionKey,
      merge: widget.player.mergeCloud,
    )..addListener(syncChanged);
    if (widget.songLoader != null) {
      selected = AccountPlaylist(
        id: widget.collectionId ?? 'browse',
        name: widget.title ?? '歌曲',
      );
    }
    session = widget.repository.sessionKey;
    widget.repository.catalog.accounts.addListener(accountChanged);
    load(reset: true);
  }

  void syncChanged() {
    if (mounted) setState(() {});
  }

  void accountChanged() {
    final next = widget.repository.sessionKey;
    if (session == next) return;
    session = next;
    selected = widget.songLoader == null
        ? null
        : AccountPlaylist(
            id: widget.collectionId ?? 'browse',
            name: widget.title ?? '歌曲',
          );
    load(reset: true);
  }

  @override
  void dispose() {
    generation++;
    sync.dispose();
    widget.repository.catalog.accounts.removeListener(accountChanged);
    super.dispose();
  }

  Future<void> load({bool reset = false}) async {
    if (busy && !reset) return;
    if (reset) sync.cancel();
    final current = ++generation;
    final sessionAtStart = widget.repository.sessionKey;
    final nextPage = reset ? 1 : page + 1;
    setState(() {
      busy = true;
      error = null;
      if (reset) {
        songs = [];
        playlists = [];
        page = 0;
        more = false;
      }
    });
    try {
      if (selected == null &&
          [
            AccountCollection.playlists,
            AccountCollection.following,
          ].contains(collection)) {
        final result = await widget.repository.playlists(
          provider,
          nextPage,
          following: collection == AccountCollection.following,
        );
        if (!mounted ||
            current != generation ||
            sessionAtStart != widget.repository.sessionKey) {
          return;
        }
        final byId = {for (final playlist in playlists) playlist.id: playlist};
        for (final playlist in result.items) {
          byId[playlist.id] = playlist;
        }
        setState(() {
          playlists = byId.values.toList();
          more = result.hasMore;
          page = nextPage;
        });
      } else {
        final result = widget.songLoader != null
            ? await widget.songLoader!(nextPage)
            : selected != null
            ? await widget.repository.playlistSongs(
                provider,
                selected!,
                nextPage,
              )
            : await widget.repository.collection(
                collection,
                nextPage,
                provider: provider,
              );
        if (!mounted ||
            current != generation ||
            sessionAtStart != widget.repository.sessionKey) {
          return;
        }
        final byId = {for (final song in songs) song.key: song};
        for (final song in result.items) {
          byId[song.key] = song;
        }
        setState(() {
          songs = byId.values.toList();
          more = result.hasMore;
          page = nextPage;
        });
      }
    } on MusicSearchException catch (failure) {
      if (mounted && current == generation) {
        setState(() => error = failure.message);
      }
    } catch (_) {
      if (mounted && current == generation) {
        setState(() => error = '读取失败，请检查网络后重试。');
      }
    } finally {
      if (mounted && current == generation) setState(() => busy = false);
    }
  }

  String label(AccountCollection value) => switch (value) {
    AccountCollection.playlists => '账号歌单',
    AccountCollection.likes => '红心歌曲',
    AccountCollection.history => '最近一周记录',
    AccountCollection.recommendations => '每日推荐',
    AccountCollection.newSongs => '新歌速递',
    AccountCollection.following => '关注歌手',
  };

  Future<void> save([
    AccountLibraryDestination destination = AccountLibraryDestination.playlist,
  ]) async {
    if (sync.busy || busy || songs.isEmpty) return;
    final sourceGeneration = generation;
    final sourceSession = session;
    final name = selected?.name ?? label(collection);
    final id = selected == null
        ? collection.name
        : '${selected!.artist ? 'artist-' : ''}${selected!.id}';
    final sourceProvider = provider;
    final sourceCollection = collection;
    final sourcePlaylist = selected;
    final sourceLoader = widget.songLoader;
    final target = switch (destination) {
      AccountLibraryDestination.playlist => '本机歌单',
      AccountLibraryDestination.favorites => '本机收藏',
      AccountLibraryDestination.history => '本机历史',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('将全部歌曲合并到$target？'),
        content: Text(
          '将逐页读取「$name」，不只保存当前已加载的歌曲。读取完成后一次合并，取消或读取失败不保存部分结果；不会修改平台账号或下载音频。'
          '${destination == AccountLibraryDestination.history ? '\n本机历史最多保留 200 首，已有记录优先保留。' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始同步'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        generation != sourceGeneration ||
        session != sourceSession ||
        sync.busy) {
      return;
    }
    try {
      final count = await sync.run(
        load:
            sourceLoader ??
            (page) => sourcePlaylist != null
                ? widget.repository.playlistSongs(
                    sourceProvider,
                    sourcePlaylist,
                    page,
                  )
                : widget.repository.collection(
                    sourceCollection,
                    page,
                    provider: sourceProvider,
                  ),
        destination: destination,
        playlistId: 'account-${sourceProvider.name}-$id',
        playlistName: name,
      );
      if (mounted &&
          generation == sourceGeneration &&
          session == sourceSession) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count == null
                  ? '已取消同步，未保存部分结果。'
                  : '已读取 $count 首歌曲并合并到$target；未修改平台账号。',
            ),
          ),
        );
      }
    } catch (failure) {
      if (mounted &&
          generation == sourceGeneration &&
          session == sourceSession) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failure is MusicSearchException
                  ? failure.message
                  : '同步失败，请检查网络与本机存储后重试。',
            ),
          ),
        );
      }
    }
  }

  List<AccountCollection> get collections => provider == MusicProvider.netease
      ? AccountCollection.values
            .where((value) => value != AccountCollection.following)
            .toList()
      : const [
          AccountCollection.playlists,
          AccountCollection.history,
          AccountCollection.recommendations,
          AccountCollection.following,
        ];

  void selectProvider(MusicProvider value) {
    provider = value;
    selected = null;
    collection = AccountCollection.playlists;
    load(reset: true);
  }

  void selectCollection(AccountCollection value) {
    collection = value;
    selected = null;
    load(reset: true);
  }

  Widget _header(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final browsing = widget.songLoader == null;
    final syncable =
        browsing &&
        selected == null &&
        [
          AccountCollection.likes,
          AccountCollection.history,
        ].contains(collection);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (browsing) ...[
          SegmentedButton<MusicProvider>(
            showSelectedIcon: false,
            segments: [
              for (final value in [MusicProvider.netease, MusicProvider.kugou])
                ButtonSegment(value: value, label: Text(value.label)),
            ],
            selected: {provider},
            onSelectionChanged: (value) => selectProvider(value.single),
          ),
          const SizedBox(height: NekoSpace.md),
          Wrap(
            spacing: NekoSpace.sm,
            runSpacing: NekoSpace.sm,
            children: [
              for (final value in collections)
                ChoiceChip(
                  label: Text(label(value)),
                  selected: collection == value && selected == null,
                  onSelected: (_) => selectCollection(value),
                ),
            ],
          ),
          const SizedBox(height: NekoSpace.sm),
          Text(
            provider == MusicProvider.kugou
                ? '原版 / 概念版跟随平台账号设置。只读浏览，不会修改平台上的歌单。'
                : '只读浏览平台内容；保存到本机不等于收藏到平台账号。',
            style: text.bodySmall,
          ),
        ],
        if (selected != null && browsing) ...[
          const SizedBox(height: NekoSpace.md),
          TextButton.icon(
            onPressed: () {
              selected = null;
              load(reset: true);
            },
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: Text(selected!.name),
          ),
        ],
        if (songs.isNotEmpty) ...[
          const SizedBox(height: NekoSpace.md),
          Wrap(
            spacing: NekoSpace.sm,
            runSpacing: NekoSpace.sm,
            children: [
              FilledButton.icon(
                onPressed: () =>
                    widget.player.play(songs.map(Track.fromOnline).toList(), 0),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text('播放已加载的 ${songs.length} 首'),
              ),
              OutlinedButton.icon(
                onPressed: sync.busy || busy ? null : () => save(),
                icon: const Icon(Icons.playlist_add_rounded, size: 18),
                label: const Text('保存全部歌曲到本机歌单'),
              ),
              if (syncable)
                OutlinedButton.icon(
                  onPressed: sync.busy || busy
                      ? null
                      : () => save(
                          collection == AccountCollection.likes
                              ? AccountLibraryDestination.favorites
                              : AccountLibraryDestination.history,
                        ),
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: Text(
                    collection == AccountCollection.likes
                        ? '全部同步到我喜欢'
                        : '全部同步到最近播放',
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: NekoSpace.lg),
        if (busy) const LinearProgressIndicator(),
        if (sync.busy)
          InlineNotice(
            '已读取 ${sync.pages} 页 · ${sync.count} 首。'
            '${sync.committing
                ? '正在保存到本机…'
                : sync.cancelled
                ? '等待当前请求结束后取消…'
                : '全部读取成功后合并到本机。'}',
            action: TextButton(
              onPressed: sync.cancelled || sync.committing ? null : sync.cancel,
              child: const Text('取消同步'),
            ),
          ),
        if (error case final message?)
          InlineNotice(
            message,
            error: true,
            action: TextButton(
              onPressed: busy ? null : () => load(reset: page == 0),
              child: const Text('重试'),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final showingPlaylists =
        selected == null &&
        [
          AccountCollection.playlists,
          AccountCollection.following,
        ].contains(collection);
    final gutter = pageGutter(context);
    final actions = LibraryActions(
      player: widget.player,
      onDownload: widget.onDownload,
      onComments: widget.onComments,
    );
    final tracks = songs.map(Track.fromOnline).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? '平台曲库')),
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.player, widget.player.engine]),
        builder: (context, _) => CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, NekoSpace.sm, gutter, 0),
              sliver: SliverToBoxAdapter(child: _header(context)),
            ),
            if (!busy && error == null && playlists.isEmpty && songs.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.inbox_outlined,
                  title: '暂无内容',
                  description: '这里还没有歌曲；也可能需要先在“音乐平台账号”中登录。',
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  gutter - NekoSpace.sm,
                  0,
                  gutter - NekoSpace.sm,
                  NekoSpace.xxl,
                ),
                sliver: SliverList.builder(
                  itemCount:
                      (showingPlaylists ? playlists.length : songs.length) +
                      (more ? 1 : 0),
                  itemBuilder: (context, index) {
                    final count = showingPlaylists
                        ? playlists.length
                        : songs.length;
                    if (index == count) {
                      return Center(
                        child: TextButton(
                          onPressed: busy ? null : load,
                          child: const Text('加载更多'),
                        ),
                      );
                    }
                    if (showingPlaylists) {
                      final playlist = playlists[index];
                      return ListTile(
                        leading: Artwork(
                          size: 48,
                          label: playlist.name,
                          radius: playlist.artist ? 24 : null,
                          icon: playlist.artist
                              ? Icons.person_rounded
                              : Icons.queue_music_rounded,
                        ),
                        title: Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: playlist.count > 0
                            ? Text('${playlist.count} 首')
                            : null,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          selected = playlist;
                          load(reset: true);
                        },
                      );
                    }
                    return actions.row(
                      context,
                      tracks[index],
                      index: index,
                      onTap: () => widget.player.play(tracks, index),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
