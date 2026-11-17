package top.nekoh2o.player.data.bilibili

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * B 站接口 DTO。字段名与线上 JSON 对齐，缺失字段一律给默认值，
 * 这样接口小改动不会因为反序列化失败把整页打挂。
 */
@Serializable
data class BiliResp<T>(
    val code: Int = -1,
    val message: String = "",
    val ttl: Int = 0,
    val data: T? = null
)

@Serializable
data class BiliWbiImg(
    @SerialName("img_url") val imgUrl: String = "",
    @SerialName("sub_url") val subUrl: String = ""
)

@Serializable
data class BiliNavData(
    @SerialName("isLogin") val isLogin: Boolean = false,
    val mid: Long = 0,
    val uname: String = "",
    val face: String = "",
    @SerialName("wbi_img") val wbiImg: BiliWbiImg = BiliWbiImg()
)

@Serializable
data class BiliSearchVideo(
    val aid: Long = 0,
    val bvid: String = "",
    val title: String = "",
    val pic: String = "",
    val author: String = "",
    val play: Long = 0,
    @SerialName("video_review") val videoReview: Long = 0,
    val duration: String = "",
    val pubdate: Long = 0,
    val description: String = "",
    val tag: String = ""
)

@Serializable
data class BiliSearchData(
    val page: Int = 1,
    @SerialName("numPages") val numPages: Int = 1,
    @SerialName("numResults") val numResults: Int = 0,
    val result: List<BiliSearchVideo> = emptyList()
)

@Serializable
data class BiliOwner(
    val mid: Long = 0,
    val name: String = "",
    val face: String = ""
)

@Serializable
data class BiliStat(
    val view: Long = 0,
    val danmaku: Long = 0,
    val reply: Long = 0,
    val favorite: Long = 0,
    val coin: Long = 0,
    val share: Long = 0,
    val like: Long = 0
)

@Serializable
data class BiliPageInfo(
    val cid: Long = 0,
    val page: Int = 1,
    val part: String = "",
    val duration: Int = 0
)

@Serializable
data class BiliViewData(
    val bvid: String = "",
    val aid: Long = 0,
    val cid: Long = 0,
    val title: String = "",
    val pic: String = "",
    val desc: String = "",
    val duration: Int = 0,
    val pubdate: Long = 0,
    val owner: BiliOwner = BiliOwner(),
    val stat: BiliStat = BiliStat(),
    val pages: List<BiliPageInfo> = emptyList(),
    val tname: String = "",
    val copyright: Int = 1
)

@Serializable
data class BiliDurl(
    val url: String = "",
    val size: Long = 0,
    val length: Long = 0,
    @SerialName("backup_url") val backupUrl: List<String> = emptyList()
)

@Serializable
data class BiliPlayData(
    val quality: Int = 0,
    @SerialName("accept_quality") val acceptQuality: List<Int> = emptyList(),
    @SerialName("accept_description") val acceptDescription: List<String> = emptyList(),
    val durl: List<BiliDurl> = emptyList(),
    val timelength: Long = 0
)

@Serializable
data class BiliRelatedData(
    val aid: Long = 0,
    val bvid: String = "",
    val title: String = "",
    val pic: String = "",
    val owner: BiliOwner = BiliOwner(),
    val stat: BiliStat = BiliStat(),
    val duration: Int = 0
)

@Serializable
data class BiliPopularData(
    val list: List<BiliRelatedData> = emptyList(),
    @SerialName("no_more") val noMore: Boolean = true
)

@Serializable
data class BiliTrendingKeyword(
    val keyword: String = "",
    @SerialName("show_name") val showName: String = ""
)

@Serializable
data class BiliTrending(val list: List<BiliTrendingKeyword> = emptyList())

@Serializable
data class BiliSquareData(val trending: BiliTrending = BiliTrending())

@Serializable
data class BiliFollowItem(
    val mid: Long = 0,
    val uname: String = "",
    val face: String = ""
)

