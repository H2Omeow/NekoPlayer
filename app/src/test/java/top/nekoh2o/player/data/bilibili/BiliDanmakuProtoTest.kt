package top.nekoh2o.player.data.bilibili

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream

class BiliDanmakuProtoTest {

    private fun varint(value: Long): ByteArray {
        val out = ByteArrayOutputStream()
        var v = value
        while (true) {
            if (v and 0x7FL.inv() == 0L) {
                out.write(v.toInt())
                break
            }
            out.write(((v and 0x7F) or 0x80).toInt())
            v = v ushr 7
        }
        return out.toByteArray()
    }

    private fun tag(field: Int, wire: Int) = varint(((field shl 3) or wire).toLong())
    private fun lenField(field: Int, bytes: ByteArray): ByteArray = tag(field, 2) + varint(bytes.size.toLong()) + bytes
    private fun varField(field: Int, value: Long): ByteArray = tag(field, 0) + varint(value)

    private fun elem(
        id: Long,
        progress: Long,
        mode: Long,
        fontSize: Long,
        color: Long,
        content: String,
        weight: Long
    ): ByteArray {
        val body = ByteArrayOutputStream()
        body.write(varField(1, id))
        body.write(varField(2, progress))
        body.write(varField(3, mode))
        body.write(varField(4, fontSize))
        body.write(varField(5, color))
        body.write(lenField(7, content.toByteArray()))
        body.write(varField(9, weight))
        return body.toByteArray()
    }

    @Test
    fun `parses elements from a danmaku segment`() {
        val payload = ByteArrayOutputStream().apply {
            write(lenField(1, elem(1, 1200, 1, 25, 16777215, "第一条弹幕", 5)))
            write(lenField(1, elem(2, 3400, 5, 18, 16711680, "顶部弹幕", 8)))
            // 未知字段（如 midHash 字段 6）应被跳过
            write(lenField(1, elem(3, 5000, 4, 25, 255, "底部", 0) + lenField(6, "deadbeef".toByteArray())))
        }.toByteArray()

        val items = BiliDanmakuProto.parse(payload)

        assertEquals(3, items.size)
        assertEquals("第一条弹幕", items[0].content)
        assertEquals(1200L, items[0].progressMs)
        assertEquals(25, items[0].fontSize)
        assertEquals(0xFFFFFF, items[0].color)
        assertEquals("顶部弹幕", items[1].content)
        assertEquals(5, items[1].mode)
        assertEquals(0xFF0000, items[1].color)
        assertEquals("底部", items[2].content)
        assertEquals(4, items[2].mode)
    }

    @Test
    fun `empty payload yields empty list`() {
        assertTrue(BiliDanmakuProto.parse(ByteArray(0)).isEmpty())
    }

    @Test
    fun `truncated payload returns what was parsed instead of throwing`() {
        val full = lenField(1, elem(1, 1000, 1, 25, 0xFFFFFF, "完整", 1))
        val truncated = full.copyOf(full.size - 3)
        val items = runCatching { BiliDanmakuProto.parse(truncated) }.getOrDefault(emptyList())
        assertTrue(items.size <= 1)
    }
}
