package top.nekoh2o.player.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.automirrored.outlined.Comment
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.data.net.CookieStore
import top.nekoh2o.player.data.repo.CommentPage
import top.nekoh2o.player.data.repo.CommentsRepository
import top.nekoh2o.player.data.repo.SongComment
import top.nekoh2o.player.i18n.NekoI18n.tr
import top.nekoh2o.player.ui.components.Artwork
import top.nekoh2o.player.ui.components.EmptyState
import top.nekoh2o.player.ui.components.InlineNotice
import top.nekoh2o.player.ui.components.NekoAlertDialog
import top.nekoh2o.player.ui.components.NekoBottomSheet
import top.nekoh2o.player.ui.components.songKey
import top.nekoh2o.player.ui.theme.NekoDefaults
import top.nekoh2o.player.ui.theme.NekoRadius
import top.nekoh2o.player.ui.theme.NekoSpace

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SongCommentsSheet(song: Song, onDismiss: () -> Unit) {
    val sources = listOf("netease" to tr("网易云"), "kugou" to tr("酷狗"), "site" to tr("本站"))
    var source by remember(song) {
        mutableStateOf(if (song.source == "netease" || song.source == "kugou") song.source else "site")
    }
    NekoBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.92f)
                .padding(horizontal = NekoSpace.lg)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(NekoSpace.md)) {
                Artwork(song.pc, size = 44.dp, thumbnail = 120)
                Column(Modifier.weight(1f)) {
                    Text(
                        song.nm,
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        song.ar,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            Spacer(Modifier.height(NekoSpace.sm))
            PrimaryTabRow(
                selectedTabIndex = sources.indexOfFirst { it.first == source }.coerceAtLeast(0),
                containerColor = Color.Transparent
            ) {
                sources.forEach { (id, label) ->
                    Tab(selected = source == id, onClick = { source = id }, text = { Text(label) })
                }
            }
            key(song.source, song.id, source, CookieStore.kgPlatformValue()) {
                CommentContent(song, source, Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun CommentContent(original: Song, source: String, modifier: Modifier) {
    val repository = remember { CommentsRepository() }
    val scope = rememberCoroutineScope()
    var target by remember { mutableStateOf<Song?>(if (source == "site" || source == original.source) original else null) }
    var matches by remember { mutableStateOf<List<Song>>(emptyList()) }
    var page by remember { mutableStateOf(CommentPage(emptyList(), 0, false)) }
    var account by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var draft by remember { mutableStateOf("") }
    var reply by remember { mutableStateOf<SongComment?>(null) }
    var thread by remember { mutableStateOf<SongComment?>(null) }
    var rootPage by remember { mutableStateOf<CommentPage?>(null) }
    var deleteTarget by remember { mutableStateOf<SongComment?>(null) }
    var reload by remember { mutableIntStateOf(0) }
    var offset by remember { mutableIntStateOf(0) }
    val selectedPlatform = remember { CookieStore.kgPlatformValue() }

    fun message(e: Exception) = e.message?.take(180) ?: tr("评论请求失败，请稍后重试")

    suspend fun refresh() {
        val track = target ?: return
        val next = repository.list(source, track, account, 0, thread, rootPage?.specialId ?: page.specialId)
        page = if (thread != null) {
            next.copy(
                specialId = rootPage?.specialId.orEmpty(),
                resourceName = rootPage?.resourceName.orEmpty()
            )
        } else next
        offset = page.comments.size
    }

    fun mutate(action: suspend () -> Unit) {
        if (busy || loading) return
        scope.launch {
            busy = true; error = null
            try {
                if (source == "kugou" && selectedPlatform != CookieStore.kgPlatformValue()) {
                    throw IllegalStateException(tr("酷狗版本已切换，请重新打开评论"))
                }
                action()
                refresh()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = message(e)
            } finally {
                busy = false
            }
        }
    }

    LaunchedEffect(target, reload, thread?.id) {
        loading = true; error = null
        try {
            if (target == null) {
                matches = repository.matches(original, source)
            } else {
                account = try {
                    repository.accountId(source)
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    ""
                }
                refresh()
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = message(e)
        } finally {
            loading = false
        }
    }

    Column(modifier) {
        if (target != null && source != original.source && source != "site") {
            Row(
                Modifier.fillMaxWidth().padding(top = NekoSpace.xs),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    tr("对应歌曲：") + "${target!!.nm} · ${target!!.ar}",
                    Modifier.weight(1f),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                TextButton(onClick = { target = null; thread = null; rootPage = null }, enabled = !busy) {
                    Text(tr("更换"))
                }
            }
        }
        if (thread != null) {
            Row(
                Modifier.fillMaxWidth().padding(vertical = NekoSpace.xs),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = { thread = null; rootPage = null; reply = null }, enabled = !busy) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = tr("返回全部评论"))
                }
                Text(tr("楼层回复"), style = MaterialTheme.typography.titleSmall)
            }
        }
        error?.let {
            Spacer(Modifier.height(NekoSpace.sm))
            InlineNotice(
                message = it,
                error = true,
                action = { TextButton(onClick = { reload++ }, enabled = !busy) { Text(tr("重试")) } }
            )
        }
        if (loading) LinearProgressIndicator(Modifier.fillMaxWidth().padding(top = NekoSpace.xs))

        if (target == null) {
            Text(
                tr("请选择在该平台对应的歌曲，避免评论发送到同名歌曲。"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(vertical = NekoSpace.md)
            )
            if (!loading && matches.isEmpty()) {
                EmptyState(Icons.AutoMirrored.Outlined.Comment, tr("未找到对应歌曲"), description = tr("可切换其他平台或稍后重试。"))
            } else {
                LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(NekoSpace.xs)) {
                    items(matches, key = { songKey(it) }) { song ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(NekoRadius.control))
                                .clickable { target = song }
                                .padding(vertical = NekoSpace.sm, horizontal = NekoSpace.xs),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(NekoSpace.md)
                        ) {
                            Artwork(song.pc, size = 44.dp, thumbnail = 120)
                            Column(Modifier.weight(1f)) {
                                Text(song.nm, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(
                                    song.ar,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }
                    }
                }
            }
        } else {
            Text(
                tr("共 {count} 条", "count" to page.total),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(vertical = NekoSpace.sm)
            )
            LazyColumn(
                Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(NekoSpace.sm),
                contentPadding = PaddingValues(bottom = NekoSpace.md)
            ) {
                if (!loading && page.comments.isEmpty()) {
                    item {
                        EmptyState(
                            Icons.AutoMirrored.Outlined.Comment,
                            tr("暂无评论"),
                            description = tr("来发表第一条评论吧")
                        )
                    }
                }
                items(page.comments, key = { it.id }) { comment ->
                    CommentCard(
                        comment = comment,
                        source = source,
                        canInteract = account.isNotBlank() && !busy && !loading && !comment.deleted,
                        canOpenThread = comment.replies > 0 && thread == null && !busy,
                        onLike = { mutate { repository.like(source, target!!, comment, rootPage ?: page) } },
                        onReply = { reply = comment },
                        onOpenThread = { rootPage = page; thread = comment; reply = null },
                        onDelete = { deleteTarget = comment }
                    )
                }
                if (page.more) {
                    item {
                        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                            TextButton(
                                enabled = !loading && !busy,
                                colors = NekoDefaults.textButtonColors(),
                                onClick = {
                                    scope.launch {
                                        loading = true; error = null
                                        try {
                                            val next = repository.list(
                                                source, target!!, account, offset, thread,
                                                rootPage?.specialId ?: page.specialId, page.nextCursor
                                            )
                                            offset += next.comments.size
                                            page = next.copy(
                                                comments = (page.comments + next.comments).distinctBy { it.id },
                                                specialId = page.specialId,
                                                resourceName = page.resourceName
                                            )
                                        } catch (e: CancellationException) {
                                            throw e
                                        } catch (e: Exception) {
                                            error = message(e)
                                        } finally {
                                            loading = false
                                        }
                                    }
                                }
                            ) { Text(tr("加载更多")) }
                        }
                    }
                }
            }

            if (source == "kugou") {
                Text(
                    tr("酷狗支持查看、发送和回复；点赞与删除暂未开放。"),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = NekoSpace.xs)
                )
            }
            if (account.isBlank()) {
                Text(
                    if (source == "kugou") tr("登录酷狗账号后可发送和回复评论。")
                    else tr("登录{platform}账号后可发送、回复、点赞和删除自己的评论。", "platform" to tr(if (source == "site") "本站" else "网易云")),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = NekoSpace.xs)
                )
            }
            reply?.let { r ->
                Surface(
                    shape = RoundedCornerShape(NekoRadius.control),
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    modifier = Modifier.fillMaxWidth().padding(bottom = NekoSpace.xs)
                ) {
                    Row(
                        Modifier.padding(start = NekoSpace.md, end = NekoSpace.xs),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            tr("回复 {name}", "name" to r.userName.ifBlank { tr("用户") }),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.weight(1f)
                        )
                        IconButton(onClick = { reply = null }, modifier = Modifier.size(32.dp)) {
                            Icon(Icons.Filled.Close, contentDescription = tr("取消回复"), modifier = Modifier.size(16.dp))
                        }
                    }
                }
            }
            Row(
                Modifier
                    .fillMaxWidth()
                    .imePadding()
                    .padding(bottom = NekoSpace.md),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(NekoSpace.sm)
            ) {
                OutlinedTextField(
                    value = draft,
                    onValueChange = { if (it.length <= 2000) draft = it },
                    modifier = Modifier.weight(1f),
                    maxLines = 4,
                    enabled = account.isNotBlank() && !busy,
                    placeholder = { Text(tr("写评论")) },
                    shape = RoundedCornerShape(NekoRadius.card),
                    colors = NekoDefaults.textFieldColors()
                )
                FilledIconButton(
                    enabled = account.isNotBlank() && draft.isNotBlank() && !busy && !loading,
                    onClick = {
                        mutate {
                            repository.send(source, target!!, draft, reply ?: thread, rootPage ?: page)
                            draft = ""
                            reply = null
                        }
                    }
                ) {
                    Icon(Icons.AutoMirrored.Filled.Send, contentDescription = tr("发送"))
                }
            }
        }
    }

    deleteTarget?.let { comment ->
        NekoAlertDialog(
            onDismissRequest = { deleteTarget = null },
            title = { Text(tr("删除评论？")) },
            text = { Text(tr("删除后无法恢复，回复处理以对应平台规则为准。")) },
            confirmButton = {
                TextButton(
                    onClick = {
                        deleteTarget = null
                        mutate { repository.delete(source, target!!, comment, rootPage ?: page) }
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)
                ) { Text(tr("删除")) }
            },
            dismissButton = {
                TextButton(onClick = { deleteTarget = null }, colors = NekoDefaults.textButtonColors()) {
                    Text(tr("取消"))
                }
            }
        )
    }
}

