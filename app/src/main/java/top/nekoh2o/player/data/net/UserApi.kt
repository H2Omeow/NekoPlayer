package top.nekoh2o.player.data.net

import top.nekoh2o.player.data.model.MeResp
import top.nekoh2o.player.data.model.SectionsPatchRequest
import top.nekoh2o.player.data.model.SectionsPatchResp
import top.nekoh2o.player.data.model.UserDataResp
import top.nekoh2o.player.data.model.WallpaperResp
import top.nekoh2o.player.data.model.NcAccountResp
import top.nekoh2o.player.data.model.NcLoginStatusResp
import top.nekoh2o.player.data.model.NcPlaylistResp
import top.nekoh2o.player.data.model.NcLikeListResp
import top.nekoh2o.player.data.model.NcPlayRecordResp
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.Response
import retrofit2.http.POST
import retrofit2.http.Query

interface UserApi {
    @GET("auth/sso/me")
    suspend fun me(): MeResp

    @POST("auth/sso/logout")
    suspend fun logout(): retrofit2.Response<Unit>

    @GET("user/data")
    suspend fun pullData(): Response<UserDataResp>

    @PATCH("user/data/sections")
    suspend fun patchSections(@Body body: SectionsPatchRequest): Response<SectionsPatchResp>

    @GET("local/wallpaper/list")
    suspend fun wallpaperList(@Query("orientation") orientation: String): WallpaperResp

    // ==================== 网易云相关接口 ====================
    @GET("nc/user/account")
    suspend fun ncAccount(): NcAccountResp

    @GET("nc/login/status")
    suspend fun ncLoginStatus(): NcLoginStatusResp

    @GET("nc/user/playlist")
    suspend fun ncUserPlaylists(@Query("uid") uid: Long): NcPlaylistResp

    @GET("nc/likelist")
    suspend fun ncLikeList(@Query("uid") uid: Long): NcLikeListResp

    @GET("nc/user/record")
    suspend fun ncUserRecord(@Query("uid") uid: Long, @Query("type") type: Int = 1): NcPlayRecordResp
}
