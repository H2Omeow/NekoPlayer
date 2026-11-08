package top.nekoh2o.player.ui.screens

import top.nekoh2o.player.i18n.NekoI18n.tr

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import top.nekoh2o.player.ui.PlayerViewModel
import top.nekoh2o.player.ui.components.Artwork
import top.nekoh2o.player.ui.components.DetailPage
import top.nekoh2o.player.ui.components.EmptyState
import top.nekoh2o.player.ui.components.NekoChip
import top.nekoh2o.player.ui.components.SettingsControlTile
import top.nekoh2o.player.ui.components.SettingsSection
import top.nekoh2o.player.ui.components.SettingsTile
import top.nekoh2o.player.ui.components.StatusBadge
import top.nekoh2o.player.ui.theme.NekoRadius
import top.nekoh2o.player.ui.theme.NekoSpace
import java.text.SimpleDateFormat
import java.util.*

/**
 * 酷狗音乐账户管理界面
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun KugouAccountScreen(vm: PlayerViewModel, onBack: () -> Unit, onLogin: () -> Unit) {
    val state by vm.ui.collectAsState()
    val kgAccount = state.kgAccount
    var showVipDialog by remember { mutableStateOf(false) }
    var showCookieManager by remember { mutableStateOf(false) }

    if (showCookieManager) {
        CookieManagerScreen(vm, initialProvider = "kugou") { showCookieManager = false }
        return
    }

    LaunchedEffect(Unit) {
        if (kgAccount.isValid) {
            vm.refreshKgAccount()
        }
    }

    // VIP领取对话框（仅概念版）
    if (showVipDialog && kgAccount.platform == 1) {
        VipReceiveDialog(
            onDismiss = { showVipDialog = false },
            onReceive = { vipType, days ->
                vm.kgReceiveVip(vipType, days)
                showVipDialog = false
            }
        )
    }

    DetailPage(
        title = tr("酷狗音乐"),
        onBack = onBack,
        actions = { TextButton(onClick = { showCookieManager = true }) { Text("Cookie") } }
    ) {
        if (!kgAccount.isValid) {
            EmptyState(
                icon = Icons.Filled.Person,
                title = tr("未登录酷狗账号"),
                description = tr("登录后可以搜索和播放酷狗音乐、查看个人歌单；概念版可领取每日权益。"),
                action = { Button(onClick = onLogin) { Text(tr("登录酷狗账号")) } }
            )
            return@DetailPage
        }
        Surface(
            shape = RoundedCornerShape(NekoRadius.artwork),
            color = MaterialTheme.colorScheme.surfaceContainer,
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(
                Modifier.padding(NekoSpace.lg),
                horizontalArrangement = Arrangement.spacedBy(NekoSpace.lg),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Artwork(kgAccount.avatar, size = 64.dp, shape = CircleShape, thumbnail = null, placeholder = Icons.Filled.Person)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(NekoSpace.xs)) {
                    Text(kgAccount.nickname.ifEmpty { tr("酷狗用户") }, style = MaterialTheme.typography.titleLarge)
                    Text(
                        "UID ${kgAccount.userId}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    StatusBadge(
                        when (kgAccount.vipType) { 1 -> tr("VIP 会员"); 2 -> tr("豪华 VIP"); else -> tr("普通用户") },
                        if (kgAccount.vipType > 0) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
                    )
                }
            }
        }

        SettingsSection(
            title = tr("账号"),
            description = tr("原版与概念版的登录状态分别保存，首次在新设备使用时请扫码或验证码登录。")
        ) {
            SettingsControlTile(title = tr("当前版本")) {
                Row(horizontalArrangement = Arrangement.spacedBy(NekoSpace.sm)) {
                    NekoChip(tr("原版"), kgAccount.platform == 0, { if (kgAccount.platform != 0) vm.kgSwitchPlatform(0) })
                    NekoChip(tr("概念版"), kgAccount.platform == 1, { if (kgAccount.platform != 1) vm.kgSwitchPlatform(1) })
                }
            }
            if (kgAccount.vipType > 0 && kgAccount.vipEndTime > 0) {
                SettingsTile(
                    title = tr("会员到期"),
                    value = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault()).format(Date(kgAccount.vipEndTime * 1000))
                )
            }
            SettingsTile(title = tr("登录其他账号"), onClick = onLogin)
        }

        if (kgAccount.platform == 1) {
            SettingsSection(
                title = tr("概念版权益"),
                description = tr("测试接口，可能随时失效；领取资格与结果以酷狗返回为准。")
            ) {
                SettingsTile(title = tr("领取每日 VIP"), onClick = { showVipDialog = true })
            }
        }
    }
}

@Composable
private fun VipReceiveDialog(
    onDismiss: () -> Unit,
    onReceive: (vipType: Int, days: Int) -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(tr("领取概念版每日权益")) },
        text = { Text(tr("领取资格、有效期与结果以酷狗返回为准。请先完成官方要求的听歌任务。")) },
        confirmButton = { TextButton(onClick = { onReceive(1, 1) }) { Text(tr("领取")) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(tr("取消")) } }
    )
}
