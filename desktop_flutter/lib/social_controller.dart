import './i18n/app_language.dart';
import './i18n/tr.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/account_store.dart';
import '../data/cloud_library.dart';
import '../data/site_client.dart';
import '../data/social_repository.dart';
import '../domain/library.dart';
import '../domain/online_music.dart';
import '../domain/social.dart';
import '../player_controller.dart';

class SocialController extends ChangeNotifier {
  SocialController({
    required AccountStore accounts,
    required SiteClient client,
    required PlayerController player,
    this.onSnack,
    this.onNotify,
  }) : repository = SocialRepository(client: client, accounts: accounts),
       _accounts = accounts,
       _player = player;

  final AccountStore _accounts;
  final PlayerController _player;
  final SocialRepository repository;
  final void Function(String message)? onSnack;
  final void Function(String title, String body, String uri)? onNotify;

  List<SocialConversation> conversations = const [];
  int unread = 0;
  List<SocialShare> feed = const [];
  List<SocialProfile> searchResults = const [];
  SocialConversation? active;
  List<SocialMessage> messages = const [];
  SocialProfile? profile;
  bool profileLoading = false;
  SocialPreferences preferences = const SocialPreferences();
  bool busy = false;
  bool loadingFeed = false;
  bool searching = false;
  bool loadingMessages = false;
  bool sseConnected = false;
  String? error;

  bool _started = false;
  bool _disposed = false;
  int _generation = 0;
  Timer? _poll;
  HttpClient? _sseClient;

