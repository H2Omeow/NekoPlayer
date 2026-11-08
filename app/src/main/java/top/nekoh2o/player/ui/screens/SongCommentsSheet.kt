package top.nekoh2o.player.ui.screens

import top.nekoh2o.player.i18n.NekoI18n.tr

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.data.net.CookieStore
import top.nekoh2o.player.data.repo.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SongCommentsSheet(song: Song, onDismiss: () -> Unit) {
    var source by remember(song) { mutableStateOf(song.source) }
    val sources=listOf("netease" to tr("网易云"), "kugou" to tr("酷狗"), "site" to tr("本站"))
    ModalBottomSheet(onDismissRequest=onDismiss, sheetState=rememberModalBottomSheetState(skipPartiallyExpanded=true)) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(0.92f).padding(horizontal=16.dp)) {
            Text(tr("{title} · 评论", "title" to song.nm),style=MaterialTheme.typography.titleLarge)
            Text(song.ar,style=MaterialTheme.typography.bodySmall)
            TabRow(selectedTabIndex=sources.indexOfFirst { it.first==source }.coerceAtLeast(0)) {
                sources.forEach { (id,label) -> Tab(selected=source==id,onClick={source=id},text={Text(label)}) }
            }
            key(song.source,song.id,source,CookieStore.kgPlatformValue()) {
                CommentContent(song,source,Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun CommentContent(original: Song, source: String, modifier: Modifier) {
    val repository=remember { CommentsRepository() }
    val scope=rememberCoroutineScope()
    var target by remember { mutableStateOf<Song?>(if(source=="site" || source==original.source) original else null) }
    var matches by remember { mutableStateOf<List<Song>>(emptyList()) }
    var page by remember { mutableStateOf(CommentPage(emptyList(),0,false)) }
    var account by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var draft by remember { mutableStateOf("") }
    var reply by remember { mutableStateOf<SongComment?>(null) }
    var thread by remember { mutableStateOf<SongComment?>(null) }
    var rootPage by remember { mutableStateOf<CommentPage?>(null) }
    var delete by remember { mutableStateOf<SongComment?>(null) }
    var reload by remember { mutableIntStateOf(0) }
    var offset by remember { mutableIntStateOf(0) }
    val selectedPlatform=remember { CookieStore.kgPlatformValue() }

    fun message(e: Exception)=e.message?.take(180) ?: tr("评论请求失败，请稍后重试")
    suspend fun refresh() {
        val track=target?:return
        val next=repository.list(source,track,account,0,thread,rootPage?.specialId?:page.specialId)
        page=if(thread!=null) next.copy(specialId=rootPage?.specialId.orEmpty(),resourceName=rootPage?.resourceName.orEmpty()) else next
        offset=page.comments.size
    }
    fun mutate(action: suspend () -> Unit) {
        if(busy || loading) return
        scope.launch {
            busy=true;error=null
            try {
                if(source=="kugou" && selectedPlatform!=CookieStore.kgPlatformValue()) throw IllegalStateException(tr("酷狗版本已切换，请重新打开评论"))
                action();refresh()
            } catch(e: CancellationException) { throw e }
              catch(e: Exception) { error=message(e) }
            finally { busy=false }
        }
    }
    LaunchedEffect(target,reload,thread?.id) {
        loading=true;error=null
        try {
            if(target==null) matches=repository.matches(original,source)
            else {
                account=try { repository.accountId(source) } catch(e: CancellationException) { throw e } catch(_: Exception) { "" }
                refresh()
            }
        } catch(e: CancellationException) { throw e } catch(e: Exception) { error=message(e) }
        finally { loading=false }
    }
    Column(modifier) {
        if(target!=null && source!=original.source && source!="site") Row(Modifier.fillMaxWidth()) {
            Text(tr("对应歌曲：")+target!!.nm+" · "+target!!.ar,Modifier.weight(1f),style=MaterialTheme.typography.bodySmall)
            TextButton(onClick={target=null;thread=null;rootPage=null},enabled=!busy) { Text(tr("更换")) }
        }
        if(thread!=null) Row {
            TextButton(onClick={thread=null;rootPage=null;reply=null},enabled=!busy) { Text(tr("返回全部评论")) }
            Text(tr("楼层回复"),Modifier.padding(top=12.dp))
        }
        error?.let { Text(it,color=MaterialTheme.colorScheme.error);TextButton(onClick={reload++},enabled=!busy) { Text(tr("重新加载")) } }
        if(loading) LinearProgressIndicator(Modifier.fillMaxWidth())
        if(target==null) {
            Text(tr("请选择在该平台对应的歌曲，避免评论发送到同名歌曲。"),Modifier.padding(vertical=12.dp))
            if(!loading && matches.isEmpty()) Text(tr("未找到对应歌曲，可切换平台或重试。"))
            LazyColumn(Modifier.weight(1f)) { items(matches,key={it.source+":"+it.id}) { song ->
                ListItem(headlineContent={Text(song.nm)},supportingContent={Text(song.ar)},modifier=Modifier.clickable {target=song})
            } }
        } else {
            Text(tr("共 {count} 条", "count" to page.total),style=MaterialTheme.typography.bodySmall,modifier=Modifier.padding(vertical=6.dp))
            LazyColumn(Modifier.weight(1f)) {
                if(!loading && page.comments.isEmpty()) item { Text(tr("暂无评论"),Modifier.padding(16.dp)) }
                items(page.comments,key={it.id}) { comment ->
                    Column(Modifier.fillMaxWidth().padding(vertical=10.dp)) {
                        Row { Text(comment.userName.ifBlank { tr("用户") },Modifier.weight(1f),fontWeight=FontWeight.Bold)
                            Text(displayCommentTime(comment.time),style=MaterialTheme.typography.labelSmall) }
                        if(comment.quotedContent.isNotBlank()) Text(tr("回复 ")+comment.quotedUser+"："+comment.quotedContent,style=MaterialTheme.typography.bodySmall)
                        Text(if(comment.deleted) tr("该评论已删除") else comment.content)
                        Row {
                            TextButton(enabled=source!="kugou" && account.isNotBlank() && !busy && !loading && !comment.deleted,
                                onClick={mutate {repository.like(source,target!!,comment,rootPage?:page)}}) {Text(if(comment.liked) tr("已赞 {count}", "count" to comment.likes) else tr("赞 {count}", "count" to comment.likes))}
                            TextButton(enabled=account.isNotBlank() && !busy && !comment.deleted,onClick={reply=comment}) {Text(tr("回复"))}
                            if(comment.replies>0 && thread==null) TextButton(enabled=!busy,onClick={rootPage=page;thread=comment;reply=null}) {Text(tr("查看回复 {count}", "count" to comment.replies))}
                            if(source!="kugou" && comment.owned && !comment.deleted) TextButton(enabled=!busy,onClick={delete=comment}) {Text(tr("删除"))}
                        }
                        HorizontalDivider()
                    }
                }
                if(page.more) item { TextButton(enabled=!loading && !busy,onClick={scope.launch {
                    loading=true;error=null
                    try {
                        val next=repository.list(source,target!!,account,offset,thread,rootPage?.specialId?:page.specialId,page.nextCursor)
                        offset+=next.comments.size
                        page=next.copy(comments=(page.comments+next.comments).distinctBy {it.id},specialId=page.specialId,resourceName=page.resourceName)
                    } catch(e: CancellationException) {throw e} catch(e: Exception) {error=message(e)} finally {loading=false}
                }}) {Text(tr("加载更多")) } }
            }
            if(source=="kugou") Text(tr("酷狗支持查看、发送和回复；点赞与删除暂未开放。"),style=MaterialTheme.typography.bodySmall)
            if(account.isBlank()) Text(
                if(source=="kugou") tr("登录酷狗账号后可发送和回复评论。")
                else tr("登录{platform}账号后可发送、回复、点赞和删除自己的评论。", "platform" to tr(if(source=="site") "本站" else "网易云")),
                style=MaterialTheme.typography.bodySmall
            )
            reply?.let { Row { Text(tr("回复 {name}", "name" to it.userName),Modifier.weight(1f));TextButton(onClick={reply=null}) {Text(tr("取消回复"))} } }
            Row(Modifier.fillMaxWidth().imePadding().padding(bottom=12.dp)) {
                OutlinedTextField(value=draft,onValueChange={if(it.length<=2000)draft=it},modifier=Modifier.weight(1f),maxLines=4,
                    enabled=account.isNotBlank() && !busy,label={Text(tr("写评论"))})
                TextButton(enabled=account.isNotBlank() && draft.isNotBlank() && !busy && !loading,onClick={mutate {
                    repository.send(source,target!!,draft,reply?:thread,rootPage?:page);draft="";reply=null
                }}) {Text(if(busy) tr("提交中") else tr("发送"))}
            }
        }
    }
    delete?.let { comment -> AlertDialog(onDismissRequest={delete=null},title={Text(tr("删除评论？"))},text={Text(tr("删除后无法恢复，回复处理以对应平台规则为准。"))},
        confirmButton={TextButton(onClick={delete=null;mutate {repository.delete(source,target!!,comment,rootPage?:page)}}) {Text(tr("删除"))}},
        dismissButton={TextButton(onClick={delete=null}) {Text(tr("取消"))}}) }
}

private fun displayCommentTime(raw: String): String = raw.toLongOrNull()?.let { time ->
    java.text.SimpleDateFormat("yyyy-MM-dd HH:mm",java.util.Locale.getDefault()).format(java.util.Date(if(time in 1..9999999999L) time*1000 else time))
} ?: raw
