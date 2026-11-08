package top.nekoh2o.player.data.sync

import kotlinx.serialization.json.JsonElement
import top.nekoh2o.player.data.net.CookieStore
import top.nekoh2o.player.data.repo.LocalStore

/** 把 LocalStore / CookieStore 适配为同步层的本地数据源。 */
class LocalSyncData(private val store: LocalStore) : SyncLocal {

    override fun count(section: SyncSection): Int = when (section) {
        SyncSection.FAVORITES -> store.favorites.size + store.foreignFavorites.size
        SyncSection.HISTORY -> store.history.size + store.foreignHistory.size
        SyncSection.PLAYLISTS -> store.playlists.size + store.foreignPlaylists.size
        SyncSection.CREDENTIALS -> readCredentials().count
    }

    override fun snapshot(section: SyncSection): JsonElement = when (section) {
        SyncSection.FAVORITES -> SyncCodec.encodeSongs(store.favorites.toList(), store.foreignFavorites)
        SyncSection.HISTORY -> SyncCodec.encodeSongs(store.history.toList(), store.foreignHistory)
        SyncSection.PLAYLISTS -> SyncCodec.encodePlaylists(store.playlists.toList(), store.foreignPlaylists)
        SyncSection.CREDENTIALS -> SyncCodec.encodeCredentials(readCredentials())
    }

    override fun merge(section: SyncSection, remote: JsonElement?): JsonElement = when (section) {
        SyncSection.FAVORITES -> {
            val r = SyncCodec.decodeSongs(remote)
            SyncCodec.encodeSongs(
                SyncMerge.songs(store.favorites, r.songs),
                SyncMerge.foreign(store.foreignFavorites, r.foreign)
            )
        }
        SyncSection.HISTORY -> {
            val r = SyncCodec.decodeSongs(remote)
            SyncCodec.encodeSongs(
                SyncMerge.history(store.history, r.songs),
                SyncMerge.foreign(store.foreignHistory, r.foreign)
            )
        }
        SyncSection.PLAYLISTS -> {
            val r = SyncCodec.decodePlaylists(remote)
            SyncCodec.encodePlaylists(
                SyncMerge.playlists(store.playlists, r.playlists),
                SyncMerge.foreign(store.foreignPlaylists, r.foreign)
            )
        }
        SyncSection.CREDENTIALS ->
            SyncCodec.encodeCredentials(SyncMerge.credentials(readCredentials(), SyncCodec.decodeCredentials(remote)))
    }

    override suspend fun apply(section: SyncSection, payload: JsonElement) {
        when (section) {
            SyncSection.FAVORITES -> SyncCodec.decodeSongs(payload).let { store.replaceFavorites(it.songs, it.foreign) }
            SyncSection.HISTORY -> SyncCodec.decodeSongs(payload).let { store.replaceHistory(it.songs, it.foreign) }
            SyncSection.PLAYLISTS -> SyncCodec.decodePlaylists(payload).let { store.replacePlaylists(it.playlists, it.foreign) }
            SyncSection.CREDENTIALS -> writeCredentials(SyncCodec.decodeCredentials(payload))
        }
    }

    private fun readCredentials(): Credentials {
        return try {
            Credentials(
                ncCookie = CookieStore.userCookieValue(),
                kgCookies = List(2) { CookieStore.kgCookieValue(it) },
                kgPlatform = CookieStore.kgPlatformValue(),
                kgToken = CookieStore.kgTokenValue()
            )
        } catch (e: UninitializedPropertyAccessException) {
            Credentials()  // CookieStore 尚未初始化
        }
    }

    /**
     * 用云端登录替换本机登录。云端没有某个平台的登录时保留本机登录（与桌面端一致），
     * 酷狗 Cookie 无效时抛出（该平台保持原状）。
     */
    private suspend fun writeCredentials(c: Credentials) {
        CookieStore.awaitReady()
        val sessions = CookieStore.kgSessions
        for (platform in 0..1) {
            val cookie = c.kgCookies.getOrElse(platform) { "" }
            if (cookie.isNotBlank() && cookie.contains("userid=")) {
                // importCookie 在内容非法时抛出且不修改已有账号
                sessions.importCookie(platform, cookie)
            }
        }
        if (c.ncCookie.isNotBlank()) CookieStore.setUserCookie(c.ncCookie)
        for (platform in 0..1) {
            val cookie = c.kgCookies.getOrElse(platform) { "" }
            if (cookie.isNotBlank() && !cookie.contains("userid=")) {
                sessions.merge(platform, mapOf("token" to cookie.removePrefix("token=")))
            }
        }
        val platform = c.kgPlatform.coerceIn(0, 1)
        val hasCookie = c.kgCookies.getOrElse(platform) { "" }.isNotBlank()
        if (hasCookie || c.kgToken.isNotBlank()) CookieStore.setKgPlatform(platform)
        if (!hasCookie && c.kgToken.isNotBlank()) CookieStore.setKgToken(c.kgToken)
    }
}
