import '../../i18n/tr.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/library.dart';
import '../../domain/online_music.dart';
import '../../player_controller.dart';
import '../playlist_picker.dart';
import '../widgets/song_row.dart';

/// Builds song rows and their context menus so every list offers the same
/// actions in the same order.
class LibraryActions {
  const LibraryActions({
    required this.player,
    this.onDownload,
    this.onComments,
    this.onShare,
  });

  final PlayerController player;
  final void Function(OnlineSong song)? onDownload;
  final void Function(OnlineSong song)? onComments;
  final void Function(Track track)? onShare;

  List<SongAction> actionsFor(
    BuildContext context,
    Track track, {
    String? playlistId,
    int? queueIndex,
  }) => [
    if (queueIndex == null)
      SongAction(
        tr('加入播放队列'),
        Icons.playlist_play_rounded,
        () => unawaited(player.enqueue(track)),
      ),
    SongAction(
      tr('添加到歌单…'),
      Icons.playlist_add_rounded,
      () => unawaited(showPlaylistPicker(context, player, track)),
    ),
    if (track.online != null && onDownload != null)
      SongAction(
        tr('下载'),
        Icons.download_rounded,
        () => onDownload!(track.online!),
      ),
    if (track.online != null && onComments != null)
      SongAction(
        tr('查看评论'),
        Icons.chat_bubble_outline_rounded,
        () => onComments!(track.online!),
      ),
    if (track.online != null && onShare != null)
      SongAction(
        tr('分享…'),
        Icons.ios_share_rounded,
        () => onShare!(track),
      ),
    if (queueIndex != null) ...[
      SongAction(
        tr('上移'),
        Icons.arrow_upward_rounded,
        () => unawaited(player.moveInQueue(queueIndex, queueIndex - 1)),
        enabled: queueIndex > 0,
      ),
      SongAction(
        tr('下移'),
        Icons.arrow_downward_rounded,
        () => unawaited(player.moveInQueue(queueIndex, queueIndex + 1)),
        enabled: queueIndex < player.queue.length - 1,
      ),
      SongAction(
        tr('从队列移除'),
        Icons.remove_circle_outline_rounded,
        () => unawaited(player.removeFromQueue(queueIndex)),
        destructive: true,
      ),
    ],
    if (playlistId != null)
      SongAction(
        tr('从歌单移除'),
        Icons.remove_circle_outline_rounded,
        () => player.removeFromPlaylist(playlistId, track),
        destructive: true,
      ),
  ];

  bool isPlaying(Track track, {int? queueIndex}) {
    final current = player.current;
    if (current == null || current.path != track.path) return false;
    return queueIndex == null || queueIndex == player.queueIndex;
  }

  Widget row(
    BuildContext context,
    Track track, {
    required VoidCallback onTap,
    int? index,
    String? playlistId,
    int? queueIndex,
    Key? key,
  }) => SongRow(
    key: key,
    title: track.title,
    subtitle: track.artist.isEmpty ? tr('未知歌手') : track.artist,
    album: track.online?.album,
    artwork: track.online?.artwork,
    artworkSeed: track.title,
    index: index,
    playing: isPlaying(track, queueIndex: queueIndex),
    favorite: player.favorites.contains(track.path),
    onFavorite: () => player.toggleFavorite(track),
    onTap: onTap,
    actions: actionsFor(
      context,
      track,
      playlistId: playlistId,
      queueIndex: queueIndex,
    ),
  );
}