  void start() {
    if (_started || _disposed || _accounts.siteToken.isEmpty) return;
    _started = true;
    _generation += 1;
    unawaited(refreshConversations(silent: true));
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(refreshConversations(silent: true));
      if (active != null) unawaited(_loadNewMessages());
    });
    unawaited(_sseLoop(_generation));
    _notify();
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _generation += 1;
    _poll?.cancel();
    _poll = null;
    _sseClient?.close(force: true);
    _sseClient = null;
    conversations = const [];
    unread = 0;
    active = null;
    messages = const [];
    profile = null;
    sseConnected = false;
    _notify();
  }

  Future<T?> _guard<T>(Future<T> Function() work) async {
    try {
      return await work();
    } on MusicSearchException catch (failure) {
      error = failure.message;
    } on HandshakeException {
      error = tr('本站 TLS 证书验证失败。');
    } on IOException {
      error = tr('无法连接本站，请检查网络。');
    } on FormatException {
      error = tr('本站响应格式异常。');
    } catch (_) {
      error = tr('操作未完成，请稍后重试。');
    }
    return null;
  }

  Future<void> refreshConversations({bool silent = false}) async {
    if (!_started) return;
    final result = await _guard(repository.conversations);
    if (result == null || _disposed) return;
    final activeId = active?.id;
    conversations = result;
    unread = result.fold(0, (sum, item) => sum + item.unread);
    if (activeId != null) {
      final updated = result.where((item) => item.id == activeId).firstOrNull;
      if (updated != null) active = updated;
    }
    if (!silent) error = null;
    _notify();
  }

  Future<void> openChat(String peerId, {SocialConversation? conversation}) async {
    if (peerId.isEmpty && conversation == null) return;
    active = conversation ??
        conversations.where((item) => item.peerId == peerId).firstOrNull;
    messages = const [];
    loadingMessages = true;
    _notify();
    final opened = await _guard(() async {
      final target = conversation ??
          conversations.where((item) => item.peerId == peerId).firstOrNull ??
          await repository.openConversation(peerId);
      final rows = await repository.messages(target.id);
      return (target, rows);
    });
    if (opened == null || _disposed) {
      loadingMessages = false;
      _notify();
      return;
    }
    active = opened.$1;
    messages = opened.$2;
    loadingMessages = false;
    await _markRead();
    _notify();
    unawaited(refreshConversations(silent: true));
  }

  void closeChat() {
    active = null;
    messages = const [];
    loadingMessages = false;
    _notify();
  }

  Future<void> _loadNewMessages() async {
    final current = active;
    if (current == null) return;
    final after = messages.isEmpty ? 0 : messages.last.seq;
    final rows = await _guard(() => repository.messages(current.id, afterSeq: after));
    if (rows == null || _disposed || active?.id != current.id) return;
    if (rows.isEmpty) return;
    _mergeMessages(rows);
    await _markRead();
    _notify();
  }

  void _mergeMessages(List<SocialMessage> rows) {
    final known = {for (final message in messages) message.id: message};
    for (final message in rows) {
      known[message.id] = message;
    }
    messages = known.values.toList()..sort((a, b) => a.seq.compareTo(b.seq));
  }

  Future<void> _markRead() async {
    final current = active;
    if (current == null || messages.isEmpty) return;
    final seq = messages.last.seq;
    final remaining = await _guard(() => repository.markRead(current.id, seq));
    if (remaining == null) return;
    final updated = conversations
        .where((item) => item.id == current.id)
        .firstOrNull;
    if (updated != null) {
      conversations = [
        for (final item in conversations)
          if (item.id == current.id)
            SocialConversation(
              id: item.id,
              peer: item.peer,
              peerId: item.peerId,
              lastMessage: item.lastMessage,
              unread: remaining,
              updatedAt: item.updatedAt,
              createdAt: item.createdAt,
            )
          else
            item,
      ];
      unread = conversations.fold(0, (sum, item) => sum + item.unread);
    }
  }

  Future<bool> sendText(String text) async {
    final current = active;
    final body = text.trim();
    if (current == null || body.isEmpty) return false;
    final sent = await _guard(
      () => repository.sendMessage(
        to: current.peerId,
        kind: 'text',
        text: body,
        clientId: _clientId(),
      ),
    );
    if (sent == null) return false;
    _mergeMessages([sent]);
    _notify();
    unawaited(refreshConversations(silent: true));
    return true;
  }

  Future<bool> sendSong(Track track) async {
    final current = active;
    if (current == null || track.online == null) return false;
    final sent = await _guard(
      () => repository.sendMessage(
        to: current.peerId,
        kind: 'song',
        song: CloudLibrary.encodeSong(track),
        platform: platformLabel(track),
        clientId: _clientId(),
      ),
    );
    if (sent == null) return false;
    _mergeMessages([sent]);
    _notify();
    unawaited(refreshConversations(silent: true));
    return true;
  }

  Future<void> deleteMessage(SocialMessage message) async {
    if (!message.owned) return;
    await _guard(() => repository.deleteMessage(message.id));
    messages = [
      for (final item in messages)
        if (item.id == message.id)
          SocialMessage(
            id: item.id,
            conversationId: item.conversationId,
            seq: item.seq,
            sender: item.sender,
            senderId: item.senderId,
            kind: item.kind,
            text: '',
            createdAt: item.createdAt,
            deleted: true,
            owned: true,
          )
        else
          item,
    ];
    _notify();
  }

  Future<void> loadFeed() async {
    if (loadingFeed) return;
    loadingFeed = true;
    _notify();
    final result = await _guard(repository.feed);
    if (result != null) feed = result;
    loadingFeed = false;
    _notify();
  }

  Future<void> search(String query) async {
    final clean = query.trim();
    if (clean.length < 2) {
      error = tr('至少输入 2 个字符。');
      _notify();
      return;
    }
    searching = true;
    _notify();
    final result = await _guard(() => repository.search(clean));
    if (result != null) searchResults = result;
    searching = false;
    _notify();
  }

  Future<void> loadProfile(String id) async {
    profileLoading = true;
    _notify();
    final result = await _guard(() => repository.profile(id));
    if (_disposed) return;
    profile = result;
    profileLoading = false;
    if (result != null) {
      unawaited(_loadPreferences());
    }
    _notify();
  }

  void closeProfile() {
    profile = null;
    _notify();
  }

  Future<void> toggleFollow(SocialProfile target) async {
    final following = await _guard(
      () => repository.follow(target.id, !target.isFollowing),
    );
    if (following == null) {
      _notify();
      return;
    }
    final updated = target.copyWith(
      isFollowing: following,
      followers: (target.followers + (following ? 1 : -1)).clamp(0, 1 << 30),
    );
    if (profile?.id == target.id) profile = updated;
    searchResults = [
      for (final item in searchResults)
        if (item.id == target.id) updated else item,
    ];
    onSnack?.call(following ? tr('已关注') : tr('已取消关注'));
    _notify();
  }

  Future<void> toggleBlock(SocialProfile target) async {
    final blocked = !target.blocked;
    await _guard(() => repository.block(target.id, blocked));
    if (profile?.id == target.id) profile = target.copyWith(blocked: blocked);
    onSnack?.call(blocked ? tr('已拉黑') : tr('已取消拉黑'));
    _notify();
  }

  Future<void> _loadPreferences() async {
    final result = await _guard(repository.preferences);
    if (result != null) {
      preferences = result;
      _notify();
    }
  }

  Future<void> savePreferences(String policy) async {
    final result = await _guard(() => repository.savePreferences(policy));
    if (result != null) {
      preferences = result;
      onSnack?.call(tr('私信设置已保存'));
      _notify();
    }
  }

  Future<SocialShare?> createShare(
    Track track, {
    required String message,
    required ShareOptions options,
    required String lyric,
    SocialProgress? progress,
  }) async {
    if (track.online == null) return null;
    final result = await _guard(
      () => repository.createShare(
        song: CloudLibrary.encodeSong(track),
        platform: platformLabel(track),
        message: message,
        options: options,
        lyric: options.lyric ? lyric : '',
        progress: options.progress ? progress : null,
      ),
    );
    if (result == null) _notify();
    return result;
  }

  Future<void> openShareToken(String token) async {
    final result = await _guard(() => repository.share(token));
    if (result == null) {
      _notify();
      return;
    }
    if (result.revoked) {
      error = tr('分享已失效。');
      _notify();
      return;
    }
    final track = result.track;
    if (track == null) {
      error = tr('分享中的歌曲无法在当前版本播放。');
      _notify();
      return;
    }
    await _player.play([track], 0);
    if (result.progress != null && result.progress!.positionMs > 0) {
      await _player.seek(result.progress!.position);
    }
  }

  void clearError() {
    error = null;
    _notify();
  }

  String _clientId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_player.hashCode}-$_generation';

  Future<void> _sseLoop(int generation) async {
    var attempt = 0;
    while (_started && !_disposed && generation == _generation) {
      final token = _accounts.siteToken;
      if (token.isEmpty) break;
      final client = HttpClient()..idleTimeout = const Duration(minutes: 10);
      _sseClient = client;
      try {
        final request = await client.getUrl(
          Uri.https('player.nekoh2o.top', '/social/events'),
        );
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
        request.headers.set(
          HttpHeaders.acceptLanguageHeader,
          AppLanguage.currentTag,
        );
        final response = await request.close();
        if (response.statusCode == 401) {
          client.close(force: true);
          return;
        }
        if (response.statusCode != 200) {
          throw       MusicSearchException(tr('实时连接失败。'));
        }
        var event = 'message';
        final data = <String>[];
        await for (final line in response
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (!_started || generation != _generation) break;
          if (line.isEmpty) {
            if (data.isNotEmpty) {
              _handleSse(event, data.join('\n'));
              event = 'message';
              data.clear();
            }
            continue;
          }
          if (line.startsWith(':')) continue;
          final colon = line.indexOf(':');
          final field = colon < 0 ? line : line.substring(0, colon);
          final value = colon < 0 ? '' : line.substring(colon + 1).replaceFirst(RegExp(r'^ '), '');
          if (field == 'event') event = value;
          if (field == 'data') data.add(value);
        }
      } catch (_) {
        // 断线后重连
      } finally {
        client.close(force: true);
        if (identical(_sseClient, client)) _sseClient = null;
      }
      if (!_started || generation != _generation) break;
      sseConnected = false;
      attempt += 1;
      await Future<void>.delayed(
        Duration(seconds: (1 << attempt.clamp(0, 5)).clamp(1, 60)),
      );
    }
  }

  void _handleSse(String event, String data) {
    if (event == 'ready') {
      sseConnected = true;
      _notify();
      return;
    }
    if (event == 'follow') {
      onSnack?.call(tr('有新粉丝关注了你'));
      return;
    }
    if (event != 'message') return;
    final decoded = jsonDecode(data);
    if (decoded is! Map<String, dynamic>) return;
    final messageJson = decoded['message'];
    if (messageJson is! Map<String, dynamic>) return;
    final message = SocialMessage.fromJson(messageJson);
    final current = active;
    if (current != null && current.id == message.conversationId) {
      _mergeMessages([message]);
      if (!message.owned) unawaited(_markRead());
      _notify();
    } else {
      unawaited(refreshConversations(silent: true));
      if (!message.owned) {
        final sender = message.sender?.displayName ?? tr('新消息');
        final body = message.deleted
            ? ''
            : message.kind == 'song'
            ? tr('[歌曲] {title}', {
                'title': message.song['nm'] ?? tr('分享'),
              })
            : message.text;
        onSnack?.call('$sender：$body');
        onNotify?.call(
          sender,
          body.isEmpty ? tr('发来一条消息') : body,
          'nekoplayer://chat?peer=${Uri.encodeComponent(decoded['peerId']?.toString() ?? message.senderId)}',
        );
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}

String platformLabel(Track track) {
  final provider = track.online?.provider;
  if (provider == null) return tr('音乐');
  return provider.label;
}
