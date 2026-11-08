package top.nekoh2o.player.data.net.nativeapi

import top.nekoh2o.player.i18n.NekoI18n.tr

import top.nekoh2o.player.data.net.ProviderPreferences
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import top.nekoh2o.player.data.net.CookieStore
import java.io.IOException

/** Native equivalents of NeteaseCloudMusicApi modules; no Node bridge is used. */
class NeteaseNativeInterceptor(private val prefs: ProviderPreferences) : Interceptor {
    private val device = prefs.getString("device", null)?.takeIf { it.matches(Regex("[A-F0-9]{52}")) } ?: Crypto.randomHex(26).uppercase().also { prefs.edit().putString("device", it).apply() }
    override fun intercept(chain: Interceptor.Chain): Response {
        val original = chain.request()
        val endpoint = original.url.encodedPath.removePrefix("/api/")
        val p = parameters(original)
        fun arg(name: String, fallback: String = "") = p[name] ?: fallback
        fun number(name: String, fallback: Long = 0) = p[name]?.toLongOrNull() ?: fallback
        if (endpoint == "login/qr/create") {
            val url = "https://music.163.com/login?codekey=" + arg("key")
            return jsonResponse(original, obj("code" to 200, "data" to obj("qrurl" to url, "qrimg" to qrImage(url))))
        }
        var weapi = false
        var path: String
        var data: JsonObject
        when (endpoint) {
            "search" -> { path = "/api/search/get"; data = obj("s" to arg("keywords"), "type" to number("type",1), "limit" to number("limit",30), "offset" to number("offset")) }
            "search/suggest" -> { path = "/api/search/suggest/web"; data = obj("s" to arg("keywords")); weapi=true }
            "song/detail" -> { path = "/api/v3/song/detail"; data=obj("c" to arg("ids").split(',').map { obj("id" to it.toLong()) }.let { JsonArray(it).toString() }); weapi=true }
            "song/url/v1" -> { path="/api/song/enhance/player/url/v1"; data=obj("ids" to ("["+arg("id")+"]"), "level" to arg("level","exhigh"), "encodeType" to "flac"); if(arg("level")=="sky") data=JsonObject(data+("immerseType" to JsonPrimitive("c51"))) }
            "song/url" -> { path="/api/song/enhance/player/url"; val ids=JsonArray(arg("id").split(',').map(::JsonPrimitive)).toString(); data=obj("ids" to ids, "br" to number("br",320000)) }
            "song/music/detail" -> { path="/api/song/music/detail/get"; data=obj("songId" to arg("id")) }
            "song/download/url/v1" -> { path="/api/song/enhance/download/url/v1"; data=obj("id" to arg("id"), "level" to arg("level"), "immerseType" to "c51") }
            "lyric/new" -> { path="/api/song/lyric/v1"; data=obj("id" to arg("id"),"cp" to false,"tv" to 0,"lv" to 0,"rv" to 0,"kv" to 0,"yv" to 0,"ytv" to 0,"yrv" to 0) }
            "lyric" -> { path="/api/song/lyric"; data=obj("id" to arg("id"),"tv" to -1,"lv" to -1,"rv" to -1,"kv" to -1,"_nmclfl" to 1) }
            "personalized" -> { path="/api/personalized/playlist"; data=obj("limit" to number("limit",30),"total" to true,"n" to 1000);weapi=true }
            "recommend/songs" -> { path="/api/v3/discovery/recommend/songs"; data=obj();weapi=true }
            "top/song" -> { path="/api/v1/discovery/new/songs"; data=obj("areaId" to number("type"),"total" to true);weapi=true }
            "playlist/detail" -> { path="/api/v6/playlist/detail"; data=obj("id" to arg("id"),"n" to 100000,"s" to 8) }
            "artist/top/song" -> { path="/api/artist/top/song"; data=obj("id" to arg("id"));weapi=true }
            "album" -> { path="/api/v1/album/"+number("id"); data=obj();weapi=true }
            "user/playlist" -> { path="/api/user/playlist"; data=obj("uid" to arg("uid"),"limit" to number("limit",30),"offset" to number("offset"),"includeVideo" to true);weapi=true }
            "likelist" -> { path="/api/song/like/get"; data=obj("uid" to arg("uid")) }
            "user/record" -> { path="/api/v1/play/record"; data=obj("uid" to arg("uid"),"type" to number("type"));weapi=true }
            "user/account", "login/status" -> { path=if(endpoint=="login/status") "/api/w/nuser/account/get" else "/api/nuser/account/get"; data=obj();weapi=true }
            "login/qr/key" -> { path="/api/login/qrcode/unikey"; data=obj("type" to 3) }
            "login/qr/check" -> { path="/api/login/qrcode/client/login"; data=obj("key" to arg("key"),"type" to 3) }
            "register/anonimous" -> {
                val magic="3go8&\$8*3*3h0k(2)2"
                val xor=device.mapIndexed { i,c -> (c.code xor magic[i%magic.length].code).toChar() }.joinToString("")
                val digest=java.security.MessageDigest.getInstance("MD5").digest(xor.toByteArray())
                path="/api/register/anonimous";data=obj("username" to Crypto.b64((device+" "+Crypto.b64(digest)).toByteArray()));weapi=true
            }
            "comment/music" -> { path="/api/v1/resource/comments/R_SO_4_"+number("id");data=obj("rid" to arg("id"),"limit" to number("limit",20),"offset" to number("offset"),"beforeTime" to number("before"));weapi=true }
            "comment" -> {
                val action=mapOf("0" to "delete","1" to "add","2" to "reply")[arg("t")] ?: throw IOException(tr("无效评论操作"))
                path="/api/resource/comments/"+action;data=obj("threadId" to ("R_SO_4_"+number("id")))
                if(action!="add") data=JsonObject(data+("commentId" to JsonPrimitive(arg("commentId"))))
                if(action!="delete") data=JsonObject(data+("content" to JsonPrimitive(arg("content"))))
                weapi=true
            }
            "comment/like" -> { path="/api/v1/comment/"+(if(arg("t")=="1") "like" else "unlike");data=obj("threadId" to ("R_SO_4_"+number("id")),"commentId" to arg("cid"));weapi=true }
            "comment/floor" -> { path="/api/resource/comment/floor/get";data=obj("parentCommentId" to arg("parentCommentId"),"threadId" to ("R_SO_4_"+number("id")),"time" to number("time",-1),"limit" to number("limit",20));weapi=true }
            else -> throw IOException(tr("尚未支持的网易云接口：")+endpoint)
        }
        val cookies = (p["cookie"] ?: CookieStore.activeCookie()).split(';').mapNotNull { part ->
            val i=part.indexOf('=');if(i<=0) null else part.substring(0,i).trim() to part.substring(i+1).trim()
        }.filter { (k,v) -> k.matches(Regex("[A-Za-z0-9_]+")) && v.none { it=='\r'||it=='\n' } }.toMap().toMutableMap()
        cookies.putIfAbsent("deviceId",device);cookies.putIfAbsent("os","pc");cookies.putIfAbsent("appver","3.1.17.204416")
        cookies.putIfAbsent("osver","Microsoft-Windows-10-Professional-build-19045-64bit");cookies.putIfAbsent("channel","netease")
        cookies["__remember_me"]="true";cookies["ntes_kaola_ad"]="1";cookies["_ntes_nuid"]=device
        data=JsonObject(data+("e_r" to JsonPrimitive(false)))
        val url: String
        val body: RequestBody
        if(weapi) {
            data=JsonObject(data+("csrf_token" to JsonPrimitive(cookies["__csrf"].orEmpty())))
            url="https://music.163.com"+path.replaceFirst("/api/","/weapi/");body=Crypto.weapi(data.toString())
        } else {
            val header=cookies.filterKeys { it in setOf("osver","deviceId","os","appver","channel","__csrf","MUSIC_U","MUSIC_A") }.toMutableMap()
            header["versioncode"]="140";header["buildver"]=(System.currentTimeMillis()/1000).toString();header["resolution"]="1920x1080"
            header["requestId"]=System.currentTimeMillis().toString()+"_"+Crypto.randomText(3)
            data=JsonObject(data+("header" to value(header)));cookies.putAll(header)
            url="https://interface.music.163.com"+path.replaceFirst("/api/","/eapi/");body=Crypto.eapi(path,data.toString())
        }
        val request=Request.Builder().url(url).post(body).header("Referer","https://music.163.com/")
            .header("User-Agent","Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0.0.0 Safari/537.36")
            .header("Cookie",cookies.entries.joinToString("; ") { it.key+"="+it.value }).build()
        return chain.proceed(request).use { response ->
            var result=try { Json.parseToJsonElement(response.body?.string().orEmpty()).jsonObject } catch (_: Exception) { throw IOException(tr("网易云响应格式异常（HTTP ")+response.code+"）") }
            when(endpoint) {
                "login/qr/key" -> result=obj("code" to (result["code"]?:JsonPrimitive(200)),"data" to result)
                "login/status" -> result=obj("data" to result)
                "login/qr/check","register/anonimous" -> {
                    val cookie=response.headers.values("Set-Cookie").mapNotNull { Cookie.parse(request.url,it) }.joinToString("; ") { it.name+"="+it.value }
                    result=JsonObject(result+("cookie" to JsonPrimitive(cookie)))
                }
            }
            response.newBuilder().request(original).removeHeader("Content-Encoding").body(result.toString().toResponseBody("application/json".toMediaType())).build()
        }
    }
}
