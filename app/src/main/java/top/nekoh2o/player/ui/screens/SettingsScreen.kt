package top.nekoh2o.player.ui.screens

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckBox
import androidx.compose.material.icons.filled.CheckBoxOutlineBlank
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.outlined.BatteryChargingFull
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.GraphicEq
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.LibraryMusic
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.Subtitles
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import top.nekoh2o.player.data.model.AppSettings
import top.nekoh2o.player.data.model.BgSource
import top.nekoh2o.player.ui.PlayerViewModel
import top.nekoh2o.player.ui.components.Artwork
import top.nekoh2o.player.ui.components.ChipRow
import top.nekoh2o.player.ui.components.DetailPage
import top.nekoh2o.player.ui.components.DetailTopBar
import top.nekoh2o.player.ui.components.EmptyState
import top.nekoh2o.player.ui.components.InlineNotice
import top.nekoh2o.player.ui.components.NekoChip
import top.nekoh2o.player.ui.components.SettingsControlTile
import top.nekoh2o.player.ui.components.SettingsSection
import top.nekoh2o.player.ui.components.SettingsSliderTile
import top.nekoh2o.player.ui.components.SettingsSwitchTile
import top.nekoh2o.player.ui.components.SettingsTile
import top.nekoh2o.player.ui.theme.NekoDefaults
import top.nekoh2o.player.ui.theme.NekoSpace

/** 设置页的各个子页面。 */
enum class SettingsDestination(val title: String) {
    PERSONALIZATION("主题与背景"),
    AUDIO_EFFECTS("音效"),
    PLAYBACK("播放与歌词"),
    STORAGE("下载与存储"),
    CLOUD_SYNC("云端同步"),
    ACCOUNT("音乐平台 Cookie"),
    ADVANCED("后台播放"),
    CACHE("缓存管理"),
    DOWNLOADS("下载管理")
}

@Composable
fun SettingsScreen(vm: PlayerViewModel, onBack: () -> Unit) {
    val sync by vm.cloudSync.state.collectAsState()
    // 子页面栈：从分类页进入缓存 / 下载管理后，返回时回到分类页
    var stack by remember { mutableStateOf(listOf<SettingsDestination>()) }
    var cookieProvider by remember { mutableStateOf<String?>(null) }
    val open: (SettingsDestination) -> Unit = { stack = stack + it }
    val back: () -> Unit = { stack = stack.dropLast(1) }

    cookieProvider?.let { provider ->
        CookieManagerScreen(vm, initialProvider = provider) { cookieProvider = null }
        return
    }
    when (val top = stack.lastOrNull()) {
        null -> SettingsHome(
            conflicts = sync.conflictCount,
            onOpen = open,
            onBack = onBack
        )
        SettingsDestination.CLOUD_SYNC -> CloudSyncScreen(vm, back)
        SettingsDestination.CACHE -> CacheManagerScreen(vm, back)
        SettingsDestination.DOWNLOADS -> DownloadManagerScreen(vm, back)
        else -> DetailPage(title = top.title, onBack = back) {
            val state by vm.ui.collectAsState()
            val s = state.settings
            when (top) {
                SettingsDestination.PERSONALIZATION -> PersonalizationSettings(vm, s)
                SettingsDestination.AUDIO_EFFECTS -> AudioEffectsSettingsContent(vm)
                SettingsDestination.PLAYBACK -> PlaybackSettings(vm, state.quality, s)
                SettingsDestination.STORAGE -> StorageSettings(vm, s, open)
                SettingsDestination.ACCOUNT -> AccountSettings { provider ->
                    vm.loadNcCookie()
                    cookieProvider = provider
                }
                SettingsDestination.ADVANCED -> AdvancedSettings(vm, LocalContext.current)
                else -> Unit
            }
        }
    }
}

