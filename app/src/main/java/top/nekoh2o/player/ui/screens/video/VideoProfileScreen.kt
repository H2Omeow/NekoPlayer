package top.nekoh2o.player.ui.screens.video

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.outlined.CloudUpload
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Subtitles
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import top.nekoh2o.player.data.bilibili.BiliAccount
import top.nekoh2o.player.data.bilibili.BiliSession
import top.nekoh2o.player.data.store.VideoHistoryStore
import top.nekoh2o.player.data.store.WatchEntry
import top.nekoh2o.player.ui.components.DetailTopBar
import top.nekoh2o.player.ui.theme.NekoRadius
import top.nekoh2o.player.ui.theme.NekoSpace
import top.nekoh2o.player.i18n.NekoI18n.tr

@Composable
fun VideoProfileScreen(
    account: BiliAccount,
    history: VideoHistoryStore,
    historyVersion: Int,
    onBack: () -> Unit,
    onLogin: () -> Unit,
    onOpenVideo: (String) -> Unit,
    onOpenCloudFiles: () -> Unit,
    onOpenPlayerSettings: () -> Unit,
    onOpenDanmakuSettings: () -> Unit,
    onChanged: () -> Unit
) {
    var confirmLogout by remember { mutableStateOf(false) }
    var confirmClear by remember { mutableStateOf(false) }
    var refresh by remember { mutableIntStateOf(0) }
    val entries = remember(historyVersion, refresh) { history.list() }

    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        DetailTopBar(tr("我的"), onBack)
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(
                start = NekoSpace.lg, end = NekoSpace.lg, top = NekoSpace.md, bottom = 120.dp
            )
        ) {
            item { AccountCard(account, onLogin) }
            item { Spacer(Modifier.height(NekoSpace.lg)) }
            item {
                Surface(
                    color = MaterialTheme.colorScheme.surfaceContainerLow,
                    shape = RoundedCornerShape(NekoRadius.card)
                ) {
                    Column(Modifier.fillMaxWidth()) {
                        ProfileRow(Icons.Outlined.CloudUpload, tr("云存储"), tr("上传文件、分享链接、查看额度")) { onOpenCloudFiles() }
                        ProfileRow(Icons.Outlined.Subtitles, tr("弹幕设置"), tr("字号、速度、透明度、屏蔽词")) { onOpenDanmakuSettings() }
                        ProfileRow(Icons.Outlined.Settings, tr("播放设置"), tr("默认清晰度、倍速、手势")) { onOpenPlayerSettings() }
                    }
                }
            }
            item {
                Row(
                    Modifier.fillMaxWidth().padding(top = NekoSpace.lg, bottom = NekoSpace.sm),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Outlined.History, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.width(6.dp))
                    Text(tr("观看历史"), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.weight(1f))
                    if (entries.isNotEmpty()) {
                        Text(
                            tr("清空"),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable {
                                confirmClear = true
                            }.padding(horizontal = 8.dp, vertical = 4.dp)
                        )
                    }
                }
            }
            if (entries.isEmpty()) {
                item {
                    Text(
                        tr("还没有观看记录"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(vertical = NekoSpace.lg)
                    )
                }
            } else {
                items(entries, key = { it.bvid }) { entry ->
                    HistoryRow(entry) {
                        onOpenVideo(entry.bvid)
                    }
                }
            }
            item {
                if (account.isLogin) {
                    Spacer(Modifier.height(NekoSpace.xl))
                    OutlinedButton(
                        onClick = { confirmLogout = true },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(Icons.AutoMirrored.Outlined.Logout, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(tr("退出 B 站账号"))
                    }
                }
            }
        }
    }

        if (confirmClear) {
        AlertDialog(
            onDismissRequest = { confirmClear = false },
            title = { Text(tr("清空观看历史")) },
            text = { Text(tr("清空后无法恢复，确定要继续吗？")) },
            confirmButton = {
                TextButton(onClick = {
                    confirmClear = false
                    history.clear()
                    refresh++
                    onChanged()
                }) { Text(tr("清空"), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmClear = false }) { Text(tr("取消")) } }
        )
    }

if (confirmLogout) {
        AlertDialog(
            onDismissRequest = { confirmLogout = false },
            title = { Text(tr("退出登录")) },
            text = { Text(tr("退出后将无法观看 1080P、发送弹幕或同步收藏，确定退出吗？")) },
            confirmButton = {
                TextButton(onClick = {
                    confirmLogout = false
                    BiliSession.logout()
                    onChanged()
                }) { Text(tr("退出"), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { confirmLogout = false }) { Text(tr("取消")) }
            }
        )
    }
}

@Composable
private fun AccountCard(account: BiliAccount, onLogin: () -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(NekoRadius.card)
    ) {
        Row(
            Modifier.fillMaxWidth().padding(NekoSpace.lg),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Avatar(account.face, 60.dp)
            Spacer(Modifier.width(NekoSpace.md))
            Column(Modifier.weight(1f)) {
                Text(
                    if (account.isLogin) account.name.ifBlank { tr("B 站用户") } else tr("未登录"),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    if (account.isLogin) "UID ${account.mid}" else tr("登录后可看 1080P、发弹幕、同步收藏"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (!account.isLogin) {
                Button(onClick = onLogin) { Text(tr("登录")) }
            }
        }
    }
}

@Composable
private fun ProfileRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit
) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = NekoSpace.lg, vertical = NekoSpace.md),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, null, Modifier.size(22.dp), tint = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.width(NekoSpace.md))
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun HistoryRow(entry: WatchEntry, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(NekoRadius.control))
            .clickable(onClick = onClick)
            .padding(vertical = NekoSpace.sm),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.width(104.dp)) {
            VideoCover(
                top.nekoh2o.player.data.bilibili.VideoItem(
                    bvid = entry.bvid,
                    aid = entry.aid,
                    title = entry.title,
                    cover = entry.cover,
                    upName = entry.upName,
                    upFace = "",
                    durationSec = entry.durationSec,
                    views = 0,
                    danmakuCount = 0,
                    pubdate = 0,
                    badges = emptyList()
                ),
                Modifier.fillMaxWidth(),
                showProgress = entry.progress
            )
        }
        Spacer(Modifier.width(NekoSpace.md))
        Column(Modifier.weight(1f)) {
            Text(
                entry.title,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 2
            )
            Spacer(Modifier.height(4.dp))
            Text(
                formatPosition(entry.positionMs) + " / " + formatDuration(entry.durationSec),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
