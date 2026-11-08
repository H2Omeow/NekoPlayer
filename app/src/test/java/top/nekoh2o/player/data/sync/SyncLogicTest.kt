package top.nekoh2o.player.data.sync

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import top.nekoh2o.player.data.model.Playlist
import top.nekoh2o.player.data.model.SectionsPatchRequest
import top.nekoh2o.player.data.model.Song
import java.util.TimeZone

class SyncLogicTest {

    private fun song(id: Long, source: String = "netease", hash: String = "", media: String = "") =
        Song(id = id, nm = "n$id", ar = "a", source = source, hash = hash, providerMediaId = media)

    // ---------- 状态判定 ----------

    private fun st(local: Long = 0, synced: Long = 0, remote: Long = 0) =
        SectionSyncState(localUpdatedAt = local, lastSyncedAt = synced, lastRemoteUpdatedAt = remote)

    @Test fun statusUnknownWithoutRemote() {
        assertEquals(SyncStatus.UNKNOWN, computeStatus(st(), null, 1, null))
    }

    @Test fun statusSyncedLocalRemoteConflict() {
        assertEquals(SyncStatus.SYNCED, computeStatus(st(local = 5, synced = 10, remote = 100), 100, 3, 3))
        assertEquals(SyncStatus.LOCAL_NEWER, computeStatus(st(local = 20, synced = 10, remote = 100), 100, 3, 3))
        assertEquals(SyncStatus.REMOTE_NEWER, computeStatus(st(local = 5, synced = 10, remote = 100), 200, 3, 3))
        assertEquals(SyncStatus.CONFLICT, computeStatus(st(local = 20, synced = 10, remote = 100), 200, 3, 3))
    }

    @Test fun neverSyncedIsConflictOnlyWhenBothSidesHaveData() {
        assertEquals(SyncStatus.CONFLICT, computeStatus(st(), 50, 2, 2))
        assertEquals(SyncStatus.NEVER, computeStatus(st(), 50, 0, 2))
        assertEquals(SyncStatus.NEVER, computeStatus(st(), 0, 2, 0))
        assertEquals(SyncStatus.NEVER, computeStatus(st(), 0, 0, 0))
    }

    @Test fun autoActionDirections() {
        assertEquals(AutoAction.PUSH, autoAction(SyncStatus.LOCAL_NEWER, 1, 1))
        assertEquals(AutoAction.PULL, autoAction(SyncStatus.REMOTE_NEWER, 1, 1))
        assertEquals(AutoAction.NONE, autoAction(SyncStatus.CONFLICT, 1, 1))
        assertEquals(AutoAction.NONE, autoAction(SyncStatus.SYNCED, 1, 1))
        assertEquals(AutoAction.PUSH, autoAction(SyncStatus.NEVER, 3, 0))
        assertEquals(AutoAction.PULL, autoAction(SyncStatus.NEVER, 0, 3))
        assertEquals(AutoAction.NONE, autoAction(SyncStatus.NEVER, 0, 0))
    }

    @Test fun timeFormat() {
        val utc = TimeZone.getTimeZone("UTC")
        assertEquals("从未", formatSyncTime(0, 1_000, utc))
        // 2026-11-08 14:03:00 UTC
        val t = 1_794_146_580_000L
        assertEquals("3 分钟前 · 2026-11-08 14:03", formatSyncTime(t, t + 3 * 60_000 + 5_000, utc))
        assertEquals("刚刚 · 2026-11-08 14:03", formatSyncTime(t, t + 1_000, utc))
        assertEquals("2026-11-08 14:03", formatSyncTime(t, t + 90L * 86_400_000, utc))
    }

    // ---------- 歌曲唯一键 ----------

    @Test fun keyPrefersProviderMediaIdThenHashThenId() {
        assertEquals("animemusic-kg:MEDIA", songKey(song(1, "animemusic-kg", hash = "h", media = "MEDIA")))
        assertEquals("netease:H", songKey(song(1, "netease", hash = "H")))
        assertEquals("netease:7", songKey(song(7)))
    }

