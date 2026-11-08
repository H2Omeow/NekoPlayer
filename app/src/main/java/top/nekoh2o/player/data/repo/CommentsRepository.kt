package top.nekoh2o.player.data.repo

import top.nekoh2o.player.i18n.NekoI18n.tr

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.data.net.*
import java.io.IOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

data class SongComment(val id: String, val userId: String, val userName: String, val content: String,
    val avatar: String = "", val time: String = "", val likes: Long = 0, val liked: Boolean = false,
    val replies: Long = 0, val owned: Boolean = false, val deleted: Boolean = false,
    val parentId: String = "", val quotedUser: String = "", val quotedContent: String = "")
data class CommentPage(val comments: List<SongComment>, val total: Long, val more: Boolean,
    val specialId: String = "", val resourceName: String = "", val nextCursor: String = "")

class CommentsRepository {
    private val nc get() = ApiFactory.nativeMusic
    private val kg get() = ApiFactory.kugou
    suspend fun matches(song: Song, source: String): List<Song> {
        if(source=="site" || source==song.source) return listOf(song)
        val query=song.nm+" "+song.ar
        return if(source=="kugou") KugouRepository().search(query).take(10) else MusicRepository().search(query,0,10)
    }
    suspend fun accountId(source: String): String {
        CookieStore.awaitReady();ApiFactory.awaitReady()
        return when(source) {
            "netease" -> if(!CookieStore.hasNcUserCookie()) "" else nc.get("user/account").obj("account").text("id").takeIf { (it.toLongOrNull() ?: 0) > 0 }.orEmpty()
            "kugou" -> if(!CookieStore.hasKgToken()) "" else KugouRepository().getUserInfo()?.userid?.takeIf { it>0 }?.toString().orEmpty()
            else -> if(CookieStore.appTokenValue().isBlank()) "" else "site"
        }
    }
    suspend fun list(source: String, song: Song, accountId: String, offset: Int = 0, parent: SongComment? = null, specialId: String = "", cursor: String = ""): CommentPage {
        CookieStore.awaitReady();ApiFactory.awaitReady()
        return when(source) {
            "netease" -> {
                val args=mutableMapOf("id" to song.id.toString(),"limit" to "20","offset" to offset.toString())
                if(parent!=null) { args["parentCommentId"]=parent.id; args["time"]=cursor.ifBlank { "-1" } }
                val root=nc.get(if(parent==null) "comment/music" else "comment/floor",args).checkedNc()
                neteasePage(root,accountId,parent!=null)
            }
            "kugou" -> {
                KugouRepository().ensureInitialized()
                val mix=song.albumAudioId.takeIf { it>0 } ?: KugouRepository().getSongDetail(song.hash)?.albumAudioId?.takeIf { it>0 }
                    ?: throw IOException(tr("该歌曲缺少评论资源标识，请重新搜索"))
                val args=mutableMapOf("mixsongid" to mix.toString(),"pagesize" to "20","page" to (offset/20+1).toString())
                if(parent!=null) { args["tid"]=parent.id;args["special_id"]=specialId }
                val root=kg.get(if(parent==null) "comment/music" else "comment/floor",CookieStore.kgPlatformValue(),args).kugouBody()
                kugouPage(root,accountId,offset).let { page ->
                    if (parent == null) page else page.copy(comments=page.comments.map { it.copy(parentId=parent.id) })
                }
            }
            else -> {
                val query=mutableMapOf("song" to songKey(song),"offset" to offset.toString(),"limit" to "20")
                parent?.let { query["parent"]=it.id }
                sitePage(site("GET","comments",query))
            }
        }
    }
    suspend fun send(source: String, song: Song, content: String, parent: SongComment?, page: CommentPage) {
        require(content.trim().isNotEmpty() && content.length<=2000) { tr("评论需为 1–2000 个字符") }
        requireAccount(source)
        when(source) {
            "netease" -> {
                val args=mutableMapOf("id" to song.id.toString(),"type" to "0","t" to if(parent==null) "1" else "2","content" to content.trim())
                parent?.let { args["commentId"]=it.id }
                nc.post("comment",args).checkedNc()
            }
            "kugou" -> {
                require(page.specialId.isNotBlank()) { tr("无法识别酷狗评论资源，请刷新") }
                val args=mutableMapOf("special_id" to page.specialId,"name" to page.resourceName.ifBlank { song.ar+" - "+song.nm },
                    "mixsongid" to song.albumAudioId.toString(),"content" to content.trim())
                parent?.let {
                    args["tid"]=it.parentId.ifBlank { it.id }
                    args["pid"]=if(it.parentId.isBlank()) "0" else it.id
                    args["is_t"]=if(it.parentId.isBlank()) "1" else "0"
                }
                kg.post(if(parent==null) "comment/music/send" else "comment/floor/send",CookieStore.kgPlatformValue(),args).kugouBody().checkedKgMutation()
            }
            else -> site("POST","comments",body=buildJsonObject { put("song",songKey(song));put("content",content.trim());parent?.let { put("parentId",it.id) } })
        }
    }
    suspend fun like(source: String, song: Song, comment: SongComment, page: CommentPage) {
        requireAccount(source)
        when(source) {
            "netease" -> nc.post("comment/like",mapOf("id" to song.id.toString(),"type" to "0","cid" to comment.id,"t" to if(comment.liked) "0" else "1")).checkedNc()
            "kugou" -> throw IOException(tr("酷狗点赞接口尚未验证，暂不开放"))
            else -> site("POST","comments/"+comment.id+"/like",body=buildJsonObject { put("liked",!comment.liked) })
        }
    }
    suspend fun delete(source: String, song: Song, comment: SongComment, page: CommentPage) {
        requireAccount(source);require(comment.owned) { tr("只能删除本人评论") }
        when(source) {
            "netease" -> nc.post("comment",mapOf("id" to song.id.toString(),"type" to "0","commentId" to comment.id,"t" to "0")).checkedNc()
            "kugou" -> throw IOException(tr("酷狗删除接口尚未验证，暂不开放"))
            else -> site("DELETE","comments/"+comment.id)
        }
    }
    private fun requireAccount(source: String) {
        require(when(source) { "netease" -> CookieStore.hasNcUserCookie(); "kugou" -> CookieStore.hasKgToken(); else -> CookieStore.appTokenValue().isNotBlank() }) { tr("请先登录对应平台账号") }
    }
    private fun JsonObject.checkedNc(): JsonObject { if(text("code")!="200") throw IOException(text("message","msg").ifBlank { tr("网易云操作失败，请检查登录和权限") });return this }
    private fun JsonObject.checkedKgMutation(): JsonObject { if(text("status")!="1") throw IOException(text("message","msg").ifBlank { tr("酷狗未确认操作成功") });return this }
    private suspend fun site(method: String, path: String, query: Map<String,String> = emptyMap(), body: JsonObject? = null): JsonObject {
        val url=(ApiFactory.BASE+path).toHttpUrl().newBuilder();query.forEach { (k,v) -> url.addQueryParameter(k,v) }
        val request=Request.Builder().url(url.build()).method(method,if(method=="POST") body.toString().toRequestBody("application/json".toMediaType()) else null).build()
        val response=ApiFactory.client().newCall(request).awaitResponse()
        return response.use {
            val root=runCatching { Json.parseToJsonElement(it.body?.string().orEmpty()).jsonObject }.getOrNull()?:throw IOException(tr("本站评论服务响应异常"))
            if(!it.isSuccessful || root.text("code")!="200") throw IOException(root.text("message").ifBlank { tr("本站评论请求失败") })
            root
        }
    }
    companion object {
        internal fun songKey(song: Song)=if(song.source=="kugou") "kugou:"+song.hash.lowercase() else "netease:"+song.id
        internal fun neteasePage(root: JsonObject, uid: String, floor: Boolean=false): CommentPage {
            val data=if(floor) root.obj("data") else root
            val rows=data.items("comments").map { item ->
                val user=item.obj("user");val quote=item.items("beReplied").firstOrNull()
                SongComment(item.text("commentId"),user.text("userId"),user.text("nickname"),item.text("content"),user.text("avatarUrl"),item.text("timeStr","time"),
                    item.number("likedCount"),item.text("liked")=="true",item.number("replyCount"),uid.isNotEmpty()&&uid==user.text("userId"),
                    quotedUser=quote?.obj("user")?.text("nickname").orEmpty(),quotedContent=quote?.text("content").orEmpty())
            }
            return CommentPage(rows,data.number("total","totalCount"),data.text("more","hasMore")=="true", nextCursor=data.items("comments").lastOrNull()?.text("time").orEmpty())
        }
        internal fun kugouPage(root: JsonObject, uid: String, offset: Int=0): CommentPage {
            val rows=root.items("list").ifEmpty { root.payload().items("list") }
            val comments=rows.map { item -> SongComment(item.text("id","tid"),item.text("user_id","kugouid"),item.text("user_name","username"),item.text("content"),
                item.text("user_pic"),item.text("addtime"),item.obj("like").number("count","likenum"),item.obj("like").text("haslike") in listOf("true","1"),
                item.number("reply_num"),uid.isNotEmpty()&&uid==item.text("user_id","kugouid"),quotedUser=item.text("puser"),quotedContent=item.text("pcontent")) }
            val total=root.number("count","combine_count")
            return CommentPage(comments,total,comments.isNotEmpty() && offset+comments.size<total,
                root.text("childrenid").ifBlank { rows.firstOrNull()?.text("special_child_id").orEmpty() },
                rows.firstOrNull()?.text("special_child_name","song_show_text").orEmpty())
        }
        internal fun sitePage(root: JsonObject)=CommentPage(root.items("comments").map { item -> SongComment(item.text("id"),item.text("userId"),item.text("userName"),
            item.text("content"),time=item.text("createdAt"),likes=item.number("likes"),liked=item.text("liked")=="true",replies=item.number("replies"),
            owned=item.text("owned")=="true",deleted=item.text("deleted")=="true",parentId=item.text("parentId"),
            quotedUser=item.text("quotedUser"),quotedContent=item.text("quotedContent")) },root.number("total"),root.text("more")=="true")
    }
}

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
private suspend fun Call.awaitResponse(): Response = suspendCancellableCoroutine { continuation ->
    continuation.invokeOnCancellation { cancel() }
    enqueue(object: Callback {
        override fun onFailure(call: Call, e: IOException) { if(!continuation.isCancelled) continuation.resumeWithException(e) }
        override fun onResponse(call: Call, response: Response) { continuation.resume(response) { response.close() } }
    })
}
