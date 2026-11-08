package top.nekoh2o.player.data.sync

import kotlinx.serialization.json.JsonElement
import top.nekoh2o.player.data.model.SectionMeta

class CloudSnapshot(
    val meta: Map<SyncSection, SectionMeta>,
    val payloads: Map<SyncSection, JsonElement>
) {
    fun updatedAt(section: SyncSection): Long = meta[section]?.updatedAt ?: 0L
    fun count(section: SyncSection): Int = SyncCodec.count(section, payloads[section])
}

sealed interface FetchResult {
    class Ok(val snapshot: CloudSnapshot) : FetchResult
    class Failure(val message: String) : FetchResult
}

sealed interface PatchResult {
    class Ok(val meta: Map<SyncSection, SectionMeta>) : PatchResult
    class Conflict(val meta: Map<SyncSection, SectionMeta>, val message: String) : PatchResult
    class Failure(val message: String) : PatchResult
}

/** 云端读写，失败必须以结果返回，不能吞掉。 */
interface SyncRemote {
    suspend fun fetch(): FetchResult
    suspend fun patch(device: String, sections: Map<SyncSection, JsonElement>, expected: Map<SyncSection, Long>?): PatchResult
}

/** 本机数据读写；apply 为覆盖本地，不得更新 localUpdatedAt。 */
interface SyncLocal {
    fun count(section: SyncSection): Int
    fun snapshot(section: SyncSection): JsonElement
    suspend fun apply(section: SyncSection, payload: JsonElement)
    fun merge(section: SyncSection, remote: JsonElement?): JsonElement
}
