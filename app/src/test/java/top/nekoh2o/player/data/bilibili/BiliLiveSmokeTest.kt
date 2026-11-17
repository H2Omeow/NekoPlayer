package top.nekoh2o.player.data.bilibili

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test

/**
 * 真机联网冒烟测试：只有在设置环境变量 `BILI_LIVE=1` 时才跑，
 * 避免 CI / 离线构建时因网络抖动失败。
 *
 * 覆盖真实链路上最容易出错的四件事：wbi 签名、搜索、取播放地址、弹幕 protobuf。
 */
class BiliLiveSmokeTest {

    private val client = BiliClient()

    @Before
    fun onlyWhenRequested() {
        assumeTrue("set BILI_LIVE=1 to run live bilibili tests", System.getenv("BILI_LIVE") == "1")
    }

    @Test
    fun `search returns playable videos`() = runBlocking {
        val page = client.search("东京", 1)
        assertTrue("search should return items", page.items.isNotEmpty())
        val first = page.items.first()
        assertTrue(first.bvid.startsWith("BV"))
        assertTrue(first.title.isNotBlank())
        assertTrue(first.durationSec >= 0)
        println("search -> ${first.bvid} ${first.title} ${first.durationSec}s")
    }

    @Test
    fun `view and playurl resolve a real stream`() = runBlocking {
        val page = client.search("音乐现场", 1)
        val candidate = page.items.first()
        val detail = client.view(candidate.bvid)
        assertTrue(detail.cid > 0)
        assertTrue(detail.item.title.isNotBlank())

        val source = client.playUrl(candidate.bvid, detail.cid, qn = 64)
        assertNotNull(source)
        assertTrue("play url should be http(s)", source!!.url.startsWith("http"))
        println("playurl -> ${source.qualityLabel} ${source.url.take(80)}")
    }

    @Test
    fun `danmaku segment decodes into items`() = runBlocking {
        val page = client.search("东京", 1)
        val candidate = page.items.first()
        val detail = client.view(candidate.bvid)
        val items = client.danmakuSegment(detail.cid, candidate.aid, 1)
        assertTrue("segment should contain danmaku", items.isNotEmpty())
        assertTrue(items.all { it.content.isNotEmpty() })
        println("danmaku -> ${items.size} items, first=${items.first().content}")
    }

    @Test
    fun `qr login generate returns a ticket`() = runBlocking {
        val ticket = client.qrGenerate()
        assertTrue(ticket.key.length in 20..64)
        assertTrue(ticket.url.startsWith("http"))
        println("qr -> ${ticket.url}")
    }
}