@Composable
private fun CommentCard(
    comment: SongComment,
    source: String,
    canInteract: Boolean,
    canOpenThread: Boolean,
    onLike: () -> Unit,
    onReply: () -> Unit,
    onOpenThread: () -> Unit,
    onDelete: () -> Unit
) {
    val colors = MaterialTheme.colorScheme
    Surface(
        shape = RoundedCornerShape(NekoRadius.card),
        color = colors.surfaceContainerLow,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            Modifier.padding(NekoSpace.md),
            horizontalArrangement = Arrangement.spacedBy(NekoSpace.md),
            verticalAlignment = Alignment.Top
        ) {
            Artwork(
                url = comment.avatar.takeIf { it.isNotBlank() },
                size = 36.dp,
                shape = CircleShape,
                thumbnail = 100,
                placeholder = Icons.Filled.Person
            )
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(NekoSpace.xs)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        comment.userName.ifBlank { tr("用户") },
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f)
                    )
                    Text(
                        displayCommentTime(comment.time),
                        style = MaterialTheme.typography.labelSmall,
                        color = colors.onSurfaceVariant
                    )
                }
                if (comment.quotedContent.isNotBlank()) {
                    Surface(
                        shape = RoundedCornerShape(NekoRadius.cover),
                        color = colors.surfaceContainerHigh,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            tr("回复 ") + "${comment.quotedUser}：${comment.quotedContent}",
                            style = MaterialTheme.typography.bodySmall,
                            color = colors.onSurfaceVariant,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.padding(horizontal = NekoSpace.sm, vertical = 6.dp)
                        )
                    }
                }
                Text(
                    if (comment.deleted) tr("该评论已删除") else comment.content,
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (comment.deleted) colors.onSurfaceVariant else colors.onSurface
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(NekoSpace.md),
                    modifier = Modifier.padding(top = 2.dp)
                ) {
                    if (source != "kugou") {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .clip(RoundedCornerShape(6.dp))
                                .clickable(enabled = canInteract, onClick = onLike)
                                .padding(horizontal = 4.dp, vertical = 2.dp)
                        ) {
                            Icon(
                                if (comment.liked) Icons.Filled.ThumbUp else Icons.Outlined.ThumbUp,
                                contentDescription = tr("点赞"),
                                tint = if (comment.liked) colors.primary else colors.onSurfaceVariant,
                                modifier = Modifier.size(15.dp)
                            )
                            Spacer(Modifier.width(4.dp))
                            Text(
                                comment.likes.toString(),
                                style = MaterialTheme.typography.labelSmall,
                                color = if (comment.liked) colors.primary else colors.onSurfaceVariant
                            )
                        }
                    }
                    if (canInteract) {
                        Text(
                            tr("回复"),
                            style = MaterialTheme.typography.labelMedium,
                            color = colors.onSurfaceVariant,
                            modifier = Modifier
                                .clip(RoundedCornerShape(6.dp))
                                .clickable(onClick = onReply)
                                .padding(horizontal = 4.dp, vertical = 2.dp)
                        )
                    }
                    if (canOpenThread) {
                        Text(
                            tr("查看回复 {count}", "count" to comment.replies),
                            style = MaterialTheme.typography.labelMedium,
                            color = colors.primary,
                            modifier = Modifier
                                .clip(RoundedCornerShape(6.dp))
                                .clickable(onClick = onOpenThread)
                                .padding(horizontal = 4.dp, vertical = 2.dp)
                        )
                    }
                    Spacer(Modifier.weight(1f))
                    if (source != "kugou" && comment.owned && !comment.deleted) {
                        Icon(
                            Icons.Filled.Delete,
                            contentDescription = tr("删除"),
                            tint = colors.onSurfaceVariant,
                            modifier = Modifier
                                .size(18.dp)
                                .clip(RoundedCornerShape(4.dp))
                                .clickable(enabled = canInteract, onClick = onDelete)
                        )
                    }
                }
            }
        }
    }
}

private fun displayCommentTime(raw: String): String = raw.toLongOrNull()?.let { time ->
    java.text.SimpleDateFormat("yyyy-MM-dd HH:mm", java.util.Locale.getDefault())
        .format(java.util.Date(if (time in 1..9999999999L) time * 1000 else time))
} ?: raw
