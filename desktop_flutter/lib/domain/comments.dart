import '../i18n/tr.dart';

enum CommentSource {
  site('本站'),
  netease('网易云'),
  kugou('酷狗');

  const CommentSource(this.rawLabel);
  final String rawLabel;
  String get label => tr(rawLabel);
}

class SongComment {
  const SongComment({
    required this.id,
    required this.user,
    required this.content,
    this.userId = '',
    this.time = '',
    this.likes = 0,
    this.liked = false,
    this.replies = 0,
    this.owned = false,
    this.deleted = false,
    this.parentId = '',
    this.quotedUser = '',
    this.quotedContent = '',
  });
  final String id;
  final String userId;
  final String user;
  final String content;
  final String time;
  final int likes;
  final bool liked;
  final int replies;
  final bool owned;
  final bool deleted;
  final String parentId;
  final String quotedUser;
  final String quotedContent;
}

class CommentPage {
  const CommentPage({
    this.comments = const [],
    this.total = 0,
    this.hasMore = false,
    this.specialId = '',
    this.resourceName = '',
    this.cursor = '',
  });
  final List<SongComment> comments;
  final int total;
  final bool hasMore;
  final String specialId;
  final String resourceName;
  final String cursor;
}
