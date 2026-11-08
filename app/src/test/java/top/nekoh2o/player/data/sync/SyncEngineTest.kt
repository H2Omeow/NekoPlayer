package top.nekoh2o.player.data.sync

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import top.nekoh2o.player.data.model.SectionMeta
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.data.net.ProviderPreferences

class SyncEngineTest {

    private class MemPrefs : ProviderPreferences {
        val map = HashMap<String, Any>()
        override fun getString(key: String, fallback: String?) = map[key] as? String ?: fallback
        override fun getBoolean(key: String, fallback: Boolean) = map[key] as? Boolean ?: fallback
        override fun edit(): ProviderPreferences.Editor = object : ProviderPreferences.Editor {
            override fun putString(key: String, value: String) = apply { map[key] = value }
            override fun putBoolean(key: String, value: Boolean) = apply { map[key] = value }
            override fun remove(key: String) = apply { map.remove(key) }
            override fun apply() {}
        }
    }

    private class FakeRemote : SyncRemote {
        var fail: String? = null
        var meta = HashMap<SyncSection, SectionMeta>()
        val data = HashMap<SyncSection, JsonElement>()
        var patches = 0
        var lastExpected: Map<SyncSection, Long>? = null
        var clock = 1000L

        override suspend fun fetch(): FetchResult {
            fail?.let { return FetchResult.Failure(it) }
            return FetchResult.Ok(CloudSnapshot(HashMap(meta), HashMap(data)))
        }

        override suspend fun patch(device: String, sections: Map<SyncSection, JsonElement>, expected: Map<SyncSection, Long>?): PatchResult {
            patches++
            lastExpected = expected
            expected?.forEach { (s, at) ->
                if ((meta[s]?.updatedAt ?: 0L) != at) return PatchResult.Conflict(HashMap(meta), "conflict")
            }
            sections.forEach { (s, p) -> data[s] = p; meta[s] = SectionMeta(++clock, device) }
            return PatchResult.Ok(HashMap(meta))
        }
    }

    private class FakeLocal : SyncLocal {
        val data = HashMap<SyncSection, JsonElement>()
        override fun count(section: SyncSection) = SyncCodec.count(section, data[section])
        override fun snapshot(section: SyncSection): JsonElement = data[section] ?: JsonArray(emptyList())
        override suspend fun apply(section: SyncSection, payload: JsonElement) { data[section] = payload }
        override fun merge(section: SyncSection, remote: JsonElement?): JsonElement {
            val l = SyncCodec.decodeSongs(data[section]).songs
            val r = SyncCodec.decodeSongs(remote).songs
            return SyncCodec.encodeSongs(SyncMerge.songs(l, r))
        }
    }

    private lateinit var remote: FakeRemote
    private lateinit var local: FakeLocal
    private lateinit var store: SyncStateStore
    private lateinit var engine: SyncEngine
    private var now = 10_000L
    private var loggedIn = true
    private val applied = ArrayList<Set<SyncSection>>()

    private fun songs(vararg ids: Long) =
        SyncCodec.encodeSongs(ids.map { Song(it, "n$it", "a") })

    @Before fun setUp() {
        remote = FakeRemote(); local = FakeLocal(); store = SyncStateStore(MemPrefs()); loggedIn = true; now = 10_000L
        applied.clear()
        engine = SyncEngine(remote, local, store, CoroutineScope(Job() + Dispatchers.Unconfined), "Android · Test",
            { loggedIn }, { now }, { applied.add(it) })
    }

    @Test fun failedGetNeverUploads() = runBlocking {
        local.data[SyncSection.FAVORITES] = songs(1)
        store.markLocalChanged(SyncSection.FAVORITES, 5_000)
        remote.fail = "boom"
        engine.autoSync()
        engine.upload(setOf(SyncSection.FAVORITES))
        engine.merge(setOf(SyncSection.FAVORITES))
        assertEquals(0, remote.patches)
        assertTrue(engine.state.value.error!!.contains("boom"))
        assertTrue(engine.state.value.results.all { it.outcome == Outcome.FAILED })
    }

