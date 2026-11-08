package top.nekoh2o.player.data.repo

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*
import top.nekoh2o.player.data.model.*
import top.nekoh2o.player.data.net.*
import retrofit2.Response

/** Server API adapter. All requests retain the selected platform and its device session. */
class KugouRepository(
    private val suppliedApi: KugouApi? = null,
    private val suppliedSessions: KugouSessionStore? = null
) {
    private val api get() = suppliedApi ?: ApiFactory.kugou
    private val sessions get() = suppliedSessions ?: CookieStore.kgSessions

    private suspend fun ready() {
        if (suppliedApi == null) { CookieStore.awaitReady(); ApiFactory.awaitReady() }
    }

    suspend fun ensureInitialized(platform: Int = CookieStore.kgPlatformValue()) {
        ready()
        initialization[platform].withLock {
            if (sessions.value(platform, "dfid").isNotBlank()) return
            val body = api.get("register/dev", platform).kugouBody()
            val dfid = body.payload().text("dfid")
            if (dfid.isBlank()) throw KugouApiException("酷狗设备初始化失败，请重试")
            sessions.merge(platform, mapOf("dfid" to dfid))
        }
    }

    suspend fun getDfid(): String? = optional {
        val platform = CookieStore.kgPlatformValue()
        ensureInitialized(platform)
        sessions.value(platform, "dfid")
    }

    suspend fun sendCode(phone: String, platform: Int) {
        require(phone.matches(Regex("1[3-9][0-9]{9}"))) { "请输入有效的大陆手机号" }
        ensureInitialized(platform)
        val result = api.post("captcha/sent", platform, mapOf("mobile" to phone)).kugouBody()
        if (result.text("status") != "1" && result.text("code") != "200") {
            throw KugouApiException("酷狗未确认验证码发送成功，请稍后重试")
        }
    }

    suspend fun login(phone: String, code: String, platform: Int, userid: String? = null): KgLoginData {
        require(phone.matches(Regex("1[3-9][0-9]{9}"))) { "请输入有效的大陆手机号" }
        require(code.matches(Regex("[0-9]{4,8}"))) { "请输入有效验证码" }
        ensureInitialized(platform)
        val fields = mutableMapOf("mobile" to phone, "code" to code)
        userid?.takeIf { it.toLongOrNull()?.let { id -> id > 0 } == true }?.let { fields["userid"] = it }
        val response = api.post("login/cellphone", platform, fields)
        val body = response.kugouBody()
        val data = body.payload()
        if (data.text("token").isBlank()) {
            val accounts = data.values.filterIsInstance<JsonArray>().flatMap { it.filterIsInstance<JsonObject>() }
                .filter { it.number("userid") > 0 }.map { KgLoginAccount(it.number("userid"), it.text("nickname", "username")) }
                .distinctBy { it.userid }
            if (accounts.isNotEmpty()) throw KugouAccountSelection(accounts)
        }
        return acceptLogin(platform, response, data)
    }

    suspend fun createLoginQR(platform: Int): KgQrSession {
        ensureInitialized(platform)
        val key = api.get("login/qr/key", platform).kugouBody().payload().text("qrcode", "key", "unikey")
        if (key.isBlank()) throw KugouApiException("酷狗未返回二维码标识，请重试")
        val image = api.get("login/qr/create", platform, mapOf("key" to key, "qrimg" to "true"))
            .kugouBody().payload().text("base64", "qrcode_img", "qrimg")
        if (image.isBlank()) throw KugouApiException("酷狗未返回二维码图片，请重试")
        return KgQrSession(key, image, platform)
    }

    suspend fun checkLoginQR(session: KgQrSession): KgQrCheckResult {
        ready()
        val response = api.get("login/qr/check", session.platform, mapOf("key" to session.key))
        val data = response.kugouBody().payload()
        val status = data.text("status").toIntOrNull()
            ?: throw KugouApiException("无法识别酷狗扫码状态，请刷新二维码")
        if (status !in setOf(0, 1, 2, 4)) throw KugouApiException("酷狗扫码授权失败，请刷新二维码")
        return KgQrCheckResult(status, if (status == 4) acceptLogin(session.platform, response, data) else null)
    }

    private suspend fun acceptLogin(platform: Int, response: Response<JsonObject>, data: JsonObject): KgLoginData {
        val token = data.text("token")
        val userid = data.number("userid")
        if (token.isBlank() || token in setOf("undefined", "null") || userid <= 0) {
            throw KugouApiException("酷狗未返回有效登录凭据，请重新扫码或使用验证码登录")
        }
        currentCoroutineContext().ensureActive()
        sessions.commitLogin(platform, response.raw().request.url, response.headers().values("Set-Cookie"), token, userid, data.text("dfid"))
        return KgLoginData(token, userid, data.text("nickname", "username"), sessions.value(platform, "dfid"))
    }

    suspend fun refreshLogin(): Boolean = optional {
        val platform = CookieStore.kgPlatformValue()
        ready()
        if (sessions.value(platform, "token").isEmpty()) return@optional false
        val response = api.get("login/token", platform)
        val data = response.kugouBody().payload()
        val token = data.text("token")
        if (token.isEmpty()) return@optional false
        currentCoroutineContext().ensureActive()
        sessions.mergeResponse(platform, response.raw().request.url, response.headers().values("Set-Cookie"), true)
        sessions.merge(platform, mapOf("token" to token))
        true
    } ?: false

    private suspend fun get(endpoint: String, parameters: Map<String, String> = emptyMap(), platform: Int = CookieStore.kgPlatformValue()): JsonObject {
        ensureInitialized(platform)
        return api.get(endpoint, platform, parameters).kugouBody()
    }

    suspend fun getUserInfo(platform: Int = CookieStore.kgPlatformValue()): KgUserInfo? = optional {
        ready()
        if (sessions.value(platform, "token").isBlank()) return@optional null
        val data = get("user/detail", platform = platform).payload()
        val info = data.obj("userinfo").ifEmpty { data }
        KgUserInfo(
            userid = info.number("userid").takeIf { it > 0 } ?: sessions.value(platform, "userid").toLongOrNull() ?: 0,
            username = info.text("username"), nickname = info.text("nickname", "nick_name", "username"),
            avatar = info.text("pic", "avatar", "picurl")
        )
    }

    suspend fun getVipInfo(platform: Int = CookieStore.kgPlatformValue()): KgVipInfo? = optional {
        val data = get("user/vip/detail", platform = platform).payload()
        val info = data.obj("vip").ifEmpty { data }
        KgVipInfo(info.number("vip_type", "vip_level").toInt(), info.text("vip_token"), info.number("end_time", "vip_end_time"))
    }

    suspend fun getUserPlaylists(): List<KgPlaylistItem> = optional {
        val data = get("user/playlist").payload()
        data.items("info").ifEmpty { data.items("list") }.map {
            KgPlaylistItem(it.number("listid", "specialid"), it.text("name", "specialname"), it.text("pic", "imgurl"), it.number("count", "songcount").toInt(), it.text("global_collection_id"))
        }
    }.orEmpty()

    suspend fun getPlaylistDetail(collectionId: String): List<Song> = optional {
        val data = get("playlist/track/all", mapOf("id" to collectionId, "pagesize" to "100")).payload()
        data.items("songs").ifEmpty { data.items("info") }.map(::song)
    }.orEmpty()

    suspend fun search(keyword: String, page: Int = 1): List<Song> = optional {
        get("search", mapOf("keywords" to keyword, "page" to page.toString(), "pagesize" to "30"))
            .payload().let { it.items("lists").ifEmpty { it.items("info") } }.map(::song)
    }.orEmpty()

    suspend fun searchSuggest(keyword: String): List<String> = optional {
        val data = get("search/suggest", mapOf("keywords" to keyword)).payload()
        data.items("list").flatMap { it.items("RecordDatas") }.map { it.text("HintInfo") }.filter(String::isNotBlank)
            .ifEmpty { data.items("song").map { it.text("songname") } }.distinct()
    }.orEmpty()

    suspend fun getSongUrl(hash: String, quality: String = "320"): String? = optional {
        require(hash.matches(Regex("[a-fA-F0-9]{32}"))) { "歌曲缺少酷狗 hash，请重新搜索并添加该歌曲" }
        val data = get("song/url", mapOf("hash" to hash, "quality" to quality)).payload()
        playableUrl(data)
    }

    suspend fun getSongQualities(hash: String): List<KgQualityItem> = optional {
        val body = get("privilege/lite", mapOf("hash" to hash))
        val data = body.items("data").firstOrNull() ?: body.payload()
        data.items("relate_goods").mapNotNull { item ->
            val info = item.obj("info")
            val quality = when (info.number("bitrate")) { 128L -> "128"; 320L -> "320"; else -> if (info.text("extname") == "flac") "flac" else null }
            quality?.let { KgQualityItem(it, if (it == "flac") "无损" else it + " kbps", info.number("bitrate").toInt()) }
        }.distinctBy { it.quality }
    }.orEmpty()

    suspend fun getLyric(hash: String): String? = optional {
        require(hash.matches(Regex("[a-fA-F0-9]{32}")))
        val candidates = get("search/lyric", mapOf("hash" to hash)).items("candidates")
        val candidate = candidates.firstOrNull { it.text("id").isNotBlank() && it.text("accesskey").isNotBlank() } ?: return@optional null
        val result = get("lyric", mapOf("id" to candidate.text("id"), "accesskey" to candidate.text("accesskey"), "fmt" to "lrc", "decode" to "true"))
        result.text("decodeContent").ifBlank {
            result.text("content").takeIf(String::isNotBlank)?.let { String(top.nekoh2o.player.data.net.nativeapi.NativePlatform.unbase64(it), Charsets.UTF_8) }.orEmpty()
        }.takeIf(String::isNotBlank)
    }

    suspend fun getSongDetail(hash: String): KgSongDetail? = optional {
        val body = get("privilege/lite", mapOf("hash" to hash))
        val data = body.items("data").firstOrNull() ?: return@optional null
        KgSongDetail(data.number("audio_id"), data.text("hash"), data.number("album_audio_id"), data.text("songname", "song_name"), data.text("singername", "author_name"), data.text("img"))
    }

    suspend fun receiveVip(vipType: Int = 1, days: Int = 1): String? = optional {
        if (CookieStore.kgPlatformValue() != 1) return@optional "此功能仅限概念版"
        val data = get("youth/day/vip", mapOf("receive_day" to "1")).payload()
        data.text("message", "msg").ifEmpty { "已提交领取，请刷新账号查看实际权益" }
    }

    suspend fun getFollowArtists(): List<KgArtistItem> = optional {
        get("user/follow").payload().items("info").map { KgArtistItem(it.number("singerid", "userid"), it.text("singername", "nickname"), it.text("imgurl", "pic")) }
    }.orEmpty()

    suspend fun getArtistSongs(singerId: Long): List<Song> = optional {
        get("artist/audios", mapOf("id" to singerId.toString(), "pagesize" to "50")).payload().items("info").map(::song)
    }.orEmpty()

    suspend fun getUserHistory(): List<Song> = optional {
        val data = get("user/history").payload()
        data.items("info").ifEmpty { data.items("list") }.map(::song)
    }.orEmpty()

    suspend fun getRecommendSongs(): List<Song> = optional {
        val data = get("personal/fm").payload()
        data.items("song_list").ifEmpty { data.items("lists") }.map(::song)
    }.orEmpty()

    private suspend fun <T> optional(block: suspend () -> T): T? = try { block() } catch (e: CancellationException) { throw e } catch (_: Exception) { null }

    companion object {
        private val initialization = Array(2) { Mutex() }

        internal fun playableUrl(data: JsonObject): String? {
            for (key in listOf("url", "play_url", "backup_url", "play_backup_url")) {
                val value = data[key]
                val candidates = when (value) { is JsonArray -> value; is JsonPrimitive -> listOf(value); else -> emptyList() }
                for (candidate in candidates) {
                    val url = (candidate as? JsonPrimitive)?.contentOrNull.orEmpty()
                    if (url.startsWith("https://") || url.startsWith("http://")) return url
                }
            }
            return null
        }

        internal fun song(item: JsonObject): Song {
            val hash = item.text("FileHash", "Hash", "hash")
            // Cloud playlists return a combined "歌手 - 歌名" in `name` and the
            // cover in `cover`; search lists use the other spellings below.
            val filename = item.text("FileName", "filename", "audio_name", "name")
                .replace(Regex("\\.(mp3|flac|m4a|aac|wav|ogg|ape)$", RegexOption.IGNORE_CASE), "")
            val id = item.number("MixSongID", "mixsongid", "album_audio_id", "Audioid", "audio_id", "songid")
                .takeIf { it > 0 } ?: hash.take(15).toLongOrNull(16) ?: 0
            val artwork = item.text("Image", "img", "album_img", "cover")
                .ifEmpty { item.obj("trans_param").text("union_cover") }
                .replace("{size}", "400")
                .let { if (it.startsWith("//")) "https:$it" else it }
            return Song(id = id,
                nm = item.text("SongName", "OriSongName", "song_name", "songname", "songName").ifEmpty { filename.substringAfter(" - ", filename) },
                ar = item.text("SingerName", "singername", "singer_name", "author_name").ifEmpty { item.items("singerinfo").joinToString(", ") { it.text("name") } }.ifEmpty { filename.substringBefore(" - ", "") },
                pc = artwork.takeIf(String::isNotEmpty),
                source = "kugou", hash = hash,
                albumId = item.text("AlbumID", "album_id", "albumid"),
                albumAudioId = item.number("MixSongID", "mixsongid", "album_audio_id"))
        }
    }
}
