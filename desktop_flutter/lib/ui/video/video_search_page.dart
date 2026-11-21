import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/tr.dart';
import '../../video/bili_client.dart';
import '../neko_theme.dart';
import 'video_widgets.dart';

/// 独立的搜索结果页：关键词、排序、热搜、分页都在这里。
class VideoSearchPage extends StatefulWidget {
  const VideoSearchPage({
    super.key,
    required this.client,
    required this.onOpenVideo,
    this.initialQuery = '',
  });

  final BiliClient client;
  final void Function(BiliVideo video) onOpenVideo;
  final String initialQuery;

  @override
  State<VideoSearchPage> createState() => _VideoSearchPageState();
}

class _VideoSearchPageState extends State<VideoSearchPage> {
  static const _orders = [
    ('totalrank', '综合'),
    ('click', '最多播放'),
    ('pubdate', '最新发布'),
    ('dm', '最多弹幕'),
  ];

  late final TextEditingController controller;
  final scrollController = ScrollController();

  String query = '';
  String order = 'totalrank';
  List<BiliVideo> results = const [];
  List<String> hotWords = const [];
  bool loading = false;
  bool loadingMore = false;
  bool hasMore = true;
  String? error;
  int page = 0;

  @override
  void initState() {
    super.initState();
    query = widget.initialQuery.trim();
    controller = TextEditingController(text: query);
    scrollController.addListener(_onScroll);
    unawaited(_loadHotWords());
    if (query.isNotEmpty) unawaited(_search(reset: true));
  }

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHotWords() async {
    final words = await widget.client.hotSearchWords();
    if (!mounted) return;
    setState(() => hotWords = words);
  }

  void _onScroll() {
    if (!hasMore || loading || loadingMore) return;
    if (scrollController.position.pixels >= scrollController.position.maxScrollExtent - 240) {
      unawaited(_search(reset: false));
    }
  }

  Future<void> _search({required bool reset}) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return;
    setState(() {
      if (reset) {
        loading = true;
        error = null;
        results = const [];
        page = 0;
        hasMore = true;
      } else {
        loadingMore = true;
      }
    });
    try {
      final next = reset ? 1 : page + 1;
      final list = await widget.client.search(keyword, page: next, order: order);
      if (!mounted) return;
      setState(() {
        page = next;
        results = reset ? list : [...results, ...list.where((e) => !results.any((x) => x.bvid == e.bvid))];
        hasMore = list.isNotEmpty;
        loading = false;
        loadingMore = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        error = err.toString();
        loading = false;
        loadingMore = false;
        hasMore = false;
      });
    }
  }

  void _submit() {
    query = controller.text.trim();
    if (query.isEmpty) return;
    unawaited(_search(reset: true));
  }

  void _pickWord(String word) {
    controller.text = word;
    _submit();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: NekoPalette.of(context).canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSearchBar(context, colors),
            _buildSortRow(context, colors),
            Expanded(child: _buildBody(context, colors)),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(NekoSpace.lg, NekoSpace.md, NekoSpace.lg, NekoSpace.sm),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
            tooltip: tr('返回'),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: widget.initialQuery.isEmpty,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: tr('搜索视频、UP 主，或直接粘贴 BV 号'),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          controller.clear();
                          setState(() => query = '');
                        },
                      ),
                isDense: true,
                filled: true,
                fillColor: colors.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(NekoRadius.control),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _submit, child: Text(tr('搜索'))),
        ],
      ),
    );
  }

  Widget _buildSortRow(BuildContext context, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NekoSpace.lg),
      child: Row(
        children: [
          for (final item in _orders)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(tr(item.$2)),
                selected: order == item.$1,
                onSelected: (_) {
                  if (order == item.$1) return;
                  setState(() => order = item.$1);
                  if (query.trim().isNotEmpty) unawaited(_search(reset: true));
                },
                visualDensity: VisualDensity.compact,
                showCheckmark: false,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme colors) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (query.trim().isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(NekoSpace.lg),
        children: [
          Text(tr('大家都在搜'), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: NekoSpace.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final word in hotWords)
                ActionChip(
                  label: Text(word),
                  onPressed: () => _pickWord(word),
                ),
            ],
          ),
        ],
      );
    }
    if (error != null && results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('搜索失败：') + error!, style: TextStyle(color: colors.onSurfaceVariant)),
            const SizedBox(height: NekoSpace.md),
            OutlinedButton(onPressed: () => unawaited(_search(reset: true)), child: Text(tr('重试'))),
          ],
        ),
      );
    }
    if (results.isEmpty) {
      return Center(child: Text(tr('没有找到相关视频'), style: TextStyle(color: colors.onSurfaceVariant)));
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(NekoSpace.lg, NekoSpace.sm, NekoSpace.lg, NekoSpace.xl),
      itemCount: results.length + (loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= results.length) {
          return const Padding(
            padding: EdgeInsets.all(NekoSpace.lg),
            child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final video = results[index];
        return VideoListRow(video: video, onTap: () => widget.onOpenVideo(video));
      },
    );
  }
}
