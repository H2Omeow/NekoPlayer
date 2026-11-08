package top.nekoh2o.player.data.net

import android.content.Context
import top.nekoh2o.player.i18n.NekoI18n
import com.jakewharton.retrofit2.converter.kotlinx.serialization.asConverterFactory
import kotlinx.serialization.json.Json
import kotlinx.coroutines.CompletableDeferred
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import java.util.concurrent.TimeUnit

object ApiFactory {

    private val ready = CompletableDeferred<Unit>()

    suspend fun awaitReady() = ready.await()

    const val BASE = "https://player.nekoh2o.top/"
    const val PLAYER_HOST = "player.nekoh2o.top"
    const val ANIMEMUSIC_BASE = "https://animemusic.bzxhkj.com/v1/"

    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
        isLenient = true
    }

    lateinit var cookieJar: PersistentCookieJar
        private set

    private lateinit var httpClient: OkHttpClient
    private lateinit var nativeNetease: OkHttpClient

    fun init(context: Context) {
        cookieJar = PersistentCookieJar(context.applicationContext)

        httpClient = OkHttpClient.Builder()
            .cookieJar(cookieJar)
            // 让本站社区/云同步/评论接口按界面语言返回错误信息。
            .addInterceptor { chain ->
                val req = chain.request()
                if (req.header("Accept-Language") != null) chain.proceed(req)
                else chain.proceed(req.newBuilder().header("Accept-Language", NekoI18n.activeLanguageTag()).build())
            }
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .writeTimeout(20, TimeUnit.SECONDS)
            // SSO 鉴权：仅对 player 域名注入 Bearer token（账户中心下发的 JWT），
            // 避免把 token 泄露给下载走的第三方 CDN 域名。
            .addInterceptor { chain ->
                val req = chain.request()
                val token = CookieStore.appTokenValue()
                if (req.url.host == PLAYER_HOST) {
                    if (token.isNotEmpty()) {
                        chain.proceed(req.newBuilder().header("Authorization", "Bearer " + token).build())
                    } else chain.proceed(req)
                } else {
                    chain.proceed(req)
                }
            }
            .addInterceptor(
                HttpLoggingInterceptor().apply {
                    level = HttpLoggingInterceptor.Level.NONE
                }
            )
            .build()

        nativeNetease = httpClient.newBuilder().cookieJar(okhttp3.CookieJar.NO_COOKIES)
            .apply { interceptors().clear() }.followRedirects(false).callTimeout(30, TimeUnit.SECONDS)
            .addInterceptor(top.nekoh2o.player.data.net.nativeapi.NeteaseNativeInterceptor(top.nekoh2o.player.data.net.AndroidProviderPreferences(
                context.getSharedPreferences("netease_native", Context.MODE_PRIVATE)))).build()
        ready.complete(Unit)
    }

    private fun retrofit(baseUrl: String, client: OkHttpClient = httpClient): Retrofit {
        return Retrofit.Builder()
            .baseUrl(baseUrl)
            .client(client)
            .addConverterFactory(
                json.asConverterFactory(
                    "application/json".toMediaType()
                )
            )
            .build()
    }

    val music: MusicApi by lazy {
        retrofit(BASE, nativeNetease).create(MusicApi::class.java)
    }

    val user: UserApi by lazy {
        retrofit(BASE).create(UserApi::class.java)
    }

    val social: top.nekoh2o.player.data.social.SocialApi by lazy {
        retrofit(BASE).create(top.nekoh2o.player.data.social.SocialApi::class.java)
    }

    val netease: NeteaseApi by lazy {
        retrofit(BASE, nativeNetease).create(NeteaseApi::class.java)
    }

    val kugou: KugouApi by lazy {
        val client = httpClient.newBuilder()
            .cookieJar(okhttp3.CookieJar.NO_COOKIES)
            .apply { interceptors().clear() }
            .followRedirects(false).callTimeout(30, TimeUnit.SECONDS)
            .addInterceptor(KugouInterceptor(CookieStore.kgSessions))
            .addInterceptor(top.nekoh2o.player.data.net.nativeapi.KugouNativeInterceptor(CookieStore.kgSessions))
            .build()
        retrofit(BASE, client).create(KugouApi::class.java)
    }

    val nativeMusic: ProviderApi by lazy { retrofit(BASE, nativeNetease).create(ProviderApi::class.java) }
    val animemusic: AnimemusicApi by lazy {
        val pluginClient = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS).readTimeout(25, TimeUnit.SECONDS)
            .callTimeout(30, TimeUnit.SECONDS).followRedirects(false)
            .cookieJar(okhttp3.CookieJar.NO_COOKIES)
            .build()
        retrofit(ANIMEMUSIC_BASE, pluginClient).create(AnimemusicApi::class.java)
    }
    fun client(): OkHttpClient = httpClient
}
