package top.nekoh2o.player.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

// ==================== 播放器内部统一歌曲结构（对应 web {id,nm,ar,pc}）====================
@Serializable
data class Song(
    val id: Long,
    val nm: String,
    val ar: String,
    val pc: String? = null,
    val source: String = "netease",  // netease | kugou | animemusic-*
    val hash: String = "",
    val albumId: String = "",
    val albumAudioId: Long = 0,
    /** Underlying provider used by the external aggregation source (kg/kw/wy/tx/mg/bilibili). */
    val providerSource: String = "",
    val providerMediaId: String = "",
    val pluginMetadata: String = "",
    /** 桌面端写入的字段，本端不解释，仅在云同步中原样回传，避免上传时丢失。 */
    val pluginSource: JsonElement? = null,
    val pluginData: JsonElement? = null
)

// 自定义歌单（对应 web customPlaylists）
@Serializable
data class Playlist(
    val id: String,
    val name: String,
    val songs: MutableList<Song> = mutableListOf(),
    /** 云端歌单中本端无法解析的歌曲，原样保留并随歌单回传。 */
    val foreignSongs: List<JsonElement> = emptyList()
)

// ==================== 搜索 /search?keywords= ====================
@Serializable
data class SearchResp(
    val code: Int = 0,
    val result: SearchResult? = null
)
@Serializable
data class SearchResult(
    val songs: List<SearchSong> = emptyList()
)
@Serializable
data class SearchSong(
    val id: Long,
    val name: String = "",
    val artists: List<Artist> = emptyList()
)
@Serializable
data class Artist(
    val name: String = "",
    @SerialName("img1v1Url") val img: String? = null
)

// ==================== 搜索建议 /search/suggest?keywords= ====================
@Serializable
data class SuggestResp(
    val code: Int = 0,
    val result: SuggestResult? = null
)
@Serializable
data class SuggestResult(
    val songs: List<Named> = emptyList(),
    val artists: List<Named> = emptyList(),
    val albums: List<Named> = emptyList()
)
@Serializable
data class Named(val name: String = "")

// ==================== 详情 /song/detail?ids= ====================
@Serializable
data class SongDetailResp(
    val code: Int = 0,
    val songs: List<DetailSong> = emptyList()
)
@Serializable
data class DetailSong(
    val id: Long,
    val name: String = "",
    val ar: List<Artist> = emptyList(),
    val al: Album? = null
)
@Serializable
data class Album(
    val name: String = "",
    val picUrl: String? = null
)

// ==================== 播放地址 /song/url/v1 与 /song/url ====================
@Serializable
data class SongUrlResp(
    val code: Int = 0,
    val data: List<SongUrlData> = emptyList()
)
@Serializable
data class SongUrlData(
    val id: Long = 0,
    val url: String? = null,
    val br: Int = 0
)

// ==================== 歌词 /lyric/new 与 /lyric ====================
@Serializable
data class LyricResp(
    val code: Int = 0,
    val lrc: LyricBlock? = null,
    val tlyric: LyricBlock? = null,
    val yrc: LyricBlock? = null
)
@Serializable
data class LyricBlock(val lyric: String = "")

// ==================== 推荐歌单 /personalized?limit= ====================
@Serializable
data class PersonalizedResp(
    val code: Int = 0,
    val result: List<PersonalizedItem> = emptyList()
)
@Serializable
data class PersonalizedItem(
    val id: Long,
    val name: String = "",
    val picUrl: String? = null
)

// ==================== 每日推荐 /recommend/songs ====================
@Serializable
data class RecommendSongsResp(
    val code: Int = 0,
    val data: RecommendData? = null
)
@Serializable
data class RecommendData(
    val dailySongs: List<DetailSong> = emptyList()
)

// ==================== 榜单兜底 /top/song?type=0 ====================
@Serializable
data class TopSongResp(
    val code: Int = 0,
    val data: List<DetailSong> = emptyList()
)

// ==================== 歌单详情 /playlist/detail?id= ====================
@Serializable
data class PlaylistDetailResp(
    val code: Int = 0,
    val playlist: PlaylistDetail? = null
)
@Serializable
data class PlaylistDetail(
    val name: String = "",
    val tracks: List<DetailSong> = emptyList()
)

