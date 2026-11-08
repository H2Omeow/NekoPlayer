import '../i18n/tr.dart';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/comments.dart';
import '../domain/online_music.dart';
import 'native_music_catalog.dart';
import 'site_client.dart';

class CommentsRepository {
  CommentsRepository(this.catalog, {SiteClient? site})
    : site = site ?? SiteClient();
  final NativeMusicCatalog catalog;
  final SiteClient site;
  static const commentCode = 'fc4be23b4e972707f36b8a828a93ba8a';

  static String text(Object? value) => value?.toString() ?? '';
  static int number(Object? value) => int.tryParse(text(value)) ?? 0;
  static Map<String, dynamic> object(Object? value) =>
      value is Map<String, dynamic> ? value : {};
  static List<Map<String, dynamic>> items(Object? value) =>
      value is List ? value.whereType<Map<String, dynamic>>().toList() : [];
  static Map<String, dynamic> payload(Map<String, dynamic> body) =>
      body['data'] is Map<String, dynamic> ? object(body['data']) : body;
  static String songKey(OnlineSong song) {
    if (song.provider == MusicProvider.kugou) {
      return 'kugou:${song.hash.toLowerCase()}';
    }
    if (song.provider.gateway == null) return 'netease:${song.id}';
    var hash = 0;
    for (final unit in '${song.provider.gateway}:${song.id}'.codeUnits) {
      hash = (hash * 31 + unit).toSigned(32);
    }
    return 'netease:${hash == 0 ? 1 : hash}';
  }

  bool loggedIn(CommentSource source) => switch (source) {
    CommentSource.site => catalog.accounts.siteToken.isNotEmpty,
    CommentSource.netease => catalog.accounts.neteaseLoggedIn,
    CommentSource.kugou => catalog.accounts.kugouLoggedIn(),
  };

  Future<String> accountId(CommentSource source) async {
    if (!loggedIn(source)) return '';
    if (source == CommentSource.site) return 'site';
    if (source == CommentSource.kugou) {
      return catalog.accounts.kugou()['userid'] ?? '';
    }
    final body = await catalog.neteaseApi(
      '/api/nuser/account/get',
      {},
      weapi: true,
    );
    return text(object(body['account'])['id']);
  }

  Future<List<OnlineSong>> matches(
    CommentSource source,
    OnlineSong song,
  ) async {
    if (source == CommentSource.site || source.name == song.provider.name) {
      return [song];
    }
    final result = await catalog.search(
      source == CommentSource.netease
          ? MusicProvider.netease
          : MusicProvider.kugou,
      '${song.title} ${song.artist}',
      1,
    );
    return result.songs.take(10).toList();
  }