/** 设置首页：按主题分组的入口。 */
@Composable
fun SettingsHome(
    conflicts: Int,
    onOpen: (SettingsDestination) -> Unit,
    onBack: () -> Unit
) {
    DetailPage(title = "设置", onBack = onBack) {
        SettingsSection(title = "外观") {
            SettingsTile(
                title = "主题与背景",
                subtitle = "壁纸、模糊、遮罩、控件透明度和界面缩放",
                icon = Icons.Outlined.Palette,
                onClick = { onOpen(SettingsDestination.PERSONALIZATION) }
            )
        }
        SettingsSection(title = "播放") {
            SettingsTile(
                title = "音效",
                subtitle = "均衡器、低音增强、环绕与混响",
                icon = Icons.Outlined.GraphicEq,
                onClick = { onOpen(SettingsDestination.AUDIO_EFFECTS) }
            )
            SettingsTile(
                title = "播放与歌词",
                subtitle = "默认音质、悬浮歌词",
                icon = Icons.Outlined.Subtitles,
                onClick = { onOpen(SettingsDestination.PLAYBACK) }
            )
        }
        SettingsSection(title = "数据与账号") {
            SettingsTile(
                title = "下载与存储",
                subtitle = "下载目录、歌曲缓存",
                icon = Icons.Outlined.Folder,
                onClick = { onOpen(SettingsDestination.STORAGE) }
            )
            SettingsTile(
                title = "云端同步",
                subtitle = if (conflicts > 0) "有 $conflicts 项两端都改过，需要选择方向"
                else "选择上传、拉取或合并，并设置自动同步",
                icon = Icons.Outlined.Cloud,
                onClick = { onOpen(SettingsDestination.CLOUD_SYNC) }
            )
            SettingsTile(
                title = "音乐平台 Cookie",
                subtitle = "手动管理网易云 / 酷狗登录",
                icon = Icons.Outlined.Key,
                onClick = { onOpen(SettingsDestination.ACCOUNT) }
            )
        }
        SettingsSection(title = "系统") {
            SettingsTile(
                title = "后台播放",
                subtitle = "电池优化与自启动",
                icon = Icons.Outlined.BatteryChargingFull,
                onClick = { onOpen(SettingsDestination.ADVANCED) }
            )
        }
    }
}

private fun percent(value: Float) = "${(value * 100).toInt()}%"

@Composable
private fun PersonalizationSettings(vm: PlayerViewModel, s: AppSettings) {
    SettingsSection(title = "布局") {
        SettingsSwitchTile(
            title = "横屏模式",
            subtitle = "全屏播放器固定为横屏布局（封面 + 歌词），平板会自动检测",
            checked = s.landscapeMode,
            onCheckedChange = vm::setLandscapeMode
        )
        SettingsSliderTile(
            title = "界面缩放",
            subtitle = "调整界面元素大小，适配小屏设备或视力需求",
            value = s.uiScale,
            valueLabel = percent(s.uiScale),
            onValueChange = vm::setUiScale,
            valueRange = 0.8f..1.3f,
            steps = 9
        )
    }
    SettingsSection(
        title = "全局背景",
        description = if (s.globalBgEnabled) "控件透明度只在壁纸背景下生效。" else null
    ) {
        SettingsSwitchTile(
            title = "壁纸背景",
            checked = s.globalBgEnabled,
            onCheckedChange = vm::setGlobalBgEnabled
        )
        if (s.globalBgEnabled) {
            SettingsTile(title = "换一张壁纸", onClick = { vm.refreshWallpaper(s.landscapeMode) })
            SettingsSliderTile(
                title = "遮罩明暗", value = s.globalMaskAlpha, valueLabel = percent(s.globalMaskAlpha),
                onValueChange = vm::setGlobalMaskAlpha, valueRange = 0f..0.9f
            )
            SettingsSliderTile(
                title = "模糊强度", value = s.globalBlurRadius.toFloat(), valueLabel = "${s.globalBlurRadius}px",
                onValueChange = { vm.setGlobalBlurRadius(it.toInt()) }, valueRange = 0f..40f
            )
            SettingsSliderTile(
                title = "控件不透明度", value = s.controlAlpha, valueLabel = percent(s.controlAlpha),
                onValueChange = vm::setControlAlpha
            )
        }
    }
    SettingsSection(title = "全屏播放器", description = "模糊仅在 Android 12 及以上生效。") {
        SettingsControlTile(title = "背景") {
            Row(horizontalArrangement = Arrangement.spacedBy(NekoSpace.sm)) {
                NekoChip("歌曲封面", s.fpBgSource == BgSource.COVER, { vm.setFpBgSource(BgSource.COVER) })
                NekoChip("壁纸", s.fpBgSource == BgSource.WALLPAPER, { vm.setFpBgSource(BgSource.WALLPAPER) })
            }
        }
        SettingsSliderTile(
            title = "遮罩明暗", value = s.fpMaskAlpha, valueLabel = percent(s.fpMaskAlpha),
            onValueChange = vm::setFpMaskAlpha, valueRange = 0f..0.9f
        )
        SettingsSliderTile(
            title = "模糊强度", value = s.fpBlurRadius.toFloat(), valueLabel = "${s.fpBlurRadius}px",
            onValueChange = { vm.setFpBlurRadius(it.toInt()) }, valueRange = 0f..40f
        )
    }
}

