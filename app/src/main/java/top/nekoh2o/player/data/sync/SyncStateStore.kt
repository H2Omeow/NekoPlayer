package top.nekoh2o.player.data.sync

import top.nekoh2o.player.data.net.ProviderPreferences

/** 每个分区的 localUpdatedAt / lastSyncedAt / lastRemoteUpdatedAt / autoSync 持久化。 */
class SyncStateStore(private val prefs: ProviderPreferences) {

    @Synchronized
    fun get(section: SyncSection): SectionSyncState = SectionSyncState(
        localUpdatedAt = long(section, LOCAL),
        lastSyncedAt = long(section, SYNCED),
        lastRemoteUpdatedAt = long(section, REMOTE),
        autoSync = prefs.getBoolean(name(section, AUTO), section.defaultAuto)
    )

    @Synchronized
    fun markLocalChanged(section: SyncSection, now: Long) {
        val next = maxOf(now, long(section, LOCAL) + 1)
        prefs.edit().putString(name(section, LOCAL), next.toString()).apply()
    }

    @Synchronized
    fun markSynced(section: SyncSection, syncedAt: Long, remoteUpdatedAt: Long) {
        prefs.edit()
            .putString(name(section, SYNCED), syncedAt.toString())
            .putString(name(section, REMOTE), remoteUpdatedAt.toString())
            .apply()
    }

    @Synchronized
    fun setAutoSync(section: SyncSection, enabled: Boolean) {
        prefs.edit().putBoolean(name(section, AUTO), enabled).apply()
    }

    /** 换了本站账号后，旧账号的同步进度不再有效，重置为“从未同步”。 */
    @Synchronized
    fun bindAccount(userId: String) {
        if (prefs.getString(ACCOUNT, "") == userId) return
        val edit = prefs.edit()
        SyncSection.entries.forEach {
            edit.putString(name(it, SYNCED), "0").putString(name(it, REMOTE), "0")
        }
        edit.putString(ACCOUNT, userId).apply()
    }

    private fun long(section: SyncSection, field: String): Long =
        prefs.getString(name(section, field), null)?.toLongOrNull() ?: 0L

    private fun name(section: SyncSection, field: String) = section.key + "." + field

    private companion object {
        const val LOCAL = "localUpdatedAt"
        const val SYNCED = "lastSyncedAt"
        const val REMOTE = "lastRemoteUpdatedAt"
        const val AUTO = "autoSync"
        const val ACCOUNT = "account"
    }
}
