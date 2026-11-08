import '../i18n/tr.dart';
import 'package:flutter/material.dart';

import '../domain/library.dart';
import '../player_controller.dart';
import 'neko_theme.dart';
import 'widgets/artwork.dart';

Future<void> showPlaylistPicker(
  BuildContext context,
  PlayerController player,
  Track track,
) => showDialog<void>(
  context: context,
  builder: (_) => _PlaylistPicker(player: player, track: track),
);

class _PlaylistPicker extends StatefulWidget {
  const _PlaylistPicker({required this.player, required this.track});
  final PlayerController player;
  final Track track;

  @override
  State<_PlaylistPicker> createState() => _PlaylistPickerState();
}

class _PlaylistPickerState extends State<_PlaylistPicker> {
  final name = TextEditingController();

  void add(String id) {
    widget.player.addToPlaylist(id, widget.track);
    Navigator.pop(context);
  }

  void create() {
    final id = widget.player.createPlaylist(name.text);
    if (id != null) add(id);
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.player,
    builder: (context, _) => AlertDialog(
      title:       Text(tr('添加到歌单')),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.track.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (widget.player.playlists.isEmpty)
                    Text(tr('还没有歌单，可以在下方新建。'))
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.player.playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = widget.player.playlists[index];
                    final contains = playlist.paths.contains(widget.track.path);
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: NekoSpace.sm,
                      ),
                      leading: Artwork(
                        size: 40,
                        label: playlist.name,
                        icon: Icons.queue_music_rounded,
                      ),
                      title: Text(playlist.name),
                      subtitle: Text(
                        contains ? tr('已在歌单中') : '${playlist.paths.length} 首',
                      ),
                      trailing: contains
                          ? Icon(
                              Icons.check_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                      onTap: () => add(playlist.id),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              maxLength: 100,
              decoration:       InputDecoration(
                hintText: tr('新歌单名称'),
                prefixIcon: Icon(Icons.add_rounded),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => create(),
            ),
            Text(
              tr('只修改本机歌单，不会改动平台账号，也不会开始播放。'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:       Text(tr('取消')),
        ),
        ListenableBuilder(
          listenable: name,
          builder: (context, _) => FilledButton(
            onPressed: name.text.trim().isEmpty ? null : create,
            child:       Text(tr('新建并加入')),
          ),
        ),
      ],
    ),
  );
}
