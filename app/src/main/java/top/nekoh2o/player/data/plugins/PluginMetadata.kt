package top.nekoh2o.player.data.plugins

import top.nekoh2o.player.i18n.NekoI18n.tr

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import okio.ByteString.Companion.toByteString
import java.security.MessageDigest

internal fun verifyPluginChecksum(script: String, expected: String?) {
    if (expected == null) return
    val digest = MessageDigest.getInstance("SHA-256").digest(script.toByteArray()).toByteString()
    val valid = if (expected.matches(Regex("^[a-fA-F0-9]{64}$"))) digest.hex() == expected.lowercase()
        else expected == "sha256-${digest.base64()}"
    require(valid) { tr("音源脚本 SHA256 校验失败，已停止导入") }
}

internal fun parsePluginMetadata(script: String): JsonObject? {
    val assignment = Regex("""\b(?:const|let|var)\s+META\s*=\s*""").find(script) ?: return null
    val start = assignment.range.last + 1
    if (script.getOrNull(start) != '{') return null
    var depth = 0
    var quoted = false
    var escaped = false
    for (index in start until script.length) {
        val character = script[index]
        if (quoted) {
            if (escaped) escaped = false
            else if (character == '\\') escaped = true
            else if (character == '"') quoted = false
        } else when (character) {
            '"' -> quoted = true
            '{' -> depth++
            '}' -> {
                depth--
                if (depth == 0) return runCatching { Json.parseToJsonElement(script.substring(start, index + 1)).jsonObject }.getOrNull()
            }
        }
    }
    return null
}
