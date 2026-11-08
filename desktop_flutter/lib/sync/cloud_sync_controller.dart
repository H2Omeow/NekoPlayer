import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../data/account_store.dart';
import '../data/cloud_library.dart';
import '../data/library_store.dart';
import '../data/site_client.dart';
import '../domain/online_music.dart';
import '../player_controller.dart';
import '../site_controller.dart';
import 'account_verifier.dart';
import 'cloud_credentials.dart';
import 'sync_section.dart';
import 'sync_state_store.dart';

class SectionResult {
  const SectionResult(this.section, this.ok, this.message);
  final SyncSection section;
  final bool ok;
  final String message;
}

typedef CloudSnapshot = ({
  Map<String, dynamic> data,
  Map<String, dynamic> meta,
});

String defaultDeviceName() {
  final system = switch (Platform.operatingSystem) {
    'linux' => 'Linux',
    'windows' => 'Windows',
    'macos' => 'macOS',
    final other => other,
  };
  String host;
  try {
    host = Platform.localHostname;
  } catch (_) {
    host = '';
  }
  return host.isEmpty ? system : '$system · $host';
}

class CloudSyncController extends ChangeNotifier with WidgetsBindingObserver {
  CloudSyncController({
    required this.site,
    required this.player,
    required LibraryStore store,
    this.verifier,
    String Function()? deviceName,
    int Function()? clock,
    this.debounce = const Duration(seconds: 3),
    this.focusThrottle = const Duration(seconds: 60),
  }) : _store = SyncStateStore(store),
       deviceName = deviceName ?? defaultDeviceName,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final SiteController site;
  final PlayerController player;
  final AccountVerifier? verifier;
  final String Function() deviceName;
  final Duration debounce;
  final Duration focusThrottle;
  final SyncStateStore _store;
  final int Function() _clock;

  SyncState _state = SyncState();
  Map<SyncSection, RemoteSection> remote = {};
  List<SectionResult> results = [];
  bool busy = false;
  String? error;
  Timer? _timer;
  bool _started = false;
  bool _disposed = false;
  int _applyingCredentials = 0;
  int _lastAutoAt = 0;
  String _lastToken = '';

  AccountStore get accounts => site.accounts;
  SiteClient get client => site.client;
  bool get signedIn => accounts.siteToken.isNotEmpty;
  int get lastCheckedAt => _state.lastCheckedAt;
  SectionState stateOf(SyncSection section) => _state.sections[section]!;

  int now() => _clock();

  int localCount(SyncSection section) {
    final online = {
      for (final track in player.tracks)
        if (track.online != null) track.path,
    };
    return switch (section) {
      SyncSection.favorites => player.favorites.where(online.contains).length,
      SyncSection.history => player.history.where(online.contains).length,
      SyncSection.playlists => player.playlists.length,
      SyncSection.credentials => CloudCredentials.localCount(accounts),
    };
  }

  SyncStatus statusOf(SyncSection section) {
    if (remote.isEmpty) return SyncStatus.unknown;
    return sectionStatus(
      state: stateOf(section),
      remote: remote[section] ?? const RemoteSection(),
      localHasData: localCount(section) > 0,
    );
  }

