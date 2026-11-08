import '../data/native_music_catalog.dart';
import '../domain/online_music.dart';

/// 导入登录后向平台确认账号有效，返回昵称；失败时抛出异常。
typedef AccountVerifier = Future<String> Function(MusicProvider provider);

AccountVerifier catalogVerifier(NativeMusicCatalog catalog) =>
    (provider) async {
      if (provider == MusicProvider.netease) {
        final response = await catalog.neteaseApi(
          '/api/nuser/account/get',
          {},
          weapi: true,
        );
        if (response['code'] != 200 || response['account'] is! Map) {
          throw const MusicSearchException('网易云未确认账号有效，请重新登录。');
        }
        final profile = response['profile'] is Map
            ? response['profile'] as Map
            : const {};
        return profile['nickname']?.toString() ?? '网易云用户';
      }
      final info = await catalog.kugouAccountInfo();
      return (info['nickname'] ?? info['username'] ?? '酷狗用户').toString();
    };
