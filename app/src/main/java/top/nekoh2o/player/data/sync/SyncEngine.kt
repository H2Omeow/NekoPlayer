package top.nekoh2o.player.data.sync

import top.nekoh2o.player.i18n.NekoI18n.tr

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonElement

enum class Outcome { OK, SKIPPED, FAILED }

data class SectionResult(val section: SyncSection, val outcome: Outcome, val message: String)

data class SectionRow(
    val section: SyncSection,
    val localCount: Int,
    val remoteCount: Int?,
    val localUpdatedAt: Long,
    val lastSyncedAt: Long,
    val remoteUpdatedAt: Long?,
    val remoteDevice: String,
    val status: SyncStatus,
    val autoSync: Boolean
)

data class SyncUiState(
    val rows: List<SectionRow> = emptyList(),
    val remoteLoaded: Boolean = false,
    val busy: Boolean = false,
    val lastCheckedAt: Long = 0,
    val error: String? = null,
    val results: List<SectionResult> = emptyList()
) {
    val conflictCount: Int get() = rows.count { it.status == SyncStatus.CONFLICT }
}

/**
 * 云同步协调器。规则：
 * - 任何操作都先 GET，GET 失败即中止，绝不上传；
 * - 上传 = 覆盖云端分区，拉取 = 覆盖本地分区，合并仅由用户手动触发；
 * - 自动同步只处理 autoSync 分区，冲突不处理，上传带 expected 乐观锁。
 */
