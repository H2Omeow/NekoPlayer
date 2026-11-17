package top.nekoh2o.player.data.bilibili

import top.nekoh2o.player.data.store.DanmakuSettings

/**
 * 弹幕筛选：纯函数，方便单测。
 * 排序按时间；同屏数量在渲染层再做一次裁剪。
 */
object DanmakuFilter {

    fun allows(item: DanmakuItem, settings: DanmakuSettings): Boolean {
        if (!settings.enabled) return false
        // mode: 1-3 滚动，4 底部，5 顶部，6 逆向，7/8/9 高级
        val isScroll = item.mode in 1..3 || item.mode == 6
        val isBottom = item.mode == 4
        val isTop = item.mode == 5
        if (isScroll && !settings.showScroll) return false
        if (isTop && !settings.showTop) return false
        if (isBottom && !settings.showBottom) return false
        // 高级弹幕本期不支持，直接丢弃（避免渲染成错位的文字块）
        if (item.mode in 7..9) return false
        if (!settings.keepColor && item.color != 0xFFFFFF) return false
        if (settings.blockWords.any { it.isNotEmpty() && item.content.contains(it, ignoreCase = true) }) return false
        return item.content.isNotBlank()
    }

    fun apply(items: List<DanmakuItem>, settings: DanmakuSettings): List<DanmakuItem> {
        val filtered = items.filter { allows(it, settings) }.sortedBy { it.progressMs }
        if (!settings.mergeDuplicate) return filtered
        val seen = HashSet<String>(filtered.size)
        return filtered.filter { seen.add(it.content) }
    }

    /** 渲染层同屏裁剪：保留 weight 高的前 [limit] 条。 */
    fun capByDensity(items: List<DanmakuItem>, limit: Int): List<DanmakuItem> =
        if (items.size <= limit) items else items.sortedByDescending { it.weight }.take(limit)
}
