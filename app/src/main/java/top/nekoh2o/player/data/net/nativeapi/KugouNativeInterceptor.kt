package top.nekoh2o.player.data.net.nativeapi

import top.nekoh2o.player.i18n.NekoI18n.tr

import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.ResponseBody.Companion.toResponseBody
import top.nekoh2o.player.data.net.*
import java.io.IOException
import java.math.BigInteger

/** Direct provider transport. Platform identity, signatures and cookies are isolated per request. */
class KugouNativeInterceptor(private val sessions: KugouSessionStore) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val original=chain.request();val input=parameters(original)
        val platform=input["platform"]?.toIntOrNull()?.takeIf { it in 0..1 } ?: 0
        val lite=platform==1;val appid=if(lite) 3116 else 1005;val ver=if(lite) 11440 else 20489
        val rsa=if(lite) Crypto.KUGOU_LITE_RSA else Crypto.KUGOU_RSA
        synchronized(sessions) {
            if(sessions.value(platform,"KUGOU_API_GUID").isBlank()) {
                val guid=Crypto.randomHex(16)
                sessions.merge(platform,mapOf("KUGOU_API_GUID" to guid,"KUGOU_API_MID" to BigInteger(Crypto.md5(guid),16).toString(),
                    "KUGOU_API_DEV" to Crypto.randomHex(16).uppercase(),"KUGOU_API_MAC" to "02:00:00:00:00:00"))
            }
        }
        fun cookie(name: String)=sessions.value(platform,name)
        fun arg(name: String, fallback: String="")=input[name]?:fallback
        fun number(name: String, fallback: Long=0)=input[name]?.toLongOrNull()?:fallback
        val endpoint=original.url.encodedPath.removePrefix("/kgapi/")
        if(endpoint=="login/qr/create") {
            val url="https://h5.kugou.com/apps/loginQRCode/html/index.html?qrcode="+arg("key")
            return jsonResponse(original,obj("code" to 200,"data" to obj("url" to url,"base64" to qrImage(url))))
        }
        val now=System.currentTimeMillis();val seconds=now/1000;val mid=cookie("KUGOU_API_MID");val token=cookie("token")
        val uid=cookie("userid").ifBlank { "0" };val dfid=cookie("dfid").ifBlank { "-" }
        fun key(data: Any)=Crypto.md5(appid.toString()+salt(lite)+ver+data)
        fun rawRsa(data: JsonObject)=Crypto.rsa(data.toString().toByteArray(),rsa,padEnd=true).uppercase()
        var host="https://gateway.kugou.com";var path="";var method="GET";var router="";var web=false;var clear=false;var sign=true
        val params=linkedMapOf<String,Any?>();var data: JsonElement?=null;var rawBody: String?=null
        var decryptKey: String?=null;var registerKey: String?=null
        val headers=linkedMapOf<String,String>()
        fun query(vararg pairs: Pair<String,Any?>) { params.putAll(pairs) }
        fun post(body: JsonElement) { method="POST";data=body }
        fun t1()=Crypto.hex(Crypto.aes((cookie("t1")+"|"+now).toByteArray(),"5e4ef500e9597fe004bd09a46d8add98","04bd09a46d8add98"))
        fun t2()=Crypto.hex(Crypto.aes((cookie("KUGOU_API_GUID")+"|0f607264fc6318a92b9e13c65db7cd3c|"+cookie("KUGOU_API_MAC")+"|"+cookie("KUGOU_API_DEV")+"|"+now).toByteArray(),"fd14b35e3f81af3817a20ae7adae7020","17a20ae7adae7020"))
        when(endpoint) {
            "register/dev" -> {
                host="https://userservice.kugou.com";path="/risk/v2/r_register_dev";method="POST"
                val device=linkedMapOf<String,Any?>("availableRamSize" to 4983533568L,"availableRomSize" to 48114719,"availableSDSize" to 48114717,
                    "basebandVer" to "","batteryLevel" to 100,"batteryStatus" to 3,"brand" to NativePlatform.brand,
                    "buildSerial" to "unknown","device" to NativePlatform.device,"imei" to cookie("KUGOU_API_GUID"),"imsi" to "",
                    "manufacturer" to NativePlatform.manufacturer,"uuid" to cookie("KUGOU_API_GUID"))
                listOf("accelerometer","gravity","gyroscope","light","magnetic","orientation","pressure","step_counter","temperature").forEach { device[it]=false;device[it+"Value"]="" }
                val secret=Crypto.randomText(6);registerKey=secret;val hash=Crypto.md5(secret)
                rawBody=Crypto.b64(Crypto.aes(value(device).toString().toByteArray(),hash.take(16),hash.takeLast(16)))
                query("part" to 1,"platid" to 1,"p" to Crypto.rsa(obj("aes" to secret,"uid" to uid.toLong(),"token" to token).toString().toByteArray(),rsa,pkcs=true))
            }
            // The legacy dotted login host has a mismatched TLS certificate.
            "captcha/sent" -> { host=LOGIN_HOST;path="/v7/send_mobile_code";post(obj("businessid" to 5,"mobile" to arg("mobile"),"plat" to 3)) }
            "login/cellphone", "login/token" -> {
                val secret=Crypto.randomText(16);decryptKey=secret;val hash=Crypto.md5(secret)
                val content=if(endpoint=="login/cellphone") obj("mobile" to arg("mobile"),"code" to arg("code")) else obj()
                val encrypted=Crypto.hex(Crypto.aes(content.toString().toByteArray(),hash,hash.takeLast(16)))
                val body=linkedMapOf<String,Any?>("plat" to 1,"t1" to if(lite) t1() else 0,"t2" to if(lite) t2() else 0,
                    "clienttime_ms" to now,"pk" to rawRsa(obj("clienttime_ms" to now,"key" to secret)),"params" to encrypted)
                if(endpoint=="login/cellphone") {
                    val mobile=arg("mobile");body["mobile"]=mobile.take(2)+"*****"+mobile.takeLast(1)
                    body["support_multi"]=1;body["key"]=key(now);input["userid"]?.let { body["userid"]=it }
                    host="https://loginserviceretry.kugou.com";path="/v7/login_by_verifycode"
                    headers["support-calm"]="1";headers["User-Agent"]="Android16-1070-11440-130-0-LOGIN-wifi"
                } else {
                    val k=if(lite) "c24f74ca2820225badc01946dba4fdf7" else "90b8382a1bb4ccdcf063102053fd75b8"
                    body["p3"]=Crypto.hex(Crypto.aes(obj("clienttime" to seconds,"token" to token).toString().toByteArray(),k,k.takeLast(16)))
                    body["userid"]=uid;body["dfid"]=dfid;host=LOGIN_HOST;path="/v5/login_by_token"
                }
                if(lite) { body["dfid"]=dfid;body["dev"]=cookie("KUGOU_API_DEV");body["gitversion"]="5f0b7c4" }
                else body["t3"]="MCwwLDAsMCwwLDAsMCwwLDA="
                post(value(body))
            }
            "login/qr/key" -> { host="https://login-user.kugou.com";path="/v2/qrcode";web=true
                query("appid" to 1001,"type" to 1,"plat" to 4,"srcappid" to 2919,"qrcode_txt" to ("https://h5.kugou.com/apps/loginQRCode/html/index.html?appid="+appid+"&")) }
            "login/qr/check" -> { host="https://login-user.kugou.com";path="/v2/get_userinfo_qrcode";web=true
                query("plat" to 4,"appid" to appid,"srcappid" to 2919,"qrcode" to arg("key"),"dev" to cookie("KUGOU_API_DEV")) }
            "user/detail" -> { path="/v3/get_my_info";router="usercenter.kugou.com";query("plat" to 1)
                post(obj("visit_time" to seconds,"usertype" to 1,"p" to rawRsa(obj("token" to token,"clienttime" to seconds)),"userid" to uid.toLong())) }
            "user/vip/detail" -> { host="https://kugouvip.kugou.com";path="/v1/get_union_vip";query("busi_type" to "concept") }
            "user/playlist" -> { path="/v7/get_all_list";router="cloudlist.service.kugou.com";query("plat" to 1,"userid" to uid.toLong(),"token" to token)
                post(obj("userid" to uid,"token" to token,"total_ver" to 979,"type" to 2,"page" to number("page",1),"pagesize" to number("pagesize",30))) }
            "playlist/track/all" -> { path="/pubsongs/v2/get_other_list_file_nofilt"
                query("area_code" to 1,"begin_idx" to (number("page",1)-1)*number("pagesize",30),"plat" to 1,"type" to 1,"mode" to 1,"personal_switch" to 1,"extend_fields" to "abtags,hot_cmt,popularization","pagesize" to number("pagesize",30),"global_collection_id" to arg("id")) }
            "search" -> {
                // Public catalog endpoint: Android v2/v3 currently returns business error 152.
                host="https://songsearch.kugou.com";path="/song_search_v2";clear=true;web=true
                query("keyword" to arg("keywords"),"page" to number("page",1),"pagesize" to number("pagesize",30),"platform" to "WebFilter",
                    "appid" to 1014,"srcappid" to 2919,"clientver" to 20000,"clienttime" to now,"mid" to now,"uuid" to now,"dfid" to "-")
            }
            "search/suggest" -> { path="/v2/getSearchTip";router="searchtip.kugou.com";query("keyword" to arg("keywords"),"AlbumTipCount" to 10,"CorrectTipCount" to 10,"MVTipCount" to 10,"MusicTipCount" to 10,"radiotip" to 1) }
            "search/lyric" -> { host="https://lyrics.kugou.com";path="/v1/search";clear=true
                query("album_audio_id" to number("album_audio_id"),"appid" to appid,"clientver" to ver,"duration" to 0,"hash" to arg("hash"),"keyword" to arg("keywords"),"lrctxt" to 1,"man" to "no") }
            "lyric" -> { host="https://lyrics.kugou.com";path="/download";query("ver" to 1,"client" to "android","id" to arg("id"),"accesskey" to arg("accesskey"),"fmt" to "lrc","charset" to "utf8") }
            "song/url" -> {
                path="/v5/url";router="trackercdn.kugou.com"
                query("album_id" to number("album_id"),"area_code" to 1,"hash" to arg("hash").lowercase(),"ssa_flag" to "is_fromtrack",
                    "version" to 11430,"page_id" to if(lite) 967177915 else 151369488,"quality" to arg("quality","128"),"album_audio_id" to number("album_audio_id"),
                    "behavior" to arg("behavior","play"),"pid" to if(lite) 411 else 2,"cmd" to 26,"pidversion" to 3001,"IsFreePart" to 0,
                    "ppage_id" to if(lite) "356753938,823673182,967485191" else "463467626,350369493,788954147","cdnBackup" to 1,"module" to "","clientver" to 11430,
                    "key" to Crypto.md5(arg("hash").lowercase()+(if(lite) "185672dd44712f60bb1736df5a377e82" else "57ae12eb6890223e355ccfcb74edf70d")+appid+mid+uid))
            }
            "privilege/lite" -> { path="/v2/get_res_privilege/lite";router="media.store.kugou.com"
                post(obj("appid" to appid,"area_code" to 1,"behavior" to arg("behavior","play"),"clientver" to ver,"need_hash_offset" to 1,"relate" to 1,"support_verify" to 1,
                    "resource" to arg("hash").split(',').map { obj("type" to "audio","page_id" to 0,"hash" to it,"album_id" to arg("album_id","0")) },
                    "qualities" to listOf("128","320","flac","high","viper_atmos","viper_tape","viper_clear","super","multitrack"))) }
            "youth/day/vip" -> { path="/youth/v1/recharge/receive_vip_listen_song";method="POST";query("source_id" to 90139,"receive_day" to 1) }
            "user/follow" -> { path="/v4/follow_list";router="relationuser.kugou.com";query("plat" to 1)
                post(obj("merge" to 2,"need_iden_type" to 1,"ext_params" to "k_pic,jumptype,singerid,score","userid" to uid,"type" to 0,"id_type" to 0,"p" to rawRsa(obj("clienttime" to seconds,"token" to token)))) }
            "artist/audios" -> { host="https://openapi.kugou.com";path="/kmr/v1/audio_group/author";headers["kg-tid"]="220"
                post(obj("appid" to appid,"clientver" to ver,"mid" to mid,"clienttime" to seconds,"key" to key(seconds),"author_id" to arg("id"),"pagesize" to number("pagesize",30),"page" to number("page",1),"sort" to 2,"area_code" to "all")) }
            "user/history" -> { path="/playhistory/v1/get_songs";post(obj("token" to token,"userid" to uid,"source_classify" to "app","to_subdivide_sr" to 1)) }
            "personal/fm" -> { path="/v2/personal_recommend";router="persnfm.service.kugou.com"
                val body=linkedMapOf<String,Any?>("appid" to appid,"clienttime" to now,"mid" to mid,"action" to "play","recommend_source_locked" to 0,"song_pool_id" to 0,
                    "callerid" to 0,"m_type" to 1,"platform" to "ios","area_code" to 1,"remain_songcnt" to 0,"clientver" to ver,"is_overplay" to 0,"mode" to "normal",
                    "fakem" to "ca981cfc583a4c37f28d2d49000013c16a0a","key" to key(now))
                if(uid!="0") { body["userid"]=uid;body["kguid"]=uid };if(token.isNotEmpty()) body["token"]=token
                if(cookie("vip_type").isNotEmpty()) body["vip_type"]=cookie("vip_type");post(value(body)) }
            "comment/music", "comment/floor" -> {
                path=if(endpoint=="comment/music") "/mcomment/v1/cmtlist" else "/mcomment/v1/hot_replylist";method="POST"
                query("mixsongid" to arg("mixsongid"),"need_show_image" to 1,"p" to number("page",1),"pagesize" to number("pagesize",20),"show_classify" to 1,"show_hotword_list" to 1,"extdata" to "0","code" to COMMENT_CODE)
                if(endpoint=="comment/floor") query("childrenid" to arg("special_id"),"tid" to arg("tid"))
            }
            "comment/music/send", "comment/floor/send" -> {
                path="/index.php";router="m.comment.service.kugou.com";method="POST";clear=true;sign=false
                query("r" to if(endpoint=="comment/music/send") "commentsv3/add" else "commentsv2/reply","code" to COMMENT_CODE,
                    "childrenid" to arg("special_id"),"childrenname" to arg("name"),"kugouid" to uid,"ver" to 6,"clienttoken" to token,
                    "appid" to appid,"clientver" to ver,"mid" to mid,"clienttime" to seconds,"uuid" to "-","dfid" to dfid)
                if(endpoint=="comment/music/send") {
                    post(obj("data" to obj("content" to arg("content"),"album_audio_id" to arg("mixsongid"),"images" to emptyList<Any>())))
                    query("key" to key(seconds.toString()+mid+data.toString()))
                } else query("key" to key(seconds.toString()+mid),"content" to arg("content"),"tid" to arg("tid"),"is_t" to number("is_t",1),"pid" to number("pid"))
            }
            else -> throw IOException(tr("尚未支持的酷狗接口：")+endpoint)
        }
        val merged=linkedMapOf<String,Any?>()
        if(!clear) { merged.putAll(linkedMapOf("dfid" to dfid,"mid" to mid,"uuid" to "-","appid" to appid,"clientver" to ver,"clienttime" to seconds));if(token.isNotEmpty()) merged["token"]=token;if(uid!="0") merged["userid"]=uid }
        merged.putAll(params)
        val body=rawBody?:data?.toString().orEmpty()
        if(sign) merged["signature"]=signature(merged,body,lite,web)
        val url=(host+path).toHttpUrl().newBuilder();merged.forEach { (k,v) -> if(v!=null) url.addQueryParameter(k,v.toString()) }
        val request=Request.Builder().url(url.build()).header("User-Agent","Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi")
            .header("dfid",dfid).header("mid",mid).header("clienttime",seconds.toString()).header("kg-rc","1").header("kg-thash","5d816a0")
            .header("kg-rec","1").header("kg-rf","B9EDA08A64250DEFFBCADDEE00F8F25F")
        if(endpoint=="search") {
            request.headers(Headers.Builder().add("User-Agent","Mozilla/5.0").add("Referer","https://www.kugou.com/").build())
        }
        if(router.isNotEmpty()) request.header("x-router",router)
        headers.forEach { (k,v) -> request.header(k,v) }
        if(method=="POST") request.post(body.toRequestBody((if(data!=null) "application/json; charset=UTF-8" else "application/x-www-form-urlencoded").toMediaType()))
        return chain.proceed(request.build()).use { response ->
            val bytes=response.body?.bytes()?:throw IOException(tr("酷狗返回空响应"))
            val decoded=try { registerKey?.let { secret -> val h=Crypto.md5(secret);String(Crypto.aes(bytes,h.take(16),h.takeLast(16),true)) } ?: String(bytes) }
                catch (_: Exception) { throw IOException(tr("酷狗设备响应解密失败")) }
            var result=try { Json.parseToJsonElement(decoded).jsonObject } catch (_: Exception) { throw IOException(tr("酷狗响应格式异常（HTTP ")+response.code+"）") }
            val additional=mutableMapOf<String,String>()
            if(registerKey!=null && result.text("status")=="1") additional["dfid"]=result.obj("data").text("dfid")
            if(decryptKey!=null && result.text("status")=="1") {
                val values=result.obj("data").toMutableMap();val encrypted=result.obj("data").text("secu_params")
                if(encrypted.isNotBlank()) {
                    val h=Crypto.md5(decryptKey!!)
                    val clearText=try { String(Crypto.aes(Crypto.unhex(encrypted),h,h.takeLast(16),true)) } catch (_: Exception) { throw IOException(tr("酷狗登录响应解密失败")) }
                    val parsed=runCatching { Json.parseToJsonElement(clearText) as? JsonObject }.getOrNull()
                    if(parsed!=null) values.putAll(parsed) else values["token"]=JsonPrimitive(clearText)
                }
                result=JsonObject(result+("data" to JsonObject(values)))
                listOf("token","userid","vip_type","vip_token","t1").forEach { name -> result.obj("data").text(name).takeIf(String::isNotBlank)?.let { additional[name]=it } }
            }
            if(endpoint=="lyric") result.text("content").takeIf(String::isNotBlank)?.let { result=JsonObject(result+("decodeContent" to JsonPrimitive(String(Crypto.unb64(it))))) }
            val builder=response.newBuilder().request(original).removeHeader("Content-Encoding").body(result.toString().toResponseBody("application/json".toMediaType()))
            additional.filterValues { it.none { c -> c=='\r'||c=='\n'||c==';' } }.forEach { (k,v) -> builder.addHeader("Set-Cookie",k+"="+v+"; Path=/") }
            builder.build()
        }
    }
    companion object {
        private const val LOGIN_HOST="https://login-user.kugou.com"
        const val COMMENT_CODE="fc4be23b4e972707f36b8a828a93ba8a"
        internal fun salt(lite: Boolean)=if(lite) "LnT6xpN3khm36zse0QzvmgTZ3waWdRSA" else "OIlwieks28dk2k092lksi2UIkp"
        internal fun signature(params: Map<String,Any?>,body: String,lite: Boolean,web: Boolean=false): String {
            val salt=if(web) "NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt" else salt(lite)
            val text=params.toSortedMap().entries.joinToString("") { it.key+"="+it.value.toString() }
            return Crypto.md5(salt+text+(if(web) "" else body)+salt)
        }
    }
}
