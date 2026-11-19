package top.nekoh2o.player.ui.screens.video

import android.graphics.Bitmap
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.Hd
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.outlined.Subtitles
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import top.nekoh2o.player.data.bilibili.QrState
import top.nekoh2o.player.data.bilibili.QrTicket
import top.nekoh2o.player.data.repo.VideoRepository
import top.nekoh2o.player.ui.theme.NekoRadius
import top.nekoh2o.player.ui.theme.NekoSpace
import androidx.compose.foundation.text.KeyboardOptions
import top.nekoh2o.player.i18n.NekoI18n.tr

/** 登录方式：App 扫码、应用内网页登录、Cookie 导入。 */
private enum class LoginMethod(val label: String) {
    Scan(tr("App 扫码")),
    Web(tr("网页登录")),
    Cookie(tr("Cookie 导入"))
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VideoLoginScreen(
    repo: VideoRepository,
    onClose: () -> Unit,
    onLoggedIn: () -> Unit
) {
    var method by remember { mutableStateOf(LoginMethod.Scan) }
    val scope = rememberCoroutineScope()

    var importing by remember { mutableStateOf(false) }
    var importError by remember { mutableStateOf<String?>(null) }
    fun finish(raw: String) {
        if (raw.isBlank()) {
            importError = tr("请先填入 Cookie")
            return
        }
        scope.launch {
            importing = true
            importError = null
            val ok = runCatching { repo.importCookie(raw) }.getOrDefault(false)
            importing = false
            if (ok) onLoggedIn() else importError = tr("Cookie 无效或已过期，请重新获取")
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .statusBarsPadding()
    ) {
        Column(Modifier.fillMaxSize().padding(horizontal = NekoSpace.xl)) {
            Row(Modifier.fillMaxWidth().padding(vertical = NekoSpace.sm), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onClose) {
                    Icon(Icons.Filled.Close, tr("关闭"), tint = MaterialTheme.colorScheme.onSurface)
                }
                Spacer(Modifier.weight(1f))
                Text(
                    tr("遇到问题？"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.clickable { method = LoginMethod.Cookie }.padding(8.dp)
                )
            }

            Spacer(Modifier.height(NekoSpace.md))
            Box(
                Modifier
                    .align(Alignment.CenterHorizontally)
                    .size(64.dp)
                    .clip(RoundedCornerShape(NekoRadius.artwork))
                    .background(
                        Brush.linearGradient(
                            listOf(MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.tertiary)
                        )
                    )
            )
            Spacer(Modifier.height(NekoSpace.md))
            Text(
                tr("登录 B 站账号"),
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.align(Alignment.CenterHorizontally)
            )
            Spacer(Modifier.height(NekoSpace.sm))
            Text(
                tr("登录后可解锁 1080P / 4K 画质、发送弹幕，\n并与 B 站同步收藏、关注与历史记录"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.align(Alignment.CenterHorizontally),
                textAlign = TextAlign.Center
            )
            Spacer(Modifier.height(NekoSpace.lg))

            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.Center
            ) {
                LoginMethod.entries.forEach { item ->
                    val selected = method == item
                    Surface(
                        shape = RoundedCornerShape(999.dp),
                        color = if (selected) {
                            MaterialTheme.colorScheme.primary.copy(alpha = 0.18f)
                        } else {
                            MaterialTheme.colorScheme.surfaceContainerHigh
                        },
                        contentColor = if (selected) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        },
                        modifier = Modifier
                            .padding(horizontal = 4.dp)
                            .clickable { method = item }
                    ) {
                        Text(
                            item.label,
                            style = MaterialTheme.typography.labelMedium,
                            modifier = Modifier.padding(horizontal = 14.dp, vertical = 7.dp)
                        )
                    }
                }
            }

            Spacer(Modifier.height(NekoSpace.lg))
            Box(Modifier.weight(1f).fillMaxWidth()) {
                when (method) {
                    LoginMethod.Scan -> ScanPane(repo = repo, onLoggedIn = onLoggedIn)
                    LoginMethod.Web -> WebPane(onCookies = ::finish)
                    LoginMethod.Cookie -> CookiePane(onCookies = ::finish)
                }
            }

            Text(
                tr("登录即表示同意《用户协议》与《隐私政策》，Cookie 仅保存在本机"),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = NekoSpace.sm, bottom = NekoSpace.lg)
            )
        }
    }
}