    @Test fun notLoggedInDoesNothing() = runBlocking {
        loggedIn = false
        engine.autoSync()
        engine.upload(setOf(SyncSection.FAVORITES))
        assertEquals(0, remote.patches)
    }

    @Test fun manualUploadOverwritesWithoutExpectedAndRecordsMeta() = runBlocking {
        local.data[SyncSection.FAVORITES] = songs(1, 2)
        remote.data[SyncSection.FAVORITES] = songs(9)
        remote.meta[SyncSection.FAVORITES] = SectionMeta(500, "桌面")
        store.markLocalChanged(SyncSection.FAVORITES, 5_000)
        engine.upload(setOf(SyncSection.FAVORITES))
        assertEquals(1, remote.patches)
        assertEquals(null, remote.lastExpected)
        assertEquals(2, SyncCodec.count(SyncSection.FAVORITES, remote.data[SyncSection.FAVORITES]))
        val s = store.get(SyncSection.FAVORITES)
        assertEquals(remote.meta[SyncSection.FAVORITES]!!.updatedAt, s.lastRemoteUpdatedAt)
        assertEquals(10_000L, s.lastSyncedAt)
        assertEquals(5_000L, s.localUpdatedAt)
        val row = engine.state.value.rows.first { it.section == SyncSection.FAVORITES }
        assertEquals(SyncStatus.SYNCED, row.status)
    }

    @Test fun pullOverwritesLocalWithoutBumpingLocalUpdatedAt() = runBlocking {
        local.data[SyncSection.FAVORITES] = songs(1, 2, 3)
        remote.data[SyncSection.FAVORITES] = songs(7)
        remote.meta[SyncSection.FAVORITES] = SectionMeta(500, "桌面")
        engine.pull(setOf(SyncSection.FAVORITES))
        assertEquals(1, SyncCodec.count(SyncSection.FAVORITES, local.data[SyncSection.FAVORITES]))
        assertEquals(0L, store.get(SyncSection.FAVORITES).localUpdatedAt)
        assertEquals(500L, store.get(SyncSection.FAVORITES).lastRemoteUpdatedAt)
        assertEquals(listOf(setOf(SyncSection.FAVORITES)), applied)
        assertEquals(0, remote.patches)
    }

    @Test fun pullSkipsEmptyCloudSection() = runBlocking {
        local.data[SyncSection.HISTORY] = songs(1)
        engine.pull(setOf(SyncSection.HISTORY))
        assertEquals(1, SyncCodec.count(SyncSection.HISTORY, local.data[SyncSection.HISTORY]))
        assertEquals(Outcome.SKIPPED, engine.state.value.results.single().outcome)
    }

    @Test fun mergeAppliesUnionLocallyAndUploadsWithExpected() = runBlocking {
        local.data[SyncSection.FAVORITES] = songs(1, 2)
        remote.data[SyncSection.FAVORITES] = songs(2, 3)
        remote.meta[SyncSection.FAVORITES] = SectionMeta(500, "桌面")
        engine.merge(setOf(SyncSection.FAVORITES))
        assertEquals(3, SyncCodec.count(SyncSection.FAVORITES, local.data[SyncSection.FAVORITES]))
        assertEquals(3, SyncCodec.count(SyncSection.FAVORITES, remote.data[SyncSection.FAVORITES]))
        assertEquals(mapOf(SyncSection.FAVORITES to 500L), remote.lastExpected)
    }

    @Test fun autoSyncPushesLocalNewerWithExpected() = runBlocking {
        store.markSynced(SyncSection.FAVORITES, 1_000, 500)
        store.markLocalChanged(SyncSection.FAVORITES, 2_000)
        remote.meta[SyncSection.FAVORITES] = SectionMeta(500, "桌面")
        remote.data[SyncSection.FAVORITES] = songs(1)
        local.data[SyncSection.FAVORITES] = songs(1, 2)
        engine.autoSync()
        assertEquals(mapOf(SyncSection.FAVORITES to 500L), remote.lastExpected)
        assertEquals(2, SyncCodec.count(SyncSection.FAVORITES, remote.data[SyncSection.FAVORITES]))
    }