private val QualityLevels = listOf(
    "standard" to "标准", "higher" to "较高", "exhigh" to "极高",
    "lossless" to "无损 SQ", "hires" to "Hi-Res", "jyeffect" to "高清臻音",
    "sky" to "沉浸环绕声", "jymaster" to "超清母带", "dolby" to "臻音全景声"
)

@Composable
private fun PlaybackSettings(vm: PlayerViewModel, quality: String, s: AppSettings) {
    SettingsSection(
        title = "默认播放音质",
        description = "每首歌先查询可用音质；支持默认档位时优先使用，否则选择当前账号可播放的最高档位。下载另行核验下载权限。"
    ) {
        QualityLevels.forEach { (value, label) ->
            SettingsTile(
                title = label,
                modifier = Modifier.selectable(
                    selected = quality == value,
                    role = Role.RadioButton,
                    onClick = { vm.setQuality(value) }
                ),
                trailing = { RadioButton(selected = quality == value, onClick = null) }
            )
        }
    }
    SettingsSection(title = "悬浮歌词", description = "在全屏播放器中点「悬浮词」开启，这里的设置即时生效。") {
        SettingsSwitchTile(
            title = "双行显示",
            subtitle = "同时显示当前行与翻译或下一行",
            checked = s.floatingLyricDoubleRow,
            onCheckedChange = vm::setFloatingLyricDoubleRow
        )
        SettingsSwitchTile(
            title = "显示翻译",
            subtitle = "外语歌曲显示翻译行（需歌词含翻译）",
            checked = s.floatingLyricShowTranslation,
            onCheckedChange = vm::setFloatingLyricShowTranslation
        )
    }
}

@Composable
private fun StorageSettings(
    vm: PlayerViewModel,
    s: AppSettings,
    open: (SettingsDestination) -> Unit
) {
    val context = LocalContext.current
    val dirPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri: Uri? ->
        if (uri != null) {
            runCatching {
                context.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            }
            vm.setDownloadDir(uri.toString())
        }
    }
    SettingsSection(title = "下载") {
        SettingsTile(
            title = "下载目录",
            value = if (s.downloadDirUri.isBlank()) "音乐/NekoPlayer"
            else Uri.parse(s.downloadDirUri).lastPathSegment ?: s.downloadDirUri,
            onClick = { dirPicker.launch(null) }
        )
        if (s.downloadDirUri.isNotBlank()) {
            SettingsTile(title = "恢复默认目录", onClick = { vm.setDownloadDir("") })
        }
        SettingsTile(title = "下载管理", onClick = { open(SettingsDestination.DOWNLOADS) })
    }
    SettingsSection(title = "歌曲缓存") {
        SettingsSwitchTile(
            title = "缓存播放过的歌曲",
            subtitle = "没有网络时仍可播放",
            checked = s.cacheEnabled,
            onCheckedChange = vm::setCacheEnabled
        )
        SettingsTile(
            title = "管理已缓存音乐",
            onClick = { vm.refreshCacheList(); open(SettingsDestination.CACHE) }
        )
    }
}

@Composable
private fun AccountSettings(onOpenCookies: (String) -> Unit) {
    SettingsSection(
        description = "Cookie 用于获取账号权限内的歌曲和音质。扫码登录入口在「我的」页；多端同步请使用「云端同步」。"
    ) {
        SettingsTile(title = "网易云音乐 Cookie", icon = Icons.Outlined.LibraryMusic, onClick = { onOpenCookies("netease") })
        SettingsTile(title = "酷狗音乐 Cookie", subtitle = "原版与概念版分别保存", icon = Icons.Outlined.LibraryMusic, onClick = { onOpenCookies("kugou") })
    }
}

@Composable
private fun AdvancedSettings(vm: PlayerViewModel, context: Context) {
    SettingsSection(
        title = "电池优化",
        description = "允许应用忽略电池优化，防止系统在后台暂停播放。部分机型长时间熄屏后仍可能结束播放，请同时设置自启动白名单。"
    ) {
        SettingsTile(title = "申请电池优化豁免", onClick = { vm.requestIgnoreBatteryOptimizations(context) })
    }
    InlineNotice(
        "MIUI、ColorOS、HarmonyOS 等系统需要手动允许自启动：系统设置 → 应用管理 → NekoPlayer → 自启动 / 后台限制。"
    )
}