/* ------------------------------- 扫码 ------------------------------- */

@Composable
private fun ScanPane(repo: VideoRepository, onLoggedIn: () -> Unit) {
    var ticket by remember { mutableStateOf<QrTicket?>(null) }
    var bitmap by remember { mutableStateOf<Bitmap?>(null) }
    var status by remember { mutableStateOf(tr("正在生成二维码…")) }
    var expired by remember { mutableStateOf(false) }
    var countdown by remember { mutableIntStateOf(180) }
    var error by remember { mutableStateOf<String?>(null) }
    var pollKey by remember { mutableIntStateOf(0) }

    LaunchedEffect(pollKey) {
        status = tr("正在生成二维码…")
        expired = false
        countdown = 180
        runCatching { repo.qrGenerate() }
            .onSuccess { t ->
                ticket = t
                bitmap = runCatching {
                    kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { qrBitmap(t.url) }
                }.getOrNull()
                status = tr("打开哔哩哔哩 App 扫一扫")
            }
            .onFailure {
                error = it.message
                status = tr("二维码生成失败，点击重试")
            }
    }

    LaunchedEffect(ticket) {
        val t = ticket ?: return@LaunchedEffect
        while (isActive) {
            delay(1000)
            if (countdown > 0) countdown--
            if (countdown == 0) {
                expired = true
                status = tr("二维码已失效，点击刷新")
                return@LaunchedEffect
            }
            if (countdown % 2 == 0) {
                val state = runCatching { repo.qrPoll(t.key) }.getOrNull()
                when (state) {
                    QrState.Scanned -> status = tr("已扫码，请在手机上确认")
                    is QrState.Success -> {
                        status = tr("登录成功")
                        delay(600)
                        onLoggedIn()
                        return@LaunchedEffect
                    }
                    is QrState.Expired -> {
                        expired = true
                        status = state.message
                        return@LaunchedEffect
                    }
                    else -> Unit
                }
            }
        }
    }

    Column(
        Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Surface(shape = RoundedCornerShape(NekoRadius.card), color = Color.White) {
            Column(Modifier.padding(NekoSpace.md), horizontalAlignment = Alignment.CenterHorizontally) {
                val bmp = bitmap
                if (bmp != null && !expired) {
                    Image(
                        bitmap = bmp.asImageBitmap(),
                        contentDescription = tr("登录二维码"),
                        modifier = Modifier.size(200.dp)
                    )
                } else {
                    Box(
                        Modifier.size(200.dp).background(Color(0xFFF2F2F2)),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            if (expired) tr("二维码已失效\n点击刷新") else tr("生成中…"),
                            color = Color(0xFF333333),
                            style = MaterialTheme.typography.bodySmall,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.clickable { pollKey++ }
                        )
                    }
                }
                Spacer(Modifier.height(8.dp))
                Text(
                    text = if (expired) tr("点击刷新二维码") else "二维码 $countdown 秒后失效 · 点击刷新",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.clickable { pollKey++ }
                )
            }
        }
        Spacer(Modifier.height(NekoSpace.md))
        Text(
            status,
            style = MaterialTheme.typography.bodyMedium,
            color = if (error != null) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant
        )
        if (error != null) {
            Text(
                tr("网络异常，请检查代理或稍后重试"),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Spacer(Modifier.height(NekoSpace.lg))
        BenefitRow(Icons.Outlined.Hd, tr("1080P / 4K 原画，登录后自动取最高可用清晰度"))
        BenefitRow(Icons.Outlined.Subtitles, tr("发送与屏蔽弹幕，同步自己的弹幕偏好"))
        BenefitRow(Icons.Outlined.Shield, tr("Cookie 仅保存在本机，可随时退出并清除"))
    }
}

/* ------------------------------ 网页登录 ------------------------------ */

@Composable
private fun WebPane(onCookies: (String) -> Unit) {
    var loaded by remember { mutableStateOf(false) }
    var blocked by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf(tr("正在打开 B 站登录页…")) }
    val target = "https://passport.bilibili.com/login"

    // 先清掉 WebView 里可能残留的旧登录态，避免把上一次的 Cookie 当成新登录
    remember { CookieManager.getInstance().removeAllCookies(null) }

    LaunchedEffect(Unit) {
        while (isActive) {
            val cookie = readBiliCookie()
            if (cookie.contains("SESSDATA=") && cookie.length > 40) {
                status = tr("登录成功，正在同步账号信息…")
                onCookies(cookie)
                return@LaunchedEffect
            }
            delay(900)
        }
    }

    Column(Modifier.fillMaxSize()) {
        Surface(
            shape = RoundedCornerShape(NekoRadius.card),
            color = MaterialTheme.colorScheme.surfaceContainerLow,
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.3f), RoundedCornerShape(NekoRadius.card))
        ) {
            Box(Modifier.fillMaxSize()) {
                AndroidView(
                    factory = { context ->
                        WebView(context).apply {
                            layoutParams = ViewGroup.LayoutParams(
                                ViewGroup.LayoutParams.MATCH_PARENT,
                                ViewGroup.LayoutParams.MATCH_PARENT
                            )
                            settings.javaScriptEnabled = true
                            settings.domStorageEnabled = true
                            settings.databaseEnabled = true
                            settings.userAgentString =
                                "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) " +
                                    "Chrome/124.0.0.0 Mobile Safari/537.36"
                            CookieManager.getInstance().setAcceptCookie(true)
                            CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                            webViewClient = object : WebViewClient() {
                                override fun onPageFinished(view: WebView?, url: String?) {
                                    loaded = true
                                }

                                override fun onReceivedError(
                                    view: WebView?,
                                    request: WebResourceRequest?,
                                    error: android.webkit.WebResourceError?
                                ) {
                                    if (request?.isForMainFrame == true) blocked = true
                                }
                            }
                            loadUrl(target)
                        }
                    },
                    onRelease = { web ->
                        web.stopLoading()
                        web.destroy()
                    },
                    modifier = Modifier.fillMaxSize()
                )
                if (!loaded) {
                    Column(
                        Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.Center,
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        CircularProgressIndicator()
                        Spacer(Modifier.height(8.dp))
                        Text(
                            tr("加载中…"),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
                if (blocked) {
                    Text(
                        tr("登录页被拦截，请改用扫码或 Cookie 导入"),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.align(Alignment.TopCenter).padding(8.dp)
                    )
                }
            }
        }
        Spacer(Modifier.height(NekoSpace.sm))
        Text(
            status,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth()
        )
        Text(
            tr("在下方网页里用账号密码 / 短信验证码登录，完成后会自动跳回；") +
                tr("若页面空白，请改用扫码登录"),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().padding(top = 2.dp, bottom = NekoSpace.sm)
        )
    }
}

/** 合并 www 与 passport 两个域下的 Cookie，B 站登录态分布在两处。 */
private fun readBiliCookie(): String {
    val manager = CookieManager.getInstance()
    val parts = linkedSetOf<String>()
    listOf("https://www.bilibili.com", "https://passport.bilibili.com", "https://api.bilibili.com")
        .forEach { host ->
            manager.getCookie(host)
                ?.split(';')
                ?.map { it.trim() }
                ?.filter { it.contains('=') }
                ?.forEach { parts.add(it) }
        }
    return parts.joinToString("; ")
}

/* ----------------------------- Cookie 导入 ----------------------------- */

@Composable
private fun CookiePane(onCookies: (String) -> Unit) {
    var sessData by remember { mutableStateOf("") }
    var biliJct by remember { mutableStateOf("") }
    var dedeUser by remember { mutableStateOf("") }
    var rawCookie by remember { mutableStateOf("") }
    var advanced by remember { mutableStateOf(false) }
    val clipboard = LocalClipboardManager.current

    fun build(): String {
        if (rawCookie.isNotBlank()) return rawCookie.trim()
        val parts = mutableListOf<String>()
        if (sessData.isNotBlank()) parts += "SESSDATA=${sessData.trim()}"
        if (biliJct.isNotBlank()) parts += "bili_jct=${biliJct.trim()}"
        if (dedeUser.isNotBlank()) parts += "DedeUserID=${dedeUser.trim()}"
        return parts.joinToString("; ")
    }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState())
    ) {
        Text(
            tr("SESSDATA 与 bili_jct 是登录态里最关键的两个值；") +
                tr("完整 Cookie 里还有 DedeUserID 等字段，粘贴整串更省事。"),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(NekoSpace.md))

        if (!advanced) {
            CookieField("SESSDATA", sessData, tr("从浏览器 Cookie 里复制 SESSDATA 的值")) { sessData = it }
            Spacer(Modifier.height(NekoSpace.sm))
            CookieField("bili_jct", biliJct, tr("用于发送弹幕，可留空")) { biliJct = it }
            Spacer(Modifier.height(NekoSpace.sm))
            CookieField("DedeUserID", dedeUser, tr("可留空"), KeyboardType.Number) { dedeUser = it }
        } else {
            OutlinedTextField(
                value = rawCookie,
                onValueChange = { rawCookie = it },
                minLines = 4,
                maxLines = 7,
                placeholder = { Text("SESSDATA=...; bili_jct=...; DedeUserID=...") },
                modifier = Modifier.fillMaxWidth()
            )
        }

        Spacer(Modifier.height(NekoSpace.md))
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { advanced = !advanced }) {
                Text(if (advanced) tr("改为分字段填写") else tr("粘贴整串 Cookie"))
            }
            Spacer(Modifier.weight(1f))
            TextButton(
                onClick = {
                    val text = clipboard.getText()?.text?.trim().orEmpty()
                    if (text.isNotEmpty()) {
                        if (advanced || text.contains("SESSDATA=")) {
                            advanced = true
                            rawCookie = text
                        } else if (text.length > 60) {
                            sessData = text
                        }
                    }
                }
            ) {
                Icon(Icons.Outlined.ContentPaste, null, Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text(tr("从剪贴板粘贴"))
            }
        }

        Spacer(Modifier.height(NekoSpace.sm))
        Button(
            onClick = {
                val cookie = build()
                if (cookie.isNotBlank()) onCookies(cookie)
            },
            enabled = (advanced && rawCookie.isNotBlank()) || sessData.isNotBlank(),
            modifier = Modifier.fillMaxWidth()
        ) { Text(tr("登录")) }

        Spacer(Modifier.height(NekoSpace.lg))
        Text(
            tr("获取方法：桌面浏览器打开 bilibili.com 并登录 → F12 → Application → Cookies → ") +
                tr("复制 sessdata.bilibili.com 下的 SESSDATA 与 bili_jct。"),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.75f)
        )
    }
}

@Composable
private fun CookieField(
    label: String,
    value: String,
    hint: String,
    keyboardType: KeyboardType = KeyboardType.Text,
    onChange: (String) -> Unit
) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(label) },
        placeholder = { Text(hint) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType, imeAction = ImeAction.Next),
        modifier = Modifier.fillMaxWidth()
    )
}

@Composable
private fun BenefitRow(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier
                .size(32.dp)
                .clip(RoundedCornerShape(9.dp))
                .background(MaterialTheme.colorScheme.surfaceContainerHigh),
            contentAlignment = Alignment.Center
        ) {
            Icon(icon, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
        }
        Spacer(Modifier.width(NekoSpace.md))
        Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** 用 zxing 把登录链接画成二维码位图（不依赖服务端出图）。 */
private fun qrBitmap(content: String, size: Int = 512): Bitmap {
    val matrix = QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, size, size)
    val pixels = IntArray(size * size)
    for (y in 0 until size) {
        for (x in 0 until size) {
            pixels[y * size + x] = if (matrix.get(x, y)) android.graphics.Color.BLACK else android.graphics.Color.WHITE
        }
    }
    return Bitmap.createBitmap(pixels, size, size, Bitmap.Config.ARGB_8888)
}
