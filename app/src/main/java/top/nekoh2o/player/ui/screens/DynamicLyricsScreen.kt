package top.nekoh2o.player.ui.screens

import top.nekoh2o.player.i18n.NekoI18n.tr

import android.annotation.SuppressLint
import android.graphics.Color as AndroidColor
import android.net.Uri
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import org.json.JSONObject
import top.nekoh2o.player.ui.UiState
import top.nekoh2o.player.ui.lyrics.dynamicLyricsPayload
import java.io.ByteArrayInputStream

private const val LyricsOrigin = "https://neko-lyrics.invalid"
private const val LyricsPage = "$LyricsOrigin/lyric_engine/index.html?native=1"

@Composable
fun DynamicLyricsScreen(
    state: UiState,
    onClose: () -> Unit,
    onToggle: () -> Unit,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onSeek: (Long) -> Unit
) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().systemBarsPadding()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text(tr("动态歌词"), Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                    TextButton(onClick = onClose) { Text(tr("返回原歌词")) }
                }
                DynamicLyricsWebView(state, Modifier.weight(1f).fillMaxWidth())
                Column(Modifier.padding(horizontal = 20.dp)) {
                    Slider(
                        value = state.positionMs.toFloat().coerceIn(0f, maxOf(1f, state.durationMs.toFloat())),
                        valueRange = 0f..maxOf(1f, state.durationMs.toFloat()),
                        enabled = state.durationMs > 0,
                        onValueChange = { onSeek(it.toLong()) }
                    )
                    Row(
                        Modifier.fillMaxWidth().padding(bottom = 8.dp),
                        horizontalArrangement = Arrangement.SpaceEvenly,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        IconButton(onClick = onPrevious) {
                            Icon(Icons.Filled.SkipPrevious, contentDescription = tr("上一首"), modifier = Modifier.size(32.dp))
                        }
                        FilledIconButton(onClick = onToggle, enabled = state.current != null, modifier = Modifier.size(60.dp)) {
                            Icon(
                                if (state.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                                contentDescription = if (state.isPlaying) tr("暂停") else tr("播放"),
                                modifier = Modifier.size(30.dp)
                            )
                        }
                        IconButton(onClick = onNext) {
                            Icon(Icons.Filled.SkipNext, contentDescription = tr("下一首"), modifier = Modifier.size(32.dp))
                        }
                    }
                }
            }
        }
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun DynamicLyricsWebView(state: UiState, modifier: Modifier) {
    var webView by remember { mutableStateOf<WebView?>(null) }
    var ready by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var active by remember { mutableStateOf(lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) }

    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, _ ->
            active = lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)
            if (active) webView?.onResume() else {
                webView?.evaluateJavascript("window.nekoLyrics?.suspend()", null)
                webView?.onPause()
            }
        }
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            webView?.stopLoading()
            webView?.destroy()
            webView = null
        }
    }

    Box(modifier) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { context ->
                WebView(context).apply {
                    webView = this
                    setBackgroundColor(AndroidColor.TRANSPARENT)
                    settings.javaScriptEnabled = true
                    settings.allowFileAccess = false
                    settings.allowContentAccess = false
                    // The engine reads its display preferences from localStorage at startup.
                    settings.domStorageEnabled = true
                    settings.javaScriptCanOpenWindowsAutomatically = false
                    settings.setSupportMultipleWindows(false)
                    webViewClient = object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = true

                        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse {
                            return lyricAsset(context.assets, request.url, request.method)
                        }

                        override fun onPageFinished(view: WebView, url: String) {
                            ready = url == LyricsPage
                        }

                        override fun onReceivedError(view: WebView, request: WebResourceRequest,
                            error: android.webkit.WebResourceError) {
                            if (request.isForMainFrame) failed = true
                        }
                    }
                    loadUrl(LyricsPage)
                }
            },
            update = { view ->
                if (ready && active) {
                    val payload = JSONObject.quote(dynamicLyricsPayload(state).toString())
                    view.evaluateJavascript("window.nekoLyrics?.push(JSON.parse($payload))", null)
                }
            }
        )
        if (failed) {
            Surface(Modifier.fillMaxSize()) {
                Box(contentAlignment = Alignment.Center) {
                    Text(tr("动态歌词加载失败，请更新 Android System WebView，或返回原歌词。"),
                        modifier = Modifier.padding(24.dp))
                }
            }
        }
    }
}

internal fun lyricAsset(assets: android.content.res.AssetManager, uri: Uri, method: String): WebResourceResponse {
    fun denied() = WebResourceResponse("text/plain", "utf-8", 403, "Forbidden", emptyMap(), ByteArrayInputStream(byteArrayOf()))
    if (method != "GET" || uri.scheme != "https" || uri.host != "neko-lyrics.invalid" ||
        uri.port != -1 || uri.userInfo != null) return denied()
    val parts = uri.pathSegments
    if (parts.any { it.isEmpty() || it == "." || it == ".." || it.contains('/') || it.contains('\\') }) return denied()
    val path = parts.joinToString("/")
    if (!(path in setOf("lyric_engine/index.html", "lyric_engine/host.js", "lyric_engine/host.css",
            "fonts/NotoSansCJKsc-Regular.otf") || path.startsWith("lyric_engine/assets/"))) return denied()
    val stream = try { assets.open(path) } catch (_: java.io.IOException) { return denied() }
    val mime = when (path.substringAfterLast('.')) {
        "html" -> "text/html"
        "js" -> "text/javascript"
        "css" -> "text/css"
        "png" -> "image/png"
        "jpg", "jpeg" -> "image/jpeg"
        "webp" -> "image/webp"
        "svg" -> "image/svg+xml"
        "otf" -> "font/otf"
        else -> "application/octet-stream"
    }
    return WebResourceResponse(mime, "utf-8", 200, "OK", mapOf(
        "Content-Security-Policy" to "default-src 'none'; script-src 'self' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self' data: blob:; worker-src 'self' blob:; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
        "X-Content-Type-Options" to "nosniff",
        "Cache-Control" to "no-store"
    ), stream)
}
