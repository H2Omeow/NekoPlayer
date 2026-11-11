import '../i18n/tr.dart';
import 'music_plugin.dart';

enum MusicProvider {
  netease('网易云'),
  kugou('酷狗'),
  gatewayKugou('内置 · 酷狗', gateway: 'kg'),
  gatewayKuwo('内置 · 酷我', gateway: 'kw'),
  gatewayNetease('内置 · 网易', gateway: 'wy'),
  gatewayTencent('内置 · QQ', gateway: 'tx'),
  gatewayMigu('内置 · 咪咕', gateway: 'mg'),
  gatewayBilibili('内置 · B站', gateway: 'bilibili'),
  pluginQishui('内置 · 汽水', gateway: 'qishui');

  const MusicProvider(this.rawLabel, {this.gateway});
  final String rawLabel;
  String get label => tr(rawLabel);
  final String? gateway;
  String get sourceId => gateway == null ? name : 'animemusic-$gateway';
}

class KugouLoginChoice {
  const KugouLoginChoice(this.id, this.name);
  final String id;
  final String name;
}

class KugouAccountSelection implements Exception {
  const KugouAccountSelection(this.accounts);
  final List<KugouLoginChoice> accounts;
}

class OnlineSong {
  const OnlineSong({
    required this.provider,
    required this.id,
    required this.title,
    required this.artist,
    this.album = '',
    this.hash = '',
    this.albumId = '',
    this.albumAudioId = '',
    this.artwork = '',
    this.pluginSource,
    this.pluginData = const {},
  });

  final MusicProvider provider;
  final String id;
  final String title;
  final String artist;
  final String album;
  final String hash;
  final String albumId;
  final String albumAudioId;
  final String artwork;
  final MusicPluginSource? pluginSource;
  final Map<String, dynamic> pluginData;

  factory OnlineSong.fromJson(Map<String, dynamic> json) => OnlineSong(
    provider: MusicProvider.values.byName(json['provider'] as String),
    id: json['id'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    album: json['album'] as String? ?? '',
    hash: json['hash'] as String? ?? '',
    albumId: json['albumId'] as String? ?? '',
    albumAudioId: json['albumAudioId'] as String? ?? '',
    artwork: json['artwork'] as String? ?? '',
    pluginSource: json['pluginSource'] == null
        ? null
        : MusicPluginSource.fromJson(
            json['pluginSource'] as Map<String, dynamic>,
            reference: true,
          ),
    pluginData: Map<String, dynamic>.from(json['pluginData'] as Map? ?? {}),
  );

  Map<String, dynamic> toJson() => {
    'provider': provider.name,
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'hash': hash,
    'albumId': albumId,
    'albumAudioId': albumAudioId,
    'artwork': artwork,
    if (pluginSource != null)
      'pluginSource': pluginSource!.toJson(includeScript: false),
    if (pluginData.isNotEmpty) 'pluginData': pluginData,
  };

  String get key =>
      '${pluginSource?.id ?? provider.sourceId}:${pluginSource?.platform == 'all' ? '${provider.sourceId}:' : ''}${pluginSource != null || provider.gateway != null || hash.isEmpty ? id : hash}';
}

class SearchPage {
  const SearchPage({required this.songs, required this.hasMore});

  final List<OnlineSong> songs;
  final bool hasMore;
}

class MusicSearchException implements Exception {
  const MusicSearchException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AudioUnavailableException extends MusicSearchException {
  const AudioUnavailableException(super.message);
}

class AudioQuality {
  const AudioQuality(this.id, this.rawLabel, this.rank, {this.size = 0});
  final String id;
  final String rawLabel;
  String get label => tr(rawLabel);
  final int rank;
  final int size;