class SyncEngine(
    private val remote: SyncRemote,
    private val local: SyncLocal,
    private val store: SyncStateStore,
    private val scope: CoroutineScope,
    private val deviceName: String,
    private val isLoggedIn: () -> Boolean,
    private val clock: () -> Long = System::currentTimeMillis,
    private val onLocalApplied: (Set<SyncSection>) -> Unit = {}
) {
    private val mutex = Mutex()
    private var snapshot: CloudSnapshot? = null
    private var lastCheckedAt = 0L
    private var lastAutoAt = 0L
    private var error: String? = null
    private var results: List<SectionResult> = emptyList()
    private var busy = false
    private var autoJob: Job? = null

    private val _state = MutableStateFlow(build())
    val state: StateFlow<SyncUiState> = _state

    /** 订阅本地分区变化（LocalStore.changes）。 */
    fun watch(changes: Flow<SyncSection>) {
        scope.launch { changes.collect { onLocalChanged(it) } }
    }

    fun onLocalChanged(section: SyncSection) {
        publish()
        if (store.get(section).autoSync) requestAutoSync(AUTO_DEBOUNCE_MS)
    }

    fun bindAccount(userId: String) {
        store.bindAccount(userId)
        publish()
    }

    fun onLoggedIn() = requestAutoSync(0)

    fun onLoggedOut() {
        autoJob?.cancel()
        snapshot = null
        error = null
        results = emptyList()
        lastCheckedAt = 0
        publish()
    }

    /** 回到前台：已登录且距上次自动同步至少 60 秒才检查。 */
    fun onForeground() {
        if (isLoggedIn() && clock() - lastAutoAt >= FOREGROUND_THROTTLE_MS) requestAutoSync(0)
    }

    fun setAutoSync(section: SyncSection, enabled: Boolean) {
        store.setAutoSync(section, enabled)
        publish()
        if (enabled) requestAutoSync(0)
    }

    fun requestAutoSync(delayMs: Long) {
        if (!isLoggedIn()) return
        autoJob?.cancel()
        autoJob = scope.launch {
            if (delayMs > 0) delay(delayMs)
            autoSync()
        }
    }

    fun launchRefresh() { scope.launch { refresh() } }
    fun launchUpload(sections: Set<SyncSection>) { scope.launch { upload(sections) } }
    fun launchPull(sections: Set<SyncSection>) { scope.launch { pull(sections) } }
    fun launchMerge(sections: Set<SyncSection>) { scope.launch { merge(sections) } }

    suspend fun refresh(): Boolean = exclusive {
        if (!requireLogin()) return@exclusive false
        fetch() != null
    }

    suspend fun upload(sections: Set<SyncSection>) {
        exclusive { manual(sections, tr("上传")) { snap, out -> doUpload(snap, sections, out) } }
    }

    suspend fun pull(sections: Set<SyncSection>) {
        exclusive { manual(sections, tr("拉取")) { snap, out -> doPull(snap, sections, out) } }
    }

    suspend fun merge(sections: Set<SyncSection>) {
        exclusive { manual(sections, tr("合并")) { snap, out -> doMerge(snap, sections, out) } }
    }

    suspend fun autoSync() {
        exclusive {
            if (!isLoggedIn()) return@exclusive
            val sections = SyncSection.entries.filter { store.get(it).autoSync }
            if (sections.isEmpty()) return@exclusive
            lastAutoAt = clock()
            val snap = fetch() ?: return@exclusive
            val out = ArrayList<SectionResult>()
            val pulled = LinkedHashSet<SyncSection>()
            for (section in sections) {
                val lc = localCount(section)
                val rc = snap.count(section)
                val current = snapshot ?: snap
                val status = computeStatus(store.get(section), current.updatedAt(section), lc, rc)
                when (autoAction(status, lc, rc)) {
                    AutoAction.PULL -> pullOne(current, section, out, pulled)
                    AutoAction.PUSH -> pushOne(section, current.updatedAt(section), out)
                    AutoAction.NONE -> Unit
                }
            }
            if (pulled.isNotEmpty()) onLocalApplied(pulled)
            if (out.isNotEmpty()) results = out
            publish()
        }
    }

    // ---------- 手动操作 ----------

    private suspend fun manual(
        sections: Set<SyncSection>,
        verb: String,
        body: suspend (CloudSnapshot, MutableList<SectionResult>) -> Unit
    ) {
        if (sections.isEmpty()) return
        val out = ArrayList<SectionResult>()
        val snap = if (requireLogin()) fetch() else null
        if (snap == null) {
            val reason = error ?: tr("无法获取云端状态")
            results = sections.map { SectionResult(it, Outcome.FAILED, tr("{reason}，已取消{action}", "reason" to reason, "action" to verb)) }
            publish()
            return
        }
        body(snap, out)
        results = out
        publish()
    }

    private suspend fun doUpload(snap: CloudSnapshot, sections: Set<SyncSection>, out: MutableList<SectionResult>) {
        val startedAt = clock()
        val payloads = LinkedHashMap<SyncSection, JsonElement>()
        for (section in sections) {
            try { payloads[section] = local.snapshot(section) }
            catch (e: CancellationException) { throw e }
            catch (e: Exception) { out.add(failed(section, tr("读取本地数据失败：{reason}", "reason" to e.message))) }
        }
        if (payloads.isEmpty()) return
        commitPatch(payloads, null, startedAt, out) { tr("已覆盖云端（{count} {unit}）", "count" to localCount(it), "unit" to it.unit) }
    }

    private suspend fun doPull(snap: CloudSnapshot, sections: Set<SyncSection>, out: MutableList<SectionResult>) {
        val applied = LinkedHashSet<SyncSection>()
        sections.forEach { pullOne(snap, it, out, applied) }
        if (applied.isNotEmpty()) onLocalApplied(applied)
    }

    private suspend fun doMerge(snap: CloudSnapshot, sections: Set<SyncSection>, out: MutableList<SectionResult>) {
        val startedAt = clock()
        val payloads = LinkedHashMap<SyncSection, JsonElement>()
        for (section in sections) {
            try {
                val merged = local.merge(section, snap.payloads[section])
                local.apply(section, merged)
                payloads[section] = merged
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { out.add(failed(section, tr("合并失败：{reason}", "reason" to e.message))) }
        }
        if (payloads.isEmpty()) return
        val expected = payloads.keys.associateWith { snap.updatedAt(it) }
        val ok = commitPatch(payloads, expected, startedAt, out) { tr("已合并并上传（{count} {unit}）", "count" to localCount(it), "unit" to it.unit) }
        // 本地已被合并结果改写但云端未更新：标记本地较新，避免被误判为已同步
        if (!ok) payloads.keys.forEach { store.markLocalChanged(it, clock()) }
        onLocalApplied(payloads.keys.toSet())
    }

    // ---------- 单分区动作 ----------

    private suspend fun pullOne(
        snap: CloudSnapshot,
        section: SyncSection,
        out: MutableList<SectionResult>,
        applied: MutableSet<SyncSection>
    ) {
        val payload = snap.payloads[section]
        val remoteAt = snap.updatedAt(section)
        if (payload == null || (remoteAt == 0L && snap.count(section) == 0)) {
            out.add(SectionResult(section, Outcome.SKIPPED, tr("云端暂无数据，已跳过")))
            return
        }
        val startedAt = clock()
        try {
            local.apply(section, payload)
            store.markSynced(section, startedAt, remoteAt)
            applied.add(section)
            out.add(SectionResult(section, Outcome.OK, tr("已用云端数据覆盖本地（{count} {unit}）", "count" to snap.count(section), "unit" to section.unit)))
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) { out.add(failed(section, tr("写入本地失败：{reason}", "reason" to e.message))) }
    }

    /** 自动上传：带 expected，409 表示云端已被其他设备更新。 */
    private suspend fun pushOne(section: SyncSection, remoteAt: Long, out: MutableList<SectionResult>) {
        val startedAt = clock()
        val payload = try { local.snapshot(section) }
        catch (e: CancellationException) { throw e }
        catch (e: Exception) { out.add(failed(section, tr("读取本地数据失败：{reason}", "reason" to e.message))); return }
        commitPatch(mapOf(section to payload), mapOf(section to remoteAt), startedAt, out) { tr("已自动上传（{count} {unit}）", "count" to localCount(it), "unit" to it.unit) }
    }

    private suspend fun commitPatch(
        payloads: Map<SyncSection, JsonElement>,
        expected: Map<SyncSection, Long>?,
        startedAt: Long,
        out: MutableList<SectionResult>,
        okMessage: (SyncSection) -> String
    ): Boolean {
        when (val r = remote.patch(deviceName, payloads, expected)) {
            is PatchResult.Ok -> {
                var meta = r.meta
                if (payloads.keys.any { !meta.containsKey(it) }) {
                    fetch()?.let { meta = meta + it.meta }
                }
                val base = snapshot
                snapshot = CloudSnapshot(
                    base?.meta.orEmpty() + meta,
                    base?.payloads.orEmpty() + payloads
                )
                payloads.keys.forEach { section ->
                    val updatedAt = meta[section]?.updatedAt
                    if (updatedAt == null) out.add(failed(section, tr("云端未返回更新时间，请刷新后重试")))
                    else {
                        store.markSynced(section, startedAt, updatedAt)
                        out.add(SectionResult(section, Outcome.OK, okMessage(section)))
                    }
                }
                return true
            }
            is PatchResult.Conflict -> {
                val base = snapshot
                snapshot = CloudSnapshot(base?.meta.orEmpty() + r.meta, base?.payloads.orEmpty())
                payloads.keys.forEach {
                    out.add(failed(it, tr("云端已被其他设备更新，请刷新后选择拉取或合并")))
                }
            }
            is PatchResult.Failure -> payloads.keys.forEach { out.add(failed(it, r.message)) }
        }
        return false
    }

    // ---------- 基础 ----------

    private suspend fun fetch(): CloudSnapshot? {
        return when (val r = remote.fetch()) {
            is FetchResult.Ok -> {
                snapshot = r.snapshot
                lastCheckedAt = clock()
                error = null
                publish()
                r.snapshot
            }
            is FetchResult.Failure -> {
                error = r.message
                publish()
                null
            }
        }
    }

    private fun requireLogin(): Boolean {
        if (isLoggedIn()) return true
        error = tr("请先登录本站账号")
        publish()
        return false
    }

    /** 串行执行；NonCancellable 避免请求已发出却因取消而没有记录结果（会造成假冲突）。 */
    private suspend fun <T> exclusive(block: suspend () -> T): T = withContext(NonCancellable) {
        mutex.withLock {
            busy = true
            publish()
            try { block() } finally {
                busy = false
                publish()
            }
        }
    }

    private fun failed(section: SyncSection, message: String) = SectionResult(section, Outcome.FAILED, message)

    private fun localCount(section: SyncSection): Int = runCatching { local.count(section) }.getOrDefault(0)

    private fun publish() { _state.value = build() }

    private fun build(): SyncUiState {
        val snap = snapshot
        val rows = SyncSection.entries.map { section ->
            val st = store.get(section)
            val lc = localCount(section)
            val rc = snap?.count(section)
            val ru = snap?.updatedAt(section)
            SectionRow(
                section, lc, rc, st.localUpdatedAt, st.lastSyncedAt, ru,
                snap?.meta?.get(section)?.device.orEmpty(),
                computeStatus(st, ru, lc, rc), st.autoSync
            )
        }
        return SyncUiState(rows, snap != null, busy, lastCheckedAt, error, results)
    }

    companion object {
        const val AUTO_DEBOUNCE_MS = 3_000L
        const val FOREGROUND_THROTTLE_MS = 60_000L
    }
}
