package top.nekoh2o.player.ui.screens.cloud

import top.nekoh2o.player.ui.components.NekoAlertDialog

import android.annotation.SuppressLint
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONTokener
import top.nekoh2o.player.data.cloud.CloudApi
import top.nekoh2o.player.ui.theme.NekoRadius
import top.nekoh2o.player.i18n.NekoI18n.tr

/**
 * 网页登录兜底：鹰角短信接口风控要求人机验证时，在 WebView 里走官方登录页，
 * 登录成功后从 localStorage 里取出 token，交给账户中心换 cred 完成绑定。
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun SklandWebLoginDialog(onDismiss: () -> Unit, onBound: () -> Unit) {
    var status by remember { mutableStateOf(tr("在下方登录森空岛（含人机验证）")) }
    var webView by remember { mutableStateOf<WebView?>(null) }
    var finished by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val tried = remember { mutableSetOf<String>() }

    NekoAlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(tr("网页登录森空岛")) },
        text = {
            Column {
                Text(status, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(8.dp))
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(420.dp)
                        .clip(RoundedCornerShape(NekoRadius.control))
                ) {
                    AndroidView(
                        modifier = Modifier.fillMaxSize(),
                        factory = { ctx ->
                            WebView(ctx).apply {
                                settings.javaScriptEnabled = true
                                settings.domStorageEnabled = true
                                settings.databaseEnabled = true
                                settings.userAgentString =
                                    "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36"
                                CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                                webViewClient = WebViewClient()
                                loadUrl("https://user.hypergryph.com/")
                                webView = this
                            }
                        }
                    )
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text(tr("关闭")) } }
    )

    DisposableEffect(webView) {
        onDispose {
            webView?.apply {
                stopLoading()
                loadUrl("about:blank")
                destroy()
            }
        }
    }

    LaunchedEffect(webView) {
        val view = webView ?: return@LaunchedEffect
        while (!finished) {
            delay(1500)
            val script = """
                (function(){
                  var out = [];
                  try {
                    for (var i = 0; i < localStorage.length; i++) {
                      var k = localStorage.key(i);
                      var v = localStorage.getItem(k) || '';
                      if (v.length >= 24 && v.length <= 2048 && v.indexOf(' ') < 0) out.push(k + '\u0002' + v);
                    }
                  } catch (e) {}
                  return out.join('\n');
                })()
            """.trimIndent()
            view.evaluateJavascript(script) { raw ->
                val text = runCatching {
                    (JSONTokener(raw).nextValue() as? String) ?: ""
                }.getOrDefault("")
                if (text.isBlank()) return@evaluateJavascript
                text.lineSequence().forEach { line ->
                    val parts = line.split('\u0002')
                    if (parts.size != 2) return@forEach
                    val value = parts[1].trim()
                    if (value.length < 24 || !tried.add(value)) return@forEach
                    // 只尝试看起来像 token 的值，避免把主题等无关内容提交上去
                    if (!value.matches(Regex("[A-Za-z0-9._~+/=-]{24,2048}"))) return@forEach
                    status = tr("正在校验登录状态…")
                    scope.launch {
                        val ok = runCatching { CloudApi.sklandWebToken(value) }.isSuccess
                        if (ok && !finished) {
                            finished = true
                            onBound()
                        } else if (!finished) {
                            status = tr("在下方登录森空岛（含人机验证）")
                        }
                    }
                }
            }
        }
    }
}