  static List<AudioQuality> supported(MusicProvider provider) {
    final formats = provider.gateway != null
        ? const {
            '128k': '标准 128k',
            '192k': '较高 192k',
            '320k': '高品质 320k',
            'flac': '无损 FLAC',
            'hires': 'Hi-Res',
          }
        : provider == MusicProvider.kugou
        ? const {
            '128': '标准 128k',
            '320': '高品质 320k',
            'flac': '无损 FLAC',
            'high': 'Hi-Res',
            'viper_atmos': '全景声',
            'viper_tape': '蝰蛇磁带',
            'viper_clear': '蝰蛇超清',
            'super': '超清母带',
          }
        : const {
            'standard': '标准 128k',
            'higher': '较高 192k',
            'exhigh': '极高 320k',
            'lossless': '无损 SQ',
            'hires': 'Hi-Res',
            'jyeffect': '高清臻音',
            'sky': '沉浸环绕声',
            'jymaster': '超清母带',
            'dolby': '臻音全景声',
          };
    return [
      for (var index = 0; index < formats.length; index++)
        AudioQuality(
          formats.keys.elementAt(index),
          formats.values.elementAt(index),
          index,
        ),
    ];
  }
}

class MusicHttpException extends MusicSearchException {
  MusicHttpException(this.status)
      : super(
          tr('音乐平台请求失败（HTTP {status}），请稍后重试。', {
            'status': status,
          }),
        );
  final int status;
}

/// Human-readable label for the quality that was actually resolved for a
/// track. Unknown platform/plugin identifiers are shown as-is, and a known
/// file format is used as the fallback for local or format-only sources.
String describeAudioQuality(String quality, {String format = ''}) {
  final id = quality.trim().toLowerCase();
  final label = switch (id) {
    'standard' || '128' || '128k' || 'low' => '标准 128k',
    'higher' || '192' || '192k' => '较高 192k',
    'exhigh' || '320' || '320k' || 'high_320' => '高品质 320k',
    'lossless' || 'sq' => '无损 SQ',
    'flac' || 'flac24bit' || 'hires' || 'high' => 'Hi-Res',
    'jyeffect' => '高清臻音',
    'sky' => '沉浸环绕声',
    'jymaster' || 'super' => '超清母带',
    'dolby' => '臻音全景声',
    'viper_atmos' => '全景声',
    'viper_tape' => '蝰蛇磁带',
    'viper_clear' => '蝰蛇超清',
    _ => '',
  };
  if (label.isNotEmpty) return tr(label);
  if (id.isNotEmpty) return quality.trim().toUpperCase();
  final extension = format.trim().toUpperCase();
  return extension;
}

abstract interface class MusicCatalog {
  Future<SearchPage> search(MusicProvider provider, String keyword, int page);
}

abstract interface class PluginMusicCatalog {
  Future<SearchPage> searchPlugin(
    MusicPluginSource source,
    String keyword,
    int page,
  );
}

class ResolvedAudio {
  const ResolvedAudio(
    this.uri,
    this.quality, {
    this.size = 0,
    this.format = '',
    this.checksum = '',
    this.headers = const {},
  });
  final Uri uri;
  final String quality;
  final int size;
  final String format;
  final String checksum;
  final Map<String, String> headers;
}

abstract interface class OnlineAudioSource {
  Future<ResolvedAudio> resolve(OnlineSong song, {String preferred = 'exhigh'});
  Future<String> lyrics(OnlineSong song);
}

abstract interface class OnlineDownloadSource {
  Future<ResolvedAudio> resolveDownload(OnlineSong song, String quality);
}

class LoginQr {
  const LoginQr(this.provider, this.key, this.uri, this.platform);
  final MusicProvider provider;
  final String key;
  final Uri uri;
  final int platform;
}

enum LoginProgress { waiting, scanned, expired, authorized }

class MusicVideo {
  const MusicVideo({
    required this.provider,
    required this.id,
    required this.title,
    required this.artist,
    this.artwork = '',
  });
  final MusicProvider provider;
  final String id;
  final String title;
  final String artist;
  final String artwork;
  String get key => '${provider.sourceId}:$id';
}

class SearchVideoPage {
  const SearchVideoPage(this.videos, this.hasMore);
  final List<MusicVideo> videos;
  final bool hasMore;
}
