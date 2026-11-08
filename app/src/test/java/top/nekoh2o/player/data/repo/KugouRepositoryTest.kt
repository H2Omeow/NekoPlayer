package top.nekoh2o.player.data.repo

import android.content.Context
import com.jakewharton.retrofit2.converter.kotlinx.serialization.asConverterFactory
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import okhttp3.CookieJar
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import retrofit2.Retrofit
import top.nekoh2o.player.data.model.*
import top.nekoh2o.player.data.net.*
import top.nekoh2o.player.playback.SongPlaybackUri
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class KugouRepositoryTest {
    private lateinit var server: MockWebServer
    private lateinit var sessions: KugouSessionStore
    private lateinit var repository: KugouRepository
    private val json = Json { ignoreUnknownKeys = true }
    private val hash = "a123456789012345678901234567890bcd"

    @Before fun setup() {
        val prefs = RuntimeEnvironment.getApplication().getSharedPreferences("kg_test", Context.MODE_PRIVATE)
        prefs.edit().clear().commit()
        sessions = KugouSessionStore(top.nekoh2o.player.data.net.AndroidProviderPreferences(prefs))
        server = MockWebServer().also { it.start() }
        val client = OkHttpClient.Builder().cookieJar(CookieJar.NO_COOKIES)
            .readTimeout(2, TimeUnit.SECONDS).addInterceptor(KugouInterceptor(sessions)).build()
        val api = Retrofit.Builder().baseUrl(server.url("/")).client(client)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType())).build().create(KugouApi::class.java)
        repository = KugouRepository(api, sessions)
    }
    @After fun tearDown() { server.shutdown() }

    private fun response(body: String, code: Int = 200, vararg cookies: String) {
        server.enqueue(MockResponse().setResponseCode(code).setHeader("Content-Type", "application/json")
            .setBody(body).apply { cookies.forEach { addHeader("Set-Cookie", it) } })
    }
    private fun initialized(platform: Int) = sessions.merge(platform, mapOf("dfid" to "fingerprint", "KUGOU_API_MID" to "device"))

    @Test fun smsInitializesDeviceAndPostsWithoutCachingOrLeakingCredentials() = runBlocking {
        response("""{"status":1,"data":{"dfid":"lite-device"}}""", 200, "KUGOU_API_GUID=guid; Path=/", "KUGOU_API_MID=mid; Path=/")
        response("""{"status":1,"error_code":0}""")
        repository.sendCode("13800000000", 1)
        val device = server.takeRequest()
        val sms = server.takeRequest()
        assertEquals("/kgapi/register/dev", device.requestUrl!!.encodedPath)
        assertEquals("POST", sms.method)
        assertEquals("1", sms.requestUrl!!.queryParameter("platform"))
        assertEquals("/kgapi/captcha/sent", sms.requestUrl!!.encodedPath)
        assertFalse(sms.path!!.contains("13800000000"))
        assertEquals("mobile=13800000000", sms.body.readUtf8())
        assertTrue(sms.getHeader("Cookie")!!.contains("KUGOU_API_GUID=guid"))
        assertTrue(sms.getHeader("Cookie")!!.contains("dfid=lite-device"))
        assertNull(sms.getHeader("Authorization"))
        assertNotEquals(device.requestUrl!!.queryParameter("timestamp"), sms.requestUrl!!.queryParameter("timestamp"))
    }

    @Test fun qrOuterSuccessIsNotLoginAndOnlyConfirmedCredentialsAreCommitted() = runBlocking {
        initialized(1)
        sessions.merge(0, mapOf("token" to "standard", "userid" to "100"))
        response("""{"status":1,"data":{"qrcode":"qr-session"}}""")
        response("""{"code":200,"data":{"base64":"data:image/png;base64,aGVsbG8="}}""")
        val qr = repository.createLoginQR(1)
        response("""{"status":1,"data":{"status":1}}""")
        response("""{"status":1,"data":{"status":2}}""")
        response("""{"status":1,"data":{"status":4,"token":"lite","userid":"200","nickname":"test"}}""", 200, "vip_token=vip; Path=/")
        assertEquals(1, repository.checkLoginQR(qr).status)
        assertEquals("", sessions.value(1, "token"))
        assertEquals(2, repository.checkLoginQR(qr).status)
        assertEquals("", sessions.value(1, "token"))
        val success = repository.checkLoginQR(qr)
        assertEquals(4, success.status)
        assertEquals(200L, success.account!!.userid)
        assertEquals("lite", sessions.value(1, "token"))
        assertEquals("standard", sessions.value(0, "token"))
        assertEquals("fingerprint", sessions.value(1, "dfid"))
        assertEquals("vip", sessions.value(1, "vip_token"))
        val requests = List(5) { server.takeRequest() }
        assertEquals(5, requests.map { it.requestUrl!!.queryParameter("timestamp") }.toSet().size)
        assertTrue(requests.all { it.requestUrl!!.queryParameter("platform") == "1" })
        assertTrue(requests.drop(2).all { it.requestUrl!!.queryParameter("key") == "qr-session" })
    }

    @Test fun expiredQrIsNotSuccessfulAndInvalidSuccessDoesNotReplaceExistingLogin() = runBlocking {
        initialized(0)
        sessions.merge(0, mapOf("token" to "previous", "userid" to "11"))
        val qr = KgQrSession("session", "image", 0)
        response("""{"status":1,"data":{"status":0}}""")
        assertEquals(0, repository.checkLoginQR(qr).status)
        response("""{"status":1,"data":{"status":4,"userid":0}}""", 200, "token=undefined; Path=/", "userid=0; Path=/")
        try { repository.checkLoginQR(qr); fail("missing credentials must fail") } catch (_: KugouApiException) { }
        assertEquals("previous", sessions.value(0, "token"))
        assertEquals("11", sessions.value(0, "userid"))
    }

    @Test fun smsBusinessErrorsArePreservedEvenWhenServerUsesHttp502() = runBlocking {
        initialized(0)
        response("""{"status":0,"error_code":20028,"error_msg":"verify required"}""", 502)
        try { repository.sendCode("13800000000", 0); fail("expected API error") }
        catch (e: KugouApiException) { assertEquals(20028, e.errorCode); assertTrue(e.message!!.contains("安全验证")) }
        assertEquals("", sessions.value(0, "token"))
    }

    @Test fun cellphoneLoginPreservesDeviceWhenDfidIsOmitted() = runBlocking {
        initialized(1)
        response("""{"status":1,"data":{"userid":123,"token":"new-token"}}""")
        val login = repository.login("13800000000", "123456", 1)
        assertEquals("fingerprint", login.dfid)
        assertEquals("fingerprint", sessions.value(1, "dfid"))
        val request = server.takeRequest()
        assertEquals("POST", request.method)
        assertFalse(request.path!!.contains("123456"))
        assertTrue(request.body.readUtf8().contains("code=123456"))
    }

    @Test fun multipleAccountsRequireExplicitSelection() = runBlocking {
        initialized(0)
        response("""{"status":1,"data":{"users":[{"userid":12,"nickname":"first"},{"userid":13,"nickname":"second"}]}}""")
        try { repository.login("13800000000", "123456", 0); fail("selection required") }
        catch (e: KugouAccountSelection) { assertEquals(listOf(12L, 13L), e.accounts.map { it.userid }) }
        assertEquals("", sessions.value(0, "token"))
    }

    @Test fun invalidPhoneNeverStartsNetworkOrInitialization() = runBlocking {
        try { repository.sendCode("12", 0); fail("invalid phone") } catch (_: IllegalArgumentException) { }
        assertEquals(0, server.requestCount)
    }

    @Test fun sessionsSurviveRecreationAndLogoutIsScoped() {
        val prefs = RuntimeEnvironment.getApplication().getSharedPreferences("kg_test", Context.MODE_PRIVATE)
        sessions.migrate(0, "old", "1", "device-zero")
        sessions.merge(1, mapOf("token" to "lite", "userid" to "2", "dfid" to "device-one"))
        sessions.clearLogin(0)
        val restored = KugouSessionStore(top.nekoh2o.player.data.net.AndroidProviderPreferences(prefs))
        restored.migrate(0, "old", "1", "old-dfid")
        assertEquals("", restored.value(0, "token"))
        assertEquals("device-zero", restored.value(0, "dfid"))
        assertEquals("lite", restored.value(1, "token"))
        assertEquals("device-one", restored.value(1, "dfid"))
    }

    @Test fun searchRetainsHashAndProviderThroughStorageAndPlaybackAddress() {
        val song = KugouRepository.song(Json.parseToJsonElement("""{"FileHash":"$hash","MixSongID":123,"AlbumID":"456","SongName":"Song","SingerName":"Artist"}""").jsonObject)
        assertEquals(hash, song.hash)
        val restored = json.decodeFromString<Song>(json.encodeToString(song))
        assertEquals(song, restored)
        val playback = SongPlaybackUri.decode(SongPlaybackUri.encode(restored))!!
        assertEquals("kugou", playback.source)
        assertEquals(hash, playback.hash)
        assertEquals("456", playback.albumId)
        assertEquals(123L, playback.albumAudioId)
        val old = json.decodeFromString<Song>("""{"id":9,"nm":"Old","ar":"Artist"}""")
        assertEquals("netease", old.source)
        assertEquals(9L, SongPlaybackUri.decode(SongPlaybackUri.encode(old))!!.id)
    }

    @Test fun cloudPlaylistRowsKeepCombinedNameSingerAndCover() {
        val song = KugouRepository.song(Json.parseToJsonElement("""{"hash":"$hash","name":"PENGIN - ビューティフル","cover":"http://imge.kugou.com/stdmusic/{size}/20150718/cover.jpg","singerinfo":[{"name":"PENGIN"}],"albuminfo":{"id":900843,"name":"PENGIN FAMILY"},"mixsongid":31480287,"album_id":"900843"}""").jsonObject)
        assertEquals("ビューティフル", song.nm)
        assertEquals("PENGIN", song.ar)
        assertEquals("http://imge.kugou.com/stdmusic/400/20150718/cover.jpg", song.pc)
        assertEquals(31480287L, song.id)
        assertEquals("900843", song.albumId)
    }

    @Test fun songUrlsUseAudioFieldsAndSupportArraysWithoutChoosingArtwork() {
        val body = Json.parseToJsonElement("""{"url":["","https://audio.example/music.mp3"],"img":"https://image.example/cover.jpg"}""").jsonObject
        assertEquals("https://audio.example/music.mp3", KugouRepository.playableUrl(body))
        assertNull(KugouRepository.playableUrl(Json.parseToJsonElement("""{"img":"https://image.example/cover.jpg"}""").jsonObject))
    }
}
