package top.nekoh2o.player.data.social

import top.nekoh2o.player.i18n.NekoI18n.tr

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import top.nekoh2o.player.data.model.Song

@Serializable
data class SocialProfile(
    val id: String = "",
    val username: String = "",
    val nickname: String = "",
    val avatar: String = "",
    val bio: String = "",
    val followers: Int = 0,
    val following: Int = 0,
    val isFollowing: Boolean = false,
    val isSelf: Boolean = false,
    val blocked: Boolean = false
) {
    val displayName: String get() = nickname.ifBlank { username.ifBlank { tr("用户") } }
}

@Serializable
data class SocialProgress(
    val positionMs: Long = 0,
    val durationMs: Long = 0
)

@Serializable
data class SocialSong(
    val id: Long = 0,
    val nm: String = "",
    val ar: String = "",
    val pc: String? = null,
    val al: String? = null,
    val source: String = "netease",
    val hash: String = "",
    val albumId: String = "",
    val albumAudioId: Long = 0,
    val providerSource: String = "",
    val providerMediaId: String = "",
    val pluginMetadata: String = "",
    val pluginSource: JsonElement? = null,
    val pluginData: JsonElement? = null
) {
    fun toSong(): Song = Song(
        id = id,
        nm = nm.ifBlank { tr("未知歌曲") },
        ar = ar.ifBlank { tr("未知歌手") },
        pc = pc,
        source = source,
        hash = hash,
        albumId = albumId,
        albumAudioId = albumAudioId,
        providerSource = providerSource,
        providerMediaId = providerMediaId,
        pluginMetadata = pluginMetadata,
        pluginSource = pluginSource,
        pluginData = pluginData
    )

    companion object {
        fun from(song: Song): SocialSong = SocialSong(
            id = song.id,
            nm = song.nm,
            ar = song.ar,
            pc = song.pc,
            source = song.source,
            hash = song.hash,
            albumId = song.albumId,
            albumAudioId = song.albumAudioId,
            providerSource = song.providerSource,
            providerMediaId = song.providerMediaId,
            pluginMetadata = song.pluginMetadata,
            pluginSource = song.pluginSource,
            pluginData = song.pluginData
        )
    }
}

fun platformLabel(song: Song): String = when (song.source) {
    "netease" -> tr("网易云音乐")
    "kugou" -> tr("酷狗音乐")
    "animemusic-kg" -> tr("内置音源")
    "animemusic-kw" -> tr("内置音源")
    "animemusic-wy" -> tr("内置音源")
    "animemusic-tx" -> tr("内置音源")
    "animemusic-mg" -> tr("内置音源")
    "animemusic-bilibili" -> tr("内置音源")
    else -> song.source.ifBlank { tr("音乐") }
}

@Serializable
data class SocialMessage(
    val id: String = "",
    val seq: Long = 0,
    val conversationId: String = "",
    val sender: SocialProfile? = null,
    val senderId: String = "",
    val kind: String = "text",
    val text: String = "",
    val song: SocialSong? = null,
    val shareToken: String? = null,
    val createdAt: Long = 0,
    val deleted: Boolean = false,
    val owned: Boolean = false
)

@Serializable
data class SocialConversation(
    val id: String = "",
    val peer: SocialProfile? = null,
    val peerId: String = "",
    val lastMessage: SocialMessage? = null,
    val unread: Int = 0,
    val updatedAt: Long = 0,
    val createdAt: Long = 0
)

@Serializable
data class SocialShare(
    val token: String = "",
    val url: String = "",
    val appUrl: String = "",
    val platform: String = tr("音乐"),
    val song: SocialSong = SocialSong(),
    val message: String = "",
    val lyricSnippet: String = "",
    val progress: SocialProgress? = null,
    val sharer: SocialProfile? = null,
    val createdAt: Long = 0,
    val revoked: Boolean = false,
    val owned: Boolean = false
)

@Serializable
data class ShareOptions(
    val showSharer: Boolean = true,
    val cover: Boolean = true,
    val album: Boolean = false,
    val lyric: Boolean = false,
    val progress: Boolean = false
)

@Serializable
data class ShareRequest(
    val song: SocialSong,
    val platform: String = tr("音乐"),
    val message: String = "",
    val options: ShareOptions = ShareOptions(),
    val lyricSnippet: String = "",
    val progress: SocialProgress? = null
)

@Serializable
data class SendMessageRequest(
    val to: String,
    val kind: String,
    val body: String = "",
    val song: SocialSong? = null,
    val platform: String = "",
    val clientId: String
)

@Serializable
data class FollowRequest(val following: Boolean)

@Serializable
data class BlockRequest(val blocked: Boolean = true)

@Serializable
data class ReadRequest(val seq: Long)

@Serializable
data class CreateConversationRequest(val peer: String)

@Serializable
data class PreferencesRequest(val dmPolicy: String)

@Serializable
data class SocialPreferences(val dmPolicy: String = "everyone")

// ==================== 响应包装 ====================
@Serializable
data class SocialConversationsResp(
    val code: Int = -1,
    val msg: String = "",
    val conversations: List<SocialConversation> = emptyList()
)

@Serializable
data class SocialConversationResp(
    val code: Int = -1,
    val msg: String = "",
    val conversation: SocialConversation? = null
)

@Serializable
data class SocialMessagesResp(
    val code: Int = -1,
    val msg: String = "",
    val messages: List<SocialMessage> = emptyList(),
    val conversation: SocialConversation? = null
)

@Serializable
data class SocialSendResp(
    val code: Int = -1,
    val msg: String = "",
    val message: SocialMessage? = null,
    val conversation: SocialConversation? = null,
    val duplicate: Boolean = false
)

@Serializable
data class SocialReadResp(
    val code: Int = -1,
    val msg: String = "",
    val unread: Int = 0,
    val lastSeq: Long = 0
)

@Serializable
data class SocialProfileResp(
    val code: Int = -1,
    val msg: String = "",
    val profile: SocialProfile? = null
)

@Serializable
data class SocialSearchResp(
    val code: Int = -1,
    val msg: String = "",
    val users: List<SocialProfile> = emptyList()
)

@Serializable
data class SocialFollowResp(
    val code: Int = -1,
    val msg: String = "",
    val following: Boolean = false,
    val followers: Int = 0,
    val followingCount: Int = 0
)

@Serializable
data class SocialBlockResp(
    val code: Int = -1,
    val msg: String = "",
    val blocked: Boolean = false
)

@Serializable
data class SocialFeedResp(
    val code: Int = -1,
    val msg: String = "",
    val shares: List<SocialShare> = emptyList()
)

@Serializable
data class SocialShareResp(
    val code: Int = -1,
    val msg: String = "",
    val share: SocialShare? = null
)

@Serializable
data class SocialPreferencesResp(
    val code: Int = -1,
    val msg: String = "",
    val preferences: SocialPreferences = SocialPreferences()
)

@Serializable
data class SocialUnreadResp(
    val code: Int = -1,
    val msg: String = "",
    val unread: Int = 0
)

@Serializable
data class SocialMessageEvent(
    val message: SocialMessage? = null,
    val conversation: SocialConversation? = null,
    val peerId: String = ""
)

@Serializable
data class SocialErrorMessage(val code: Int = 0, val msg: String = "")

class SocialException(message: String, val status: Int = 0) : Exception(message)
