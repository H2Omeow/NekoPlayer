package top.nekoh2o.player.data.bilibili

import org.junit.Assert.assertEquals
import org.junit.Test

class BiliFormatTest {

    @Test
    fun `formatDuration renders mm ss and h mm ss`() {
        assertEquals("00:00", BiliClient.formatDuration(0))
        assertEquals("00:07", BiliClient.formatDuration(7))
        assertEquals("04:36", BiliClient.formatDuration(276))
        assertEquals("1:02:36", BiliClient.formatDuration(3756))
    }

    @Test
    fun `parseDuration reads search page duration strings`() {
        assertEquals(276, BiliClient.parseDuration("4:36"))
        assertEquals(3756, BiliClient.parseDuration("1:02:36"))
        assertEquals(42, BiliClient.parseDuration("42"))
        assertEquals(0, BiliClient.parseDuration(""))
        assertEquals(0, BiliClient.parseDuration("abc"))
    }

    @Test
    fun `parse and format round trip`() {
        for (seconds in listOf(5, 59, 60, 276, 3599, 3600, 3756, 86399)) {
            assertEquals(seconds, BiliClient.parseDuration(BiliClient.formatDuration(seconds)))
        }
    }

    @Test
    fun `quality labels cover the usual ladder`() {
        assertEquals("1080P", BiliClient.qualityLabel(80))
        assertEquals("720P", BiliClient.qualityLabel(64))
        assertEquals("480P", BiliClient.qualityLabel(32))
        assertEquals("360P", BiliClient.qualityLabel(16))
        assertEquals("4K", BiliClient.qualityLabel(120))
    }

    @Test
    fun `normalizeUrl fixes protocol relative urls`() {
        assertEquals("https://i0.hdslb.com/a.jpg", BiliClient.normalizeUrl("//i0.hdslb.com/a.jpg"))
        assertEquals("https://i0.hdslb.com/a.jpg", BiliClient.normalizeUrl("https://i0.hdslb.com/a.jpg"))
        assertEquals("", BiliClient.normalizeUrl(""))
    }
}
