package top.nekoh2o.player.data.repo

import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import top.nekoh2o.player.data.model.SectionMeta
import top.nekoh2o.player.data.model.SectionsPatchRequest
import top.nekoh2o.player.data.model.SectionsPatchResp
import top.nekoh2o.player.data.model.SyncMeta
import top.nekoh2o.player.data.model.User
import top.nekoh2o.player.data.model.NcAccountResp
import top.nekoh2o.player.data.model.NcPlaylistItem
import top.nekoh2o.player.data.model.NcRecordItem
import top.nekoh2o.player.data.net.ApiFactory
import top.nekoh2o.player.data.sync.FetchResult
import top.nekoh2o.player.data.sync.PatchResult
import top.nekoh2o.player.data.sync.SyncCodec
import top.nekoh2o.player.data.sync.SyncRemote
import top.nekoh2o.player.data.sync.SyncSection

class UserRepository : SyncRemote {

    private val api = ApiFactory.user
    private val errorJson = Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true }

    suspend fun fetchMe(): User? =
        runCatching {
            val resp = api.me()
            android.util.Log.d("UserRepository", "fetchMe() - response code: ${resp.code}, user: ${resp.user}")
            if (resp.code == 0) resp.user else {
                android.util.Log.w("UserRepository", "fetchMe() - non-zero code: ${resp.code}")
                null
            }
        }.onFailure { e ->
            android.util.Log.e("UserRepository", "fetchMe() - network/parse error: ${e.message}", e)
        }.getOrNull()

    // ==================== 云同步（见 data/sync）====================

    override suspend fun fetch(): FetchResult = try {
        val resp = api.pullData()
        val body = resp.body()
        when {
            !resp.isSuccessful -> FetchResult.Failure(httpMessage(resp.code(), resp.errorBody()?.string(), "读取云端数据"))
            body == null || body.code != 0 || body.data == null ->
                FetchResult.Failure(body?.msg?.ifBlank { null } ?: "云端返回了无效数据")
            else -> FetchResult.Ok(SyncCodec.snapshot(body.data, body.meta))
        }
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        FetchResult.Failure("读取云端数据失败：" + (e.message ?: e.javaClass.simpleName))
    }

    override suspend fun patch(
        device: String,
        sections: Map<SyncSection, JsonElement>,
        expected: Map<SyncSection, Long>?
    ): PatchResult = try {
        val request = SectionsPatchRequest(
            device = device,
            sections = JsonObject(sections.mapKeys { it.key.key }),
            expected = expected?.mapKeys { it.key.key }
        )
        val resp = api.patchSections(request)
        val body = resp.body()
        when {
            resp.isSuccessful && body != null && body.code == 0 -> PatchResult.Ok(SyncCodec.parseMeta(body.meta))
            resp.code() == 409 -> {
                val err = parseError(resp.errorBody()?.string())
                PatchResult.Conflict(SyncCodec.parseMeta(err?.meta), err?.msg?.ifBlank { null } ?: "云端数据已被其他设备更新")
            }
            else -> PatchResult.Failure(httpMessage(resp.code(), resp.errorBody()?.string(), "上传到云端"))
        }
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        PatchResult.Failure("上传到云端失败：" + (e.message ?: e.javaClass.simpleName))
    }

    private fun parseError(text: String?): SectionsPatchResp? =
        text?.let { runCatching { errorJson.decodeFromString<SectionsPatchResp>(it) }.getOrNull() }

    private fun httpMessage(code: Int, text: String?, action: String): String {
        val msg = text?.let { runCatching { errorJson.decodeFromString<SectionsPatchResp>(it).msg }.getOrNull() }
        return when {
            code == 401 -> "登录已失效，请重新登录"
            !msg.isNullOrBlank() -> "$action 失败：$msg"
            else -> "$action 失败（HTTP $code）"
        }
    }

    suspend fun logout() {
        runCatching { api.logout() }
    }

    // 竖屏随机取一张壁纸，返回完整 URL；失败兜底 picsum
    suspend fun randomWallpaper(isLandscape: Boolean = false): String {
        val orientation = if (isLandscape) "horizontal" else "vertical"
        val fallback = "https://picsum.photos/${if (isLandscape) "1920/1080" else "1080/1920"}?random=" +
            (System.currentTimeMillis() % 100000)
        return runCatching {
            val resp = api.wallpaperList(orientation)
            if (resp.code == 200 && resp.data.isNotEmpty()) {
                val item = resp.data.random()
                ApiFactory.BASE.trimEnd('/') + item.url
            } else fallback
        }.getOrDefault(fallback)
    }

    // ==================== 网易云相关 ====================

    private val ncApi = ApiFactory.netease

    /**
     * 检测网易云登录状态
     * @return true 表示 Cookie 有效
     */
    suspend fun checkNcLoginStatus(): Boolean =
        runCatching {
            val cookie = top.nekoh2o.player.data.net.CookieStore.userCookieValue()
            if (cookie.isEmpty()) return@runCatching false
            val resp = ncApi.loginStatus(cookie)
            resp.data?.code == 200
        }.getOrDefault(false)

    /**
     * 获取网易云账号信息（含会员状态）
     */
    suspend fun fetchNcAccount(): NcAccountResp? =
        runCatching {
            val cookie = top.nekoh2o.player.data.net.CookieStore.userCookieValue()
            if (cookie.isEmpty()) return@runCatching null
            ncApi.userAccount(cookie)
        }.getOrNull()

    /**
     * 获取网易云用户歌单列表
     */
    suspend fun fetchNcPlaylists(uid: Long): List<NcPlaylistItem> =
        runCatching {
            val cookie = top.nekoh2o.player.data.net.CookieStore.userCookieValue()
            if (cookie.isEmpty()) return@runCatching emptyList()
            val resp = ncApi.userPlaylist(uid, cookie)
            if (resp.code == 200) resp.playlist else emptyList()
        }.getOrDefault(emptyList())

    /**
     * 获取网易云红心歌曲 ID 列表
     */
    suspend fun fetchNcLikeList(uid: Long): List<Long> =
        runCatching {
            val cookie = top.nekoh2o.player.data.net.CookieStore.userCookieValue()
            if (cookie.isEmpty()) return@runCatching emptyList()
            val resp = ncApi.likeList(uid, cookie)
            if (resp.code == 200) resp.ids else emptyList()
        }.getOrDefault(emptyList())

    /**
     * 获取网易云播放记录
     * @param type 1=最近一周 0=所有时间
     */
    suspend fun fetchNcRecord(uid: Long, type: Int = 1): List<top.nekoh2o.player.data.model.NcRecordItem> =
        runCatching {
            val cookie = top.nekoh2o.player.data.net.CookieStore.userCookieValue()
            if (cookie.isEmpty()) return@runCatching emptyList()
            val resp = ncApi.userRecord(uid, cookie, type)
            if (resp.code == 200) {
                if (type == 1) resp.weekData else resp.allData
            } else emptyList()
        }.getOrDefault(emptyList())
}
