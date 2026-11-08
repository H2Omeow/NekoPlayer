import '../data/cloud_library.dart';
import '../domain/library.dart';

class SocialProfile {
  const SocialProfile({
    required this.id,
    this.username = '',
    this.nickname = '',
    this.avatar = '',
    this.bio = '',
    this.followers = 0,
    this.following = 0,
    this.isFollowing = false,
    this.isSelf = false,
    this.blocked = false,
  });

  factory SocialProfile.fromJson(Map<String, dynamic> json) => SocialProfile(
    id: json['id']?.toString() ?? '',
    username: json['username']?.toString() ?? '',
    nickname: json['nickname']?.toString() ?? '',
    avatar: json['avatar']?.toString() ?? '',
    bio: json['bio']?.toString() ?? '',
    followers: (json['followers'] as num?)?.toInt() ?? 0,
    following: (json['following'] as num?)?.toInt() ?? 0,
    isFollowing: json['isFollowing'] == true,
    isSelf: json['isSelf'] == true,
    blocked: json['blocked'] == true,
  );

  final String id;
  final String username;
  final String nickname;
  final String avatar;
  final String bio;
  final int followers;
  final int following;
  final bool isFollowing;
  final bool isSelf;
  final bool blocked;

  String get displayName => nickname.isNotEmpty
      ? nickname
      : username.isNotEmpty
      ? username
      : '用户';

  SocialProfile copyWith({
    int? followers,
    bool? isFollowing,
    bool? blocked,
  }) => SocialProfile(
    id: id,
    username: username,
    nickname: nickname,
    avatar: avatar,
    bio: bio,
    followers: followers ?? this.followers,
    following: following,
    isFollowing: isFollowing ?? this.isFollowing,
    isSelf: isSelf,
    blocked: blocked ?? this.blocked,
  );
}

class SocialProgress {
  const SocialProgress({this.positionMs = 0, this.durationMs = 0});
  factory SocialProgress.fromJson(Map<String, dynamic> json) => SocialProgress(
    positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
  );
  final int positionMs;
  final int durationMs;
  Duration get position => Duration(milliseconds: positionMs);
}

class ShareOptions {
  const ShareOptions({
    this.showSharer = true,
    this.cover = true,
    this.album = false,
    this.lyric = false,
    this.progress = false,
  });
  final bool showSharer;
  final bool cover;
  final bool album;
  final bool lyric;
  final bool progress;

  Map<String, dynamic> toJson() => {
    'showSharer': showSharer,
    'cover': cover,
    'album': album,
    'lyric': lyric,
    'progress': progress,
  };
}

class SocialShare {
  const SocialShare({
    required this.token,
    this.url = '',
    this.appUrl = '',
    this.platform = '音乐',
    this.song = const {},
    this.message = '',
    this.lyricSnippet = '',
    this.progress,
    this.sharer,
    this.createdAt = 0,
    this.revoked = false,
    this.owned = false,
  });

  factory SocialShare.fromJson(Map<String, dynamic> json) {
    final song = json['song'];
    return SocialShare(
      token: json['token']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      appUrl: json['appUrl']?.toString() ?? '',
      platform: json['platform']?.toString() ?? '音乐',
      song: song is Map<String, dynamic> ? song : const {},
      message: json['message']?.toString() ?? '',
      lyricSnippet: json['lyricSnippet']?.toString() ?? '',
      progress: json['progress'] is Map<String, dynamic>
          ? SocialProgress.fromJson(json['progress'] as Map<String, dynamic>)
          : null,
      sharer: json['sharer'] is Map<String, dynamic>
          ? SocialProfile.fromJson(json['sharer'] as Map<String, dynamic>)
          : null,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      revoked: json['revoked'] == true,
      owned: json['owned'] == true,
    );
  }

  final String token;
  final String url;
  final String appUrl;
  final String platform;
  final Map<String, dynamic> song;
  final String message;
  final String lyricSnippet;
  final SocialProgress? progress;
  final SocialProfile? sharer;
  final int createdAt;
  final bool revoked;
  final bool owned;

  Track? get track => song.isEmpty ? null : CloudLibrary.decodeSong(song);
}

class SocialMessage {
  const SocialMessage({
    required this.id,
    required this.conversationId,
    this.seq = 0,
    this.sender,
    this.senderId = '',
    this.kind = 'text',
    this.text = '',
    this.song = const {},
    this.shareToken,
    this.createdAt = 0,
    this.deleted = false,
    this.owned = false,
  });

  factory SocialMessage.fromJson(Map<String, dynamic> json) => SocialMessage(
    id: json['id']?.toString() ?? '',
    conversationId: json['conversationId']?.toString() ?? '',
    seq: (json['seq'] as num?)?.toInt() ?? 0,
    sender: json['sender'] is Map<String, dynamic>
        ? SocialProfile.fromJson(json['sender'] as Map<String, dynamic>)
        : null,
    senderId: json['senderId']?.toString() ?? '',
    kind: json['kind']?.toString() ?? 'text',
    text: json['text']?.toString() ?? '',
    song: json['song'] is Map<String, dynamic>
        ? json['song'] as Map<String, dynamic>
        : const {},
    shareToken: json['shareToken']?.toString(),
    createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    deleted: json['deleted'] == true,
    owned: json['owned'] == true,
  );

  final String id;
  final String conversationId;
  final int seq;
  final SocialProfile? sender;
  final String senderId;
  final String kind;
  final String text;
  final Map<String, dynamic> song;
  final String? shareToken;
  final int createdAt;
  final bool deleted;
  final bool owned;

  Track? get track => song.isEmpty ? null : CloudLibrary.decodeSong(song);
}

class SocialConversation {
  const SocialConversation({
    required this.id,
    this.peer,
    this.peerId = '',
    this.lastMessage,
    this.unread = 0,
    this.updatedAt = 0,
    this.createdAt = 0,
  });

  factory SocialConversation.fromJson(Map<String, dynamic> json) =>
      SocialConversation(
        id: json['id']?.toString() ?? '',
        peer: json['peer'] is Map<String, dynamic>
            ? SocialProfile.fromJson(json['peer'] as Map<String, dynamic>)
            : null,
        peerId: json['peerId']?.toString() ?? '',
        lastMessage: json['lastMessage'] is Map<String, dynamic>
            ? SocialMessage.fromJson(json['lastMessage'] as Map<String, dynamic>)
            : null,
        unread: (json['unread'] as num?)?.toInt() ?? 0,
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final SocialProfile? peer;
  final String peerId;
  final SocialMessage? lastMessage;
  final int unread;
  final int updatedAt;
  final int createdAt;

  SocialConversation withPeer(SocialProfile value) => SocialConversation(
    id: id,
    peer: value,
    peerId: peerId,
    lastMessage: lastMessage,
    unread: unread,
    updatedAt: updatedAt,
    createdAt: createdAt,
  );
}

class SocialPreferences {
  const SocialPreferences({this.dmPolicy = 'everyone'});
  final String dmPolicy;
}

List<Map<String, dynamic>> socialMaps(Object? value) => value is List
    ? value.whereType<Map<String, dynamic>>().toList()
    : const [];