  Future<CommentPage> list(
    CommentSource source,
    OnlineSong song, {
    int offset = 0,
    String account = '',
    SongComment? parent,
    CommentPage previous = const CommentPage(),
  }) async {
    _checkSong(source, song);
    if (source == CommentSource.site) {
      final body = await site.commentRequest(
        'comments',
        catalog.accounts.siteToken,
        query: {
          'song': songKey(song),
          'offset': '$offset',
          'limit': '20',
          if (parent != null) 'parent': parent.id,
        },
      );
      return CommentPage(
        comments: [
          for (final item in items(body['comments']))
            SongComment(
              id: text(item['id']),
              userId: text(item['userId']),
              user: text(item['userName']),
              content: text(item['content']),
              time: text(item['createdAt']),
              likes: number(item['likes']),
              liked: item['liked'] == true,
              replies: number(item['replies']),
              owned: item['owned'] == true,
              deleted: item['deleted'] == true,
              parentId: text(item['parentId']),
              quotedUser: text(item['quotedUser']),
              quotedContent: text(item['quotedContent']),
            ),
        ],
        total: number(body['total']),
        hasMore: body['more'] == true,
      );
    }
    if (source == CommentSource.netease) {
      final body = await catalog.neteaseApi(
        parent == null
            ? '/api/v1/resource/comments/R_SO_4_${song.id}'
            : '/api/resource/comment/floor/get',
        {
          if (parent == null) ...{
            'rid': song.id,
            'limit': 20,
            'offset': offset,
            'beforeTime': 0,
          } else ...{
            'parentCommentId': parent.id,
            'threadId': 'R_SO_4_${song.id}',
            'time': int.tryParse(previous.cursor) ?? -1,
            'limit': 20,
          },
        },
        weapi: true,
      );
      _checkNc(body);
      final data = parent == null ? body : object(body['data']);
      final rows = items(data['comments']);
      return CommentPage(
        comments: [for (final item in rows) _neteaseComment(item, account)],
        total: number(data['total'] ?? data['totalCount']),
        hasMore: data['more'] == true || data['hasMore'] == true,
        cursor: rows.isEmpty ? '' : text(rows.last['time']),
      );
    }
    await catalog.initializeProvider(MusicProvider.kugou);
    if ((int.tryParse(song.albumAudioId) ?? 0) <= 0) {
      throw       MusicSearchException(tr('缺少酷狗评论资源标识，请重新搜索歌曲。'));
    }
    final body = await catalog.kugouApi(
      parent == null ? '/mcomment/v1/cmtlist' : '/mcomment/v1/hot_replylist',
      {
        'mixsongid': song.albumAudioId,
        'need_show_image': '1',
        'p': '${offset ~/ 20 + 1}',
        'pagesize': '20',
        'show_classify': '1',
        'show_hotword_list': '1',
        'extdata': '0',
        'code': commentCode,
        if (parent != null) ...{
          'childrenid': previous.specialId,
          'tid': parent.id,
        },
      },
      rawBody: '',
    );
    _checkKg(body);
    final rows = items(body['list']).isNotEmpty
        ? items(body['list'])
        : items(payload(body)['list']);
    final total = number(body['count'] ?? body['combine_count']);
    return CommentPage(
      comments: [
        for (final item in rows)
          SongComment(
            id: text(item['id'] ?? item['tid']),
            userId: text(item['user_id'] ?? item['kugouid']),
            user: text(item['user_name'] ?? item['username']),
            content: text(item['content']),
            time: text(item['addtime']),
            likes: number(
              object(item['like'])['count'] ?? object(item['like'])['likenum'],
            ),
            liked: [
              'true',
              '1',
            ].contains(text(object(item['like'])['haslike'])),
            replies: number(item['reply_num']),
            owned:
                account.isNotEmpty &&
                account == text(item['user_id'] ?? item['kugouid']),
            parentId: parent?.id ?? '',
            quotedUser: text(item['puser']),
            quotedContent: text(item['pcontent']),
          ),
      ],
      total: total,
      hasMore: rows.isNotEmpty && offset + rows.length < total,
      specialId: text(body['childrenid']).isNotEmpty
          ? text(body['childrenid'])
          : rows.isNotEmpty && text(rows.first['special_child_id']).isNotEmpty
          ? text(rows.first['special_child_id'])
          : previous.specialId,
      resourceName: rows.isEmpty
          ? ''
          : text(
              rows.first['special_child_name'] ?? rows.first['song_show_text'],
            ),
    );
  }

  static SongComment _neteaseComment(
    Map<String, dynamic> item,
    String account,
  ) {
    final user = object(item['user']);
    final quote = items(item['beReplied']).firstOrNull ?? {};
    return SongComment(
      id: text(item['commentId']),
      userId: text(user['userId']),
      user: text(user['nickname']),
      content: text(item['content']),
      time: text(item['timeStr'] ?? item['time']),
      likes: number(item['likedCount']),
      liked: item['liked'] == true,
      replies: number(item['replyCount']),
      owned: account.isNotEmpty && account == text(user['userId']),
      quotedUser: text(object(quote['user'])['nickname']),
      quotedContent: text(quote['content']),
    );
  }

  void _requireAccount(CommentSource source) {
    if (!loggedIn(source)) throw       MusicSearchException(tr('请先登录对应平台账号。'));
  }

  static void _checkNc(Map<String, dynamic> body) {
    if (number(body['code']) != 200) {
      throw       MusicSearchException(tr('网易云未确认评论操作成功，请检查登录与权限。'));
    }
  }

  static void _checkKg(Map<String, dynamic> body) {
    if (number(body['status']) != 1 ||
        number(body['error_code'] ?? body['errcode']) != 0) {
      throw       MusicSearchException(tr('酷狗未确认评论操作成功，请检查登录与权限。'));
    }
  }

