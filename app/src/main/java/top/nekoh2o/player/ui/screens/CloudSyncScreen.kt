package top.nekoh2o.player.ui.screens

import top.nekoh2o.player.i18n.NekoI18n.tr

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.outlined.CloudDownload
import androidx.compose.material.icons.outlined.CloudUpload
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.Merge
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import top.nekoh2o.player.data.sync.Outcome
import top.nekoh2o.player.data.sync.SectionRow
import top.nekoh2o.player.data.sync.SyncSection
import top.nekoh2o.player.data.sync.SyncStatus
import top.nekoh2o.player.data.sync.SyncUiState
import top.nekoh2o.player.data.sync.formatSyncTime
import top.nekoh2o.player.ui.PlayerViewModel
import top.nekoh2o.player.ui.components.DetailPage
import top.nekoh2o.player.ui.components.InlineNotice
import top.nekoh2o.player.ui.components.SettingsSection
import top.nekoh2o.player.ui.components.StatusBadge
import top.nekoh2o.player.ui.theme.NekoDefaults
import top.nekoh2o.player.ui.theme.NekoSpace

enum class SyncAction(private val rawLabel: String) {
    UPLOAD("上传到云端"),
    PULL("从云端拉取"),
    MERGE("合并两端");

    val label: String get() = tr(rawLabel)
}

@Composable
fun CloudSyncScreen(vm: PlayerViewModel, onBack: () -> Unit) {
    val ui by vm.ui.collectAsState()
    val sync by vm.cloudSync.state.collectAsState()
    var selected by remember {
        mutableStateOf(setOf(SyncSection.FAVORITES, SyncSection.HISTORY, SyncSection.PLAYLISTS))
    }
    var pending by remember { mutableStateOf<SyncAction?>(null) }

    LaunchedEffect(ui.loggedIn) { if (ui.loggedIn) vm.cloudSync.launchRefresh() }

    CloudSyncContent(
        loggedIn = ui.loggedIn,
        accountName = ui.user?.let { it.nickname ?: it.username ?: it.id.toString() },
        sync = sync,
        now = System.currentTimeMillis(),
        selected = selected,
        onSelect = { section, on -> selected = if (on) selected + section else selected - section },
        onAuto = vm.cloudSync::setAutoSync,
        onRefresh = vm.cloudSync::launchRefresh,
        onAction = { action ->
            // 合并不覆盖任何一端，不含凭据时无需确认
            if (action == SyncAction.MERGE && SyncSection.CREDENTIALS !in selected) run(vm, action, selected)
            else pending = action
        },
        onBack = onBack
    )

    pending?.let { action ->
        val chosen = SyncSection.entries.filter { it in selected }
        ConfirmDialog(
            action, chosen,
            onConfirm = { run(vm, action, chosen.toSet()); pending = null },
            onDismiss = { pending = null }
        )
    }
}

private fun run(vm: PlayerViewModel, action: SyncAction, sections: Set<SyncSection>) = when (action) {
    SyncAction.UPLOAD -> vm.cloudSync.launchUpload(sections)
    SyncAction.PULL -> vm.cloudSync.launchPull(sections)
    SyncAction.MERGE -> vm.cloudSync.launchMerge(sections)
}

