package top.nekoh2o.player.data.repo

import top.nekoh2o.player.i18n.NekoI18n.tr

import top.nekoh2o.player.data.model.LyricLine
import top.nekoh2o.player.data.model.PersonalizedItem
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.data.net.ApiFactory
import top.nekoh2o.player.data.net.CookieStore
import top.nekoh2o.player.lyric.LyricParser

class MusicRepository {

    private val api = ApiFactory.music

    // ---------- 游客 cookie 兜底 ----------
    suspend fun ensureGuestCookie() {
        runCatching {
            val resp = api.registerAnonymous()
            if (resp.code == 200 && resp.cookie.isNotEmpty()) {
                CookieStore.setGuestCookie(resp.cookie)
            }
        }
    }

    // ---------- 搜索 ----------
    suspend fun search(keyword: String, offset: Int, limit: Int = 30): List<Song> {
        val resp = api.search(keyword, limit, offset)
        if (resp.code != 200) return emptyList()
        val base = resp.result?.songs ?: return emptyList()
        if (base.isEmpty()) return emptyList()

        val ids = base.joinToString(",") { it.id.toString() }
        val detail = runCatching { api.songDetail(ids) }.getOrNull()
        return if (detail?.code == 200 && detail.songs.isNotEmpty()) {
            detail.songs.map {
                Song(it.id, it.name, it.ar.firstOrNull()?.name ?: tr("未知"), it.al?.picUrl)
            }
        } else {
            base.map {
                Song(it.id, it.name, it.artists.firstOrNull()?.name ?: tr("未知"),
                    it.artists.firstOrNull()?.img)
            }
        }
    }

    // 搜索建议（歌曲6 + 歌手3 + 专辑3）
    suspend fun suggest(keyword: String): List<String> {
        if (keyword.length < 2) return emptyList()
        val resp = runCatching { api.suggest(keyword) }.getOrNull() ?: return emptyList()
        if (resp.code != 200) return emptyList()
        val r = resp.result ?: return emptyList()
        val out = mutableListOf<String>()
        r.songs.take(6).forEach { out.add(it.name) }
        r.artists.take(3).forEach { out.add(it.name) }
        r.albums.take(3).forEach { out.add(it.name) }
        return out
    }

    // ---------- 推荐 ----------
    suspend fun personalizedPlaylists(limit: Int = 8): List<PersonalizedItem> {
        val resp = runCatching { api.personalized(limit) }.getOrNull() ?: return emptyList()
        return if (resp.code == 200) resp.result else emptyList()
    }

    // 每日推荐，失败回退榜单
    suspend fun recommendSongs(): List<Song> {
        val rec = runCatching { api.recommendSongs() }.getOrNull()
        val daily = rec?.data?.dailySongs
        if (rec?.code == 200 && !daily.isNullOrEmpty()) {
            return daily.take(20).map {
                Song(it.id, it.name, it.ar.firstOrNull()?.name ?: tr("未知"), it.al?.picUrl)
            }
        }
        val top = runCatching { api.topSong(0, 20) }.getOrNull()
        if (top?.code == 200) {
            return top.data.map {
                Song(it.id, it.name, it.ar.firstOrNull()?.name ?: tr("未知"), it.al?.picUrl)
            }
        }
        return emptyList()
    }

    suspend fun playlistTracks(id: Long): List<Song> {
        val resp = runCatching { api.playlistDetail(id) }.getOrNull() ?: return emptyList()
        if (resp.code != 200) return emptyList()
        return resp.playlist?.tracks?.take(30)?.map {
            Song(it.id, it.name, it.ar.firstOrNull()?.name ?: tr("未知"), it.al?.picUrl)
        } ?: emptyList()
    }

    // 批量获取歌曲详情
    suspend fun songsByIds(ids: List<Long>): List<Song> {
        if (ids.isEmpty()) return emptyList()
        val idsStr = ids.joinToString(",")
        val resp = runCatching { api.songDetail(idsStr) }.getOrNull() ?: return emptyList()
        return if (resp.code == 200 && resp.songs.isNotEmpty()) {
            resp.songs.map {
                Song(it.id, it.name, it.ar.firstOrNull()?.name ?: tr("未知"), it.al?.picUrl)
            }
        } else emptyList()
    }

