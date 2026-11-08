import 'package:flutter/material.dart';

enum Section {
  home('首页', Icons.home_outlined, Icons.home_rounded),
  discover('发现', Icons.explore_outlined, Icons.explore_rounded),
  library('音乐库', Icons.library_music_outlined, Icons.library_music_rounded),
  all('全部歌曲', Icons.music_note_outlined, Icons.music_note_rounded),
  favorites('我喜欢', Icons.favorite_border_rounded, Icons.favorite_rounded),
  recent('最近播放', Icons.history_rounded, Icons.history_rounded),
  downloads('下载', Icons.download_outlined, Icons.download_rounded),
  platform('平台曲库', Icons.cloud_outlined, Icons.cloud_rounded),
  playlist('歌单', Icons.queue_music_outlined, Icons.queue_music_rounded),
  settings('设置', Icons.settings_outlined, Icons.settings_rounded);

  const Section(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

@immutable
class Destination {
  const Destination(this.section, [this.playlistId]);
  final Section section;
  final String? playlistId;

  @override
  bool operator ==(Object other) =>
      other is Destination &&
      other.section == section &&
      other.playlistId == playlistId;

  @override
  int get hashCode => Object.hash(section, playlistId);
}