@Composable
fun CloudSyncContent(
    loggedIn: Boolean,
    accountName: String?,
    sync: SyncUiState,
    now: Long,
    selected: Set<SyncSection>,
    onSelect: (SyncSection, Boolean) -> Unit,
    onAuto: (SyncSection, Boolean) -> Unit,
    onRefresh: () -> Unit,
    onAction: (SyncAction) -> Unit,
    onBack: () -> Unit
) {
    val canOperate = loggedIn && !sync.busy
    DetailPage(
        title = tr("云端同步"),
        onBack = onBack,
        actions = {
            IconButton(onClick = onRefresh, enabled = canOperate) {
                Icon(Icons.Filled.Refresh, contentDescription = tr("刷新云端状态"))
            }
        }
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(NekoSpace.sm)) {
            InlineNotice(
                when {
                    !loggedIn -> tr("请先在「我的」页登录 NekoPlayer 账号。")
                    sync.busy -> tr("正在与云端通信…")
                    else -> tr("{account} · 上次检查 {time}", "account" to (accountName ?: tr("已登录")), "time" to formatSyncTime(sync.lastCheckedAt, now))
                }
            )
            if (sync.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            sync.error?.let { InlineNotice(it, error = true) }
        }

        SettingsSection(
            title = tr("同步内容"),
            description = tr("勾选的项目用于下方的手动操作。自动同步只处理单边改动，两端都改过时会等你选择方向。")
        ) {
            sync.rows.forEach { row ->
                SectionRowTile(
                    row = row,
                    now = now,
                    checked = row.section in selected,
                    enabled = canOperate,
                    onChecked = { onSelect(row.section, it) },
                    onAuto = { onAuto(row.section, it) }
                )
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(NekoSpace.sm)) {
            val enabled = canOperate && selected.isNotEmpty()
            Row(horizontalArrangement = Arrangement.spacedBy(NekoSpace.sm)) {
                Button(onClick = { onAction(SyncAction.UPLOAD) }, enabled = enabled, modifier = Modifier.weight(1f)) {
                    ActionLabel(Icons.Outlined.CloudUpload, tr("上传"))
                }
                FilledTonalButton(onClick = { onAction(SyncAction.PULL) }, enabled = enabled, modifier = Modifier.weight(1f)) {
                    ActionLabel(Icons.Outlined.CloudDownload, tr("拉取"))
                }
                OutlinedButton(
                    onClick = { onAction(SyncAction.MERGE) }, enabled = enabled, modifier = Modifier.weight(1f),
                    colors = NekoDefaults.outlinedButtonColors()
                ) {
                    ActionLabel(Icons.Outlined.Merge, tr("合并"))
                }
            }
            Text(
                if (selected.isEmpty()) tr("先勾选要操作的数据。")
                else tr("上传 / 拉取会让另一端与这一端完全一致（包括删除）；合并保留两端的全部条目，适合第一次同步或处理冲突。"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        if (sync.results.isNotEmpty()) {
            SettingsSection(title = tr("上次操作")) {
                sync.results.forEach { r ->
                    val tag = when (r.outcome) { Outcome.OK -> tr("成功"); Outcome.SKIPPED -> tr("跳过"); Outcome.FAILED -> tr("失败") }
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = NekoSpace.lg, vertical = NekoSpace.md),
                        horizontalArrangement = Arrangement.spacedBy(NekoSpace.sm),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(r.section.label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                        Text(
                            "$tag · ${r.message}",
                            style = MaterialTheme.typography.bodySmall,
                            color = if (r.outcome == Outcome.FAILED) MaterialTheme.colorScheme.error
                            else MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
        Text(
            tr("本地音频文件及其路径不会上传。"),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun ActionLabel(icon: ImageVector, label: String) {
    Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp))
    Spacer(Modifier.width(6.dp))
    Text(label, maxLines = 1)
}

@Composable
private fun SectionRowTile(
    row: SectionRow,
    now: Long,
    checked: Boolean,
    enabled: Boolean,
    onChecked: (Boolean) -> Unit,
    onAuto: (Boolean) -> Unit
) {
    val section = row.section
    val colors = MaterialTheme.colorScheme
    val remote = when {
        row.remoteUpdatedAt == null -> tr("未检查")
        row.remoteCount == null || row.remoteUpdatedAt <= 0L -> tr("暂无数据")
        else -> tr("{count} {unit} · {time}", "count" to row.remoteCount, "unit" to section.unit, "time" to formatSyncTime(row.remoteUpdatedAt, now)) +
            row.remoteDevice.takeIf { it.isNotBlank() }?.let { " · $it" }.orEmpty()
    }
    Row(
        Modifier
            .fillMaxWidth()
            .toggleable(value = checked, enabled = enabled, role = Role.Checkbox, onValueChange = onChecked)
            .padding(start = NekoSpace.xs, end = NekoSpace.lg, top = NekoSpace.sm, bottom = NekoSpace.sm),
        verticalAlignment = Alignment.Top
    ) {
        Checkbox(
            checked = checked,
            onCheckedChange = null,
            enabled = enabled,
            modifier = Modifier.padding(NekoSpace.md).semantics { contentDescription = tr("选择{section}", "section" to section.label) }
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            // 自动同步开关放在标题行，下面的时间信息占满整行宽度
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(NekoSpace.sm)) {
                Text(section.label, style = MaterialTheme.typography.bodyLarge)
                StatusBadge(row.status.label, statusColor(row.status))
                Spacer(Modifier.weight(1f))
                Text(tr("自动"), style = MaterialTheme.typography.labelMedium, color = colors.onSurfaceVariant)
                Switch(
                    checked = row.autoSync,
                    onCheckedChange = onAuto,
                    modifier = Modifier.scale(0.8f).semantics { contentDescription = tr("{section}自动同步", "section" to section.label) }
                )
            }
            SideLine(Icons.Outlined.PhoneAndroid, tr("本机"), "${row.localCount} ${section.unit} · ${formatSyncTime(row.localUpdatedAt, now)}")
            SideLine(Icons.Outlined.Cloud, tr("云端"), remote)
            if (section == SyncSection.CREDENTIALS) {
                Text(
                    tr("包含网易云 / 酷狗的登录 Cookie，只在信任的设备上开启。"),
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.error
                )
            }
        }
    }
}

@Composable
private fun SideLine(icon: ImageVector, label: String, value: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(14.dp))
        Spacer(Modifier.width(NekoSpace.xs))
        Text(
            "$label  $value",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun statusColor(status: SyncStatus) = when (status) {
    SyncStatus.SYNCED -> MaterialTheme.colorScheme.tertiary
    SyncStatus.CONFLICT -> MaterialTheme.colorScheme.error
    SyncStatus.LOCAL_NEWER, SyncStatus.REMOTE_NEWER -> MaterialTheme.colorScheme.primary
    else -> MaterialTheme.colorScheme.outline
}

@Composable
private fun ConfirmDialog(
    action: SyncAction,
    sections: List<SyncSection>,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    val names = sections.joinToString(tr("、")) { it.label }
    val body = buildString {
        append(when (action) {
            SyncAction.UPLOAD -> tr("将用本机的「{names}」覆盖云端对应数据，其他设备上较新的改动会丢失。", "names" to names)
            SyncAction.PULL -> tr("将用云端的「{names}」覆盖本机对应数据，本机尚未上传的改动会丢失。", "names" to names)
            SyncAction.MERGE -> tr("将合并本机与云端的「{names}」，并把结果上传到云端。", "names" to names)
        })
        if (SyncSection.CREDENTIALS in sections) {
            append("\n\n")
            append(when (action) {
                SyncAction.PULL -> tr("「音乐平台登录」会替换本机已登录的网易云 / 酷狗账号。")
                else -> tr("「音乐平台登录」包含网易云 / 酷狗 Cookie，将上传到云端，请确认这是你信任的账号和设备。")
            })
        }
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("${action.label}？") },
        text = { Text(body) },
        confirmButton = { TextButton(onClick = onConfirm) { Text(action.label) } },
        dismissButton = {
            TextButton(onClick = onDismiss, colors = NekoDefaults.textButtonColors()) { Text(tr("取消")) }
        }
    )
}
