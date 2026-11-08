package top.nekoh2o.player.data.sync

import top.nekoh2o.player.i18n.NekoI18n.tr

/** 云同步分区，key 与服务端 `meta.sections` / PATCH 请求体一致。 */
enum class SyncSection(val key: String, private val rawLabel: String, val defaultAuto: Boolean) {
    FAVORITES("favorites", "我喜欢", true),
    HISTORY("history", "播放历史", true),
    PLAYLISTS("playlists", "本地歌单", true),
    CREDENTIALS("credentials", "音乐平台登录", false);

    /** 展示名称，随界面语言变化。 */
    val label: String get() = tr(rawLabel)

    /** 条目数的展示单位。 */
    val unit: String get() = when (this) {
        FAVORITES, HISTORY -> tr("首")
        PLAYLISTS -> tr("个歌单")
        CREDENTIALS -> tr("项")
    }

    companion object {
        const val HISTORY_LIMIT = 200
        fun fromKey(key: String): SyncSection? = entries.firstOrNull { it.key == key }
    }
}

enum class SyncStatus(private val rawLabel: String) {
    UNKNOWN("未检查"),
    NEVER("从未同步"),
    SYNCED("已同步"),
    LOCAL_NEWER("本地较新"),
    REMOTE_NEWER("云端较新"),
    CONFLICT("两端都有改动");

    val label: String get() = tr(rawLabel)
}

enum class AutoAction { NONE, PUSH, PULL }

/** 单个分区在本机记录的同步状态。 */
data class SectionSyncState(
    val localUpdatedAt: Long = 0,
    val lastSyncedAt: Long = 0,
    val lastRemoteUpdatedAt: Long = 0,
    val autoSync: Boolean = false
)

/** 状态判定：localDirty = localUpdatedAt > lastSyncedAt，remoteDirty = remote.updatedAt > lastRemoteUpdatedAt。 */
fun computeStatus(
    state: SectionSyncState,
    remoteUpdatedAt: Long?,
    localCount: Int,
    remoteCount: Int?
): SyncStatus {
    if (remoteUpdatedAt == null) return SyncStatus.UNKNOWN
    if (state.lastSyncedAt == 0L) {
        return if (localCount > 0 && (remoteCount ?: 0) > 0) SyncStatus.CONFLICT else SyncStatus.NEVER
    }
    val localDirty = state.localUpdatedAt > state.lastSyncedAt
    val remoteDirty = remoteUpdatedAt > state.lastRemoteUpdatedAt
    return when {
        localDirty && remoteDirty -> SyncStatus.CONFLICT
        localDirty -> SyncStatus.LOCAL_NEWER
        remoteDirty -> SyncStatus.REMOTE_NEWER
        else -> SyncStatus.SYNCED
    }
}

/** 自动同步的方向：冲突与已同步不处理；从未同步时仅在一端为空的情况下自动选择方向。 */
fun autoAction(status: SyncStatus, localCount: Int, remoteCount: Int): AutoAction = when (status) {
    SyncStatus.LOCAL_NEWER -> AutoAction.PUSH
    SyncStatus.REMOTE_NEWER -> AutoAction.PULL
    SyncStatus.NEVER -> when {
        localCount > 0 && remoteCount == 0 -> AutoAction.PUSH
        localCount == 0 && remoteCount > 0 -> AutoAction.PULL
        else -> AutoAction.NONE
    }
    else -> AutoAction.NONE
}
