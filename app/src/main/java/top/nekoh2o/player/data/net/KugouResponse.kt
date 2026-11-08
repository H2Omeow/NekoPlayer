package top.nekoh2o.player.data.net

import top.nekoh2o.player.i18n.NekoI18n.tr

import kotlinx.serialization.json.*
import retrofit2.Response

class KugouApiException(message: String, val errorCode: Int? = null) : Exception(message)

internal fun JsonObject.text(vararg names: String): String = names.firstNotNullOfOrNull {
    (this[it] as? JsonPrimitive)?.contentOrNull?.takeIf(String::isNotBlank)
}.orEmpty()
internal fun JsonObject.number(vararg names: String): Long = text(*names).toLongOrNull() ?: 0
internal fun JsonObject.obj(name: String): JsonObject = this[name] as? JsonObject ?: JsonObject(emptyMap())
internal fun JsonObject.items(name: String): List<JsonObject> = (this[name] as? JsonArray)?.filterIsInstance<JsonObject>().orEmpty()
internal fun JsonObject.payload(): JsonObject = this["data"] as? JsonObject ?: this

internal fun Response<JsonObject>.kugouBody(): JsonObject {
    val body = body() ?: errorBody()?.use {
        runCatching { Json.parseToJsonElement(it.string()) as? JsonObject }.getOrNull()
    }
    val error = body?.text("error_code", "errcode", "err_code")?.toIntOrNull()
    if (!isSuccessful || body == null || body.text("status") == "0" || (error != null && error != 0)) {
        val message = when (error) {
            20028 -> tr("酷狗要求安全验证，请先在官方 App 完成验证后重试，或使用扫码登录")
            20018 -> tr("酷狗登录已失效，请重新登录")
            else -> body?.text("error_msg", "errmsg", "message", "msg").orEmpty()
                .takeIf { it.length in 1..160 } ?: if (code() == 503) tr("该版本的酷狗服务暂时不可用") else tr("酷狗接口请求失败")
        }
        throw KugouApiException(message + if (error != null && error != 0) "（" + error + "）" else "（HTTP " + code() + "）", error)
    }
    return body
}
