package top.nekoh2o.player.ui.social

import top.nekoh2o.player.i18n.NekoI18n.tr

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.data.social.SendMessageRequest
import top.nekoh2o.player.data.social.ShareOptions
import top.nekoh2o.player.data.social.ShareRequest
import top.nekoh2o.player.data.social.SocialConversation
import top.nekoh2o.player.data.social.SocialMessage
import top.nekoh2o.player.data.social.SocialMessageEvent
import top.nekoh2o.player.data.social.SocialProfile
import top.nekoh2o.player.data.social.SocialProgress
import top.nekoh2o.player.data.social.SocialRepository
import top.nekoh2o.player.data.social.SocialShare
import top.nekoh2o.player.data.social.SocialSong
import top.nekoh2o.player.data.social.SocialSseConnection
import top.nekoh2o.player.data.social.platformLabel
import java.util.UUID

data class SocialUiState(
    val started: Boolean = false,
    val loadingConversations: Boolean = false,
    val conversations: List<SocialConversation> = emptyList(),
    val unread: Int = 0,
    val feed: List<SocialShare> = emptyList(),
    val feedLoading: Boolean = false,
    val searchResults: List<SocialProfile> = emptyList(),
    val searching: Boolean = false,
    val active: SocialConversation? = null,
    val messages: List<SocialMessage> = emptyList(),
    val messagesLoading: Boolean = false,
    val profile: SocialProfile? = null,
    val profileLoading: Boolean = false,
    val dmPolicy: String = "everyone",
    val shareComposer: Song? = null,
    val shareBusy: Boolean = false,
    val shareResult: SocialShare? = null,
    val shareError: String? = null,
    val sseConnected: Boolean = false,
    val toast: String? = null
)

