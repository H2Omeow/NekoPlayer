package top.nekoh2o.player.data.bilibili

/**
 * 弹幕 protobuf 手写解析。
 *
 * `x/v2/dm/web/seg.so` 返回 `DmSegMobileReply`，只有一个 repeated 字段：
 * ```
 * message DmSegMobileReply { repeated DanmakuElem elems = 1; }
 * message DanmakuElem {
 *   int64  id       = 1;  int32 progress = 2;  int32 mode = 3;
 *   int32  fontsize = 4;  uint32 color   = 5;  string midHash = 6;
 *   string content  = 7;  int64  ctime   = 8;  int32 weight = 9;
 *   int32  pool     = 12; ...
 * }
 * ```
 * 只解析渲染需要的字段，未知字段按 wire type 跳过；格式错误时返回已解析部分，
 * 避免一条坏数据让整段弹幕消失。
 */
object BiliDanmakuProto {

    fun parse(bytes: ByteArray): List<DanmakuItem> {
        val out = ArrayList<DanmakuItem>(256)
        val reader = Reader(bytes)
        while (reader.hasMore()) {
            val tag = reader.readVarint()
            val field = (tag ushr 3).toInt()
            val wire = (tag and 0x7).toInt()
            if (wire == 2 && field == 1) {
                val payload = reader.readBytes() ?: return out
                parseElem(payload)?.let { out.add(it) }
            } else {
                reader.skip(wire) ?: return out
            }
        }
        return out
    }

    private fun parseElem(bytes: ByteArray): DanmakuItem? {
        var id = 0L
        var progress = 0L
        var mode = 1
        var fontSize = 25
        var color = 0xFFFFFF
        var content = ""
        var weight = 0
        val reader = Reader(bytes)
        while (reader.hasMore()) {
            val tag = reader.readVarint()
            val field = (tag ushr 3).toInt()
            val wire = (tag and 0x7).toInt()
            when {
                wire == 0 && field == 1 -> id = reader.readVarint()
                wire == 0 && field == 2 -> progress = reader.readVarint()
                wire == 0 && field == 3 -> mode = reader.readVarint().toInt()
                wire == 0 && field == 4 -> fontSize = reader.readVarint().toInt()
                wire == 0 && field == 5 -> color = reader.readVarint().toInt()
                wire == 2 && field == 7 -> content = reader.readBytes()?.toString(Charsets.UTF_8).orEmpty()
                wire == 0 && field == 9 -> weight = reader.readVarint().toInt()
                else -> if (!reader.skip(wire)) return null
            }
        }
        if (content.isBlank()) return null
        return DanmakuItem(
            id = id,
            progressMs = progress,
            mode = if (mode in 1..9) mode else 1,
            fontSize = if (fontSize > 0) fontSize else 25,
            color = color and 0xFFFFFF,
            content = content,
            weight = weight
        )
    }

    private class Reader(private val data: ByteArray) {
        private var pos = 0

        fun hasMore(): Boolean = pos < data.size

        fun readVarint(): Long {
            var result = 0L
            var shift = 0
            while (pos < data.size && shift < 64) {
                val b = data[pos++].toInt() and 0xFF
                result = result or ((b and 0x7F).toLong() shl shift)
                if (b and 0x80 == 0) return result
                shift += 7
            }
            return result
        }

        fun readBytes(): ByteArray? {
            val len = readVarint().toInt()
            if (len < 0 || pos + len > data.size) return null
            val slice = data.copyOfRange(pos, pos + len)
            pos += len
            return slice
        }

        /** 未知字段跳过；返回 false 表示数据被截断。 */
        fun skip(wire: Int): Boolean {
            when (wire) {
                0 -> readVarint()
                1 -> { if (pos + 8 > data.size) return false; pos += 8 }
                2 -> { val len = readVarint().toInt(); if (len < 0 || pos + len > data.size) return false; pos += len }
                5 -> { if (pos + 4 > data.size) return false; pos += 4 }
                else -> return false
            }
            return true
        }
    }
}