  /// 勾选了自动同步、但两端都有改动的分区。
  List<SyncSection> get conflicts => [
    for (final section in SyncSection.values)
      if (stateOf(section).autoSync && statusOf(section) == SyncStatus.conflict)
        section,
  ];

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _state = await _store.load();
    if (_disposed) return;
    final identity = CloudCredentials.identity(accounts);
    if (_state.credentialsFingerprint.isEmpty) {
      _state.credentialsFingerprint = identity;
      _save();
    } else if (_state.credentialsFingerprint != identity) {
      _state.credentialsFingerprint = identity;
      _markLocal(SyncSection.credentials);
    }
    _lastToken = accounts.siteToken;
    player.addSectionListener(_onSection);
    accounts.addListener(_onAccounts);
    WidgetsBinding.instance.addObserver(this);
    if (signedIn) unawaited(autoSync());
    _notify();
  }

  void _save() => unawaited(_store.save(_state).catchError((Object _) {}));

  void _markLocal(SyncSection section) {
    _state.sections[section] = stateOf(
      section,
    ).copyWith(localUpdatedAt: _clock());
    _save();
    _notify();
    if (stateOf(section).autoSync && signedIn) _schedule();
  }

  void _onSection(String key) {
    final section = SyncSection.byKey(key);
    if (section != null) _markLocal(section);
  }

  void _onAccounts() {
    final token = accounts.siteToken;
    if (token != _lastToken) {
      _lastToken = token;
      remote = {};
      _notify();
      if (token.isNotEmpty) unawaited(autoSync());
    }
    if (_applyingCredentials == 0) {
      final identity = CloudCredentials.identity(accounts);
      if (identity != _state.credentialsFingerprint) {
        _state.credentialsFingerprint = identity;
        _markLocal(SyncSection.credentials);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onFocus();
  }

  /// 窗口重新获得焦点；节流后检查一次。
  void onFocus() {
    if (!signedIn || _clock() - _lastAutoAt < focusThrottle.inMilliseconds) {
      return;
    }
    unawaited(autoSync());
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(autoSync()));
  }

  Future<void> setAuto(SyncSection section, bool value) async {
    _state.sections[section] = stateOf(section).copyWith(autoSync: value);
    _save();
    _notify();
    if (value && signedIn) _schedule();
  }

  // ---- 网络与状态 ----

  String _token() {
    final token = accounts.siteToken;
    if (token.isEmpty) throw const MusicSearchException('请先登录本站账号。');
    return token;
  }

  void _checkToken(String token) {
    if (_disposed || token != accounts.siteToken) {
      throw const MusicSearchException('本站账号已切换，已取消同步。');
    }
  }

  Future<void> _ensureUser(String token) async {
    final user = await site.ensureUser();
    _checkToken(token);
    final id = user['id']?.toString() ?? '';
    if (id.isNotEmpty && id != _state.userId) {
      _state.userId = id;
      _state.resetRemote();
      remote = {};
      _save();
    }
  }

  int _remoteCount(SyncSection section, Map<String, dynamic> data) {
    switch (section) {
      case SyncSection.favorites:
      case SyncSection.history:
        return CloudLibrary.items(data[section.key]).length;
      case SyncSection.playlists:
        return CloudLibrary.items(data['playlists']).length;
      case SyncSection.credentials:
        final cookies = data['kgCookies'];
        return (data['ncCookie'] is String && data['ncCookie'] != '' ? 1 : 0) +
            (cookies is List
                ? cookies.where((item) => item is String && item != '').length
                : 0);
    }
  }

  Map<String, dynamic> _metaSections(Map<String, dynamic> meta) =>
      meta['sections'] is Map<String, dynamic>
      ? meta['sections'] as Map<String, dynamic>
      : const {};

  void _applyMeta(Map<String, dynamic> meta, {Map<String, dynamic>? data}) {
    final sections = _metaSections(meta);
    remote = {
      for (final section in SyncSection.values)
        section: RemoteSection(
          updatedAt: sections[section.key] is Map
              ? ((sections[section.key] as Map)['updatedAt'] as num? ?? 0)
                    .toInt()
              : 0,
          device: sections[section.key] is Map
              ? (sections[section.key] as Map)['device']?.toString() ?? ''
              : '',
          count: data != null
              ? _remoteCount(section, data)
              : remote[section]?.count ?? 0,
        ),
    };
  }

  Future<CloudSnapshot> _fetch(String token) async {
    final snapshot = await client.fetch(token);
    _checkToken(token);
    _applyMeta(snapshot.meta, data: snapshot.data);
    _state.lastCheckedAt = _clock();
    _save();
    return snapshot;
  }

  String _describe(Object failure) => failure is SiteConflictException
      ? '云端数据已被其他设备更新，请刷新云端状态后手动选择方向。'
      : failure is MusicSearchException
      ? failure.message
      : failure is FormatException
      ? failure.message
      : failure is StateError
      ? failure.message
      : '同步未完成，请检查网络后重试。';

  Future<void> _run(Future<void> Function(String token) work) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    results = [];
    _lastAutoAt = _clock();
    _notify();
    try {
      final token = _token();
      if (!player.storageReadable) {
        throw const MusicSearchException('本地音乐库读取失败，已暂停云同步以保护数据。');
      }
      await _ensureUser(token);
      await work(token);
    } catch (failure) {
      error = _describe(failure);
    } finally {
      busy = false;
      _notify();
    }
  }

  // ---- 操作 ----

  Future<void> refresh() => _run((token) async {
    await _fetch(token);
  });

  Future<void> upload(Set<SyncSection> sections) => _run((token) async {
    final snapshot = await _fetch(token);
    await _upload(token, snapshot, sections);
  });

  Future<void> pull(Set<SyncSection> sections) => _run((token) async {
    final snapshot = await _fetch(token);
    await _pull(token, snapshot, sections);
  });

  Future<void> merge(Set<SyncSection> sections) => _run((token) async {
    final snapshot = await _fetch(token);
    final library = {
      for (final section in sections)
        if (section.isLibrary) section.key,
    };
    if (library.isNotEmpty) {
      final remoteLibrary = CloudLibrary.decode({
        for (final key in library) key: snapshot.data[key],
      });
      final local = player.snapshot;
      await player.applyCloudLibrary(
        CloudLibrary.takeSections(
          local,
          CloudLibrary.merge(local, remoteLibrary),
          library,
        ),
      );
    }
    if (sections.contains(SyncSection.credentials)) {
      await _importCredentials(token, snapshot.data, onlyMissing: true);
    }
    await _upload(
      token,
      snapshot,
      sections,
      merge: true,
      expected: {
        for (final section in sections)
          section.key: remote[section]?.updatedAt ?? 0,
      },
    );
  });

  /// 自动同步：只处理勾选的分区，且只处理单边改动。
  Future<void> autoSync() async {
    if (!_started || _disposed || !signedIn) return;
    if (busy) return _schedule();
    await _run((token) async {
      final snapshot = await _fetch(token);
      final pulls = <SyncSection>{};
      final uploads = <SyncSection>{};
      for (final section in SyncSection.values) {
        if (!stateOf(section).autoSync) continue;
        final status = statusOf(section);
        switch (autoAction(status)) {
          case SyncAction.pull:
            pulls.add(section);
          case SyncAction.upload:
            uploads.add(section);
          case SyncAction.none:
            if (status == SyncStatus.conflict) {
              results.add(SectionResult(section, false, '两端都有改动，请在云端同步页选择方向。'));
            }
        }
      }
      if (pulls.isNotEmpty) await _pull(token, snapshot, pulls);
      if (uploads.isNotEmpty) {
        await _upload(
          token,
          snapshot,
          uploads,
          expected: {
            for (final section in uploads)
              section.key: stateOf(section).lastRemoteUpdatedAt,
          },
        );
      }
    });
  }

  void _markSynced(SyncSection section, int syncedAt) {
    _state.sections[section] = stateOf(section).copyWith(
      lastSyncedAt: syncedAt,
      lastRemoteUpdatedAt: remote[section]?.updatedAt ?? 0,
    );
    _save();
  }

  Future<void> _upload(
    String token,
    CloudSnapshot snapshot,
    Set<SyncSection> sections, {
    bool merge = false,
    Map<String, int>? expected,
  }) async {
    final startedAt = _clock();
    final library = player.snapshot;
    final merged = merge ? CloudLibrary.encode(library, snapshot.data) : null;
    final payload = <String, Object?>{};
    final counts = <SyncSection, int>{};
    for (final section in sections) {
      if (section.isLibrary) {
        final value =
            merged?[section.key] ??
            CloudLibrary.overwriteSection(library, section.key, snapshot.data);
        payload[section.key] = value;
        counts[section] = (value as List).length;
        continue;
      }
      final credentials = CloudCredentials.payload(
        accounts,
        remote: merge ? snapshot.data : null,
      );
      if (credentials == null) {
        results.add(SectionResult(section, false, '本机没有登录凭据，未上传（避免清空云端）。'));
      } else {
        payload[section.key] = credentials;
        counts[section] = CloudCredentials.localCount(accounts);
      }
    }
    if (payload.isEmpty) return;
    Map<String, dynamic> meta;
    try {
      meta = await client.patchSections(
        token,
        device: deviceName(),
        sections: payload,
        expected: expected,
      );
    } on SiteConflictException catch (conflict) {
      _applyMeta(conflict.meta);
      results.addAll([
        for (final section in counts.keys)
          SectionResult(section, false, '云端刚被其他设备更新，未覆盖；请手动选择方向。'),
      ]);
      return;
    }
    _checkToken(token);
    _applyMeta(meta);
    for (final entry in counts.entries) {
      remote[entry.key] = RemoteSection(
        updatedAt: remote[entry.key]!.updatedAt,
        device: remote[entry.key]!.device,
        count: entry.value,
      );
      _markSynced(entry.key, startedAt);
      results.add(
        SectionResult(
          entry.key,
          true,
          merge ? '已合并并上传，共 ${entry.value} 项。' : '已上传到云端，共 ${entry.value} 项。',
        ),
      );
    }
  }

  Future<void> _pull(
    String token,
    CloudSnapshot snapshot,
    Set<SyncSection> sections,
  ) async {
    final library = {
      for (final section in sections)
        if (section.isLibrary) section.key,
    };
    if (library.isNotEmpty) {
      final remoteLibrary = CloudLibrary.decode({
        for (final key in library) key: snapshot.data[key],
      });
      final startedAt = _clock();
      await player.applyCloudLibrary(
        CloudLibrary.replaceSections(player.snapshot, remoteLibrary, library),
      );
      for (final key in library) {
        final section = SyncSection.byKey(key)!;
        _markSynced(section, startedAt);
        results.add(
          SectionResult(
            section,
            true,
            '已从云端拉取，共 ${remote[section]?.count ?? 0} 项。',
          ),
        );
      }
    }
    if (sections.contains(SyncSection.credentials)) {
      final startedAt = _clock();
      if (await _importCredentials(token, snapshot.data, onlyMissing: false)) {
        _markSynced(SyncSection.credentials, startedAt);
      }
    }
  }

  /// 用云端登录替换（或仅补全）本机登录，并向平台确认账号后报告结果。
  Future<bool> _importCredentials(
    String token,
    Map<String, dynamic> data, {
    required bool onlyMissing,
  }) async {
    final parsed = CloudCredentials.parse(data);
    final useNetease =
        parsed.netease != null && !(onlyMissing && accounts.neteaseLoggedIn);
    final slots = [
      for (var slot = 0; slot < 2; slot++)
        parsed.kugou[slot] != null &&
                !(onlyMissing && accounts.kugouLoggedIn(slot))
            ? parsed.kugou[slot]
            : null,
    ];
    final lines = [...parsed.notes];
    if (!useNetease && slots.every((slot) => slot == null)) {
      results.add(
        SectionResult(
          SyncSection.credentials,
          onlyMissing && !parsed.isEmpty,
          [
            onlyMissing && !parsed.isEmpty
                ? '本机登录已完整，无需导入。'
                : '云端没有可导入的有效登录凭据，本机登录未改变。',
            ...lines,
          ].join(' '),
        ),
      );
      return false;
    }
    _applyingCredentials++;
    try {
      await accounts.replaceSessions(
        netease: useNetease ? parsed.netease : null,
        kugou: slots,
        platform: slots.any((slot) => slot != null)
            ? (slots[parsed.platform ?? 0] != null
                  ? parsed.platform
                  : slots[0] != null
                  ? 0
                  : 1)
            : null,
        expectedSiteToken: token,
      );
      if (useNetease) {
        lines.add(await _verify(MusicProvider.netease, '网易云', null));
      }
      for (var slot = 0; slot < 2; slot++) {
        if (slots[slot] == null) continue;
        final label = slot == 0 ? '酷狗原版' : '酷狗概念版';
        if (accounts.kugouTokenOnly(slot)) {
          lines.add('$label：已导入 token，但云端没有 userid，可播放，账号信息与权益不可用。');
        } else if (slot == accounts.platform) {
          lines.add(await _verify(MusicProvider.kugou, label, slot));
        } else {
          lines.add('$label：已导入。');
        }
      }
    } finally {
      _applyingCredentials--;
      _state.credentialsFingerprint = CloudCredentials.identity(accounts);
      _save();
    }
    results.add(SectionResult(SyncSection.credentials, true, lines.join(' ')));
    return true;
  }

  Future<String> _verify(
    MusicProvider provider,
    String label,
    int? slot,
  ) async {
    final verify = verifier;
    if (verify == null) return '$label：已导入。';
    try {
      final name = await verify(provider);
      if (provider == MusicProvider.netease) {
        accounts.setNickname(netease: name);
      } else {
        accounts.setNickname(kugouSlot: slot, kugou: name);
      }
      return '$label：已导入并验证（$name）。';
    } catch (failure) {
      return '$label：已导入，但账号验证失败（${_describe(failure)}）。';
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (_started) {
      player.removeSectionListener(_onSection);
      accounts.removeListener(_onAccounts);
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }
}