    // ---------- 歌词 ----------
    /**
     * 根据歌曲来源获取歌词
     */
    suspend fun lyric(song: Song): List<LyricLine> {
        return when (song.source) {
            "kugou" -> lyricKugou(song)
            "netease" -> lyric(song.id)
            else -> top.nekoh2o.player.data.plugins.PluginMusicRepository().lyric(song)
        }
    }

    suspend fun lyric(id: Long): List<LyricLine> {
        val neu = runCatching { api.lyricNew(id) }.getOrNull()
        val main = neu?.yrc?.lyric?.takeIf { it.isNotBlank() } ?: neu?.lrc?.lyric
        val trans = neu?.tlyric?.lyric
        if (!main.isNullOrBlank()) return LyricParser.parse(main, trans)

        val old = runCatching { api.lyric(id) }.getOrNull()
        val oldMain = old?.lrc?.lyric
        val oldTrans = old?.tlyric?.lyric
        if (!oldMain.isNullOrBlank()) return LyricParser.parse(oldMain, oldTrans)
        return emptyList()
    }

    private suspend fun lyricKugou(song: Song): List<LyricLine> {
        val kgRepo = KugouRepository()
        val lrcText = kgRepo.getLyric(song.hash) ?: return emptyList()
        return LyricParser.parse(lrcText, null)
    }

    // ---------- 取址 ----------
    /**
     * 根据歌曲来源解析播放URL
     * @param song 歌曲对象（包含source字段）
     * @param level 音质等级
     */
    suspend fun resolvePlayUrl(song: Song, level: String = CookieStore.level): String? {
        return SongQualityRepository().resolvePlayback(song, level)?.url
    }

    suspend fun resolvePlayUrl(id: Long, level: String = CookieStore.level): String? =
        resolvePlayUrl(Song(id, "", ""), level)

    // ---------- 分类搜索：歌手 ----------
    suspend fun searchArtist(keyword: String, offset: Int, limit: Int = 30): List<top.nekoh2o.player.data.model.ArtistItem> {
        val resp = runCatching { api.searchArtist(keyword, 100, limit, offset) }.getOrNull()
        return if (resp?.code == 200) resp.result?.artists ?: emptyList() else emptyList()
    }

    // ---------- 分类搜索：专辑 ----------
    suspend fun searchAlbum(keyword: String, offset: Int, limit: Int = 30): List<top.nekoh2o.player.data.model.AlbumItem> {
        val resp = runCatching { api.searchAlbum(keyword, 10, limit, offset) }.getOrNull()
        return if (resp?.code == 200) resp.result?.albums ?: emptyList() else emptyList()
    }

    // ---------- 歌手热门歌曲 ----------
    suspend fun artistTopSongs(artistId: Long): List<Song> {
        val resp = runCatching { api.artistTopSong(artistId) }.getOrNull()
        if (resp?.code != 200) return emptyList()
        return resp.songs.map {
            Song(it.id, it.name, it.ar.firstOrNull()?.name ?: tr("未知"), it.al?.picUrl)
        }
    }

    // ---------- 专辑内容 ----------
    suspend fun albumSongs(albumId: Long): List<Song> {
        val resp = runCatching { api.albumContent(albumId) }.getOrNull()
        if (resp?.code != 200) return emptyList()
        val picUrl = resp.album?.picUrl
        return resp.songs.map {
            Song(it.id, it.name, it.ar.firstOrNull()?.name ?: tr("未知"), it.al?.picUrl ?: picUrl)
        }
    }

    // ---------- QR 登录 ----------
    suspend fun qrKey(): String? {
        val resp = runCatching { api.qrKey(System.currentTimeMillis()) }.getOrNull()
        return resp?.data?.unikey?.takeIf { resp.code == 200 && it.isNotEmpty() }
    }
    suspend fun qrCreate(key: String): String? {
        val resp = runCatching {
            api.qrCreate(key, true, System.currentTimeMillis())
        }.getOrNull()
        return resp?.data?.qrimg?.takeIf { resp.code == 200 && it.isNotEmpty() }
    }
    // 返回 code：800过期 801等待 802已扫 803成功；成功时写入 cookie
    suspend fun qrCheck(key: String): Int {
        val resp = runCatching { api.qrCheck(key, System.currentTimeMillis()) }.getOrNull()
            ?: return -1
        if (resp.code == 803 && resp.cookie.isNotEmpty()) {
            CookieStore.setUserCookie(resp.cookie)
        }
        return resp.code
    }
}
