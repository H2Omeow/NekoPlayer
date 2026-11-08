import '../../i18n/tr.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/library.dart';
import '../../domain/social.dart';
import '../../player_controller.dart';
import '../../site_controller.dart';
import '../../social_controller.dart';
import '../neko_theme.dart';
import '../widgets/artwork.dart';

const _shareBase = 'https://player.nekoh2o.top';

class SocialPage extends StatefulWidget {
  const SocialPage({
    super.key,
    required this.site,
    required this.social,
    required this.player,
    required this.onLogin,
    this.onOpenShare,
  });

  final SiteController site;
  final SocialController social;
  final PlayerController player;
  final VoidCallback onLogin;
  final void Function(Track track)? onOpenShare;

  @override
  State<SocialPage> createState() => _SocialPageState();
}

class _SocialPageState extends State<SocialPage> {
  int tab = 0;
  final text = TextEditingController();
  final search = TextEditingController();

  SocialController get social => widget.social;

  @override
  void initState() {
    super.initState();
    if (social.feed.isEmpty) unawaited(social.loadFeed());
  }

  @override
  void dispose() {
    text.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([social, widget.site]),
    builder: (context, _) {
      if (widget.site.user == null) return _login(context);
      final active = social.active;
      if (active != null) return _chat(context, active);
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(NekoSpace.lg, NekoSpace.md, NekoSpace.lg, 0),
            child: Row(
              children: [
                _TabChip(
                  label: social.unread > 0 ? '消息 ${social.unread}' : tr('消息'),
                  selected: tab == 0,
                  onTap: () => setState(() => tab = 0),
                ),
                const SizedBox(width: NekoSpace.sm),
                _TabChip(
                  label: tr('关注动态'),
                  selected: tab == 1,
                  onTap: () {
                    setState(() => tab = 1);
                    unawaited(social.loadFeed());
                  },
                ),
                const SizedBox(width: NekoSpace.sm),
                _TabChip(
                  label: tr('发现'),
                  selected: tab == 2,
                  onTap: () => setState(() => tab = 2),
                ),
                const Spacer(),
                if (social.error != null)
                  Flexible(
                    child: Text(
                      social.error!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: switch (tab) {
              0 => _messages(context),
              1 => _feed(context),
              _ => _discover(context),
            },
          ),
        ],
      );
    },
  );

  Widget _login(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.forum_outlined,
            size: 54,
            color: NekoPalette.of(context).accent,
          ),
          const SizedBox(height: NekoSpace.lg),
          Text(tr('登录后使用社区'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: NekoSpace.sm),
          Text(
            tr('关注喜欢的人、发送私信，把正在听的歌分享给朋友。'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: NekoSpace.xl),
          FilledButton(onPressed: widget.onLogin, child:       Text(tr('登录 NekoPlayer 账号'))),
        ],
      ),
    ),
  );

  Widget _messages(BuildContext context) {
    final conversations = social.conversations;
    if (conversations.isEmpty) {
      return _empty(
        context,
        Icons.forum_outlined,
        tr('还没有私信'),
        social.busy ? tr('正在加载…') : tr('在「发现」里找到朋友，开始聊天吧。'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(NekoSpace.lg),
      itemCount: conversations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final conversation = conversations[index];
        return ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NekoRadius.control),
          ),
          leading: _Avatar(profile: conversation.peer, size: 44),
          title: Text(conversation.peer?.displayName ?? tr('用户')),
          subtitle: Text(
            _preview(conversation.lastMessage),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _shortTime(conversation.updatedAt),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              if (conversation.unread > 0) ...[
                const SizedBox(height: 4),
                Badge(
                  label: Text(conversation.unread > 99 ? '99+' : '${conversation.unread}'),
                ),
              ],
            ],
          ),
          onTap: () => unawaited(social.openChat(conversation.peerId, conversation: conversation)),
        );
      },
    );
  }

  Widget _chat(BuildContext context, SocialConversation conversation) => Column(
    children: [
      Row(
        children: [
          IconButton(
            tooltip: tr('返回会话列表'),
            onPressed: social.closeChat,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          InkWell(
            onTap: conversation.peer == null
                ? null
                : () => unawaited(social.loadProfile(conversation.peer!.id)),
            child: Row(
              children: [
                _Avatar(profile: conversation.peer, size: 34),
                const SizedBox(width: NekoSpace.sm),
                Text(
                  conversation.peer?.displayName ?? tr('用户'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          const Spacer(),
          if (social.sseConnected)
            Padding(
              padding: const EdgeInsets.only(right: NekoSpace.lg),
              child: Text(tr('实时'), style: Theme.of(context).textTheme.labelSmall),
            ),
        ],
      ),
      const Divider(height: 1),
      Expanded(
        child: social.loadingMessages && social.messages.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(NekoSpace.md),
                itemCount: social.messages.length,
                itemBuilder: (context, index) {
                  final message = social.messages[social.messages.length - 1 - index];
                  return _MessageBubble(
                    message: message,
                    player: widget.player,
                    onWithdraw: () => unawaited(social.deleteMessage(message)),
                  );
                },
              ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.all(NekoSpace.sm),
        child: Row(
          children: [
            IconButton(
              tooltip: tr('分享当前歌曲'),
              onPressed: () {
                final track = widget.player.current;
                if (track != null) widget.onOpenShare?.call(track);
              },
              icon: const Icon(Icons.music_note_rounded),
            ),
            Expanded(
              child: TextField(
                controller: text,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                decoration:       InputDecoration(hintText: tr('输入消息…'), border: OutlineInputBorder()),
                onSubmitted: (_) => _send(context),
              ),
            ),
            const SizedBox(width: NekoSpace.sm),
            IconButton.filled(
              tooltip: tr('发送'),
              onPressed: () => _send(context),
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> _send(BuildContext context) async {
    final body = text.text.trim();
    if (body.isEmpty) return;
    text.clear();
    final ok = await social.sendText(body);
    if (!ok) {
      text.text = body;
      if (mounted) _showError();
    }
  }

  void _showError() {
    final message = social.error;
    if (message == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    social.clearError();
  }

  Widget _feed(BuildContext context) {
    final feed = social.feed;
    if (social.loadingFeed && feed.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (feed.isEmpty) {
      return _empty(
        context,
        Icons.people_outline_rounded,
        tr('还没有关注动态'),
        tr('去「发现」关注喜欢的人，这里会出现他们分享的歌曲。'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(NekoSpace.lg),
      itemCount: feed.length,
      itemBuilder: (context, index) {
        final share = feed[index];
        return Card(
          margin: const EdgeInsets.only(bottom: NekoSpace.md),
          child: Padding(
            padding: const EdgeInsets.all(NekoSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: share.sharer == null
                      ? null
                      : () => unawaited(social.loadProfile(share.sharer!.id)),
                  child: Row(
                    children: [
                      _Avatar(profile: share.sharer, size: 32),
                      const SizedBox(width: NekoSpace.sm),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(share.sharer?.displayName ?? tr('用户')),
                          Text(
                            '${_shortTime(share.createdAt)} · ${tr(share.platform)}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: NekoSpace.sm),
                Row(
                  children: [
                    if (share.track != null)
                      Artwork(track: share.track, size: 56)
                    else
                      const SizedBox(width: 56, height: 56),
                    const SizedBox(width: NekoSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            share.song['nm']?.toString() ?? tr('未知歌曲'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            share.song['ar']?.toString() ?? tr('未知歌手'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (share.message.isNotEmpty) ...[
                  const SizedBox(height: NekoSpace.sm),
                  Text(share.message),
                ],
                if (share.lyricSnippet.isNotEmpty) ...[
                  const SizedBox(height: NekoSpace.sm),
                  Text(
                    share.lyricSnippet,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                Row(
                  children: [
                    TextButton(
                      onPressed: share.track == null
                          ? null
                          : () => unawaited(_play(share.track!, share.progress)),
                      child:       Text(tr('播放')),
                    ),
                    TextButton(
                      onPressed: () => _openSharePage(share.token),
                      child:       Text(tr('查看分享')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _play(Track track, SocialProgress? progress) async {
    await widget.player.play([track], 0);
    if (progress != null && progress.positionMs > 0) {
      await widget.player.seek(progress.position);
    }
  }

  Widget _discover(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(NekoSpace.md),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: search,
                decoration:       InputDecoration(
                  hintText: tr('搜索用户名或昵称'),
                  prefixIcon: Icon(Icons.search_rounded),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) => unawaited(social.search(value)),
              ),
            ),
            const SizedBox(width: NekoSpace.sm),
            FilledButton(
              onPressed: social.searching ? null : () => unawaited(social.search(search.text)),
              child:       Text(tr('搜索')),
            ),
          ],
        ),
      ),
      if (social.searching) const LinearProgressIndicator(),
      Expanded(
        child: social.searchResults.isEmpty
            ? _empty(
                context,
                Icons.person_search_rounded,
                tr('发现用户'),
                tr('输入至少 2 个字符，找到朋友后可以关注或私信。'),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: NekoSpace.md),
                itemCount: social.searchResults.length,
                itemBuilder: (context, index) {
                  final profile = social.searchResults[index];
                  return ListTile(
                    leading: _Avatar(profile: profile, size: 44),
                    title: Text(profile.displayName),
                    subtitle: Text(
                      profile.bio.isNotEmpty ? profile.bio : '@${profile.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: profile.isSelf
                        ?       Text(tr('这是你'))
                        : OutlinedButton(
                            onPressed: () => unawaited(social.toggleFollow(profile)),
                            child: Text(profile.isFollowing ? tr('已关注') : tr('关注')),
                          ),
                    onTap: () => unawaited(social.loadProfile(profile.id)),
                  );
                },
              ),
      ),
    ],
  );

  Widget _empty(BuildContext context, IconData icon, String title, String description) =>
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: NekoSpace.md),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: NekoSpace.xs),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.profile, required this.size});
  final SocialProfile? profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = profile?.avatar ?? '';
    if (url.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        child: Icon(Icons.person_outline_rounded, size: size * .55),
      );
    }
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => CircleAvatar(
          radius: size / 2,
          child: const Icon(Icons.person_outline_rounded),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.player,
    required this.onWithdraw,
  });

  final SocialMessage message;
  final PlayerController player;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    if (message.deleted) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: NekoSpace.xs),
        child: Center(
          child: Text(
            message.owned ? tr('你撤回了一条消息') : tr('对方撤回了一条消息'),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      );
    }
    final colors = Theme.of(context).colorScheme;
    final alignment = message.owned ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleColor = message.owned
        ? colors.primaryContainer
        : colors.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.only(bottom: NekoSpace.sm),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: message.kind == 'song' && message.track != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Artwork(track: message.track, size: 52),
                          const SizedBox(width: NekoSpace.sm),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  message.song['nm']?.toString() ?? tr('未知歌曲'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  message.song['ar']?.toString() ?? tr('未知歌手'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: () => unawaited(player.play([message.track!], 0)),
                                      child:       Text(tr('播放')),
                                    ),
                                    if ((message.shareToken ?? '').isNotEmpty)
                                      TextButton(
                                        onPressed: () => _openSharePage(message.shareToken!),
                                        child:       Text(tr('查看')),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (message.text.isNotEmpty) ...[
                        const SizedBox(height: NekoSpace.xs),
                        Text(message.text),
                      ],
                    ],
                  )
                : Text(message.text.isEmpty ? ' ' : message.text),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _shortTime(message.createdAt),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                if (message.owned) ...[
                  const SizedBox(width: NekoSpace.sm),
                  InkWell(
                    onTap: onWithdraw,
                    child: Text(
                      tr('撤回'),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileDialog extends StatelessWidget {
  const _ProfileDialog({required this.social});
  final SocialController social;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: social,
    builder: (context, _) {
      final profile = social.profile;
      if (profile == null) {
        return const AlertDialog(
          content: SizedBox(
            width: 320,
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          ),
        );
      }
      final colors = Theme.of(context).colorScheme;
      return AlertDialog(
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Avatar(profile: profile, size: 76),
              const SizedBox(height: NekoSpace.md),
              Text(profile.displayName, style: Theme.of(context).textTheme.titleLarge),
              Text('@${profile.username}', style: Theme.of(context).textTheme.bodySmall),
              if (profile.bio.isNotEmpty) ...[
                const SizedBox(height: NekoSpace.sm),
                Text(profile.bio, textAlign: TextAlign.center),
              ],
              const SizedBox(height: NekoSpace.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(tr('{count} 粉丝', {'count': profile.followers})),
                  const SizedBox(width: NekoSpace.xl),
                  Text(tr('{count} 关注', {'count': profile.following})),
                ],
              ),
              const SizedBox(height: NekoSpace.lg),
              if (profile.isSelf)
                Column(
                  children: [
                          Text(tr('私信接收范围')),
                    const SizedBox(height: NekoSpace.sm),
                    SegmentedButton<String>(
                      segments:       [
                        ButtonSegment(value: 'everyone', label: Text(tr('所有人'))),
                        ButtonSegment(value: 'following', label: Text(tr('我关注的人'))),
                      ],
                      selected: {social.preferences.dmPolicy},
                      onSelectionChanged: (value) =>
                          unawaited(social.savePreferences(value.first)),
                    ),
                  ],
                )
              else
                Wrap(
                  spacing: NekoSpace.sm,
                  runSpacing: NekoSpace.sm,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton(
                      onPressed: () => unawaited(social.toggleFollow(profile)),
                      child: Text(profile.isFollowing ? tr('已关注') : tr('关注')),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        social.closeProfile();
                        Navigator.of(context).pop();
                        unawaited(social.openChat(profile.id));
                      },
                      child:       Text(tr('私信')),
                    ),
                    OutlinedButton(
                      onPressed: () => unawaited(social.toggleBlock(profile)),
                      style: OutlinedButton.styleFrom(foregroundColor: colors.error),
                      child: Text(profile.blocked ? tr('取消拉黑') : tr('拉黑')),
                    ),
                  ],
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              social.closeProfile();
              Navigator.of(context).pop();
            },
            child:       Text(tr('关闭')),
          ),
        ],
      );
    },
  );
}

Future<void> showSocialProfileDialog(BuildContext context, SocialController social) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ProfileDialog(social: social),
    );

Future<void> showSongShareDialog(
  BuildContext context, {
  required SocialController social,
  required Track track,
  required bool isCurrent,
  String lyric = '',
  Duration position = Duration.zero,
  Duration duration = Duration.zero,
}) async {
  final message = TextEditingController();
  var showSharer = true;
  var cover = true;
  var album = false;
  var lyricEnabled = false;
  var progressEnabled = false;
  var busy = false;
  String? failure;
  SocialShare? result;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title:       Text(tr('分享歌曲')),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Artwork(track: track, size: 52),
                    const SizedBox(width: NekoSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(
                            '${track.artist} · ${platformLabel(track)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: NekoSpace.md),
                TextField(
                  controller: message,
                  maxLength: 200,
                  maxLines: 3,
                  decoration:       InputDecoration(
                    hintText: tr('写一句留言（可选）'),
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title:       Text(tr('显示分享者身份')),
                  value: showSharer,
                  onChanged: (value) => setState(() => showSharer = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title:       Text(tr('包含封面')),
                  value: cover,
                  onChanged: (value) => setState(() => cover = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title:       Text(tr('包含专辑名')),
                  value: album,
                  onChanged: (value) => setState(() => album = value),
                ),
                if (isCurrent && lyric.isNotEmpty)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title:       Text(tr('包含当前歌词片段')),
                    value: lyricEnabled,
                    onChanged: (value) => setState(() => lyricEnabled = value),
                  ),
                if (isCurrent)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title:       Text(tr('包含播放进度')),
                    value: progressEnabled,
                    onChanged: (value) => setState(() => progressEnabled = value),
                  ),
                if (failure != null)
                  Text(
                    failure!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                if (result != null) ...[
                  const SizedBox(height: NekoSpace.sm),
                  Text(tr('分享链接已生成'), style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                  const SizedBox(height: NekoSpace.xs),
                  SelectableText(result!.url, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: NekoSpace.sm),
                  Wrap(
                    spacing: NekoSpace.sm,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: result!.url));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(tr('已复制链接'))),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_rounded),
                        label:       Text(tr('复制')),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse('$result!.url'),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.open_in_new_rounded),
                        label:       Text(tr('打开分享页')),
                      ),
                      if (social.active != null)
                        OutlinedButton.icon(
                          onPressed: () async {
                            final ok = await social.sendSong(track);
                            if (ok && context.mounted) Navigator.of(context).pop();
                          },
                          icon: const Icon(Icons.send_rounded),
                          label:       Text(tr('发到当前会话')),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.of(context).pop(),
            child:       Text(tr('关闭')),
          ),
          if (result == null)
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        failure = null;
                      });
                      final share = await social.createShare(
                        track,
                        message: message.text.trim(),
                        options: ShareOptions(
                          showSharer: showSharer,
                          cover: cover,
                          album: album,
                          lyric: lyricEnabled && isCurrent,
                          progress: progressEnabled && isCurrent,
                        ),
                        lyric: lyric,
                        progress: duration > Duration.zero
                            ? SocialProgress(
                                positionMs: position.inMilliseconds,
                                durationMs: duration.inMilliseconds,
                              )
                            : null,
                      );
                      if (!context.mounted) return;
                      setState(() {
                        busy = false;
                        result = share;
                        failure = share == null
                            ? social.error ?? tr('分享创建失败')
                            : null;
                      });
                    },
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  :       Text(tr('生成分享链接')),
            ),
        ],
      ),
    ),
  );
  message.dispose();
}

String _preview(SocialMessage? message) {
  if (message == null) return tr('开始聊天');
  if (message.deleted) return tr('[消息已撤回]');
  if (message.kind == 'song') {
    return tr('[歌曲] {title}', {
      'title': message.song['nm'] ?? tr('分享'),
    });
  }
  return message.text.isEmpty ? tr('[消息]') : message.text;
}

String _shortTime(int timestamp) {
  if (timestamp <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final now = DateTime.now();
  final sameDay = date.year == now.year && date.month == now.month && date.day == now.day;
  String two(int value) => value.toString().padLeft(2, '0');
  return sameDay
      ? '${two(date.hour)}:${two(date.minute)}'
      : '${date.month}/${date.day} ${two(date.hour)}:${two(date.minute)}';
}

void _openSharePage(String token) {
  unawaited(
    launchUrl(
      Uri.parse('$_shareBase/s/${Uri.encodeComponent(token)}'),
      mode: LaunchMode.externalApplication,
    ),
  );
}
