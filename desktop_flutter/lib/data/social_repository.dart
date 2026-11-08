import 'dart:async';

import '../data/account_store.dart';
import '../data/site_client.dart';
import '../domain/online_music.dart';
import '../domain/social.dart';

class SocialRepository {
  SocialRepository({required this.client, required this.accounts});
  final SiteClient client;
  final AccountStore accounts;

  String get _token => accounts.siteToken;

  Future<Map<String, dynamic>> _call(
    String path, {
    String method = 'GET',
    Map<String, String>? query,
    Map<String, dynamic>? body,
    bool anonymous = false,
  }) => client.social(
    path,
    _token,
    method: method,
    query: query,
    body: body,
    allowAnonymous: anonymous,
  );

  Future<List<SocialConversation>> conversations() async {
    final body = await _call('social/conversations');
    return [
      for (final row in socialMaps(body['conversations']))
        SocialConversation.fromJson(row),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<SocialConversation> openConversation(String peerId) async {
    final existing = await _call(
      'social/conversations/with/${Uri.encodeComponent(peerId)}',
    );
    final conversation = existing['conversation'];
    if (conversation is Map<String, dynamic>) {
      return SocialConversation.fromJson(conversation);
    }
    final created = await _call(
      'social/conversations',
      method: 'POST',
      body: {'peer': peerId},
    );
    final value = created['conversation'];
    if (value is! Map<String, dynamic>) {
      throw const MusicSearchException('无法创建会话。');
    }
    return SocialConversation.fromJson(value);
  }

  Future<List<SocialMessage>> messages(
    String conversationId, {
    int afterSeq = 0,
  }) async {
    final body = await _call(
      'social/conversations/${Uri.encodeComponent(conversationId)}/messages',
      query: {'limit': '100', if (afterSeq > 0) 'afterSeq': '$afterSeq'},
    );
    return [
      for (final row in socialMaps(body['messages'])) SocialMessage.fromJson(row),
    ];
  }

  Future<int> markRead(String conversationId, int seq) async {
    final body = await _call(
      'social/conversations/${Uri.encodeComponent(conversationId)}/read',
      method: 'POST',
      body: {'seq': seq},
    );
    return (body['unread'] as num?)?.toInt() ?? 0;
  }

  Future<SocialMessage> sendMessage({
    required String to,
    required String kind,
    String text = '',
    Map<String, dynamic>? song,
    String platform = '',
    required String clientId,
  }) async {
    final body = await _call(
      'social/messages',
      method: 'POST',
      body: {
        'to': to,
        'kind': kind,
        'body': text,
        'clientId': clientId,
        'song': ?song,
        if (platform.isNotEmpty) 'platform': platform,
      },
    );
    final value = body['message'];
    if (value is! Map<String, dynamic>) {
      throw const MusicSearchException('消息发送失败。');
    }
    return SocialMessage.fromJson(value);
  }

  Future<void> deleteMessage(String id) async {
    await _call('social/messages/${Uri.encodeComponent(id)}', method: 'DELETE');
  }

  Future<List<SocialProfile>> search(String query) async {
    final body = await _call(
      'social/users/search',
      query: {'q': query},
    );
    return [
      for (final row in socialMaps(body['users'])) SocialProfile.fromJson(row),
    ];
  }

  Future<SocialProfile> profile(String id) async {
    final body = await _call('social/users/${Uri.encodeComponent(id)}');
    final value = body['profile'];
    if (value is! Map<String, dynamic>) {
      throw const MusicSearchException('用户不存在。');
    }
    return SocialProfile.fromJson(value);
  }

  Future<bool> follow(String id, bool following) async {
    final body = await _call(
      'social/users/${Uri.encodeComponent(id)}/follow',
      method: following ? 'POST' : 'DELETE',
      body: following ? {'following': true} : null,
    );
    return body['following'] == true;
  }

  Future<void> block(String id, bool blocked) async {
    await _call(
      'social/blocks/${Uri.encodeComponent(id)}',
      method: blocked ? 'POST' : 'DELETE',
      body: blocked ? {'blocked': true} : null,
    );
  }

  Future<List<SocialShare>> feed() async {
    final body = await _call('social/feed');
    return [
      for (final row in socialMaps(body['shares'])) SocialShare.fromJson(row),
    ];
  }

  Future<SocialShare> createShare({
    required Map<String, dynamic> song,
    required String platform,
    String message = '',
    ShareOptions options = const ShareOptions(),
    String lyric = '',
    SocialProgress? progress,
  }) async {
    final body = await _call(
      'social/shares',
      method: 'POST',
      body: {
        'song': song,
        'platform': platform,
        'message': message,
        'options': options.toJson(),
        if (options.lyric) 'lyricSnippet': lyric,
        if (options.progress && progress != null)
          'progress': {
            'positionMs': progress.positionMs,
            'durationMs': progress.durationMs,
          },
      },
    );
    final share = body['share'];
    if (share is! Map<String, dynamic>) {
      throw const MusicSearchException('分享创建失败。');
    }
    return SocialShare.fromJson(share);
  }

  Future<SocialShare> share(String token) async {
    final body = await _call(
      'social/shares/${Uri.encodeComponent(token)}',
      anonymous: true,
    );
    final share = body['share'];
    if (share is! Map<String, dynamic>) {
      throw const MusicSearchException('分享不存在。');
    }
    return SocialShare.fromJson(share);
  }

  Future<SocialPreferences> preferences() async {
    final body = await _call('social/preferences');
    final value = body['preferences'];
    if (value is! Map<String, dynamic>) return const SocialPreferences();
    return SocialPreferences(dmPolicy: value['dmPolicy']?.toString() ?? 'everyone');
  }

  Future<SocialPreferences> savePreferences(String policy) async {
    final body = await _call(
      'social/preferences',
      method: 'PUT',
      body: {'dmPolicy': policy},
    );
    final value = body['preferences'];
    if (value is! Map<String, dynamic>) return SocialPreferences(dmPolicy: policy);
    return SocialPreferences(dmPolicy: value['dmPolicy']?.toString() ?? policy);
  }
}
