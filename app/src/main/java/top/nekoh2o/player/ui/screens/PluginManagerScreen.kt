package top.nekoh2o.player.ui.screens

import top.nekoh2o.player.i18n.NekoI18n.tr

import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.serialization.json.*
import top.nekoh2o.player.data.plugins.MusicPlugin
import top.nekoh2o.player.ui.components.DetailTopBar
import top.nekoh2o.player.ui.components.NekoChip
import top.nekoh2o.player.ui.components.PageContentPadding
import top.nekoh2o.player.ui.components.SettingsSection
import top.nekoh2o.player.ui.components.SettingsSwitchTile
import top.nekoh2o.player.ui.components.SettingsTile
import top.nekoh2o.player.ui.theme.NekoDefaults
import top.nekoh2o.player.ui.theme.NekoSpace
import top.nekoh2o.player.ui.viewmodel.PluginManagerViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PluginManagerScreen(onBack: () -> Unit, manager: PluginManagerViewModel = viewModel()) {
    val state by manager.plugins.collectAsState()
    val status by manager.status.collectAsState()
    var location by rememberSaveable { mutableStateOf("") }
    var format by rememberSaveable { mutableStateOf("auto") }
    var configuring by remember { mutableStateOf<MusicPlugin?>(null) }
    var deleting by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val snackbar = remember { SnackbarHostState() }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            runCatching { context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
            manager.import(uri.toString(), format)
        }
    }
    BackHandler(onBack = onBack)
    LaunchedEffect(status.message) {
        status.message?.let { snackbar.showSnackbar(it); manager.dismissMessage() }
    }
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            DetailTopBar(tr("音源与订阅"), onBack)
            LazyColumn(
                Modifier.fillMaxSize(),
                contentPadding = PageContentPadding,
                verticalArrangement = Arrangement.spacedBy(NekoSpace.xl)
            ) {
                item {
                    SettingsSection(
                        title = tr("添加订阅或脚本"),
                        description = tr("支持 Animemusic、MusicFree / Baka CommonJS 和 LX。LX 通过已启用的对应 Animemusic 来源搜索。")
                    ) {
                        Column(
                            Modifier.padding(NekoSpace.lg),
                            verticalArrangement = Arrangement.spacedBy(NekoSpace.md)
                        ) {
                            OutlinedTextField(
                                location, { location = it }, label = { Text(tr("订阅 JSON / 单脚本地址")) },
                                singleLine = true, modifier = Modifier.fillMaxWidth(), enabled = !status.busy,
                                colors = NekoDefaults.textFieldColors()
                            )
                            Row(horizontalArrangement = Arrangement.spacedBy(NekoSpace.sm)) {
                                listOf("auto" to tr("自动"), "musicfree" to "MusicFree", "baka" to "Baka", "lx" to "LX").forEach { (value, label) ->
                                    NekoChip(label, format == value, { if (!status.busy) format = value })
                                }
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(NekoSpace.sm)) {
                                Button(
                                    onClick = { manager.import(location.trim(), format) },
                                    enabled = !status.loading && !status.busy && location.isNotBlank()
                                ) { Text(tr("导入地址")) }
                                OutlinedButton(
                                    onClick = { picker.launch(arrayOf("*/*")) },
                                    enabled = !status.loading && !status.busy,
                                    colors = NekoDefaults.outlinedButtonColors()
                                ) { Text(tr("选择本地文件")) }
                            }
                            if (status.busy || status.loading) LinearProgressIndicator(Modifier.fillMaxWidth())
                        }
                    }
                }
                items(state.subscriptions, key = { it.id }) { subscription ->
                    SettingsSection(
                        title = subscription.name,
                        description = subscription.location.ifBlank { null }
                    ) {
                        SettingsSwitchTile(
                            title = tr("启用订阅"),
                            subtitle = if (subscription.builtIn) tr("内置 · 免登录") else tr("外部订阅 / 脚本"),
                            checked = subscription.enabled,
                            onCheckedChange = { manager.enableSubscription(subscription.id, it) },
                            enabled = !status.busy
                        )
                        state.plugins.filter { it.subscriptionId == subscription.id }.forEach { plugin ->
                            SettingsSwitchTile(
                                title = plugin.name,
                                subtitle = tr("{format} · {version}", "format" to plugin.format, "version" to plugin.version.ifBlank { tr("未标注版本") }),
                                checked = plugin.enabled,
                                onCheckedChange = { manager.enablePlugin(plugin.id, it) },
                                enabled = !status.busy && subscription.enabled
                            )
                            if (plugin.format != "animemusic/1") {
                                SettingsTile(title = tr("配置 {name} 的变量", "name" to plugin.name), enabled = !status.busy, onClick = { configuring = plugin })
                            }
                        }
                        Row(Modifier.padding(horizontal = NekoSpace.sm)) {
                            TextButton(onClick = { manager.update(subscription.id) }, enabled = !status.busy) { Text(tr("更新")) }
                            if (!subscription.builtIn) TextButton(
                                onClick = { deleting = subscription.id },
                                enabled = !status.busy,
                                colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)
                            ) { Text(tr("删除")) }
                        }
                    }
                }
            }
        }
        SnackbarHost(snackbar, Modifier.align(Alignment.BottomCenter))
    }
    deleting?.let { id ->
        AlertDialog(onDismissRequest = { deleting = null }, title = { Text(tr("删除外部订阅？")) },
            text = { Text(tr("将移除订阅内的音源及配置。歌单中的歌曲仍会保留。")) },
            confirmButton = { TextButton(onClick = { manager.delete(id); deleting = null }) { Text(tr("删除")) } },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text(tr("取消")) } })
    }
    configuring?.let { plugin -> PluginVariablesDialog(plugin, onDismiss = { configuring = null }) { values ->
        manager.configure(plugin.id, values); configuring = null
    } }
}

