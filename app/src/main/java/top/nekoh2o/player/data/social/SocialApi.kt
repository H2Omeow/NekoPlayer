package top.nekoh2o.player.data.social

import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.PUT
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

interface SocialApi {
    @GET("social/conversations")
    suspend fun conversations(): SocialConversationsResp

    @GET("social/conversations/with/{peerId}")
    suspend fun conversationWith(@Path("peerId") peerId: String): SocialConversationResp

    @POST("social/conversations")
    suspend fun createConversation(@Body body: CreateConversationRequest): SocialConversationResp

    @GET("social/conversations/{id}/messages")
    suspend fun messages(
        @Path("id") id: String,
        @Query("limit") limit: Int = 100,
        @Query("afterSeq") afterSeq: Long? = null
    ): SocialMessagesResp

    @POST("social/conversations/{id}/read")
    suspend fun markRead(@Path("id") id: String, @Body body: ReadRequest): SocialReadResp

    @POST("social/messages")
    suspend fun sendMessage(@Body body: SendMessageRequest): SocialSendResp

    @DELETE("social/messages/{id}")
    suspend fun deleteMessage(@Path("id") id: String): SocialSendResp

    @GET("social/users/search")
    suspend fun searchUsers(@Query("q") query: String): SocialSearchResp

    @GET("social/users/{id}")
    suspend fun profile(@Path("id") id: String): SocialProfileResp

    @GET("social/users/{id}/shares")
    suspend fun userShares(@Path("id") id: String): SocialFeedResp

    @GET("social/users/{id}/followers")
    suspend fun followers(@Path("id") id: String, @Query("offset") offset: Int = 0): SocialSearchResp

    @GET("social/users/{id}/following")
    suspend fun following(@Path("id") id: String, @Query("offset") offset: Int = 0): SocialSearchResp

    @POST("social/users/{id}/follow")
    suspend fun follow(@Path("id") id: String, @Body body: FollowRequest): SocialFollowResp

    @DELETE("social/users/{id}/follow")
    suspend fun unfollow(@Path("id") id: String): SocialFollowResp

    @POST("social/blocks/{id}")
    suspend fun block(@Path("id") id: String, @Body body: BlockRequest = BlockRequest()): SocialBlockResp

    @DELETE("social/blocks/{id}")
    suspend fun unblock(@Path("id") id: String): SocialBlockResp

    @GET("social/feed")
    suspend fun feed(): SocialFeedResp

    @POST("social/shares")
    suspend fun createShare(@Body body: ShareRequest): SocialShareResp

    @GET("social/shares/{token}")
    suspend fun share(@Path("token") token: String): SocialShareResp

    @DELETE("social/shares/{token}")
    suspend fun revokeShare(@Path("token") token: String): SocialShareResp

    @GET("social/preferences")
    suspend fun preferences(): SocialPreferencesResp

    @PUT("social/preferences")
    suspend fun savePreferences(@Body body: PreferencesRequest): SocialPreferencesResp

    @GET("social/unread")
    suspend fun unread(): SocialUnreadResp
}