// ==================== 游客 cookie /register/anonimous ====================
@Serializable
data class AnonResp(
    val code: Int = 0,
    val cookie: String = ""
)

// ==================== QR 登录 ====================
@Serializable
data class QrKeyResp(
    val code: Int = 0,
    val data: QrKeyData? = null
)
@Serializable
data class QrKeyData(val unikey: String = "")

@Serializable
data class QrCreateResp(
    val code: Int = 0,
    val data: QrCreateData? = null
)
@Serializable
data class QrCreateData(val qrimg: String = "")

@Serializable
data class QrCheckResp(
    val code: Int = 0,
    val cookie: String = "",
    val message: String = ""
)

// ==================== 用户信息 /auth/sso/me ====================
@Serializable
data class MeResp(
    val code: Int = -1,
    val user: User? = null
)
@Serializable
data class User(
    val id: String = "",
    val username: String? = null,
    val nickname: String? = null,
    val avatar: String? = null,
    val bio: String? = null,
    val ncAccount: NcAccountInfo? = null
)

// 网易云账户信息（从后端获取）
@Serializable
data class NcAccountInfo(
    val uid: Long = 0,
    val nickname: String = "",
    val avatarUrl: String? = null,
    val vipType: Int = 0,  // 0=普通 1=VIP 11=SVIP
    val vipExpireTime: Long = 0  // 毫秒时间戳
)

// ==================== 云端用户数据 /user/data 与 /user/data/sections ====================
@Serializable
data class SectionMeta(
    val updatedAt: Long = 0,
    val device: String = ""
)
@Serializable
data class SyncMeta(
    val sections: Map<String, SectionMeta> = emptyMap()
)
@Serializable
data class UserDataResp(
    val code: Int = 0,
    val msg: String = "",
    val data: UserData? = null,
    val meta: SyncMeta? = null
)
// 歌曲/歌单保持原始 JSON，由同步层逐条解码，避免整包解析失败或丢字段
@Serializable
data class UserData(
    val history: JsonArray = JsonArray(emptyList()),
    val favorites: JsonArray = JsonArray(emptyList()),
    val playlists: JsonArray = JsonArray(emptyList()),
    val ncCookie: String = "",
    val kgToken: String = "",
    val kgPlatform: Int = 0,
    val kgCookies: List<String> = emptyList()
)
@Serializable
data class SectionsPatchRequest(
    val device: String,
    val sections: JsonObject,
    val expected: Map<String, Long>? = null
)
@Serializable
data class SectionsPatchResp(
    val code: Int = 0,
    val msg: String = "",
    val meta: SyncMeta? = null
)

// ==================== 壁纸 /local/wallpaper/list ====================
@Serializable
data class WallpaperResp(
    val code: Int = 0,
    val data: List<WallpaperItem> = emptyList()
)
@Serializable
data class WallpaperItem(
    val name: String = "",
    val url: String = "",
    val width: Int = 0,
    val height: Int = 0
)

// ==================== 分类搜索 ====================
// 搜索类型，对应网易云 /search?type= 参数
enum class SearchType(val code: Int, val label: String) {
    SONG(1, "单曲"),
    ARTIST(100, "歌手"),
    ALBUM(10, "专辑")
}

// 分类搜索 - 歌手 (type=100)
@Serializable
data class SearchArtistResp(
    val code: Int = 0,
    val result: SearchArtistResult? = null
)
@Serializable
data class SearchArtistResult(
    val artists: List<ArtistItem> = emptyList()
)
@Serializable
data class ArtistItem(
    val id: Long,
    val name: String = "",
    val picUrl: String? = null,
    @SerialName("img1v1Url") val img1v1Url: String? = null
)

// 分类搜索 - 专辑 (type=10)
@Serializable
data class SearchAlbumResp(
    val code: Int = 0,
    val result: SearchAlbumResult? = null
)
@Serializable
data class SearchAlbumResult(
    val albums: List<AlbumItem> = emptyList()
)
@Serializable
data class AlbumItem(
    val id: Long,
    val name: String = "",
    val picUrl: String? = null,
    val artist: Artist? = null
)

// ==================== 歌手热门歌曲 /artist/top/song?id= ====================
@Serializable
data class ArtistTopSongResp(
    val code: Int = 0,
    val songs: List<DetailSong> = emptyList()
)