@Composable
private fun PluginVariablesDialog(plugin: MusicPlugin, onDismiss: () -> Unit, onSave: (JsonObject) -> Unit) {
    val declared = (plugin.descriptor["userVariables"] as? JsonArray).orEmpty().filterIsInstance<JsonObject>()
    var text by remember(plugin.id) { mutableStateOf(plugin.variables.toString()) }
    val values = remember(plugin.id) { mutableStateMapOf<String, String>().apply {
        declared.forEach { item ->
            val key = (item["key"] as? JsonPrimitive)?.contentOrNull.orEmpty()
            if (key.isNotBlank()) put(key, (plugin.variables[key] as? JsonPrimitive)?.contentOrNull.orEmpty())
        }
    } }
    var invalid by remember { mutableStateOf(false) }
    AlertDialog(onDismissRequest = onDismiss, title = { Text(tr("{name} · 变量", "name" to plugin.name)) }, text = {
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (declared.isEmpty()) {
                OutlinedTextField(text, { text = it; invalid = false }, label = { Text(tr("变量 JSON 对象")) }, isError = invalid)
            } else declared.forEach { variable ->
                val key = (variable["key"] as? JsonPrimitive)?.contentOrNull.orEmpty()
                if (key.isNotBlank()) OutlinedTextField(values[key].orEmpty(), { values[key] = it },
                    label = { Text((variable["name"] as? JsonPrimitive)?.contentOrNull ?: key) },
                    supportingText = { Text((variable["hint"] as? JsonPrimitive)?.contentOrNull.orEmpty()) },
                    visualTransformation = PasswordVisualTransformation(), singleLine = true)
            }
            if (invalid) Text(tr("请输入有效的 JSON 对象"), color = MaterialTheme.colorScheme.error)
        }
    }, confirmButton = { TextButton(onClick = {
        val result = if (declared.isEmpty()) runCatching { Json.parseToJsonElement(text).jsonObject }.getOrNull()
            else buildJsonObject { plugin.variables.forEach { (key, value) -> put(key, value) }; values.forEach { (key, value) -> put(key, value) } }
        if (result == null) invalid = true else onSave(result)
    }) { Text(tr("保存")) } }, dismissButton = { TextButton(onClick = onDismiss) { Text(tr("取消")) } })
}
