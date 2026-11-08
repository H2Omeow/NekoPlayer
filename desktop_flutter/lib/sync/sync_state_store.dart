import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/library_store.dart';
import 'sync_section.dart';

class PreferencesSyncStore implements LibraryStore {
  PreferencesSyncStore(this.preferences);
  final SharedPreferencesAsync preferences;
  static const key = 'nekoplayer.flutter.cloudsync.v2';
  @override
  Future<String?> read() => preferences.getString(key);
  @override
  Future<void> write(String value) => preferences.setString(key, value);
}

/// 同步状态按本站账号区分；账号变化时云端相关记录作废，本地修改时间保留。
class SyncState {
  SyncState({
    this.userId = '',
    this.credentialsFingerprint = '',
    this.lastCheckedAt = 0,
    Map<SyncSection, SectionState>? sections,
  }) : sections = sections ?? defaults();

  String userId;
  String credentialsFingerprint;
  int lastCheckedAt;
  final Map<SyncSection, SectionState> sections;

  static Map<SyncSection, SectionState> defaults() => {
    for (final section in SyncSection.values)
      section: SectionState(autoSync: section.defaultAuto),
  };

  void resetRemote() {
    for (final section in SyncSection.values) {
      sections[section] = sections[section]!.copyWith(
        lastSyncedAt: 0,
        lastRemoteUpdatedAt: 0,
      );
    }
  }

  factory SyncState.decode(String? value) {
    if (value == null) return SyncState();
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      final saved = json['sections'] as Map<String, dynamic>? ?? {};
      return SyncState(
        userId: json['userId'] as String? ?? '',
        credentialsFingerprint: json['credentials'] as String? ?? '',
        lastCheckedAt: json['lastCheckedAt'] is int
            ? json['lastCheckedAt'] as int
            : 0,
        sections: {
          for (final section in SyncSection.values)
            section: saved[section.key] is Map<String, dynamic>
                ? SectionState.fromJson(
                    saved[section.key] as Map<String, dynamic>,
                    section.defaultAuto,
                  )
                : SectionState(autoSync: section.defaultAuto),
        },
      );
    } catch (_) {
      return SyncState();
    }
  }

  String encode() => jsonEncode({
    'version': 2,
    'userId': userId,
    'credentials': credentialsFingerprint,
    'lastCheckedAt': lastCheckedAt,
    'sections': {
      for (final entry in sections.entries) entry.key.key: entry.value.toJson(),
    },
  });
}

class SyncStateStore {
  SyncStateStore(this.store);
  final LibraryStore store;
  Future<void> _writes = Future.value();

  Future<SyncState> load() async {
    try {
      return SyncState.decode(await store.read());
    } catch (_) {
      return SyncState();
    }
  }

  Future<void> save(SyncState state) {
    final encoded = state.encode();
    final write = _writes.then((_) => store.write(encoded));
    _writes = write.catchError((Object _) {});
    return write;
  }
}
