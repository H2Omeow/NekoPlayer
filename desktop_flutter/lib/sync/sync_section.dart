import '../i18n/tr.dart';

enum SyncSection {
  favorites('favorites', '我喜欢', true),
  history('history', '播放历史', true),
  playlists('playlists', '本地歌单', true),
  credentials('credentials', '音乐平台登录', false);

  const SyncSection(this.key, this.rawLabel, this.defaultAuto);
  final String key;
  final String rawLabel;
  String get label => tr(rawLabel);
  final bool defaultAuto;

  bool get isLibrary => this != credentials;

  static SyncSection? byKey(String key) =>
      values.where((section) => section.key == key).firstOrNull;
}

/// 单个分区在本机记录的同步状态（毫秒时间戳）。
class SectionState {
  const SectionState({
    this.localUpdatedAt = 0,
    this.lastSyncedAt = 0,
    this.lastRemoteUpdatedAt = 0,
    this.autoSync = false,
  });

  final int localUpdatedAt;
  final int lastSyncedAt;
  final int lastRemoteUpdatedAt;
  final bool autoSync;

  bool get localDirty => localUpdatedAt > lastSyncedAt;
  bool get neverSynced => lastSyncedAt == 0;

  SectionState copyWith({
    int? localUpdatedAt,
    int? lastSyncedAt,
    int? lastRemoteUpdatedAt,
    bool? autoSync,
  }) => SectionState(
    localUpdatedAt: localUpdatedAt ?? this.localUpdatedAt,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    lastRemoteUpdatedAt: lastRemoteUpdatedAt ?? this.lastRemoteUpdatedAt,
    autoSync: autoSync ?? this.autoSync,
  );

  factory SectionState.fromJson(Map<String, dynamic> json, bool defaultAuto) {
    int number(String key) => json[key] is int ? json[key] as int : 0;
    return SectionState(
      localUpdatedAt: number('localUpdatedAt'),
      lastSyncedAt: number('lastSyncedAt'),
      lastRemoteUpdatedAt: number('lastRemoteUpdatedAt'),
      autoSync: json['autoSync'] is bool
          ? json['autoSync'] as bool
          : defaultAuto,
    );
  }

  Map<String, dynamic> toJson() => {
    'localUpdatedAt': localUpdatedAt,
    'lastSyncedAt': lastSyncedAt,
    'lastRemoteUpdatedAt': lastRemoteUpdatedAt,
    'autoSync': autoSync,
  };
}

/// 云端某个分区的最近一次读取结果。
class RemoteSection {
  const RemoteSection({this.updatedAt = 0, this.device = '', this.count = 0});
  final int updatedAt;
  final String device;
  final int count;

  bool get hasData => updatedAt > 0 || count > 0;
}

enum SyncStatus {
  unknown('未检查'),
  synced('已同步'),
  localNewer('本地较新'),
  remoteNewer('云端较新'),
  conflict('两端都有改动');

  const SyncStatus(this.rawLabel);
  final String rawLabel;
  String get label => tr(rawLabel);
}

enum SyncAction { none, upload, pull }

SyncStatus sectionStatus({
  required SectionState state,
  required RemoteSection remote,
  required bool localHasData,
}) {
  if (state.neverSynced) {
    if (localHasData && remote.hasData) return SyncStatus.conflict;
    if (localHasData) return SyncStatus.localNewer;
    if (remote.hasData) return SyncStatus.remoteNewer;
    return SyncStatus.synced;
  }
  final remoteDirty = remote.updatedAt > state.lastRemoteUpdatedAt;
  if (state.localDirty && remoteDirty) return SyncStatus.conflict;
  if (state.localDirty) return SyncStatus.localNewer;
  if (remoteDirty) return SyncStatus.remoteNewer;
  return SyncStatus.synced;
}

/// 自动同步只处理单边改动；冲突与未检查的分区保持原样。
SyncAction autoAction(SyncStatus status) => switch (status) {
  SyncStatus.localNewer => SyncAction.upload,
  SyncStatus.remoteNewer => SyncAction.pull,
  _ => SyncAction.none,
};

String two(int value) => value.toString().padLeft(2, '0');

/// 相对 + 绝对时间，例如“3 分钟前 · 2026-11-08 14:03”；0 表示从未。
String describeTime(int milliseconds, DateTime now) {
  if (milliseconds <= 0) return tr('从未');
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  final difference = now.difference(time);
  final relative = difference.isNegative || difference.inSeconds < 60
      ? tr('刚刚')
      : difference.inMinutes < 60
      ? tr('{minutes} 分钟前', {'minutes': difference.inMinutes})
      : difference.inHours < 24
      ? tr('{hours} 小时前', {'hours': difference.inHours})
      : tr('{days} 天前', {'days': difference.inDays});
  return '$relative · ${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}
