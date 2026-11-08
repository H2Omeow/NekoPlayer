package top.nekoh2o.player.ui.social

import top.nekoh2o.player.i18n.NekoI18n.tr

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.data.social.ShareOptions
import top.nekoh2o.player.data.social.SocialConversation
import top.nekoh2o.player.data.social.SocialMessage
import top.nekoh2o.player.data.social.SocialProfile
import top.nekoh2o.player.data.social.SocialProgress
import top.nekoh2o.player.data.social.SocialShare
import top.nekoh2o.player.data.social.SocialSong
import top.nekoh2o.player.data.social.platformLabel
import top.nekoh2o.player.ui.PlayerViewModel
import top.nekoh2o.player.ui.components.Artwork
import top.nekoh2o.player.ui.components.EmptyState
import top.nekoh2o.player.ui.theme.NekoRadius
import top.nekoh2o.player.ui.theme.NekoSpace
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private val SOCIAL_BASE = "https://player.nekoh2o.top"

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SocialScreen(vm: PlayerViewModel, onLogin: () -> Unit) {
    val state by vm.socialVm.state.collectAsState()
    val player by vm.ui.collectAsState()
    var tab by rememberSaveable { mutableIntStateOf(0) }

    LaunchedEffect(state.started, player.loggedIn) {
        if (player.loggedIn && !state.started) vm.socialVm.start()
    }
    LaunchedEffect(tab) {
        if (tab == 1 && state.feed.isEmpty()) vm.socialVm.loadFeed()
    }

    if (!player.loggedIn) {
        LoginPrompt(onLogin)
        return
    }

    val active = state.active
    if (active != null) {
        ChatScreen(vm, active, state.messages, state.messagesLoading)
    } else {
        Column(Modifier.fillMaxSize()) {
            PrimaryTabRow(selectedTabIndex = tab) {
                Tab(selected = tab == 0, onClick = { tab = 0 }, text = {
                    Text(if (state.unread > 0) tr("消息 {count}", "count" to state.unread) else tr("消息"))
                })
                Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text(tr("关注动态")) })
                Tab(selected = tab == 2, onClick = { tab = 2 }, text = { Text(tr("发现")) })
            }
            when (tab) {
                0 -> MessagesTab(vm, state)
                1 -> FeedTab(vm, state, player.current)
                else -> DiscoverTab(vm, state)
            }
        }
    }

    if (state.profile != null || state.profileLoading) {
        ProfileSheet(vm, state)
    }
}

@Composable
private fun LoginPrompt(onLogin: () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(NekoSpace.xl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            Icons.Outlined.ChatBubbleOutline,
            contentDescription = null,
            modifier = Modifier.size(54.dp),
            tint = MaterialTheme.colorScheme.primary
        )
        Spacer(Modifier.height(NekoSpace.lg))
        Text(tr("登录后使用社区"), style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(NekoSpace.sm))
        Text(
            tr("关注喜欢的人、发送私信，把正在听的歌分享给朋友。"),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(NekoSpace.xl))
        Button(onClick = onLogin) { Text(tr("登录 NekoPlayer 账号")) }
    }
}

@Composable
private fun MessagesTab(vm: PlayerViewModel, state: SocialUiState) {
    if (state.loadingConversations && state.conversations.isEmpty()) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        return
    }
    if (state.conversations.isEmpty()) {
        EmptyState(
            Icons.Outlined.ChatBubbleOutline,
            tr("还没有私信"),
            description = tr("在「发现」里找到朋友，开始聊天吧。")
        )
        return
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = NekoSpace.xl)) {
        items(state.conversations, key = { it.id }) { conversation ->
            ConversationRow(conversation) {
                vm.socialVm.openChat(conversation.peerId, conversation)
            }
        }
    }
}

@Composable
private fun ConversationRow(conversation: SocialConversation, onClick: () -> Unit) {
    val peer = conversation.peer
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick)
            .padding(horizontal = NekoSpace.lg, vertical = NekoSpace.sm),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Avatar(peer, 48.dp)
        Spacer(Modifier.width(NekoSpace.md))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    peer?.displayName ?: tr("用户"),
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                Text(
                    shortTime(conversation.updatedAt),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Spacer(Modifier.height(3.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    preview(conversation.lastMessage),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                if (conversation.unread > 0) {
                    Spacer(Modifier.width(NekoSpace.sm))
                    Badge { Text(if (conversation.unread > 99) "99+" else conversation.unread.toString()) }
                }
            }
        }
    }
}

