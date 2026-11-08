import 'package:flutter/material.dart';

import '../data/comments_repository.dart';
import '../domain/comments.dart';
import '../domain/online_music.dart';
import 'neko_theme.dart';
import 'widgets/artwork.dart';
import 'widgets/empty_state.dart';
import 'widgets/page_layout.dart';
import 'widgets/settings_list.dart';

class CommentsPage extends StatefulWidget {
  const CommentsPage({
    super.key,
    required this.repository,
    required this.song,
    this.source = CommentSource.site,
    this.parent,
    this.parentPage = const CommentPage(),
  });
  final CommentsRepository repository;
  final OnlineSong song;
  final CommentSource source;
  final SongComment? parent;
  final CommentPage parentPage;
  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  late CommentSource source = widget.source;
  OnlineSong? selected;
  List<OnlineSong> matches = [];
  List<SongComment> comments = [];
  CommentPage page = const CommentPage();
  bool loading = false;
  bool posting = false;
  String account = '';
  String? error;
  String? message;
  int generation = 0;
  int offset = 0;

  @override
  void initState() {
    super.initState();
    prepare();
  }

  Future<void> prepare() async {
    final request = ++generation;
    setState(() {
      loading = true;
      comments = [];
      matches = [];
      selected = null;
      error = null;
      message = null;
      offset = 0;
      page = widget.parentPage;
    });
    try {
      final candidates = await widget.repository.matches(source, widget.song);
      if (!mounted || request != generation) return;
      if (source == CommentSource.site ||
          source.name == widget.song.provider.name) {
        selected = widget.song;
        await fetch(reset: true);
      } else {
        setState(() {
          matches = candidates;
          if (candidates.isEmpty) error = '没有找到对应平台歌曲，请切换评论来源。';
        });
      }
    } catch (failure) {
      if (mounted && request == generation) {
        setState(
          () => error = failure is MusicSearchException
              ? failure.message
              : '评论服务暂时不可用，请重试。',
        );
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  Future<void> fetch({bool reset = false}) async {
    final song = selected;
    if (song == null) return;
    final request = generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (reset) account = await widget.repository.accountId(source);
      final result = await widget.repository.list(
        source,
        song,
        offset: reset ? 0 : offset,
        account: account,
        parent: widget.parent,
        previous: reset ? widget.parentPage : page,
      );
      if (!mounted || request != generation) return;
      setState(() {
        comments = {
          if (!reset) ...{for (final comment in comments) comment.id: comment},
          for (final comment in result.comments) comment.id: comment,
        }.values.toList();
        offset = (reset ? 0 : offset) + result.comments.length;
        page = result;
      });
    } catch (failure) {
      if (mounted && request == generation) {
        setState(
          () => error = failure is MusicSearchException
              ? failure.message
              : '评论加载失败，请重试。',
        );
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  Future<void> mutate(Future<void> Function() action, String success) async {
    if (posting || selected == null) return;
    final request = generation;
    setState(() {
      posting = true;
      message = null;
      error = null;
    });
    try {
      await action();
      if (!mounted || request != generation) return;
      setState(() => message = success);
      await fetch(reset: true);
    } catch (failure) {
      if (mounted && request == generation) {
        setState(
          () => error = failure is MusicSearchException
              ? failure.message
              : '操作未获确认，请检查平台状态后再试，避免重复发送。',
        );
      }
    } finally {
      if (mounted && request == generation) setState(() => posting = false);
    }
  }

  Future<void> compose([SongComment? reply]) async {
    if (!widget.repository.loggedIn(source)) {
      setState(() => error = '请先在设置中登录${source.label}账号。');
      return;
    }
    final input = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(reply == null ? '发布到${source.label}' : '回复 ${reply.user}'),
        content: SizedBox(
          width: 440,
          child: TextField(
            controller: input,
            maxLength: 2000,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(hintText: '写下你想说的话…'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('确认发布'),
          ),
        ],
      ),
    );
    input.dispose();
    if (!mounted || value == null || selected == null) return;
    await mutate(
      () => widget.repository.send(
        source,
        selected!,
        value,
        parent: reply ?? widget.parent,
        page: widget.parent == null ? page : widget.parentPage,
      ),
      '评论已发布。',
    );
  }

  Future<void> delete(SongComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条评论？'),
        content: const Text('此操作不能撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted && selected != null) {
      await mutate(
        () => widget.repository.delete(source, selected!, comment),
        '评论已删除。',
      );
    }
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  Widget _comment(BuildContext context, SongComment comment) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final palette = NekoPalette.of(context);
    final name = comment.user.isEmpty ? '音乐爱好者' : comment.user;
    final idle = posting || loading || comment.deleted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NekoSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: colors.surfaceContainerHighest,
            foregroundColor: colors.onSurfaceVariant,
            child: Text(name.characters.first, style: text.labelLarge),
          ),
          const SizedBox(width: NekoSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall,
                      ),
                    ),
                    const SizedBox(width: NekoSpace.sm),
                    Text(comment.time, style: text.labelSmall),
                  ],
                ),
                const SizedBox(height: NekoSpace.xs),
                SelectableText(
                  comment.deleted ? '评论已删除' : comment.content,
                  style: text.bodyMedium?.copyWith(
                    color: comment.deleted ? colors.onSurfaceVariant : null,
                  ),
                ),
                if (comment.quotedContent.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: NekoSpace.sm),
                    padding: const EdgeInsets.all(NekoSpace.md),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(NekoRadius.control),
                    ),
                    child: Text(
                      '${comment.quotedUser}：${comment.quotedContent}',
                      style: text.bodySmall,
                    ),
                  ),
                const SizedBox(height: NekoSpace.xs),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (source != CommentSource.kugou)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: comment.liked
                              ? palette.accent
                              : colors.onSurfaceVariant,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: idle
                            ? null
                            : () => mutate(
                                () => widget.repository.like(
                                  source,
                                  selected!,
                                  comment,
                                ),
                                comment.liked ? '已取消点赞。' : '已点赞。',
                              ),
                        icon: Icon(
                          comment.liked
                              ? Icons.thumb_up_rounded
                              : Icons.thumb_up_outlined,
                          size: 16,
                        ),
                        label: Text('${comment.likes}'),
                      ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: colors.onSurfaceVariant,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: idle ? null : () => compose(comment),
                      child: const Text('回复'),
                    ),
                    if (comment.replies > 0)
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => CommentsPage(
                              repository: widget.repository,
                              song: selected!,
                              source: source,
                              parent: comment,
                              parentPage: page,
                            ),
                          ),
                        ),
                        child: Text('${comment.replies} 条回复'),
                      ),
                    if (comment.owned &&
                        source != CommentSource.kugou &&
                        !comment.deleted)
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: colors.error,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: posting || loading
                            ? null
                            : () => delete(comment),
                        child: const Text('删除'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gutter = pageGutter(context);
    final text = Theme.of(context).textTheme;
    final header = <Widget>[
      if (widget.parent == null)
        Wrap(
          spacing: NekoSpace.sm,
          runSpacing: NekoSpace.sm,
          children: [
            for (final value in CommentSource.values)
              ChoiceChip(
                label: Text(value.label),
                selected: source == value,
                onSelected: posting
                    ? null
                    : (_) {
                        source = value;
                        prepare();
                      },
              ),
          ],
        ),
      if (selected != null) ...[
        const SizedBox(height: NekoSpace.sm),
        Text(
          '${source.label} · ${selected!.title} · ${selected!.artist}',
          style: text.bodySmall,
        ),
      ],
      if (widget.parent case final parent?) ...[
        const SizedBox(height: NekoSpace.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(NekoSpace.lg),
            child: Text(
              '${parent.user}：${parent.content}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      const SizedBox(height: NekoSpace.md),
      Row(
        children: [
          if (selected != null)
            FilledButton.icon(
              onPressed: posting || loading ? null : () => compose(),
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('写评论'),
            ),
          const Spacer(),
          IconButton(
            tooltip: '刷新',
            onPressed: posting || loading
                ? null
                : () => selected == null ? prepare() : fetch(reset: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      const SizedBox(height: NekoSpace.sm),
      if (loading || posting) const LinearProgressIndicator(),
      if (message case final value?) InlineNotice(value),
      if (error case final value?) InlineNotice(value, error: true),
    ];
    final List<Widget> body;
    if (selected == null) {
      body = [
        if (matches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: NekoSpace.sm),
            child: Text('请选择对应的歌曲，避免看到其他版本的评论。', style: text.bodySmall),
          ),
        for (final song in matches)
          ListTile(
            leading: Artwork(size: 44, url: song.artwork, label: song.title),
            title: Text(song.title),
            subtitle: Text(song.artist),
            onTap: () {
              setState(() {
                selected = song;
                matches = [];
              });
              fetch(reset: true);
            },
          ),
      ];
    } else if (comments.isEmpty) {
      body = [
        if (!loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: NekoSpace.xxl),
            child: EmptyState(
              icon: Icons.forum_outlined,
              title: '暂无评论',
              description: '来写第一条吧。',
            ),
          ),
      ];
    } else {
      body = [
        for (final (index, comment) in comments.indexed) ...[
          if (index > 0) const Divider(),
          _comment(context, comment),
        ],
        if (page.hasMore)
          Center(
            child: TextButton(
              onPressed: loading ? null : fetch,
              child: const Text('加载更多'),
            ),
          ),
      ];
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.parent == null ? '${widget.song.title} · 评论' : '评论回复',
        ),
      ),
      body: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: EdgeInsets.fromLTRB(gutter, NekoSpace.sm, gutter, gutter),
            children: [...header, ...body],
          ),
        ),
      ),
    );
  }
}