// ========== 缓存管理页面 ==========
@Composable
fun CacheManagerScreen(vm: PlayerViewModel, onBack: () -> Unit) {
    val state by vm.ui.collectAsState()
    val cacheList = state.cachedItems
    val selected = state.selectedCacheKeys
    val allSelected = selected.size == cacheList.size && cacheList.isNotEmpty()
    var showClearConfirm by remember { mutableStateOf(false) }

    if (showClearConfirm) {
        AlertDialog(
            onDismissRequest = { showClearConfirm = false },
            title = { Text("清空全部缓存？") },
            text = { Text("将删除全部缓存音乐，此操作不可撤销。") },
            confirmButton = {
                TextButton(
                    onClick = { vm.clearAllCache(); showClearConfirm = false },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)
                ) { Text("清空") }
            },
            dismissButton = {
                TextButton(onClick = { showClearConfirm = false }, colors = NekoDefaults.textButtonColors()) { Text("取消") }
            }
        )
    }

    Column(Modifier.fillMaxSize()) {
        DetailTopBar(title = "缓存管理", onBack = onBack) {
            if (cacheList.isNotEmpty()) {
                IconButton(onClick = {
                    if (allSelected) cacheList.forEach { vm.toggleCacheSelect(it.key) } else vm.selectAllCache()
                }) {
                    Icon(
                        if (allSelected) Icons.Default.CheckBox else Icons.Default.CheckBoxOutlineBlank,
                        contentDescription = if (allSelected) "取消全选" else "全选"
                    )
                }
                if (selected.isNotEmpty()) {
                    IconButton(onClick = vm::clearSelectedCache) {
                        Icon(Icons.Default.DeleteSweep, contentDescription = "删除选中")
                    }
                }
                IconButton(onClick = { showClearConfirm = true }) {
                    Icon(Icons.Default.DeleteForever, contentDescription = "清空全部")
                }
            }
        }
        if (cacheList.isEmpty()) {
            EmptyState(Icons.Default.DeleteSweep, "没有缓存的歌曲", description = "开启歌曲缓存后，播放过的歌曲会保存在这里。")
        } else {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = NekoSpace.xl)) {
                items(cacheList, key = { it.key }) { item ->
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .clickable { vm.toggleCacheSelect(item.key) }
                            .padding(horizontal = NekoSpace.lg, vertical = NekoSpace.sm),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(NekoSpace.md)
                    ) {
                        Artwork(item.song?.pc, size = 44.dp)
                        Column(Modifier.weight(1f)) {
                            Text(item.song?.nm ?: "未知歌曲", maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(
                                item.song?.ar ?: item.key,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1, overflow = TextOverflow.Ellipsis
                            )
                        }
                        Checkbox(checked = item.key in selected, onCheckedChange = { vm.toggleCacheSelect(item.key) })
                    }
                }
            }
        }
    }
}

// ========== Cookie 管理页面 ==========
@Composable
fun CookieManagerScreen(vm: PlayerViewModel, initialProvider: String = "netease", onBack: () -> Unit) {
    val state by vm.ui.collectAsState()
    var ncCookieText by remember { mutableStateOf(state.ncCookie) }
    var provider by remember { mutableStateOf(initialProvider) }
    val providers = listOf("netease" to "网易云音乐", "kugou" to "酷狗音乐")

    LaunchedEffect(Unit) { vm.loadNcCookie() }
    LaunchedEffect(state.ncCookie) { ncCookieText = state.ncCookie }

    DetailPage(title = "Cookie 管理", onBack = onBack) {
        ChipRow(
            items = providers,
            selected = providers.first { it.first == provider },
            label = { it.second },
            onSelect = { provider = it.first },
            contentPadding = PaddingValues(0.dp)
        )
        if (provider == "kugou") {
            KugouCookieEditor(vm)
        } else {
            InlineNotice(
                if (state.ncCookie.isNotEmpty()) "已设置网易云 Cookie。" else "未设置 Cookie，将以游客身份访问。"
            )
            Column(verticalArrangement = Arrangement.spacedBy(NekoSpace.sm)) {
                Text(
                    "在网页版网易云音乐登录后，从浏览器开发者工具复制请求头中的 Cookie 粘贴到这里，可获取更高音质和完整歌曲。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                OutlinedTextField(
                    value = ncCookieText,
                    onValueChange = { ncCookieText = it },
                    label = { Text("网易云 Cookie") },
                    modifier = Modifier.fillMaxWidth().height(160.dp),
                    maxLines = 6,
                    colors = NekoDefaults.textFieldColors()
                )
                if (ncCookieText.length > 200) {
                    Text(
                        "共 ${ncCookieText.length} 个字符",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(NekoSpace.sm)) {
                    Button(onClick = { vm.saveNcCookie(ncCookieText) }, modifier = Modifier.weight(1f)) { Text("保存") }
                    OutlinedButton(
                        onClick = { ncCookieText = ""; vm.saveNcCookie("") },
                        colors = NekoDefaults.outlinedButtonColors()
                    ) { Text("清除") }
                }
            }
        }
    }
}