@Composable
private fun ChatScreen(
    vm: PlayerViewModel,
    conversation: SocialConversation,
    messages: List<SocialMessage>,
    loading: Boolean
) {
    var text by rememberSaveable(conversation.id) { mutableStateOf("") }
    val player by vm.ui.collectAsState()
    val listState = rememberLazyListState()

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) listState.animateScrollToItem(messages.lastIndex)
    }

    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = NekoSpace.sm, vertical = NekoSpace.xs),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = { vm.socialVm.closeChat() }) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = tr("返回会话列表"))
            }
            Row(
                Modifier.weight(1f).clickable { conversation.peer?.id?.let(vm.socialVm::loadProfile) },
                verticalAlignment = Alignment.CenterVertically
            ) {
                Avatar(conversation.peer, 38.dp)
                Spacer(Modifier.width(NekoSpace.sm))
                Text(
                    conversation.peer?.displayName ?: tr("用户"),
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
        HorizontalDivider()
        if (loading && messages.isEmpty()) {
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            LazyColumn(
                Modifier.weight(1f).fillMaxWidth(),
                state = listState,
                contentPadding = PaddingValues(NekoSpace.md),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(messages, key = { it.id }) { message ->
                    MessageBubble(vm, message)
                }
            }
        }
        Row(
            Modifier.fillMaxWidth().padding(horizontal = NekoSpace.sm, vertical = NekoSpace.sm),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = { vm.socialVm.openShareComposer(player.current) }) {
                Icon(Icons.Filled.MusicNote, contentDescription = tr("分享当前歌曲"))
            }
            OutlinedTextField(
                value = text,
                onValueChange = { text = it.take(2000) },
                modifier = Modifier.weight(1f),
                placeholder = { Text(tr("输入消息…")) },
                maxLines = 4,
                shape = RoundedCornerShape(NekoRadius.card)
            )
            Spacer(Modifier.width(NekoSpace.xs))
            FilledIconButton(onClick = {
                val body = text.trim()
                if (body.isNotEmpty()) {
                    text = ""
                    vm.socialVm.sendText(body)
                }
            }) {
                Icon(Icons.AutoMirrored.Filled.Send, contentDescription = tr("发送"))
            }
        }
    }
}

