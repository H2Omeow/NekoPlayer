package top.nekoh2o.player.data.bilibili

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import top.nekoh2o.player.data.store.DanmakuSettings

class DanmakuFilterTest {

    private val defaults = DanmakuSettings()

    private fun item(
        content: String,
        mode: Int = 1,
        color: Int = 0xFFFFFF,
        weight: Int = 1,
        progress: Long = 0
    ) = DanmakuItem(
        id = progress,
        progressMs = progress,
        mode = mode,
        fontSize = 25,
        color = color,
        content = content,
        weight = weight
    )

    @Test
    fun `scroll top bottom switches are respected`() {
        assertTrue(DanmakuFilter.allows(item("滚动"), defaults))
        assertTrue(DanmakuFilter.allows(item("顶部", mode = 5), defaults))
        assertTrue(DanmakuFilter.allows(item("底部", mode = 4), defaults))

        val onlyTop = defaults.copy(showScroll = false, showBottom = false)
        assertFalse(DanmakuFilter.allows(item("滚动"), onlyTop))
        assertFalse(DanmakuFilter.allows(item("底部", mode = 4), onlyTop))
        assertTrue(DanmakuFilter.allows(item("顶部", mode = 5), onlyTop))
    }

    @Test
    fun `advanced danmaku modes are dropped`() {
        for (mode in 7..9) {
            assertFalse("mode $mode", DanmakuFilter.allows(item("高级", mode = mode), defaults))
        }
    }

    @Test
    fun `color filter drops non white when keepColor disabled`() {
        val noColor = defaults.copy(keepColor = false)
        assertTrue(DanmakuFilter.allows(item("白色"), noColor))
        assertFalse(DanmakuFilter.allows(item("红色", color = 0xFF0000), noColor))
    }

    @Test
    fun `block words are case insensitive`() {
        val s = defaults.copy(blockWords = listOf("剧透", "SPOILER"))
        assertFalse(DanmakuFilter.allows(item("这里有剧透"), s))
        assertFalse(DanmakuFilter.allows(item("spoiler ahead"), s))
        assertTrue(DanmakuFilter.allows(item("正常弹幕"), s))
    }

    @Test
    fun `disabled danmaku hides everything`() {
        assertFalse(DanmakuFilter.allows(item("任意"), defaults.copy(enabled = false)))
    }

    @Test
    fun `apply sorts by progress and optionally dedupes`() {
        val items = listOf(
            item("b", progress = 300),
            item("a", progress = 100),
            item("a", progress = 200),
            item("c", progress = 50)
        )
        val deduped = DanmakuFilter.apply(items, defaults.copy(mergeDuplicate = true))
        assertEquals(listOf("c", "a", "b"), deduped.map { it.content })
        assertEquals(listOf(50L, 100L, 300L), deduped.map { it.progressMs })

        val kept = DanmakuFilter.apply(items, defaults.copy(mergeDuplicate = false))
        assertEquals(4, kept.size)
        assertEquals(listOf("c", "a", "a", "b"), kept.map { it.content })
    }

    @Test
    fun `density cap keeps the heaviest entries`() {
        val items = (1..10).map { item("d$it", weight = it) }
        val capped = DanmakuFilter.capByDensity(items, 3)
        assertEquals(3, capped.size)
        assertEquals(listOf(10, 9, 8), capped.map { it.weight })
    }
}
