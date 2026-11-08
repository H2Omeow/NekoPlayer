package top.nekoh2o.player.data.sync

import top.nekoh2o.player.i18n.NekoI18n.tr

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** “3 分钟前 · 2026-11-08 14:03”，0 表示从未。 */
fun formatSyncTime(timestamp: Long, now: Long, zone: TimeZone = TimeZone.getDefault()): String {
    if (timestamp <= 0L) return tr("从未")
    val absolute = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).apply { timeZone = zone }.format(Date(timestamp))
    val diff = (now - timestamp).coerceAtLeast(0) / 1000
    val relative = when {
        diff < 60 -> tr("刚刚")
        diff < 3600 -> tr("{count} 分钟前", "count" to diff / 60)
        diff < 86400 -> tr("{count} 小时前", "count" to diff / 3600)
        diff < 86400 * 30 -> tr("{count} 天前", "count" to diff / 86400)
        else -> null
    }
    return if (relative == null) absolute else "$relative · $absolute"
}