    @Test fun kugouHashIsCaseInsensitive() {
        assertEquals(songKey(song(1, "kugou", hash = "ABCDEF")), songKey(song(2, "kugou", hash = "abcdef")))
        assertEquals("kugou:abcdef", songKey(song(1, "kugou", hash = "ABCDEF")))
    }

    @Test fun sameIdDifferentSourceDoesNotCollide() {
        assertTrue(songKey(song(1, "netease")) != songKey(song(1, "kugou", hash = "x")))
        assertTrue(songKey(song(1, "netease")) != songKey(song(1, "plugin-a")))
    }

    // ---------- 合并 ----------

    @Test fun mergeSongsKeepsLocalFirstAndDedupes() {
        val merged = SyncMerge.songs(
            listOf(song(1), song(2)),
            listOf(song(2), song(3))
        )
        assertEquals(listOf(1L, 2L, 3L), merged.map { it.id })
    }

    @Test fun mergeHistoryCapsAt200WithoutDroppingLocalNewest() {
        val local = (1L..150L).map { song(it) }
        val remote = (1000L..1150L).map { song(it) }
        val merged = SyncMerge.history(local, remote)
        assertEquals(200, merged.size)
        assertEquals(1L, merged.first().id)
        assertEquals(150L, merged[149].id)
    }

    @Test fun mergePlaylistsUnionsSongsById() {
        val local = listOf(Playlist("a", "A", mutableListOf(song(1))), Playlist("b", "B", mutableListOf(song(5))))
        val remote = listOf(Playlist("a", "A2", mutableListOf(song(1), song(2))), Playlist("c", "C"))
        val merged = SyncMerge.playlists(local, remote)
        assertEquals(listOf("a", "b", "c"), merged.map { it.id })
        assertEquals("A", merged[0].name)
        assertEquals(listOf(1L, 2L), merged[0].songs.map { it.id })
    }

    @Test fun mergeCredentialsFillsBlanksOnly() {
        val merged = SyncMerge.credentials(
            Credentials("nc-local", listOf("", "kg1-local"), 1, ""),
            Credentials("nc-remote", listOf("kg0-remote", "kg1-remote"), 0, "tok")
        )
        assertEquals("nc-local", merged.ncCookie)
        assertEquals(listOf("kg0-remote", "kg1-local"), merged.kgCookies)
        assertEquals(1, merged.kgPlatform)
        assertEquals("tok", merged.kgToken)
    }

    // ---------- 编解码 ----------

    @Test fun songRoundTripKeepsDesktopFieldsAndOmitsNulls() {
        val src = buildJsonObject {
            put("id", 5); put("nm", "t"); put("ar", "a"); put("source", "plugin-x")
            put("pluginSource", buildJsonObject { put("id", "p1") })
            put("pluginData", buildJsonObject { put("k", "v") })
            put("futureField", 1)
        }
        val decoded = SyncCodec.decodeSongs(JsonArray(listOf(src)))
        assertTrue(decoded.foreign.isEmpty())
        val song = decoded.songs.single()
        assertNotNull(song.pluginSource)
        val out = SyncCodec.encodeSong(song) as JsonObject
        assertEquals(src["pluginSource"], out["pluginSource"])
        assertEquals(src["pluginData"], out["pluginData"])
        // 无桌面字段时不写 null；source 等默认值显式写出
        val plain = SyncCodec.encodeSong(song(9)) as JsonObject
        assertFalse(plain.containsKey("pluginSource"))
        assertFalse(plain.containsKey("pluginData"))
        assertFalse(plain.containsKey("pc"))
        assertEquals(JsonPrimitive("netease"), plain["source"])
    }

    @Test fun undecodableSongsAreKeptAsForeignAndReuploaded() {
        val weird = buildJsonObject { put("id", "abc"); put("nm", "x"); put("ar", "y") }
        val noId = buildJsonObject { put("nm", "x"); put("ar", "y"); put("extra", true) }
        val good = SyncCodec.encodeSong(song(1))
        val decoded = SyncCodec.decodeSongs(JsonArray(listOf(good, weird, noId)))
        assertEquals(1, decoded.songs.size)
        assertEquals(listOf(weird, noId), decoded.foreign)
        val re = SyncCodec.encodeSongs(decoded.songs, decoded.foreign)
        assertEquals(3, re.size)
        assertEquals(weird, re[1])
        assertEquals(noId, re[2])
    }