class SocialViewModel(
    app: Application,
    private val onPlayShared: (Song, Long) -> Unit
) : AndroidViewModel(app) {

    private val repo = SocialRepository()
    private val json = Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true }
    private val _state = kotlinx.coroutines.flow.MutableStateFlow(SocialUiState())
    val state: kotlinx.coroutines.flow.StateFlow<SocialUiState> = _state

    private var pollJob: Job? = null
    private var sseJob: Job? = null
    @Volatile private var sseConnection: SocialSseConnection? = null
    @Volatile private var running = false

    fun start() {
        if (running) return
        running = true
        _state.value = _state.value.copy(started = true)
        refreshConversations()
        startPolling()
        connectSse()
    }

    fun stop() {
        running = false
        pollJob?.cancel()
        pollJob = null
        sseJob?.cancel()
        sseJob = null
        sseConnection?.close()
        sseConnection = null
        _state.value = SocialUiState()
    }

    fun clearToast() {
        _state.value = _state.value.copy(toast = null)
    }

    private fun message(text: String) {
        _state.value = _state.value.copy(toast = text)
    }

    // ==================== 会话 ====================
    fun refreshConversations(silent: Boolean = false) {
        viewModelScope.launch {
            if (!silent) _state.value = _state.value.copy(loadingConversations = true)
            runCatching { repo.conversations() }
                .onSuccess { list ->
                    val activeId = _state.value.active?.id
                    _state.value = _state.value.copy(
                        conversations = list,
                        unread = list.sumOf { it.unread },
                        loadingConversations = false,
                        active = list.firstOrNull { it.id == activeId } ?: _state.value.active
                    )
                }
                .onFailure {
                    _state.value = _state.value.copy(loadingConversations = false)
                    if (!silent) message(it.message ?: tr("会话加载失败"))
                }
        }
    }

    fun openChat(peerId: String, conversation: SocialConversation? = null) {
        if (peerId.isBlank() && conversation == null) return
        viewModelScope.launch {
            _state.value = _state.value.copy(
                active = conversation ?: _state.value.conversations.firstOrNull { it.peerId == peerId },
                messages = emptyList(),
                messagesLoading = true
            )
            try {
                val conv = conversation
                    ?: _state.value.conversations.firstOrNull { it.peerId == peerId }
                    ?: repo.conversationWith(peerId)
                    ?: repo.createConversation(peerId)
                _state.value = _state.value.copy(active = conv)
                loadMessages(conv.id, replace = true)
                refreshConversations(silent = true)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                message(e.message ?: tr("无法打开会话"))
                _state.value = _state.value.copy(messagesLoading = false)
            }
        }
    }

    fun closeChat() {
        _state.value = _state.value.copy(active = null, messages = emptyList(), messagesLoading = false)
    }

    fun loadActiveMessages(replace: Boolean = false) {
        val active = _state.value.active ?: return
        viewModelScope.launch { loadMessages(active.id, replace) }
    }

    private suspend fun loadMessages(conversationId: String, replace: Boolean) {
        try {
            val after = if (replace) null else _state.value.messages.maxOfOrNull { it.seq }?.takeIf { it > 0 }
            val resp = repo.messages(conversationId, after)
            if (_state.value.active?.id != conversationId) return
            val merged = if (replace) {
                resp.messages
            } else {
                val known = _state.value.messages.associateBy { it.id }.toMutableMap()
                resp.messages.forEach { known[it.id] = it }
                known.values.sortedBy { it.seq }
            }
            val conversation = resp.conversation ?: _state.value.active
            _state.value = _state.value.copy(
                active = conversation,
                messages = merged,
                messagesLoading = false
            )
            if (merged.isNotEmpty()) {
                runCatching { repo.markRead(conversationId, merged.maxOf { it.seq }) }
                    .onSuccess { read ->
                        _state.value = _state.value.copy(
                            unread = (_state.value.unread - (activeUnreadBefore(conversationId) - read.unread))
                                .coerceAtLeast(0)
                        )
                        refreshConversations(silent = true)
                    }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _state.value = _state.value.copy(messagesLoading = false)
            message(e.message ?: tr("消息加载失败"))
        }
    }

    private fun activeUnreadBefore(conversationId: String): Int =
        _state.value.conversations.firstOrNull { it.id == conversationId }?.unread ?: 0

    fun sendText(text: String) {
        val active = _state.value.active ?: return
        val body = text.trim()
        if (body.isEmpty()) return
        send(SendMessageRequest(
            to = active.peerId,
            kind = "text",
            body = body,
            clientId = UUID.randomUUID().toString()
        ))
    }

    fun sendSong(song: Song) {
        val active = _state.value.active ?: run {
            message(tr("请先打开一个会话"))
            return
        }
        send(SendMessageRequest(
            to = active.peerId,
            kind = "song",
            song = SocialSong.from(song),
            platform = platformLabel(song),
            clientId = UUID.randomUUID().toString()
        ))
    }

    private fun send(request: SendMessageRequest) {
        viewModelScope.launch {
            runCatching { repo.sendMessage(request) }
                .onSuccess { resp ->
                    resp.message?.let { appendMessage(it) }
                    refreshConversations(silent = true)
                }
                .onFailure { message(it.message ?: tr("发送失败")) }
        }
    }

    fun deleteMessage(id: String) {
        viewModelScope.launch {
            runCatching { repo.deleteMessage(id) }
                .onSuccess { resp ->
                    resp.message?.let { updated ->
                        _state.value = _state.value.copy(
                            messages = _state.value.messages.map { if (it.id == id) updated else it }
                        )
                    }
                }
                .onFailure { message(it.message ?: tr("撤回失败")) }
        }
    }

    private fun appendMessage(message: SocialMessage) {
        if (_state.value.active?.id != message.conversationId) return
        if (_state.value.messages.any { it.id == message.id }) return
        _state.value = _state.value.copy(messages = (_state.value.messages + message).sortedBy { it.seq })
    }

    // ==================== 关注 / 资料 ====================
    fun loadFeed() {
        viewModelScope.launch {
            _state.value = _state.value.copy(feedLoading = true)
            runCatching { repo.feed() }
                .onSuccess { _state.value = _state.value.copy(feed = it, feedLoading = false) }
                .onFailure {
                    _state.value = _state.value.copy(feedLoading = false)
                    message(it.message ?: tr("动态加载失败"))
                }
        }
    }

    fun search(query: String) {
        val clean = query.trim()
        if (clean.length < 2) {
            message(tr("至少输入 2 个字符"))
            return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(searching = true)
            runCatching { repo.searchUsers(clean) }
                .onSuccess { _state.value = _state.value.copy(searchResults = it, searching = false) }
                .onFailure {
                    _state.value = _state.value.copy(searching = false)
                    message(it.message ?: tr("搜索失败"))
                }
        }
    }

    fun loadProfile(userId: String) {
        if (userId.isBlank()) return
        viewModelScope.launch {
            _state.value = _state.value.copy(profileLoading = true)
            runCatching { repo.profile(userId) }
                .onSuccess { _state.value = _state.value.copy(profile = it, profileLoading = false) }
                .onFailure {
                    _state.value = _state.value.copy(profileLoading = false)
                    message(it.message ?: tr("资料加载失败"))
                }
        }
    }

    fun closeProfile() {
        _state.value = _state.value.copy(profile = null)
    }

    fun toggleFollow(profile: SocialProfile) {
        viewModelScope.launch {
            runCatching { repo.follow(profile.id, !profile.isFollowing) }
                .onSuccess { resp ->
                    val updated = profile.copy(
                        isFollowing = resp.following,
                        followers = resp.followers
                    )
                    _state.value = _state.value.copy(
                        profile = if (_state.value.profile?.id == profile.id) updated else _state.value.profile,
                        searchResults = _state.value.searchResults.map {
                            if (it.id == profile.id) it.copy(isFollowing = resp.following) else it
                        },
                        toast = if (resp.following) tr("已关注") else tr("已取消关注")
                    )
                }
                .onFailure { message(it.message ?: tr("操作失败")) }
        }
    }

    fun toggleBlock(profile: SocialProfile) {
        if (!profile.blocked && _state.value.profile?.id != profile.id) return
        viewModelScope.launch {
            runCatching { repo.block(profile.id, !profile.blocked) }
                .onSuccess {
                    _state.value = _state.value.copy(
                        profile = _state.value.profile?.copy(blocked = !profile.blocked),
                        toast = if (profile.blocked) tr("已取消拉黑") else tr("已拉黑")
                    )
                }
                .onFailure { message(it.message ?: tr("操作失败")) }
        }
    }

    fun loadPreferences() {
        viewModelScope.launch {
            runCatching { repo.preferences() }
                .onSuccess { _state.value = _state.value.copy(dmPolicy = it.dmPolicy) }
                .onFailure { message(it.message ?: tr("设置加载失败")) }
        }
    }

    fun savePreferences(policy: String) {
        viewModelScope.launch {
            runCatching { repo.savePreferences(policy) }
                .onSuccess {
                    _state.value = _state.value.copy(dmPolicy = it.dmPolicy, toast = tr("私信设置已保存"))
                }
                .onFailure { message(it.message ?: tr("保存失败")) }
        }
    }

    // ==================== 分享 ====================
    fun openShareComposer(song: Song?) {
        if (song == null) {
            message(tr("当前没有播放歌曲"))
            return
        }
        _state.value = _state.value.copy(shareComposer = song, shareResult = null, shareError = null)
    }

    fun closeShareComposer() {
        _state.value = _state.value.copy(shareComposer = null, shareResult = null, shareError = null, shareBusy = false)
    }

    fun createShare(
        song: Song,
        messageText: String,
        options: ShareOptions,
        lyric: String,
        progress: SocialProgress?
    ) {
        viewModelScope.launch {
            _state.value = _state.value.copy(shareBusy = true, shareError = null)
            runCatching {
                repo.createShare(
                    ShareRequest(
                        song = SocialSong.from(song),
                        platform = platformLabel(song),
                        message = messageText.take(200),
                        options = options,
                        lyricSnippet = if (options.lyric) lyric.take(300) else "",
                        progress = if (options.progress) progress else null
                    )
                )
            }.onSuccess {
                _state.value = _state.value.copy(shareBusy = false, shareResult = it)
            }.onFailure {
                _state.value = _state.value.copy(shareBusy = false, shareError = it.message ?: tr("分享创建失败"))
            }
        }
    }

    fun openShareToken(token: String) {
        if (token.isBlank()) return
        viewModelScope.launch {
            runCatching { repo.share(token) }
                .onSuccess { share ->
                    if (share.revoked) {
                        message(tr("分享已失效"))
                        return@onSuccess
                    }
                    onPlayShared(share.song.toSong(), share.progress?.positionMs ?: 0)
                    message(tr("正在播放分享歌曲"))
                }
                .onFailure { message(it.message ?: tr("分享加载失败")) }
        }
    }

    // ==================== 实时与轮询 ====================
    private fun startPolling() {
        pollJob?.cancel()
        pollJob = viewModelScope.launch {
            while (isActive && running) {
                delay(10_000)
                if (!running) break
                refreshConversations(silent = true)
                _state.value.active?.let { active ->
                    runCatching {
                        val after = _state.value.messages.maxOfOrNull { it.seq } ?: 0
                        val resp = repo.messages(active.id, after.takeIf { it > 0 })
                        resp.messages.forEach { appendMessage(it) }
                        if (resp.messages.isNotEmpty()) {
                            repo.markRead(active.id, _state.value.messages.maxOf { it.seq })
                            refreshConversations(silent = true)
                        }
                    }
                }
            }
        }
    }

    private fun connectSse() {
        sseJob?.cancel()
        sseJob = viewModelScope.launch(Dispatchers.IO) {
            var attempt = 0
            while (isActive && running) {
                val connection = try {
                    SocialSseConnection.open()
                } catch (e: Exception) {
                    delay(backoff(attempt++))
                    continue
                }
                sseConnection = connection
                try {
                    connection.read { event, data -> handleSse(event, data) }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    // 断线后指数退避重连
                } finally {
                    connection.close()
                    sseConnection = null
                }
                if (!isActive || !running) break
                attempt += 1
                delay(backoff(attempt))
            }
        }
    }

    private fun backoff(attempt: Int): Long =
        (1000L shl attempt.coerceIn(0, 5)).coerceAtMost(60_000L)

    private fun handleSse(event: String, data: String) {
        if (event == "ready") {
            _state.value = _state.value.copy(sseConnected = true)
            return
        }
        if (event == "message") {
            val payload = runCatching { json.decodeFromString<SocialMessageEvent>(data) }.getOrNull() ?: return
            val incoming = payload.message ?: return
            viewModelScope.launch(Dispatchers.Main.immediate) {
                val active = _state.value.active
                if (active != null && incoming.conversationId == active.id) {
                    appendMessage(incoming)
                    if (!incoming.owned) {
                        runCatching { repo.markRead(active.id, incoming.seq) }
                    }
                }
                refreshConversations(silent = true)
            }
            return
        }
        if (event == "messageDeleted") {
            _state.value.active?.let { loadActiveMessages(replace = true) }
            refreshConversations(silent = true)
            return
        }
        if (event == "follow") {
            _state.value = _state.value.copy(toast = tr("有新粉丝关注了你"))
        }
    }

    override fun onCleared() {
        stop()
        super.onCleared()
    }
}