    @Test fun autoSyncPullsRemoteNewerWhenLocalClean() = runBlocking {
        store.markSynced(SyncSection.FAVORITES, 1_000, 500)
        remote.meta[SyncSection.FAVORITES] = SectionMeta(900, "桌面")
        remote.data[SyncSection.FAVORITES] = songs(1, 2, 3)
        local.data[SyncSection.FAVORITES] = songs(1)
        engine.autoSync()
        assertEquals(3, local.count(SyncSection.FAVORITES))
        assertEquals(0, remote.patches)
    }

    @Test fun autoSyncLeavesConflictsAlone() = runBlocking {
        store.markSynced(SyncSection.FAVORITES, 1_000, 500)
        store.markLocalChanged(SyncSection.FAVORITES, 2_000)
        remote.meta[SyncSection.FAVORITES] = SectionMeta(900, "桌面")
        remote.data[SyncSection.FAVORITES] = songs(1, 2, 3)
        local.data[SyncSection.FAVORITES] = songs(1)
        engine.autoSync()
        assertEquals(1, local.count(SyncSection.FAVORITES))
        assertEquals(0, remote.patches)
        assertEquals(1, engine.state.value.conflictCount)
    }

    @Test fun autoSyncSkipsCredentialsByDefaultAndNeverSyncedBothSides() = runBlocking {
        local.data[SyncSection.CREDENTIALS] = SyncCodec.encodeCredentials(Credentials("nc"))
        store.markLocalChanged(SyncSection.CREDENTIALS, 2_000)
        local.data[SyncSection.HISTORY] = songs(1)
        remote.data[SyncSection.HISTORY] = songs(2)
        remote.meta[SyncSection.HISTORY] = SectionMeta(900, "桌面")
        engine.autoSync()
        assertEquals(0, remote.patches)
        assertEquals(1, local.count(SyncSection.HISTORY))
    }

    @Test fun conflict409IsMarkedNotOverwritten() = runBlocking {
        store.markSynced(SyncSection.FAVORITES, 1_000, 500)
        store.markLocalChanged(SyncSection.FAVORITES, 2_000)
        remote.meta[SyncSection.FAVORITES] = SectionMeta(500, "桌面")
        remote.data[SyncSection.FAVORITES] = songs(1)
        local.data[SyncSection.FAVORITES] = songs(1, 2)
        // 在 GET 之后、PATCH 之前云端被其他设备改动
        val racing = object : SyncRemote by remote {
            override suspend fun patch(device: String, sections: Map<SyncSection, JsonElement>, expected: Map<SyncSection, Long>?): PatchResult {
                remote.meta[SyncSection.FAVORITES] = SectionMeta(777, "手机")
                return remote.patch(device, sections, expected)
            }
        }
        val e = SyncEngine(racing, local, store, CoroutineScope(Job() + Dispatchers.Unconfined), "Android · Test", { true }, { now })
        e.autoSync()
        assertEquals(1, SyncCodec.count(SyncSection.FAVORITES, remote.data[SyncSection.FAVORITES]))
        assertEquals(SyncStatus.CONFLICT, e.state.value.rows.first { it.section == SyncSection.FAVORITES }.status)
    }

    @Test fun bindingDifferentAccountResetsProgress() {
        store.bindAccount("u1")
        store.markSynced(SyncSection.FAVORITES, 1_000, 500)
        store.bindAccount("u1")
        assertEquals(1_000L, store.get(SyncSection.FAVORITES).lastSyncedAt)
        store.bindAccount("u2")
        assertEquals(0L, store.get(SyncSection.FAVORITES).lastSyncedAt)
        assertEquals(0L, store.get(SyncSection.FAVORITES).lastRemoteUpdatedAt)
    }

    @Test fun autoSyncDefaults() {
        assertTrue(store.get(SyncSection.FAVORITES).autoSync)
        assertTrue(store.get(SyncSection.HISTORY).autoSync)
        assertTrue(store.get(SyncSection.PLAYLISTS).autoSync)
        assertEquals(false, store.get(SyncSection.CREDENTIALS).autoSync)
        store.setAutoSync(SyncSection.CREDENTIALS, true)
        assertTrue(store.get(SyncSection.CREDENTIALS).autoSync)
    }
}