    @Test fun playlistsRoundTripWithForeignSongsAndPlaylists() {
        val weird = buildJsonObject { put("id", "abc"); put("nm", "x"); put("ar", "y") }
        val badPlaylist = buildJsonObject { put("id", "z"); put("paths", JsonArray(emptyList())) }
        val pl = buildJsonObject {
            put("id", "p1"); put("name", "N")
            put("songs", JsonArray(listOf(SyncCodec.encodeSong(song(1)), weird)))
        }
        val decoded = SyncCodec.decodePlaylists(JsonArray(listOf(pl, badPlaylist)))
        assertEquals(1, decoded.playlists.size)
        assertEquals(listOf(weird), decoded.playlists[0].foreignSongs)
        assertEquals(listOf(badPlaylist), decoded.foreign)
        val out = SyncCodec.encodePlaylists(decoded.playlists, decoded.foreign)
        assertEquals(2, out.size)
        val songs = (out[0] as JsonObject)["songs"] as JsonArray
        assertEquals(2, songs.size)
        assertEquals(weird, songs[1])
        assertEquals(badPlaylist, out[1])
    }

    @Test fun credentialsRoundTripAndDefaults() {
        val c = Credentials("nc", listOf("a", "b"), 1, "tok")
        val obj = SyncCodec.encodeCredentials(c)
        assertEquals(setOf("ncCookie", "kgCookies", "kgPlatform", "kgToken"), obj.keys)
        assertEquals(c, SyncCodec.decodeCredentials(obj))
        assertEquals(Credentials(), SyncCodec.decodeCredentials(null))
        assertEquals(3, c.count)
        val odd = buildJsonObject { put("kgPlatform", 9); put("kgCookies", JsonArray(listOf(JsonPrimitive("x")))) }
        val d = SyncCodec.decodeCredentials(odd)
        assertEquals(1, d.kgPlatform)
        assertEquals(listOf("x", ""), d.kgCookies)
    }

    @Test fun counts() {
        assertEquals(2, SyncCodec.count(SyncSection.FAVORITES, JsonArray(listOf(JsonPrimitive(1), JsonPrimitive(2)))))
        assertEquals(0, SyncCodec.count(SyncSection.HISTORY, null))
        assertEquals(1, SyncCodec.count(SyncSection.CREDENTIALS, SyncCodec.encodeCredentials(Credentials("x"))))
    }

    @Test fun patchRequestOmitsExpectedWhenNull() {
        val json = Json  // 与 ApiFactory 一致：不写默认值
        val body = SectionsPatchRequest("Android · Test", buildJsonObject { put("favorites", JsonArray(emptyList())) })
        val text = json.encodeToString(SectionsPatchRequest.serializer(), body)
        assertFalse(text.contains("expected"))
        assertTrue(text.contains("\"device\":\"Android · Test\""))
        val withExpected = json.encodeToString(
            SectionsPatchRequest.serializer(), body.copy(expected = mapOf("favorites" to 123L))
        )
        assertTrue(withExpected.contains("\"expected\":{\"favorites\":123}"))
    }

    @Test fun snapshotFromWireModels() {
        val wire = Json { ignoreUnknownKeys = true; coerceInputValues = true }.decodeFromString(
            top.nekoh2o.player.data.model.UserDataResp.serializer(),
            """{"code":0,"data":{"history":[{"id":1,"nm":"a","ar":"b"}],"favorites":[],"playlists":[],
               "ncCookie":"nc","kgToken":"","kgPlatform":1,"kgCookies":["x","y"]},
               "meta":{"sections":{"favorites":{"updatedAt":42,"device":"桌面"}}}}"""
        )
        val snap = SyncCodec.snapshot(wire.data!!, wire.meta)
        assertEquals(42L, snap.updatedAt(SyncSection.FAVORITES))
        assertEquals(0L, snap.updatedAt(SyncSection.HISTORY))
        assertEquals(1, snap.count(SyncSection.HISTORY))
        assertEquals(3, snap.count(SyncSection.CREDENTIALS))
        assertNull(snap.meta[SyncSection.PLAYLISTS])
    }
}