@Serializable
data class BiliFollowingsData(
    val list: List<BiliFollowItem> = emptyList(),
    val total: Int = 0
)

@Serializable
data class BiliSpaceItem(
    val aid: Long = 0,
    val bvid: String = "",
    val title: String = "",
    val pic: String = "",
    val length: String = "",
    val pubdate: Long = 0,
    val play: Long = 0,
    val video_review: Long = 0
)

@Serializable
data class BiliSpaceVlist(val vlist: List<BiliSpaceItem> = emptyList())

@Serializable
data class BiliSpaceData(val list: BiliSpaceVlist = BiliSpaceVlist())

@Serializable
data class BiliReplyMember(
    val uname: String = "",
    val avatar: String = ""
)

@Serializable
data class BiliReplyContent(val message: String = "")

@Serializable
data class BiliReply(
    val rpid: Long = 0,
    val member: BiliReplyMember = BiliReplyMember(),
    val content: BiliReplyContent = BiliReplyContent(),
    val like: Long = 0,
    val ctime: Long = 0,
    val replies: List<BiliReply> = emptyList()
)

@Serializable
data class BiliCursor(
    @SerialName("all_count") val allCount: Int = 0,
    @SerialName("is_end") val isEnd: Boolean = true,
    val next: Int = 0
)

@Serializable
data class BiliReplyData(
    val replies: List<BiliReply> = emptyList(),
    @SerialName("top_replies") val topReplies: List<BiliReply> = emptyList(),
    val cursor: BiliCursor = BiliCursor()
)

@Serializable
data class BiliQrData(
    val url: String = "",
    @SerialName("qrcode_key") val qrKey: String = ""
)

@Serializable
data class BiliQrPollData(
    val url: String = "",
    @SerialName("refresh_token") val refreshToken: String = "",
    val timestamp: Long = 0,
    val code: Int = 0,
    val message: String = ""
)

// ==================== 领域模型（UI 只认识这些） ====================

data class VideoItem(
    val bvid: String,
    val aid: Long = 0,
    val title: String,
    val cover: String,
    val upName: String = "",
    val upFace: String = "",
    val durationSec: Int = 0,
    val views: Long = 0,
    val danmakuCount: Long = 0,
    val pubdate: Long = 0,
    val badges: List<String> = emptyList()
)

data class VideoDetail(
    val item: VideoItem,
    val cid: Long,
    val desc: String = "",
    val pages: List<BiliPageInfo> = emptyList(),
    val owner: BiliOwner = BiliOwner(),
    val stat: BiliStat = BiliStat(),
    val tname: String = "",
    val copyright: Int = 1
)

data class DanmakuItem(
    val id: Long,
    val progressMs: Long,
    val mode: Int,
    val fontSize: Int,
    val color: Int,
    val content: String,
    val weight: Int = 0
)

data class PlaySource(
    val url: String,
    val quality: Int,
    val qualityLabel: String,
    val backupUrl: String = "",
    val acceptQuality: List<Int> = emptyList(),
    val acceptLabels: List<String> = emptyList()
)

data class BiliAccount(
    val mid: Long = 0,
    val name: String = "",
    val face: String = "",
    val isLogin: Boolean = false
)

data class CommentItem(
    val rpid: Long,
    val uname: String,
    val face: String,
    val content: String,
    val like: Long = 0,
    val ctime: Long = 0
)

data class BiliSearchPage(
    val items: List<VideoItem>,
    val page: Int,
    val hasMore: Boolean
)

data class QrTicket(
    val key: String,
    val url: String
)

/** 扫码状态机：等待扫码 / 已扫待确认 / 成功 / 失效。 */
sealed interface QrState {
    data object Waiting : QrState
    data object Scanned : QrState
    data class Success(val account: BiliAccount) : QrState
    data class Expired(val message: String) : QrState
}
