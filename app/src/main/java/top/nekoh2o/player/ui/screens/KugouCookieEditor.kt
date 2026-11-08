package top.nekoh2o.player.ui.screens

import top.nekoh2o.player.i18n.NekoI18n.tr

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import top.nekoh2o.player.data.net.kugouLoginError
import top.nekoh2o.player.ui.PlayerViewModel
import top.nekoh2o.player.ui.components.InlineNotice
import top.nekoh2o.player.ui.components.NekoChip
import top.nekoh2o.player.ui.theme.NekoDefaults
import top.nekoh2o.player.ui.theme.NekoSpace

@Composable
fun KugouCookieEditor(vm: PlayerViewModel) {
    val state by vm.ui.collectAsState()
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboardManager.current
    var platform by remember { mutableIntStateOf(state.kgAccount.platform) }
    var draft by remember(platform) { mutableStateOf("") }
    var saved by remember(platform) { mutableStateOf("") }
    var visible by remember(platform) { mutableStateOf(false) }
    var busy by remember(platform) { mutableStateOf(true) }
    var message by remember(platform) { mutableStateOf("") }
    var error by remember(platform) { mutableStateOf<String?>(null) }
    var confirmClear by remember(platform) { mutableStateOf(false) }

    LaunchedEffect(platform) {
        try {
            saved = vm.loadKgCookie(platform)
            draft = saved
        } catch (e: CancellationException) { throw e
        } catch (e: Exception) { error = kugouLoginError(e)
        } finally { busy = false }
    }

    Column(verticalArrangement = Arrangement.spacedBy(NekoSpace.md)) {
        Row(horizontalArrangement = Arrangement.spacedBy(NekoSpace.sm), verticalAlignment = Alignment.CenterVertically) {
            listOf(tr("原版"), tr("概念版")).forEachIndexed { index, title ->
                NekoChip(title, platform == index, { if (!busy) platform = index })
            }
            Spacer(Modifier.weight(1f))
            if (platform != state.kgAccount.platform) {
                TextButton(enabled = !busy, onClick = { vm.kgSwitchPlatform(platform) }) { Text(tr("使用此版本")) }
            } else {
                Text(tr("当前使用"), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
            }
        }
        Text(
            tr("需包含 token 和 userid；若有 dfid、KUGOU_API_* 设备字段请一并保留，网页追踪 Cookie 无法替代登录凭据。") +
                tr("两个版本分别保存。Cookie 包含账号凭据，请勿分享。"),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        OutlinedTextField(value = draft, onValueChange = { draft = it; error = null; message = "" },
            enabled = !busy, label = { Text(if (platform == 0) tr("酷狗原版 Cookie") else tr("酷狗概念版 Cookie")) },
            supportingText = {
                Text(if (saved.isEmpty()) tr("当前版本未保存 Cookie") else tr("已保存 {count} 个字符", "count" to saved.length))
            },
            modifier = Modifier.fillMaxWidth().height(180.dp), maxLines = 6,
            visualTransformation = if (visible) VisualTransformation.None else PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password), colors = NekoDefaults.textFieldColors())
        Row(
            Modifier.toggleable(value = visible, role = Role.Checkbox, onValueChange = { visible = it }),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Checkbox(checked = visible, onCheckedChange = null)
            Spacer(Modifier.width(NekoSpace.sm))
            Text(tr("显示 Cookie 内容"), style = MaterialTheme.typography.bodyMedium)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(NekoSpace.sm)) {
            Button(enabled = !busy && draft.isNotBlank(), modifier = Modifier.weight(1f), onClick = {
                busy = true; error = null; message = ""
                scope.launch {
                    try {
                        saved = vm.saveKgCookie(draft, platform)
                        draft = saved
                        message = tr("Cookie 已保存，账号有效性以酷狗返回结果为准")
                    } catch (e: CancellationException) { throw e
                    } catch (e: Exception) { error = kugouLoginError(e)
                    } finally { busy = false }
                }
            }) { Text(tr("保存")) }
            OutlinedButton(enabled = !busy && saved.isNotEmpty(), colors = NekoDefaults.outlinedButtonColors(), onClick = {
                clipboard.setText(AnnotatedString(saved)); message = tr("已复制当前版本保存的 Cookie")
            }) { Text(tr("复制")) }
            OutlinedButton(enabled = !busy && saved.isNotEmpty(), colors = NekoDefaults.outlinedButtonColors(),
                onClick = { confirmClear = true }) { Text(tr("清除")) }
        }
        if (saved.split(';').any { it.trim().startsWith("token=") }) {
            TextButton(enabled = !busy, colors = NekoDefaults.textButtonColors(), onClick = {
                busy = true; error = null; message = ""
                scope.launch {
                    try {
                        saved = vm.logoutKgCookie(platform)
                        draft = saved
                        message = tr("已退出当前版本账号，设备 Cookie 已保留")
                    } catch (e: CancellationException) { throw e
                    } catch (e: Exception) { error = kugouLoginError(e)
                    } finally { busy = false }
                }
            }) { Text(tr("退出登录（保留设备）")) }
        }
        if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (message.isNotEmpty()) InlineNotice(message)
        error?.let { InlineNotice(it, error = true) }
    }

    if (confirmClear) AlertDialog(onDismissRequest = { confirmClear = false },
        title = { Text(tr("清除{target}", "target" to (if (platform == 0) tr("酷狗原版 Cookie") else tr("酷狗概念版 Cookie")))) },
        text = { Text(tr("将清除该版本的登录及设备 Cookie，下次请求会重新初始化设备。另一版本不受影响。")) },
        confirmButton = { TextButton(onClick = {
            confirmClear = false; busy = true; error = null; message = ""
            scope.launch {
                try {
                    vm.clearKgCookie(platform)
                    saved = ""; draft = ""; message = tr("当前版本的 Cookie 已清除")
                } catch (e: CancellationException) { throw e
                } catch (e: Exception) { error = kugouLoginError(e)
                } finally { busy = false }
            }
        }) { Text(tr("清除")) } },
        dismissButton = { TextButton(onClick = { confirmClear = false }) { Text(tr("取消")) } })
}
