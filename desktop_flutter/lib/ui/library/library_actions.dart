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
  });

  final PlayerController player;
  final void Function(OnlineSong song)? onDownload;
  final void Function(OnlineSong song)? onComments;

  List<SongAction> actionsFor(
    BuildContext context,
    Track track, {
    String? playlistId,
    int? queueIndex,
  }) => [
    if (queueIndex == null)
      SongAction(
        '加入播放队列',
        Icons.playlist_play_rounded,
        () => unawaited(player.enqueue(track)),
      ),
    SongAction(
      '添加到歌单…',
      Icons.playlist_add_rounded,
      () => unawaited(showPlaylistPicker(context, player, track)),
    ),
    if (track.online != null && onDownload != null)
      SongAction(
        '下载',
        Icons.download_rounded,
        () => onDownload!(track.online!),
      ),
    if (track.online != null && onComments != null)
      SongAction(
        '查看评论',
        Icons.chat_bubble_outline_rounded,
        () => onComments!(track.online!),
      ),
    if (queueIndex != null) ...[
      SongAction(
        '上移',
        Icons.arrow_upward_rounded,
        () => unawaited(player.moveInQueue(queueIndex, queueIndex - 1)),
        enabled: queueIndex > 0,
      ),
      SongAction(
        '下移',
        Icons.arrow_downward_rounded,
        () => unawaited(player.moveInQueue(queueIndex, queueIndex + 1)),
        enabled: queueIndex < player.queue.length - 1,
      ),
      SongAction(
        '从队列移除',
        Icons.remove_circle_outline_rounded,
        () => unawaited(player.removeFromQueue(queueIndex)),
        destructive: true,
      ),
    ],
    if (playlistId != null)
      SongAction(
        '从歌单移除',
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
    subtitle: track.artist.isEmpty ? '未知歌手' : track.artist,
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
