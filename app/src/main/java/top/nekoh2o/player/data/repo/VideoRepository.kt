package top.nekoh2o.player.data.repo

import top.nekoh2o.player.data.bilibili.BiliClient
import top.nekoh2o.player.data.bilibili.BiliSearchPage
import top.nekoh2o.player.data.bilibili.CommentItem
import top.nekoh2o.player.data.bilibili.BiliSession
import top.nekoh2o.player.data.bilibili.DanmakuItem
import top.nekoh2o.player.data.bilibili.PlaySource
import top.nekoh2o.player.data.bilibili.QrState
import top.nekoh2o.player.data.bilibili.QrTicket
import top.nekoh2o.player.data.bilibili.VideoDetail
import top.nekoh2o.player.data.bilibili.VideoItem

/**
 * 视频模块的对外门面：页面只依赖这里，换实现（插件/代理）不影响 UI。
 * 所有网络异常原样抛给上层，由页面决定是提示还是降级。
 */
class VideoRepository(
    private val api: BiliClient = BiliClient()
) {

    /** 首页分区。关键词类分区走搜索，推荐走热门。 */
    suspend fun feed(category: VideoCategory, page: Int = 1): BiliSearchPage = when (category) {
        VideoCategory.RECOMMEND, VideoCategory.HOT -> {
            val items = api.popular(page)
            BiliSearchPage(items = items, page = page, hasMore = items.isNotEmpty())
        }
        VideoCategory.FOLLOW -> {
            if (!BiliSession.isLogin()) throw BiliException(-101, "登录后可查看关注动态")
            val items = api.followingFeed()
            BiliSearchPage(items = items, page = 1, hasMore = false)
        }
        else -> api.search(category.keyword, page = page)
    }

    suspend fun search(keyword: String, page: Int = 1, order: String = "totalrank"): BiliSearchPage =
        api.search(keyword = keyword, page = page, order = order)

    suspend fun detail(bvid: String): VideoDetail = api.view(bvid)

    suspend fun play(bvid: String, cid: Long, qn: Int): PlaySource = api.playUrl(bvid, cid, qn)

    suspend fun danmaku(cid: Long, aid: Long, durationSec: Int): List<DanmakuItem> =
        api.allDanmaku(cid, aid, durationSec)

    suspend fun related(bvid: String): List<VideoItem> = api.related(bvid)

    suspend fun comments(aid: Long): Pair<List<CommentItem>, Int> = api.comments(aid)

    suspend fun searchSquare(): List<String> = api.searchSquare()

    suspend fun postDanmaku(
        cid: Long,
        aid: Long,
        content: String,
        progressMs: Long,
        mode: Int = 1,
        fontSize: Int = 25,
        color: Int = 0xFFFFFF
    ): Boolean = api.postDanmaku(cid, aid, content, progressMs, mode, fontSize, color)

    suspend fun like(aid: Long): Boolean = api.like(aid)
    suspend fun coin(aid: Long): Boolean = api.coin(aid)
    suspend fun favorite(aid: Long): Boolean = api.favorite(aid)

    suspend fun qrGenerate(): QrTicket = api.qrGenerate()

    suspend fun qrPoll(key: String): QrState = api.qrPoll(key)

    /** 手动导入 Cookie：写入后立即拉一次 nav 补全昵称头像。 */
    suspend fun importCookie(raw: String) {
        BiliSession.importCookie(raw)
        runCatching { api.nav() }
    }

    suspend fun refreshAccount() {
        runCatching { api.nav() }
    }
}

enum class VideoCategory(val label: String, val keyword: String) {
    RECOMMEND("推荐", ""),
    FOLLOW("关注", ""),
    HOT("热门", ""),
    LIVE("音乐现场", "音乐现场"),
    MV("MV", "MV 音乐"),
    KNOWLEDGE("知识", "知识科普")
}

class BiliException(val code: Int, override val message: String) : Exception(message)
