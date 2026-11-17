package top.nekoh2o.player.data.bilibili

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BiliSignTest {

    @Test
    fun `keyFromUrl strips dir and extension`() {
        assertEquals(
            "7cd084941338484aae1ad9425b84077c",
            BiliSign.keyFromUrl("https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png")
        )
        assertEquals("", BiliSign.keyFromUrl(""))
    }

    @Test
    fun `mixinKey reorders by the fixed table`() {
        val img = "https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png"
        val sub = "https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png"
        // 置换表固定，前 32 位重排结果应当稳定
        assertEquals("ea1db124af3c7062474693fa704f4ff8", BiliSign.mixinKey(img, sub))
    }

    @Test
    fun `sign sorts params, appends wts and w_rid`() {
        val mixin = "ea1db124af3c7062474693fa704f4ff8"
        val query = BiliSign.sign(
            mapOf("foo" to "114", "bar" to "514", "zab" to "1919810"),
            mixin,
            wts = 1702204169L
        )
        assertEquals(
            "bar=514&foo=114&wts=1702204169&zab=1919810&w_rid=8f6f2b5b3d485fe1886cec6a0be8c5d4",
            query
        )
        // w_rid 是 32 位小写 md5
        val rid = query.substringAfter("w_rid=")
        assertEquals(32, rid.length)
        assertTrue(rid.all { it in '0'..'9' || it in 'a'..'f' })
    }

    @Test
    fun `encode escapes reserved characters`() {
        assertEquals("a%20b", BiliSign.encode("a b"))
        assertEquals("%E6%B5%8B%E8%AF%95", BiliSign.encode("测试"))
        assertEquals("a%2Fb%3Fc", BiliSign.encode("a/b?c"))
        assertFalse(BiliSign.encode("abc").contains("%"))
    }
}
