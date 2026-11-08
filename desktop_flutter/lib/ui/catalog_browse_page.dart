import '../i18n/tr.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../data/catalog_browse_repository.dart';
import '../domain/online_music.dart';
import '../player_controller.dart';
import 'account_music_page.dart';
import 'neko_theme.dart';
import 'widgets/artwork.dart';
import 'widgets/empty_state.dart';
import 'widgets/page_layout.dart';
import 'widgets/settings_list.dart';

class CatalogBrowsePage extends StatefulWidget {
  const CatalogBrowsePage({
    super.key,
    required this.repository,
    required this.player,
    required this.onComments,
    this.onDownload,
  });
  final CatalogBrowseRepository repository;
  final PlayerController player;
  final void Function(OnlineSong) onComments;
  final void Function(OnlineSong)? onDownload;
  @override
  State<CatalogBrowsePage> createState() => _CatalogBrowsePageState();
}

class _CatalogBrowsePageState extends State<CatalogBrowsePage> {
  final input = TextEditingController();
  CatalogKind kind = CatalogKind.artist;
  List<CatalogItem> results = [];
  List<String> suggestions = [];
  String keyword = '';
  String? error;
  bool busy = false;
  bool recommended = false;
  bool more = false;
  int page = 0;
  int generation = 0;
  int suggestionGeneration = 0;
  Timer? debounce;

  String label(CatalogKind value) => switch (value) {
    CatalogKind.artist => tr('歌手'),
    CatalogKind.album => tr('专辑'),
    CatalogKind.playlist => tr('歌单'),
  };

  void suggest(String value) {
    debounce?.cancel();
    final request = ++suggestionGeneration;
    if (value.trim().isEmpty) {
      setState(() => suggestions = []);
      return;
    }
    debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final words = await widget.repository.suggestions(value);
        if (mounted && request == suggestionGeneration) {
          setState(() => suggestions = words);
        }
      } catch (_) {
        if (mounted && request == suggestionGeneration) {
          setState(() => suggestions = []);
        }
      }
    });
  }

  Future<void> search({bool reset = true, bool recommendations = false}) async {
    if (busy && !reset) return;
    final nextKeyword = reset ? input.text.trim() : keyword;
    if (!recommendations && nextKeyword.isEmpty) return;
    final request = ++generation;
    ++suggestionGeneration;
    debounce?.cancel();
    final nextPage = reset ? 1 : page + 1;
    setState(() {
      busy = true;
      error = null;
      suggestions = [];
      recommended = recommendations;
      if (reset) {
        results = [];
        page = 0;
        more = false;
        keyword = nextKeyword;
      }
    });
    try {
      final response = recommendations
          ? await widget.repository.recommendedPlaylists()
          : await widget.repository.search(kind, nextKeyword, nextPage);
      if (!mounted || request != generation) return;
      final byId = {
        for (final item in results) '${item.kind}:${item.id}': item,
      };
      for (final item in response.items) {
        byId['${item.kind}:${item.id}'] = item;
      }
      setState(() {
        results = byId.values.toList();
        page = nextPage;
        more = response.hasMore;
      });
    } catch (failure) {
      if (mounted && request == generation) {
        setState(
          () => error = failure is MusicSearchException
              ? failure.message
              : tr('分类内容读取失败，请重试。'),
        );
      }
    } finally {
      if (mounted && request == generation) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    generation++;
    suggestionGeneration++;
    debounce?.cancel();
    input.dispose();
    super.dispose();
  }

  void selectKind(CatalogKind value) {
    generation++;
    suggestionGeneration++;
    debounce?.cancel();
    setState(() {
      kind = value;
      recommended = false;
      busy = false;
      results = [];
      suggestions = [];
      page = 0;
      more = false;
      error = null;
    });
    if (input.text.trim().isNotEmpty) search();
  }

  void open(CatalogItem item) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AccountMusicPage(
        repository: widget.repository.music,
        player: widget.player,
        onComments: widget.onComments,
        onDownload: widget.onDownload,
        title: item.name,
        collectionId: 'browse-${item.kind.name}-${item.id}',
        songLoader: (page) => widget.repository.songs(item, page),
      ),
    ),
  );

  Widget _header(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: input,
        maxLength: 200,
        onChanged: suggest,
        onSubmitted: (_) => search(),
        decoration: InputDecoration(
          hintText: tr('搜索{kind}', {'kind': label(kind)}),
          counterText: '',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: IconButton(
            tooltip: tr('搜索'),
            onPressed: () => search(),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ),
      ),
      const SizedBox(height: NekoSpace.md),
      Wrap(
        spacing: NekoSpace.sm,
        runSpacing: NekoSpace.sm,
        children: [
          for (final value in CatalogKind.values)
            ChoiceChip(
              label: Text(label(value)),
              selected: kind == value && !recommended,
              onSelected: (_) => selectKind(value),
            ),
          ChoiceChip(
            avatar: const Icon(Icons.auto_awesome_rounded),
            label:       Text(tr('推荐歌单')),
            selected: recommended,
            onSelected: (_) => search(recommendations: true),
          ),
        ],
      ),
      if (suggestions.isNotEmpty) ...[
        const SizedBox(height: NekoSpace.md),
        Wrap(
          spacing: NekoSpace.sm,
          runSpacing: NekoSpace.sm,
          children: [
            for (final word in suggestions)
              ActionChip(
                avatar: const Icon(Icons.north_west_rounded),
                label: Text(word),
                onPressed: () {
                  input.text = word;
                  search();
                },
              ),
          ],
        ),
      ],
      const SizedBox(height: NekoSpace.lg),
      if (busy) const LinearProgressIndicator(),
      if (error case final message?)
        InlineNotice(
          message,
          error: true,
          action: TextButton(
            onPressed: busy
                ? null
                : () => search(reset: page == 0, recommendations: recommended),
            child:       Text(tr('重试')),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final gutter = pageGutter(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title:       Text(tr('歌手、专辑与歌单'))),
      body: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(gutter, NekoSpace.sm, gutter, 0),
                sliver: SliverToBoxAdapter(child: _header(context)),
              ),
              if (results.isEmpty && !busy && error == null)
                      SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.library_music_outlined,
                    title: tr('输入关键词，或浏览推荐歌单'),
                    description: tr('分类内容来自网易云目录；歌曲能否播放仍取决于平台权限。'),
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
                    itemCount: results.length + (more ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == results.length) {
                        return Center(
                          child: TextButton(
                            onPressed: busy ? null : () => search(reset: false),
                            child:       Text(tr('加载更多')),
                          ),
                        );
                      }
                      final item = results[index];
                      final artist = item.kind == CatalogKind.artist;
                      return ListTile(
                        leading: Artwork(
                          size: 48,
                          label: item.name,
                          radius: artist ? 24 : null,
                          icon: switch (item.kind) {
                            CatalogKind.artist => Icons.person_rounded,
                            CatalogKind.album => Icons.album_rounded,
                            CatalogKind.playlist => Icons.queue_music_rounded,
                          },
                        ),
                        title: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          [
                            item.subtitle,
                            if (item.count > 0)
                              tr('{count} 首', {'count': item.count}),
                          ].where((value) => value.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => open(item),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
