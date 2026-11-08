package top.nekoh2o.player.ui.screens

import android.graphics.BitmapFactory
import android.os.SystemClock
import android.util.Base64
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import top.nekoh2o.player.data.model.*
import top.nekoh2o.player.data.net.KugouApiException
import top.nekoh2o.player.data.net.kugouLoginError
import top.nekoh2o.player.ui.PlayerViewModel
import top.nekoh2o.player.ui.components.DetailTopBar
import top.nekoh2o.player.ui.components.InlineNotice
import top.nekoh2o.player.ui.components.NekoChip
import top.nekoh2o.player.ui.components.PageContentPadding
import top.nekoh2o.player.ui.components.SettingsControlTile
import top.nekoh2o.player.ui.components.SettingsSection
import top.nekoh2o.player.ui.theme.NekoDefaults
import top.nekoh2o.player.ui.theme.NekoRadius
import top.nekoh2o.player.ui.theme.NekoSpace

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun KugouLoginScreen(vm: PlayerViewModel, onBack: () -> Unit) {
    val state by vm.ui.collectAsState()
    val scope = rememberCoroutineScope()
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val finish by rememberUpdatedState(onBack)
    var phone by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var platform by remember { mutableIntStateOf(state.kgAccount.platform) }
    var method by remember { mutableIntStateOf(0) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var message by remember { mutableStateOf("") }
    var deadline by remember { mutableLongStateOf(0L) }
    var seconds by remember { mutableIntStateOf(0) }
    var qr by remember { mutableStateOf<KgQrSession?>(null) }
    var qrDeadline by remember { mutableLongStateOf(0L) }
    var polling by remember { mutableStateOf(false) }
    var accounts by remember { mutableStateOf<List<KgLoginAccount>>(emptyList()) }

    LaunchedEffect(deadline) {
        do {
            seconds = ((deadline - SystemClock.elapsedRealtime() + 999) / 1000).coerceAtLeast(0).toInt()
            if (seconds > 0) delay(500)
        } while (seconds > 0)
    }

    LaunchedEffect(platform, method) {
        qr = null
        polling = false
        error = null
        message = ""
        accounts = emptyList()
        code = ""
    }

    LaunchedEffect(qr?.key, polling, platform, method) {
        val session = qr ?: return@LaunchedEffect
        if (!polling || method != 1 || session.platform != platform) return@LaunchedEffect
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            var failures = 0
            while (polling) {
                if (SystemClock.elapsedRealtime() >= qrDeadline) {
                    polling = false
                    message = "二维码已过期，请刷新"
                    break
                }
                delay(2000)
                try {
                    val result = vm.kgCheckLoginQR(session)
                    failures = 0
                    error = null
                    when (result.status) {
                        0 -> { polling = false; message = "二维码已过期，请刷新" }
                        1 -> message = "等待使用酷狗 App 扫码"
                        2 -> message = "已扫码，请在酷狗 App 中确认登录"
                        4 -> { polling = false; finish() }
                    }
                } catch (e: CancellationException) { throw e
                } catch (e: Exception) {
                    failures++
                    error = kugouLoginError(e)
                    if (e is KugouApiException || failures >= 3) polling = false
                }
            }
        }
    }

    fun submit(userId: Long? = null) {
        if (busy) return
        busy = true
        error = null
        accounts = emptyList()
        scope.launch {
            try {
                vm.kgLogin(phone.trim(), code.trim(), platform, userId?.toString())
                finish()
            } catch (e: CancellationException) { throw e
            } catch (e: KugouAccountSelection) { accounts = e.accounts
            } catch (e: Exception) { error = kugouLoginError(e)
            } finally { busy = false }
        }
    }

    Column(Modifier.fillMaxSize()) {
        DetailTopBar("登录酷狗音乐", onBack)
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(PageContentPadding),
            verticalArrangement = Arrangement.spacedBy(NekoSpace.lg)
        ) {
            SettingsSection(description = "两个版本的登录凭据分别保存，扫码时请使用对应版本的酷狗 App。") {
                SettingsControlTile(title = "版本") {
                    Row(horizontalArrangement = Arrangement.spacedBy(NekoSpace.sm)) {
                        listOf("原版", "概念版").forEachIndexed { index, title ->
                            NekoChip(title, platform == index, { if (!busy) platform = index })
                        }
                    }
                }
                SettingsControlTile(title = "登录方式") {
                    Row(horizontalArrangement = Arrangement.spacedBy(NekoSpace.sm)) {
                        listOf("短信验证码", "App 扫码").forEachIndexed { index, title ->
                            NekoChip(title, method == index, { if (!busy) method = index })
                        }
                    }
                }
            }
            if (method == 0) {
                OutlinedTextField(value = phone, onValueChange = { phone = it.filter(Char::isDigit).take(11) },
                    label = { Text("大陆手机号") }, enabled = !busy, singleLine = true, modifier = Modifier.fillMaxWidth(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone), colors = NekoDefaults.textFieldColors())
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(value = code, onValueChange = { code = it.filter(Char::isDigit).take(8) },
                        label = { Text("验证码") }, enabled = !busy, singleLine = true, modifier = Modifier.weight(1f),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), colors = NekoDefaults.textFieldColors())
                    Button(enabled = !busy && seconds == 0 && phone.length == 11, onClick = {
                        busy = true; error = null
                        scope.launch {
                            try {
                                vm.kgSendCode(phone.trim(), platform)
                                deadline = SystemClock.elapsedRealtime() + 60000
                                message = "验证码已发送"
                            } catch (e: CancellationException) { throw e
                            } catch (e: Exception) { error = kugouLoginError(e)
                            } finally { busy = false }
                        }
                    }) { Text(if (seconds > 0) seconds.toString() + "s" else "发送验证码") }
                }
                Button(onClick = { submit() }, enabled = !busy && phone.length == 11 && code.length in 4..8, modifier = Modifier.fillMaxWidth()) {
                    Text(if (busy) "处理中…" else "登录")
                }
            } else {
                val bitmap = remember(qr?.image) {
                    runCatching {
                        val raw = qr?.image ?: return@runCatching null
                        val bytes = Base64.decode(raw.substringAfter("base64,", raw).removePrefix("base64://"), Base64.DEFAULT)
                        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
                    }.getOrNull()
                }
                if (qr != null) {
                    if (bitmap != null) Surface(
                        color = androidx.compose.ui.graphics.Color.White,
                        shape = androidx.compose.foundation.shape.RoundedCornerShape(NekoRadius.card),
                        modifier = Modifier.align(Alignment.CenterHorizontally)
                    ) {
                        Image(bitmap, "酷狗登录二维码", Modifier.padding(NekoSpace.md).size(220.dp))
                    }
                    else Text("二维码图片无法显示，请刷新", color = MaterialTheme.colorScheme.error)
                }
                Button(enabled = !busy, modifier = Modifier.fillMaxWidth(), onClick = {
                    qr = null; polling = false; busy = true; error = null; message = "正在获取二维码"
                    scope.launch {
                        try {
                            qr = vm.kgCreateLoginQR(platform)
                            qrDeadline = SystemClock.elapsedRealtime() + 180000
                            polling = true
                            message = "请使用" + if (platform == 1) "酷狗概念版扫码并确认" else "酷狗音乐 App 扫码并确认"
                        } catch (e: CancellationException) { throw e
                        } catch (e: Exception) { error = kugouLoginError(e); message = ""
                        } finally { busy = false }
                    }
                }) { Text(if (busy) "获取中…" else if (qr == null) "获取二维码" else "刷新二维码") }
                if (polling) CircularProgressIndicator(Modifier.size(24.dp).align(Alignment.CenterHorizontally))
            }
            if (message.isNotEmpty()) InlineNotice(message)
            error?.let { InlineNotice(it, error = true) }
        }
    }
    if (accounts.isNotEmpty()) AlertDialog(onDismissRequest = { accounts = emptyList() }, title = { Text("选择酷狗账号") }, text = {
        Column {
            accounts.forEach { account ->
                TextButton(onClick = { submit(account.userid) }) {
                    Text(account.nickname.ifBlank { "酷狗账号" } + "（" + account.userid + "）")
                }
            }
        }
    }, confirmButton = {}, dismissButton = { TextButton(onClick = { accounts = emptyList() }) { Text("取消") } })
}
