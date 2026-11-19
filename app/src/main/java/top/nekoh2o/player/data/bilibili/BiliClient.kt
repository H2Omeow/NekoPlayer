package top.nekoh2o.player.data.bilibili

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.FormBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.util.concurrent.TimeUnit

/**
 * B 站网页端接口客户端（不走插件，直接 HTTPS）。
 *
 * 为什么不用 Retrofit：这些接口要么需要 wbi 动态签名、要么返回 protobuf，
 * 手写一次请求/解析比给每个方法单独配注解更直白，也方便把 Cookie 显式注入。
 *
 * 风控约定：所有请求带桌面 UA + `Referer: https://www.bilibili.com/`；
 * 被风控返回 -412 时抛 [BiliHttpException]，上层降级提示而不是崩溃。
 */
class BiliClient(
    private val client: OkHttpClient = defaultClient()
) {

    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
        isLenient = true
    }

    @Volatile private var mixinKey: String = ""
    @Volatile private var mixinKeyAt: Long = 0

    // ==================== 搜索 ====================

    suspend fun search(keyword: String, page: Int = 1, order: String = "totalrank"): BiliSearchPage {
        val params = linkedMapOf(
            "search_type" to "video",
            "keyword" to keyword,
            "page" to page.toString(),
            "page_size" to "20",
            "order" to order
        )
        val text = getJson("https://api.bilibili.com/x/web-interface/wbi/search/type?${signed(params)}")
        val resp = json.decodeFromString<BiliResp<BiliSearchData>>(text)
        if (resp.code != 0) throw BiliHttpException(resp.code, resp.message)
        val data = resp.data ?: BiliSearchData()
        val items = data.result.map { it.toItem() }
        return BiliSearchPage(items = items, page = data.page, hasMore = data.page < data.numPages)
    }

    // ==================== 详情 / 播放地址 ====================

    suspend fun view(bvid: String): VideoDetail {
        val text = getJson("https://api.bilibili.com/x/web-interface/wbi/view?${signed(mapOf("bvid" to bvid))}")
        val resp = json.decodeFromString<BiliResp<BiliViewData>>(text)
        if (resp.code != 0) throw BiliHttpException(resp.code, resp.message)
        val d = resp.data ?: throw BiliHttpException(-404, "视频不存在")
        val cid = d.pages.firstOrNull { it.cid != 0L }?.cid?.takeIf { it != 0L } ?: d.cid
        return VideoDetail(
            item = VideoItem(
                bvid = d.bvid,
                aid = d.aid,
                title = d.title,
                cover = normalizeUrl(d.pic),
                upName = d.owner.name,
                upFace = normalizeUrl(d.owner.face),
                durationSec = d.duration,
                views = d.stat.view,
                danmakuCount = d.stat.danmaku,
                pubdate = d.pubdate,
                badges = emptyList()
            ),
            cid = cid,
            desc = d.desc,
            pages = d.pages,
            owner = d.owner,
            stat = d.stat,
            tname = d.tname,
            copyright = d.copyright
        )
    }

    suspend fun playUrl(bvid: String, cid: Long, qn: Int = 80): PlaySource {
        val params = linkedMapOf(
            "bvid" to bvid,
            "cid" to cid.toString(),
            "qn" to qn.toString(),
            "fnval" to "1",   // 1 = mp4 直链，ExoPlayer 单个 MediaItem 即可播
            "fnver" to "0",
            "fourk" to "0"
        )
        val text = getJson("https://api.bilibili.com/x/player/wbi/playurl?${signed(params)}")
        val resp = json.decodeFromString<BiliResp<BiliPlayData>>(text)
        if (resp.code != 0) throw BiliHttpException(resp.code, resp.message)
        val d = resp.data ?: throw BiliHttpException(-404, "无播放地址")
        val first = d.durl.firstOrNull() ?: throw BiliHttpException(-404, "无播放地址")
        val label = d.acceptQuality.indexOf(d.quality)
            .takeIf { it >= 0 && it < d.acceptDescription.size }
            ?.let { d.acceptDescription[it] }
            ?: qualityLabel(d.quality)
        return PlaySource(
            url = first.url,
            backupUrl = first.backupUrl.firstOrNull().orEmpty(),
            quality = d.quality,
            qualityLabel = label,
            acceptQuality = d.acceptQuality,
            acceptLabels = d.acceptDescription
        )
    }

    // ==================== 弹幕 ====================

    suspend fun danmakuSegment(cid: Long, aid: Long, segment: Int): List<DanmakuItem> {
        val url = "https://api.bilibili.com/x/v2/dm/web/seg.so" +
            "?type=1&oid=$cid&pid=$aid&segment_index=$segment"
        val bytes = getBytes(url) ?: return emptyList()
        return runCatching { BiliDanmakuProto.parse(bytes) }
            .getOrElse {
                Log.w(TAG, "弹幕段解析失败 segment=$segment", it)
                emptyList()
            }
    }

    /** 按 6 分钟一段并发受限地拉取整片弹幕。 */
    suspend fun allDanmaku(cid: Long, aid: Long, durationSec: Int): List<DanmakuItem> {
        val segments = ((durationSec + 359) / 360).coerceIn(1, 60)
        val out = ArrayList<DanmakuItem>(512)
        for (i in 1..segments) {
            out += danmakuSegment(cid, aid, i)
        }
        return out.sortedBy { it.progressMs }
    }

    // ==================== 推荐 / 热门 ====================

    suspend fun comments(aid: Long, next: Int = 0, ps: Int = 20): Pair<List<CommentItem>, Int> {
        val text = getJson(
            "https://api.bilibili.com/x/v2/reply/main?oid=$aid&type=1&mode=3&next=$next&ps=$ps"
        )
        val resp = json.decodeFromString<BiliResp<BiliReplyData>>(text)
        if (resp.code != 0) return emptyList<CommentItem>() to 0
        val all = resp.data?.topReplies.orEmpty() + resp.data?.replies.orEmpty()
        val items = all.map {
            CommentItem(
                rpid = it.rpid,
                uname = it.member.uname,
                face = normalizeUrl(it.member.avatar),
                content = it.content.message,
                like = it.like,
                ctime = it.ctime
            )
        }
        return items to (resp.data?.cursor?.allCount ?: 0)
    }

    suspend fun related(bvid: String): List<VideoItem> {
        val text = getJson("https://api.bilibili.com/x/web-interface/archive/related?bvid=$bvid")
        val resp = json.decodeFromString<BiliResp<List<BiliRelatedData>>>(text)
        if (resp.code != 0) return emptyList()
        return resp.data.orEmpty().map { it.toItem() }
    }

    /** 搜索框下方的热搜词。失败时返回空列表，不阻塞搜索页。 */
    suspend fun searchSquare(): List<String> {
        val text = getJson("https://api.bilibili.com/x/web-interface/search/square?limit=12")
        val resp = json.decodeFromString<BiliResp<BiliSquareData>>(text)
        if (resp.code != 0) return emptyList()
        return resp.data?.trending?.list.orEmpty()
            .map { it.showName.ifBlank { it.keyword } }
            .filter { it.isNotBlank() }
    }

    suspend fun followings(mid: Long, page: Int = 1): List<BiliFollowItem> {
        val text = getJson("https://api.bilibili.com/x/relation/followings?vmid=$mid&pn=$page&ps=12&order=desc")
        val resp = json.decodeFromString<BiliResp<BiliFollowingsData>>(text)
        if (resp.code != 0) return emptyList()
        return resp.data?.list.orEmpty()
    }

    suspend fun spaceVideos(mid: Long, page: Int = 1, size: Int = 5): List<VideoItem> {
        val params = linkedMapOf(
            "mid" to mid.toString(),
            "ps" to size.toString(),
            "pn" to page.toString(),
            "index" to "0",
            "order" to "pubdate"
        )
        val text = getJson("https://api.bilibili.com/x/space/wbi/arc/search?${signed(params)}")
        val resp = json.decodeFromString<BiliResp<BiliSpaceData>>(text)
        if (resp.code != 0) return emptyList()
        return resp.data?.list?.vlist.orEmpty().map {
            VideoItem(
                bvid = it.bvid,
                aid = it.aid,
                title = it.title,
                cover = normalizeUrl(it.pic),
                durationSec = parseDuration(it.length),
                views = it.play,
                danmakuCount = it.video_review,
                pubdate = it.pubdate
            )
        }
    }

    /** 关注动态：取前几个关注 UP 的最新投稿，按时间交错。失败的分支直接跳过。 */
    suspend fun followingFeed(limitUps: Int = 6, perUp: Int = 3): List<VideoItem> {
        val mid = BiliSession.account.value.mid
        if (mid == 0L) return emptyList()
        val ups = followings(mid).take(limitUps)
        val out = ArrayList<VideoItem>(ups.size * perUp)
        for (up in ups) {
            val videos = runCatching { spaceVideos(up.mid, size = perUp) }.getOrDefault(emptyList())
            videos.forEach { v ->
                out += v.copy(
                    upName = up.uname,
                    upFace = normalizeUrl(up.face),
                    badges = v.badges + up.uname.take(6)
                )
            }
        }
        return out.distinctBy { it.bvid }.sortedByDescending { it.pubdate }
    }

    suspend fun popular(page: Int = 1): List<VideoItem> {
        val text = getJson("https://api.bilibili.com/x/web-interface/popular?ps=20&pn=$page")
        val resp = json.decodeFromString<BiliResp<BiliPopularData>>(text)
        if (resp.code != 0) throw BiliHttpException(resp.code, resp.message)
        return resp.data?.list.orEmpty().map { it.toItem() }
    }

    // ==================== 登录 ====================

    suspend fun qrGenerate(): QrTicket {
        val text = getJson("https://passport.bilibili.com/x/passport-login/web/qrcode/generate")
        val resp = json.decodeFromString<BiliResp<BiliQrData>>(text)
        val d = resp.data ?: throw BiliHttpException(resp.code, resp.message)
        return QrTicket(key = d.qrKey, url = d.url)
    }

    /**
     * 轮询扫码结果。成功时服务端通过 Set-Cookie 下发 SESSDATA/bili_jct/DedeUserID，
     * 这里立刻并入 [BiliSession]，并刷新 nav 拿到昵称头像。
     */
    suspend fun qrPoll(key: String): QrState {
        val (body, cookies) = getJsonWithCookies(
            "https://passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=$key"
        )
        val resp = json.decodeFromString<BiliResp<BiliQrPollData>>(body)
        val d = resp.data
        if (d == null) {
            return if (resp.code == 0) QrState.Waiting else QrState.Expired(resp.message)
        }
        return when (d.code) {
            0 -> {
                if (cookies.isNotEmpty()) BiliSession.mergeCookies(cookies)
                val nav = runCatching { nav() }.getOrNull()
                val account = nav?.let {
                    BiliAccount(mid = it.mid, name = it.uname, face = normalizeUrl(it.face), isLogin = true)
                } ?: BiliAccount(isLogin = true)
                if (account.name.isNotEmpty()) {
                    BiliSession.updateProfile(account.mid, account.name, account.face)
                }
                QrState.Success(account)
            }
            86101 -> QrState.Waiting
            86090 -> QrState.Scanned
            86038 -> QrState.Expired(d.message.ifBlank { "二维码已失效" })
            else -> QrState.Expired(d.message.ifBlank { "登录失败（${d.code}）" })
        }
    }

    suspend fun nav(): BiliNavData? {
        val text = getJson("https://api.bilibili.com/x/web-interface/nav")
        val resp = json.decodeFromString<BiliResp<BiliNavData>>(text)
        val data = resp.data ?: return null
        rememberKeys(data)
        if (data.isLogin) {
            BiliSession.updateProfile(data.mid, data.uname, normalizeUrl(data.face))
        }
        return data
    }

    // ==================== 互动 ====================

    suspend fun postDanmaku(
        cid: Long,
        aid: Long,
        content: String,
        progressMs: Long,
        mode: Int = 1,
        fontSize: Int = 25,
        color: Int = 0xFFFFFF
    ): Boolean {
        val csrf = BiliSession.csrf()
        if (csrf.isEmpty()) throw BiliHttpException(-101, "请先登录 B 站账号")
        val body = FormBody.Builder()
            .add("type", "1")
            .add("oid", cid.toString())
            .add("msg", content)
            .add("aid", aid.toString())
            .add("progress", progressMs.toString())
            .add("mode", mode.toString())
            .add("fontsize", fontSize.toString())
            .add("color", color.toString())
            .add("csrf", csrf)
            .build()
        val text = postForm("https://api.bilibili.com/x/v2/dm/post", body)
        val resp = json.decodeFromString<BiliResp<Any>>(text)
        if (resp.code != 0) throw BiliHttpException(resp.code, resp.message)
        return true
    }

    suspend fun like(aid: Long, liked: Boolean = true): Boolean =
        action("https://api.bilibili.com/x/web-interface/archive/like", mapOf(
            "aid" to aid.toString(), "like" to if (liked) "1" else "2"
        ))

    suspend fun coin(aid: Long, count: Int = 1): Boolean =
        action("https://api.bilibili.com/x/web-interface/coin/add", mapOf(
            "aid" to aid.toString(), "multiply" to count.toString(), "select_like" to "1"
        ))

    suspend fun favorite(aid: Long): Boolean =
        action("https://api.bilibili.com/x/v3/fav/resource/deal", mapOf(
            "rid" to aid.toString(), "type" to "2", "add_media_ids" to "0"
        ))

    /** 是否已关注该 UP（0 未关注，2/6 已关注）。 */
    suspend fun isFollowing(mid: Long): Boolean {
        if (!BiliSession.isLogin()) return false
        val (text, _) = getJsonWithCookies("https://api.bilibili.com/x/relation?fid=$mid")
        val obj = json.parseToJsonElement(text).jsonObject
        if (obj["code"]?.jsonPrimitive?.intOrNull != 0) return false
        val attr = obj["data"]?.jsonObject?.get("attribute")?.jsonPrimitive?.intOrNull ?: 0
        return attr == 2 || attr == 6
    }

    /** 关注 / 取关。 */
    suspend fun follow(mid: Long, follow: Boolean): Boolean =
        action("https://api.bilibili.com/x/relation/modify", mapOf(
            "fid" to mid.toString(),
            "act" to if (follow) "1" else "2",
            "re_src" to "11"
        ))

    private suspend fun action(url: String, extra: Map<String, String>): Boolean {
        val csrf = BiliSession.csrf()
        if (csrf.isEmpty()) throw BiliHttpException(-101, "请先登录 B 站账号")
        val body = FormBody.Builder().apply {
            extra.forEach { (k, v) -> add(k, v) }
            add("csrf", csrf)
        }.build()
        val text = postForm(url, body)
        val resp = json.decodeFromString<BiliResp<Any>>(text)
        if (resp.code != 0) throw BiliHttpException(resp.code, resp.message)
        return true
    }

    // ==================== HTTP 基础设施 ====================

    private suspend fun signed(params: Map<String, String>): String {
        val key = ensureMixinKey()
        return BiliSign.sign(params, key)
    }

    private suspend fun ensureMixinKey(): String {
        val cached = mixinKey
        val fresh = System.currentTimeMillis() - mixinKeyAt < 6 * 60 * 60 * 1000
        if (cached.isNotEmpty() && fresh) return cached
        val nav = nav() ?: throw BiliHttpException(-1, "无法获取签名密钥，请检查网络")
        rememberKeys(nav)
        return mixinKey
    }

    private fun rememberKeys(nav: BiliNavData) {
        val key = BiliSign.mixinKey(nav.wbiImg.imgUrl, nav.wbiImg.subUrl)
        if (key.isNotEmpty()) {
            mixinKey = key
            mixinKeyAt = System.currentTimeMillis()
        }
    }

    private suspend fun getJson(url: String): String = withContext(Dispatchers.IO) {
        val request = requestBuilder(url).get().build()
        client.newCall(request).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                throw BiliHttpException(response.code, "HTTP ${response.code}")
            }
            body
        }
    }

    private suspend fun getJsonWithCookies(url: String): Pair<String, Map<String, String>> =
        withContext(Dispatchers.IO) {
            val request = requestBuilder(url).get().build()
            client.newCall(request).execute().use { response ->
                val body = response.body?.string().orEmpty()
                val cookies = response.headers("Set-Cookie").mapNotNull { raw ->
                    val pair = raw.substringBefore(';')
                    val name = pair.substringBefore('=', "")
                    val value = pair.substringAfter('=', "")
                    if (name.isEmpty()) null else name to value
                }.toMap()
                if (!response.isSuccessful) throw BiliHttpException(response.code, "HTTP ${response.code}")
                body to cookies
            }
        }

    private suspend fun getBytes(url: String): ByteArray? = withContext(Dispatchers.IO) {
        val request = requestBuilder(url).get().build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                Log.w(TAG, "HTTP ${response.code} $url")
                return@withContext null
            }
            response.body?.bytes()
        }
    }

    private suspend fun postForm(url: String, body: FormBody): String = withContext(Dispatchers.IO) {
        val request = requestBuilder(url).post(body).build()
        client.newCall(request).execute().use { response ->
            val text = response.body?.string().orEmpty()
            if (!response.isSuccessful) throw BiliHttpException(response.code, "HTTP ${response.code}")
            text
        }
    }

    private fun requestBuilder(url: String): Request.Builder {
        val builder = Request.Builder()
            .url(url.toHttpUrl())
            .header("User-Agent", USER_AGENT)
            .header("Referer", "https://www.bilibili.com/")
            .header("Origin", "https://www.bilibili.com")
            .header("Accept", "application/json, text/plain, */*")
            .header("Accept-Language", "zh-CN,zh;q=0.9")
        val cookie = BiliSession.cookieHeader()
        if (cookie.isNotEmpty()) builder.header("Cookie", cookie)
        return builder
    }

    companion object {
        private const val TAG = "BiliClient"
        const val USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

        private fun defaultClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(12, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .writeTimeout(20, TimeUnit.SECONDS)
            .callTimeout(30, TimeUnit.SECONDS)
            .followRedirects(true)
            .build()

        fun normalizeUrl(raw: String): String = when {
            raw.isEmpty() -> ""
            raw.startsWith("//") -> "https:$raw"
            raw.startsWith("http") -> raw
            else -> raw
        }

        fun qualityLabel(qn: Int): String = when (qn) {
            127 -> "8K"
            126 -> "杜比视界"
            125 -> "HDR"
            120 -> "4K"
            116 -> "1080P60"
            112 -> "1080P+"
            80 -> "1080P"
            74 -> "720P60"
            64 -> "720P"
            32 -> "480P"
            16 -> "360P"
            else -> "${qn}P"
        }

        fun formatDuration(seconds: Int): String {
            if (seconds <= 0) return "00:00"
            val h = seconds / 3600
            val m = seconds % 3600 / 60
            val s = seconds % 60
            return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%02d:%02d".format(m, s)
        }

        /** 搜索接口的时长是 "4:36" / "1:02:36" 这种字符串。 */
        fun parseDuration(raw: String): Int {
            if (raw.isBlank()) return 0
            val parts = raw.split(':').mapNotNull { it.trim().toIntOrNull() }
            return when (parts.size) {
                3 -> parts[0] * 3600 + parts[1] * 60 + parts[2]
                2 -> parts[0] * 60 + parts[1]
                1 -> parts[0]
                else -> 0
            }
        }
    }
}

private fun BiliSearchVideo.toItem(): VideoItem {
    val clean = title.replace(Regex("<[^>]+>"), "").replace("&quot;", "\"")
    val badges = buildList {
        if (clean.contains("4K", ignoreCase = true)) add("4K")
        if (play >= 1_000_000) add("热门")
    }
    return VideoItem(
        bvid = bvid,
        aid = aid,
        title = clean,
        cover = BiliClient.normalizeUrl(pic),
        upName = author,
        durationSec = BiliClient.parseDuration(duration),
        views = play,
        danmakuCount = videoReview,
        pubdate = pubdate,
        badges = badges
    )
}

private fun BiliRelatedData.toItem(): VideoItem = VideoItem(
    bvid = bvid,
    aid = aid,
    title = title,
    cover = BiliClient.normalizeUrl(pic),
    upName = owner.name,
    upFace = BiliClient.normalizeUrl(owner.face),
    durationSec = duration,
    views = stat.view,
    danmakuCount = stat.danmaku
)

class BiliHttpException(val code: Int, override val message: String) : Exception(message)