// ==================== 专辑内容 /album?id= ====================
@Serializable
data class AlbumContentResp(
    val code: Int = 0,
    val album: AlbumInfo? = null,
    val songs: List<DetailSong> = emptyList()
)
@Serializable
data class AlbumInfo(
    val id: Long = 0,
    val name: String = "",
    val picUrl: String? = null
)

// ==================== 已缓存歌曲信息（缓存管理用）====================
data class CachedItem(
    val key: String,
    val song: Song? = null,
    val sizeBytes: Long = 0L
)

// ==================== 音质选项枚举 ====================
enum class QualityLevel(val value: String, val label: String, val minVipType: Int, val description: String) {
    STANDARD("standard", "标准", 0, "标准音质"),
    HIGHER("higher", "较高", 0, "较高音质"),
    EXHIGH("exhigh", "极高", 0, "极高音质"),
    LOSSLESS("lossless", "无损 SQ", 11, "高保真无损音质，最高48kHz/16bit"),
    HIRES("hires", "Hi-Res", 11, "高清臻音 96kHz/24bit"),
    JYEFFECT("jyeffect", "高清臻音", 11, "Spatial Audio 沉浸感"),
    SKY("sky", "沉浸环绕声", 12, "Surround Audio 环绕音感 最高5.1声道"),
    JYMASTER("jymaster", "超清母带", 12, "Master 极致细节 192kHz/24bit"),
    DOLBY("dolby", "臻音全景声", 12, "Audio Vivid 沉浸三维空间音频，最高7.1.4声道");

    companion object {
        fun fromValue(v: String): QualityLevel = entries.find { it.value == v } ?: EXHIGH

        // 根据会员类型返回可用的音质列表
        fun availableQualities(vipType: Int): List<QualityLevel> =
            entries.filter { it.minVipType <= vipType }
    }
}

// ==================== 个性化设置 ====================
enum class BgSource { WALLPAPER, COVER }

data class AppSettings(
    // App 全局背景（默认开，用壁纸）
    val globalBgEnabled: Boolean = true,
    val globalMaskAlpha: Float = 0.6f,
    val globalBlurRadius: Int = 15,
    // 全屏播放器背景
    val fpBgSource: BgSource = BgSource.COVER,
    val fpMaskAlpha: Float = 0.4f,
    val fpBlurRadius: Int = 20,
    // 歌曲缓存开关（默认开启）
    val cacheEnabled: Boolean = true,
    // 控件透明度：0 完全透明，1 不透明；与个性化联动
    val controlAlpha: Float = 0.3f,
    // 播放倍速（0.5x ~ 2.0x），跨曲保持
    val playbackSpeed: Float = 1.0f,
    // 播放/暂停淡入淡出
    val fadePlayback: Boolean = true,
    // 淡入淡出时长（毫秒），50 ~ 2000
    val fadeMilliseconds: Int = 300,
    // 悬浮窗歌词开关（需悬浮窗权限）
    val floatingLyricEnabled: Boolean = false,
    // 悬浮窗歌词：显示双行（当前行 + 下一行）
    val floatingLyricDoubleRow: Boolean = false,
    // 悬浮窗歌词：显示翻译行（若歌词含翻译）
    val floatingLyricShowTranslation: Boolean = true,
    // 下载目录：SAF tree URI 字符串（空串 = 默认 Music/NekoPlayer/）
    val downloadDirUri: String = "",
    // 音质选项：standard/higher/exhigh/lossless/hires/jyeffect/sky/dolby/jymaster
    val audioQuality: String = "exhigh",
    // 横屏模式：强制横屏布局（默认 false，自动检测屏幕方向）
    val landscapeMode: Boolean = false,
    // UI 缩放：0.8x（放大文字）~ 1.3x（缩小内容），适配小屏设备
    val uiScale: Float = 1.0f,
    // 音效设置
    val audioEffects: AudioEffectSettings = AudioEffectSettings(),
    // 自定义界面字体：App 私有目录下的 TTF / OTF 路径（空串 = 内置字体）
    val customFontPath: String = "",
    // 自定义字体的原始文件名（用于设置页显示）
    val customFontName: String = "",
    // 社区后台消息推送（前台服务 + SSE，默认开启）
    val socialPushEnabled: Boolean = true,
    // 界面语言：system / zh-CN / zh-TW / en / ja
    val language: String = "system"
)
