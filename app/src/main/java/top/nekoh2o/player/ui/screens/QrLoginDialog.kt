package top.nekoh2o.player.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import top.nekoh2o.player.ui.PlayerViewModel

@Composable
fun QrLoginDialog(vm: PlayerViewModel, onDismiss: () -> Unit) {
    var qrBase64 by remember { mutableStateOf<String?>(null) }
    var message by remember { mutableStateOf("正在获取二维码...") }
    var done by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        val key = vm.qrKeyOnce()
        if (key == null) { message = "获取二维码失败"; return@LaunchedEffect }
        val img = vm.qrCreateOnce(key)
        if (img == null) { message = "二维码生成失败"; return@LaunchedEffect }
        qrBase64 = img
        message = "请使用网易云音乐 App 扫码"
        // 轮询
        while (!done) {
            delay(2000)
            when (vm.qrCheckOnce(key)) {
                803 -> { message = "登录成功"; done = true }
                802 -> message = "已扫码，请在手机确认"
                800 -> { message = "二维码已过期，请重开"; done = true }
            }
        }
    }

    LaunchedEffect(done) {
        if (done && message == "登录成功") {
            delay(800); onDismiss()
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("网易云扫码登录") },
        text = {
            Column(
                Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                val bmp = remember(qrBase64) { qrBase64?.let { decodeBase64Image(it) } }
                if (bmp != null) {
                    // 二维码需要白底才能被扫描
                    Surface(color = androidx.compose.ui.graphics.Color.White, shape = MaterialTheme.shapes.medium) {
                        androidx.compose.foundation.Image(
                            bitmap = bmp.asImageBitmap(),
                            contentDescription = "二维码",
                            modifier = Modifier.padding(12.dp).size(200.dp)
                        )
                    }
                } else {
                    Box(Modifier.size(200.dp), Alignment.Center) { CircularProgressIndicator() }
                }
                Spacer(Modifier.height(12.dp))
                Text(message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("关闭") } }
    )
}

// data URI 里的 base64 图片解码
private fun decodeBase64Image(dataUri: String): android.graphics.Bitmap? {
    return runCatching {
        val base64 = dataUri.substringAfter(",", dataUri)
        val bytes = android.util.Base64.decode(base64, android.util.Base64.DEFAULT)
        android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
    }.getOrNull()
}