@Composable
private fun MessageBubble(vm: PlayerViewModel, message: SocialMessage) {
    val context = LocalContext.current
    if (message.deleted) {
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Text(
                if (message.owned) tr("你撤回了一条消息") else tr("对方撤回了一条消息"),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        return
    }
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = if (message.owned) Arrangement.End else Arrangement.Start
    ) {
        Column(
            Modifier.widthIn(max = 300.dp).clip(RoundedCornerShape(14.dp))
                .background(
                    if (message.owned) MaterialTheme.colorScheme.primary.copy(alpha = 0.9f)
                    else MaterialTheme.colorScheme.surfaceContainerHigh
                )
                .padding(horizontal = 12.dp, vertical = 9.dp)
        ) {
            if (message.kind == "song" && message.song != null) {
                val song = message.song
                Row(verticalAlignment = Alignment.CenterVertically) {
                    AsyncImage(
                        model = song.pc,
                        contentDescription = null,
                        modifier = Modifier.size(52.dp).clip(RoundedCornerShape(8.dp))
                    )
                    Spacer(Modifier.width(10.dp))
                    Column {
                        Text(
                            song.nm,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            song.ar,
                            style = MaterialTheme.typography.labelSmall,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Row {
                            TextButton(onClick = { vm.playSharedSong(song.toSong(), 0) }) { Text(tr("播放")) }
                            if (!message.shareToken.isNullOrBlank()) {
                                TextButton(onClick = {
                                    context.startActivity(
                                        Intent(
                                            Intent.ACTION_VIEW,
                                            Uri.parse("$SOCIAL_BASE/s/${message.shareToken}")
                                        )
                                    )
                                }) { Text(tr("查看")) }
                            }
                        }
                    }
                }
                if (message.text.isNotBlank()) {
                    Spacer(Modifier.height(4.dp))
                    Text(message.text, style = MaterialTheme.typography.bodyMedium)
                }
            } else {
                Text(message.text.ifBlank { " " }, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = if (message.owned) Arrangement.End else Arrangement.Start
    ) {
        Text(
            shortTime(message.createdAt),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        if (message.owned) {
            Spacer(Modifier.width(NekoSpace.sm))
            Text(
                tr("撤回"),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.clickable { vm.socialVm.deleteMessage(message.id) }
            )
        }
    }
}

@Composable
private fun FeedTab(vm: PlayerViewModel, state: SocialUiState, current: Song?) {
    if (state.feedLoading && state.feed.isEmpty()) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        return
    }
    if (state.feed.isEmpty()) {
        EmptyState(
            Icons.Filled.PersonAdd,
            tr("还没有关注动态"),
            description = tr("去「发现」关注喜欢的人，这里会出现他们分享的歌曲。")
        )
        return
    }
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(NekoSpace.md),
        verticalArrangement = Arrangement.spacedBy(NekoSpace.md)
    ) {
        items(state.feed, key = { it.token }) { share ->
            FeedCard(vm, share)
        }
    }
}

@Composable
private fun FeedCard(vm: PlayerViewModel, share: SocialShare) {
    val context = LocalContext.current
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp)) {
            Row(
                Modifier.clickable { share.sharer?.id?.let(vm.socialVm::loadProfile) },
                verticalAlignment = Alignment.CenterVertically
            ) {
                Avatar(share.sharer, 32.dp)
                Spacer(Modifier.width(8.dp))
                Column {
                    Text(share.sharer?.displayName ?: tr("用户"), style = MaterialTheme.typography.labelLarge)
                    Text(
                        "${shortTime(share.createdAt)} · ${tr(share.platform)}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Spacer(Modifier.height(10.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                AsyncImage(
                    model = share.song.pc,
                    contentDescription = null,
                    modifier = Modifier.size(60.dp).clip(RoundedCornerShape(9.dp))
                )
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        share.song.nm.ifBlank { tr("未知歌曲") },
                        style = MaterialTheme.typography.titleSmall,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        share.song.ar.ifBlank { tr("未知歌手") },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            if (share.message.isNotBlank()) {
                Spacer(Modifier.height(8.dp))
                Text(share.message, style = MaterialTheme.typography.bodySmall)
            }
            if (share.lyricSnippet.isNotBlank()) {
                Spacer(Modifier.height(8.dp))
                Text(
                    share.lyricSnippet,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Row(Modifier.padding(top = 4.dp)) {
                TextButton(onClick = {
                    vm.playSharedSong(share.song.toSong(), share.progress?.positionMs ?: 0)
                }) { Text(tr("播放")) }
                TextButton(onClick = {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("$SOCIAL_BASE/s/${share.token}")))
                }) { Text(tr("查看分享")) }
            }
        }
    }
}

@Composable
private fun DiscoverTab(vm: PlayerViewModel, state: SocialUiState) {
    var query by rememberSaveable { mutableStateOf("") }
    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().padding(NekoSpace.md),
            verticalAlignment = Alignment.CenterVertically
        ) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it.take(64) },
                modifier = Modifier.weight(1f),
                placeholder = { Text(tr("搜索用户名或昵称")) },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                singleLine = true,
                shape = RoundedCornerShape(NekoRadius.card)
            )
            Spacer(Modifier.width(NekoSpace.sm))
            Button(onClick = { vm.socialVm.search(query) }, enabled = !state.searching) {
                Text(tr("搜索"))
            }
        }
        if (state.searching) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (state.searchResults.isEmpty()) {
            EmptyState(
                Icons.Filled.Search,
                tr("发现用户"),
                description = tr("输入至少 2 个字符，找到朋友后可以关注或私信。")
            )
        } else {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = NekoSpace.xl)) {
                items(state.searchResults, key = { it.id }) { profile ->
                    Row(
                        Modifier.fillMaxWidth().clickable { vm.socialVm.loadProfile(profile.id) }
                            .padding(horizontal = NekoSpace.lg, vertical = NekoSpace.sm),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Avatar(profile, 44.dp)
                        Spacer(Modifier.width(NekoSpace.md))
                        Column(Modifier.weight(1f)) {
                            Text(profile.displayName, style = MaterialTheme.typography.titleSmall)
                            Text(
                                profile.bio.ifBlank { "@${profile.username}" },
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                        if (profile.isSelf) {
                            Text(tr("这是你"), style = MaterialTheme.typography.labelSmall)
                        } else {
                            OutlinedButton(
                                onClick = { vm.socialVm.toggleFollow(profile) },
                                enabled = !profile.isFollowing
                            ) { Text(if (profile.isFollowing) tr("已关注") else tr("关注")) }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProfileSheet(vm: PlayerViewModel, state: SocialUiState) {
    var blockConfirm by remember { mutableStateOf(false) }
    ModalBottomSheet(onDismissRequest = { vm.socialVm.closeProfile() }) {
        val profile = state.profile
        if (state.profileLoading && profile == null) {
            Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
            return@ModalBottomSheet
        }
        if (profile == null) return@ModalBottomSheet
        Column(
            Modifier.fillMaxWidth().padding(horizontal = NekoSpace.xl).padding(bottom = NekoSpace.xl),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Avatar(profile, 76.dp)
            Spacer(Modifier.height(NekoSpace.md))
            Text(profile.displayName, style = MaterialTheme.typography.headlineSmall)
            Text(
                "@${profile.username}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            if (profile.bio.isNotBlank()) {
                Spacer(Modifier.height(NekoSpace.sm))
                Text(profile.bio, style = MaterialTheme.typography.bodyMedium)
            }
            Spacer(Modifier.height(NekoSpace.md))
            Row(horizontalArrangement = Arrangement.spacedBy(NekoSpace.xl)) {
                Text(tr("{count} 粉丝", "count" to profile.followers), style = MaterialTheme.typography.labelLarge)
                Text(tr("{count} 关注", "count" to profile.following), style = MaterialTheme.typography.labelLarge)
            }
            Spacer(Modifier.height(NekoSpace.lg))
            if (profile.isSelf) {
                Text(tr("私信接收范围"), style = MaterialTheme.typography.titleSmall)
                Row(horizontalArrangement = Arrangement.spacedBy(NekoSpace.sm)) {
                    FilterChip(
                        selected = state.dmPolicy == "everyone",
                        onClick = { vm.socialVm.savePreferences("everyone") },
                        label = { Text(tr("所有人")) }
                    )
                    FilterChip(
                        selected = state.dmPolicy == "following",
                        onClick = { vm.socialVm.savePreferences("following") },
                        label = { Text(tr("我关注的人")) }
                    )
                }
                LaunchedEffect(Unit) { vm.socialVm.loadPreferences() }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(NekoSpace.sm)) {
                    Button(onClick = { vm.socialVm.toggleFollow(profile) }) {
                        Text(if (profile.isFollowing) tr("已关注") else tr("关注"))
                    }
                    OutlinedButton(onClick = {
                        vm.socialVm.closeProfile()
                        vm.socialVm.openChat(profile.id)
                    }) { Text(tr("私信")) }
                    OutlinedButton(onClick = { blockConfirm = true }) {
                        Text(if (profile.blocked) tr("取消拉黑") else tr("拉黑"))
                    }
                }
            }
        }
    }
    if (blockConfirm) {
        val profile = state.profile ?: return
        AlertDialog(
            onDismissRequest = { blockConfirm = false },
            title = { Text(if (profile.blocked) tr("取消拉黑？") else tr("拉黑该用户？")) },
            text = { Text(if (profile.blocked) tr("取消后可以重新关注和私信。") else tr("拉黑后双方无法私信或关注。")) },
            confirmButton = {
                TextButton(onClick = {
                    blockConfirm = false
                    vm.socialVm.toggleBlock(profile)
                }) { Text(tr("确定")) }
            },
            dismissButton = { TextButton(onClick = { blockConfirm = false }) { Text(tr("取消")) } }
        )
    }
}

// ==================== 分享弹窗 ====================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShareSongSheet(vm: PlayerViewModel) {
    val state by vm.socialVm.state.collectAsState()
    val player by vm.ui.collectAsState()
    val song = state.shareComposer ?: return
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    var message by rememberSaveable(song.id, song.source) { mutableStateOf("") }
    var showSharer by rememberSaveable(song.id, song.source) { mutableStateOf(true) }
    var cover by rememberSaveable(song.id, song.source) { mutableStateOf(true) }
    var album by rememberSaveable(song.id, song.source) { mutableStateOf(false) }
    var lyric by rememberSaveable(song.id, song.source) { mutableStateOf(false) }
    var progress by rememberSaveable(song.id, song.source) { mutableStateOf(false) }
    val isCurrent = player.current?.let { it.id == song.id && it.source == song.source } == true
    val currentLyric = if (isCurrent && player.lyricIndex in player.lyrics.indices) {
        player.lyrics[player.lyricIndex].text
    } else ""

    ModalBottomSheet(onDismissRequest = { vm.socialVm.closeShareComposer() }) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = NekoSpace.xl).padding(bottom = NekoSpace.xl)
        ) {
            Text(tr("分享歌曲"), style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.height(NekoSpace.md))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Artwork(song.pc, size = 54.dp)
                Spacer(Modifier.width(NekoSpace.md))
                Column {
                    Text(song.nm, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(
                        "${song.ar} · ${platformLabel(song)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Spacer(Modifier.height(NekoSpace.md))
            OutlinedTextField(
                value = message,
                onValueChange = { message = it.take(200) },
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text(tr("写一句留言（可选）")) },
                maxLines = 3
            )
            Spacer(Modifier.height(NekoSpace.sm))
            SwitchRow(tr("显示分享者身份"), showSharer) { showSharer = it }
            SwitchRow(tr("包含封面"), cover) { cover = it }
            SwitchRow(tr("包含专辑名"), album) { album = it }
            if (isCurrent && currentLyric.isNotBlank()) {
                SwitchRow(tr("包含当前歌词片段"), lyric) { lyric = it }
            }
            if (isCurrent) {
                SwitchRow(tr("包含播放进度"), progress) { progress = it }
            }
            Spacer(Modifier.height(NekoSpace.md))
            val result = state.shareResult
            if (result != null) {
                Text(
                    tr("分享链接已生成"),
                    color = MaterialTheme.colorScheme.primary,
                    style = MaterialTheme.typography.titleSmall
                )
                Spacer(Modifier.height(NekoSpace.sm))
                OutlinedTextField(
                    value = result.url,
                    onValueChange = {},
                    readOnly = true,
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
                Row(Modifier.padding(top = NekoSpace.sm), horizontalArrangement = Arrangement.spacedBy(NekoSpace.sm)) {
                    OutlinedButton(onClick = {
                        clipboard.setText(AnnotatedString(result.url))
                        android.widget.Toast.makeText(context, tr("已复制链接"), android.widget.Toast.LENGTH_SHORT).show()
                    }) { Text(tr("复制")) }
                    OutlinedButton(onClick = {
                        val share = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, "${result.song.nm} - ${result.song.ar}\n${result.url}")
                        }
                        context.startActivity(Intent.createChooser(share, tr("分享链接")))
                    }) { Text(tr("系统分享")) }
                    if (state.active != null) {
                        OutlinedButton(onClick = {
                            vm.socialVm.sendSong(song)
                            vm.socialVm.closeShareComposer()
                        }) { Text(tr("发到当前会话")) }
                    }
                }
            } else {
                Button(
                    onClick = {
                        vm.socialVm.createShare(
                            song = song,
                            messageText = message,
                            options = ShareOptions(
                                showSharer = showSharer,
                                cover = cover,
                                album = album,
                                lyric = lyric && isCurrent,
                                progress = progress && isCurrent
                            ),
                            lyric = if (isCurrent) currentLyric else "",
                            progress = if (isCurrent && player.durationMs > 0) {
                                SocialProgress(player.positionMs, player.durationMs)
                            } else null
                        )
                    },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !state.shareBusy
                ) {
                    if (state.shareBusy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    else Text(tr("生成分享链接"))
                }
                state.shareError?.let {
                    Spacer(Modifier.height(NekoSpace.sm))
                    Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}

@Composable
private fun SwitchRow(title: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable { onCheckedChange(!checked) }.padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

// ==================== 通用小组件 ====================

@Composable
private fun Avatar(profile: SocialProfile?, size: androidx.compose.ui.unit.Dp) {
    if (profile?.avatar.isNullOrBlank()) {
        Box(
            Modifier.size(size).clip(CircleShape)
                .background(MaterialTheme.colorScheme.surfaceContainerHighest),
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.Filled.PersonAdd, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    } else {
        AsyncImage(
            model = profile?.avatar,
            contentDescription = null,
            modifier = Modifier.size(size).clip(CircleShape)
        )
    }
}

private fun preview(message: SocialMessage?): String = when {
    message == null -> tr("开始聊天")
    message.deleted -> tr("[消息已撤回]")
    message.kind == "song" -> tr("[歌曲] {title}", "title" to (message.song?.nm ?: tr("分享")))
    message.text.isNotBlank() -> message.text
    else -> tr("[消息]")
}

private fun shortTime(timestamp: Long): String {
    if (timestamp <= 0) return ""
    val date = Date(timestamp)
    val now = Date()
    val sameDay = SimpleDateFormat("yyyyMMdd", Locale.getDefault()).format(date) ==
        SimpleDateFormat("yyyyMMdd", Locale.getDefault()).format(now)
    return SimpleDateFormat(if (sameDay) "HH:mm" else "MM/dd HH:mm", Locale.getDefault()).format(date)
}
