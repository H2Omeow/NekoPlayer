package top.nekoh2o.player.diagnostics

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class DiagnosticsReporterTest {

    @Test
    fun runtimeLogAndReportRedactCredentials() {
        val context = RuntimeEnvironment.getApplication()
        AppLog.install(context)
        AppLog.info(
            "test",
            "Cookie: MUSIC_U=secret-cookie; access https://example.com/audio?token=hidden-token"
        )
        val report = DiagnosticsReporter.build(context)
        assertTrue(report.contains("NekoPlayer diagnostics export"))
        assertTrue(report.contains("runtime log"))
        assertFalse(report.contains("secret-cookie"))
        assertFalse(report.contains("hidden-token"))
        assertTrue(report.contains("<redacted>"))
    }

    @Test
    fun redactionCoversHeadersBearersAndSecretFields() {
        val text = AppLog.redact(
            "Authorization: Bearer abc.def\n" +
                "token=plain-token\n" +
                "https://example.com/x?signature=private"
        )
        assertFalse(text.contains("abc.def"))
        assertFalse(text.contains("plain-token"))
        assertFalse(text.contains("private"))
        assertTrue(text.contains("<redacted>"))
    }
}
