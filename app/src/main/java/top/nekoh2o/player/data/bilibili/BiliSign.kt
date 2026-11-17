package top.nekoh2o.player.data.bilibili

import java.net.URLEncoder
import java.security.MessageDigest

/**
 * B 站 wbi 签名。
 *
 * 签名算法（bilibili-API-collect / wbi.md）：
 * 1. 从 `x/web-interface/nav` 的 `wbi_img.img_url`、`sub_url` 里取出文件名（去掉目录与 .png）；
 * 2. 两段拼接后按 [MIXIN_KEY_ENC_TAB] 重排，取前 32 位得到 mixin key；
 * 3. 参数按 key 升序排序 + `wts`，拼成 query 后与 mixin key 做 md5，得到 `w_rid`。
 *
 * 表里的下标是 B 站固定的置换表，不要改顺序。
 */
object BiliSign {

    private val MIXIN_KEY_ENC_TAB = intArrayOf(
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
        27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
        37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
        22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52
    )

    /** 从 wbi 图片地址里取 32 位 key（`.../7cd0....png` → `7cd0...`）。 */
    fun keyFromUrl(url: String): String {
        val file = url.substringAfterLast('/', "")
        return file.substringBefore('.')
    }

    fun mixinKey(imgUrl: String, subUrl: String): String {
        val raw = keyFromUrl(imgUrl) + keyFromUrl(subUrl)
        if (raw.length < 64) return raw.take(32)
        val sb = StringBuilder(32)
        for (i in 0 until 32) {
            sb.append(raw[MIXIN_KEY_ENC_TAB[i]])
        }
        return sb.toString()
    }

    /**
     * 生成带签名的 query。`wts` 由调用方传入，方便测试固定时间戳。
     * 返回的字符串可直接拼到 `?` 后面。
     */
    fun sign(
        params: Map<String, String>,
        mixinKey: String,
        wts: Long = System.currentTimeMillis() / 1000
    ): String {
        val all = params.toMutableMap()
        all["wts"] = wts.toString()
        val query = all.keys.sorted().joinToString("&") { key ->
            "$key=${encode(all[key].orEmpty())}"
        }
        val wRid = md5(query + mixinKey)
        return "$query&w_rid=$wRid"
    }

    fun md5(input: String): String {
        val digest = MessageDigest.getInstance("MD5").digest(input.toByteArray(Charsets.UTF_8))
        val out = StringBuilder(digest.size * 2)
        for (b in digest) {
            val v = b.toInt() and 0xFF
            if (v < 0x10) out.append('0')
            out.append(Integer.toHexString(v))
        }
        return out.toString()
    }

    /** wbi 要求 RFC3986 编码：空格 %20，`!'()*` 不转义以外的字符按标准转义。 */
    fun encode(value: String): String =
        URLEncoder.encode(value, "UTF-8")
            .replace("+", "%20")
            .replace("%21", "!")
            .replace("%27", "'")
            .replace("%28", "(")
            .replace("%29", ")")
            .replace("%2A", "*")
}
