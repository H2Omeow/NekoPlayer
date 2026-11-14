package top.nekoh2o.player.data.plugins

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GatewayPlaybackHeadersTest {
    @Test
    fun bilibiliAudioRequestsSendRangeAndBrowserHeaders() {
        val headers = GatewayPlaybackHeaders.forPlatform("bilibili")
        assertEquals("bytes=0-", headers["Range"])
        assertEquals("https://www.bilibili.com/", headers["Referer"])
        assertTrue(headers["User-Agent"].orEmpty().startsWith("Mozilla/5.0"))
    }

    @Test
    fun otherPlatformsDoNotGetBilibiliHeaders() {
        assertTrue(GatewayPlaybackHeaders.forPlatform("kg").isEmpty())
        assertTrue(GatewayPlaybackHeaders.forPlatform("wy").isEmpty())
    }
}