  Future<void> send(
    CommentSource source,
    OnlineSong song,
    String content, {
    SongComment? parent,
    CommentPage page = const CommentPage(),
  }) async {
    _checkSong(source, song);
    _requireAccount(source);
    content = content.trim();
    if (content.isEmpty || content.length > 2000) {
      throw       MusicSearchException(tr('评论需为 1–2000 个字符。'));
    }
    if (source == CommentSource.site) {
      await site.commentRequest(
        'comments',
        catalog.accounts.siteToken,
        method: 'POST',
        body: {
          'song': songKey(song),
          'content': content,
          if (parent != null) 'parentId': parent.id,
        },
      );
    } else if (source == CommentSource.netease) {
      _checkNc(
        await catalog.neteaseApi(
          '/api/resource/comments/${parent == null ? 'add' : 'reply'}',
          {
            'threadId': 'R_SO_4_${song.id}',
            'content': content,
            if (parent != null) 'commentId': parent.id,
          },
          weapi: true,
        ),
      );
    } else {
      if (page.specialId.isEmpty) {
        throw       MusicSearchException(tr('缺少酷狗评论资源，请刷新后重试。'));
      }
      final session = catalog.accounts.kugou();
      final lite = catalog.accounts.platform == 1;
      final seconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final body = parent == null
          ? {
              'data': {
                'content': content,
                'album_audio_id': song.albumAudioId,
                'images': [],
              },
            }
          : null;
      final mid = session['KUGOU_API_MID']!;
      final appid = lite ? 3116 : 1005;
      final version = lite ? 11440 : 20489;
      final salt = lite
          ? 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA'
          : 'OIlwieks28dk2k092lksi2UIkp';
      final keyText =
          '$appid$salt$version$seconds$mid${parent == null ? jsonEncode(body!) : ''}';
      final result = await catalog.kugouApi(
        '/index.php',
        {
          'r': parent == null ? 'commentsv3/add' : 'commentsv2/reply',
          'code': commentCode,
          'childrenid': page.specialId,
          'childrenname': page.resourceName.isEmpty
              ? '${song.artist} - ${song.title}'
              : page.resourceName,
          'kugouid': session['userid']!,
          'ver': '6',
          'clienttoken': session['token']!,
          'appid': '$appid',
          'clientver': '$version',
          'mid': mid,
          'clienttime': '$seconds',
          'uuid': '-',
          'dfid': session['dfid'] ?? '-',
          'key': md5.convert(utf8.encode(keyText)).toString(),
          if (parent != null) ...{
            'content': content,
            'tid': parent.parentId.isEmpty ? parent.id : parent.parentId,
            'pid': parent.parentId.isEmpty ? '0' : parent.id,
            'is_t': parent.parentId.isEmpty ? '1' : '0',
          },
        },
        router: 'm.comment.service.kugou.com',
        body: body,
        rawBody: body == null ? '' : null,
        clear: true,
        sign: false,
      );
      _checkKg(result);
    }
  }

  Future<void> like(
    CommentSource source,
    OnlineSong song,
    SongComment comment,
  ) async {
    _checkSong(source, song);
    _requireAccount(source);
    if (source == CommentSource.site) {
      await site.commentRequest(
        'comments/${comment.id}/like',
        catalog.accounts.siteToken,
        method: 'POST',
        body: {'liked': !comment.liked},
      );
    } else if (source == CommentSource.netease) {
      _checkNc(
        await catalog.neteaseApi(
          '/api/v1/comment/${comment.liked ? 'unlike' : 'like'}',
          {'threadId': 'R_SO_4_${song.id}', 'commentId': comment.id},
          weapi: true,
        ),
      );
    } else {
      throw       MusicSearchException(tr('酷狗点赞接口尚未验证，暂不开放。'));
    }
  }

  Future<void> delete(
    CommentSource source,
    OnlineSong song,
    SongComment comment,
  ) async {
    _checkSong(source, song);
    _requireAccount(source);
    if (!comment.owned) throw       MusicSearchException(tr('只能删除本人评论。'));
    if (source == CommentSource.site) {
      await site.commentRequest(
        'comments/${comment.id}',
        catalog.accounts.siteToken,
        method: 'DELETE',
      );
    } else if (source == CommentSource.netease) {
      _checkNc(
        await catalog.neteaseApi('/api/resource/comments/delete', {
          'threadId': 'R_SO_4_${song.id}',
          'commentId': comment.id,
        }, weapi: true),
      );
    } else {
      throw       MusicSearchException(tr('酷狗删除接口尚未验证，暂不开放。'));
    }
  }

  static void _checkSong(CommentSource source, OnlineSong song) {
    if (source == CommentSource.site) return;
    if (source.name != song.provider.name ||
        (source == CommentSource.netease &&
            !RegExp(r'^\d+$').hasMatch(song.id)) ||
        (source == CommentSource.kugou &&
            !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(song.hash))) {
      throw       MusicSearchException(tr('评论歌曲与平台不匹配，请重新选择歌曲。'));
    }
  }
}
