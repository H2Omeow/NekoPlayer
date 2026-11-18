package top.nekoh2o.player.ui.screens.cloud

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.outlined.CloudUpload
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.Image
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import top.nekoh2o.player.data.cloud.CloudApi
import top.nekoh2o.player.data.social.SendMessageRequest
import top.nekoh2o.player.data.social.SocialConversation
import top.nekoh2o.player.data.social.SocialRepository
import java.util.UUID
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material.icons.filled.Person
import top.nekoh2o.player.i18n.NekoI18n.tr
import top.nekoh2o.player.ui.components.DetailTopBar
import top.nekoh2o.player.ui.theme.NekoRadius
import top.nekoh2o.player.ui.theme.NekoSpace

private enum class CloudTab(private val raw: String) {
    FILES("文件"),
    QUOTA("额度"),
    SPONSOR("赞赏");

    val label: String get() = tr(raw)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CloudFilesScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val social = remember { SocialRepository() }
    var tab by remember { mutableStateOf(CloudTab.FILES) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var needSkland by remember { mutableStateOf(false) }
    var files by remember { mutableStateOf(JsonArray(emptyList())) }
    var quota by remember { mutableStateOf<JsonObject?>(null) }
    var usage by remember { mutableStateOf<JsonObject?>(null) }
    var uploadProgress by remember { mutableStateOf<Float?>(null) }
    var showSkland by remember { mutableStateOf(false) }
    var shareTarget by remember { mutableStateOf<JsonObject?>(null) }
    var notifications by remember { mutableStateOf(JsonArray(emptyList())) }
    var unread by remember { mutableStateOf(0) }
    var showNotices by remember { mutableStateOf(false) }
    var pendingShare by remember { mutableStateOf<String?>(null) }
    var pendingName by remember { mutableStateOf("") }
    var showFriendPicker by remember { mutableStateOf(false) }

    suspend fun reload() {
        loading = true
        error = null
        try {
            val root = CloudApi.files()
            files = CloudApi.filesOf(root)
            quota = root["quota"] as? JsonObject
            usage = root["usage"] as? JsonObject
            needSkland = false
            runCatching { CloudApi.notifications() }.onSuccess { n ->
                notifications = n["data"] as? JsonArray ?: JsonArray(emptyList())
                unread = n["unread"]?.jsonPrimitive?.content?.toIntOrNull() ?: 0
            }
        } catch (e: CloudApi.CloudException) {
            needSkland = e.needSkland
            error = if (e.needSkland) null else e.message
        } catch (e: Throwable) {
            error = e.message ?: tr("加载失败")
        } finally {
            loading = false
        }
    }

    LaunchedEffect(Unit) { reload() }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val (name, size) = queryNameAndSize(context, uri)
            uploadProgress = 0f
            try {
                CloudApi.upload(context, uri, name, size, guessCategory(name), { p -> uploadProgress = p })
                uploadProgress = null
                reload()
            } catch (e: CloudApi.CloudException) {
                uploadProgress = null
                needSkland = e.needSkland
                if (!e.needSkland) error = e.message
            } catch (e: Throwable) {
                uploadProgress = null
                error = e.message ?: tr("上传失败")
            }
        }
    }

    Column(Modifier.fillMaxSize()) {
        DetailTopBar(tr("云存储"), onBack, actions = {
            Box {
                IconButton(onClick = { showNotices = true }) {
                    Icon(Icons.Outlined.Notifications, contentDescription = tr("消息"))
                }
                if (unread > 0) {
                    Box(
                        Modifier.align(Alignment.TopEnd).padding(top = 8.dp, end = 6.dp)
                            .size(8.dp)
                            .background(MaterialTheme.colorScheme.error, RoundedCornerShape(50))
                    )
                }
            }
            IconButton(onClick = { picker.launch(arrayOf("*/*")) }) {
                Icon(Icons.Outlined.CloudUpload, contentDescription = tr("上传"))
            }
        })

        TabRow(selectedTabIndex = tab.ordinal) {
            CloudTab.entries.forEach { item ->
                Tab(selected = tab == item, onClick = { tab = item }, text = { Text(item.label) })
            }
        }

        when {
            needSkland -> SklandGate(onBind = { showSkland = true }, modifier = Modifier.fillMaxSize())
            loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            error != null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(error!!, color = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.height(NekoSpace.md))
                    OutlinedButton(onClick = { scope.launch { reload() } }) { Text(tr("重试")) }
                }
            }
            else -> when (tab) {
                CloudTab.FILES -> FilesTab(
                    files = files,
                    quota = quota,
                    usage = usage,
                    uploadProgress = uploadProgress,
                    onUpload = { picker.launch(arrayOf("*/*")) },
                    onDelete = { id -> scope.launch { runCatching { CloudApi.delete(id) }; reload() } },
                    onShare = { item -> shareTarget = item }
                )
                CloudTab.QUOTA -> QuotaTab(quota, usage)
                CloudTab.SPONSOR -> SponsorTab(scope, onChanged = { scope.launch { reload() } })
            }
        }
    }

    if (showNotices) {
        AlertDialog(
            onDismissRequest = { showNotices = false },
            title = { Text(tr("消息")) },
            text = {
                Column {
                    if (notifications.isEmpty()) {
                        Text(tr("暂时没有新消息"), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    } else {
                        notifications.take(20).forEach { el ->
                            val item = el as JsonObject
                            Text(
                                item["title"]?.jsonPrimitive?.content ?: "",
                                fontWeight = FontWeight.SemiBold
                            )
                            Text(
                                item["body"]?.jsonPrimitive?.content ?: "",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Spacer(Modifier.height(NekoSpace.sm))
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    showNotices = false
                    scope.launch { runCatching { CloudApi.markNotificationsRead() }; reload() }
                }) { Text(tr("全部已读")) }
            },
            dismissButton = { TextButton(onClick = { showNotices = false }) { Text(tr("关闭")) } }
        )
    }

    if (showSkland) {
        SklandBindDialog(onDismiss = { showSkland = false }, onBound = {
            showSkland = false
            scope.launch { reload() }
        })
    }

    shareTarget?.let { item ->
        ShareDialog(
            item = item,
            onDismiss = { shareTarget = null },
            onShare = { mode, days ->
                scope.launch {
                    runCatching { CloudApi.share(item["id"]!!.jsonPrimitive.content, mode, days) }
                        .onSuccess {
                            pendingShare = it["token"]?.jsonPrimitive?.content
                            pendingName = item["name"]?.jsonPrimitive?.content ?: tr("文件")
                        }
                    shareTarget = null
                    reload()
                }
            }
        )
    }
    pendingShare?.let { token ->
        val base = "https://player.nekoh2o.top/s/$token"
        AlertDialog(
            onDismissRequest = { pendingShare = null },
            title = { Text(tr("分享链接已生成")) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(base)
                    Text(
                        tr("直链不需要登录即可下载，流量按分享者计算。"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            },
            confirmButton = {
                Row {
                    TextButton(onClick = { showFriendPicker = true }) { Text(tr("发送给好友")) }
                    TextButton(onClick = { pendingShare = null }) { Text(tr("完成")) }
                }
            }
        )
    }
    if (showFriendPicker && pendingShare != null) {
        FriendPickerDialog(
            onDismiss = { showFriendPicker = false },
            onPick = { peerId, peerName ->
                val link = "https://player.nekoh2o.top/s/$pendingShare"
                scope.launch {
                    runCatching {
                        social.sendMessage(
                            SendMessageRequest(
                                to = peerId,
                                kind = "text",
                                body = tr("分享了一个文件给你：") + pendingName + "\n" + link,
                                clientId = UUID.randomUUID().toString()
                            )
                        )
                    }.onSuccess {
                        showFriendPicker = false
                        pendingShare = null
                        android.widget.Toast.makeText(
                            context, tr("已发送给") + peerName, android.widget.Toast.LENGTH_SHORT
                        ).show()
                    }
                }
            }
        )
    }
}

@Composable
private fun FriendPickerDialog(
    onDismiss: () -> Unit,
    onPick: (peerId: String, peerName: String) -> Unit
) {
    val repo = remember { SocialRepository() }
    var loading by remember { mutableStateOf(true) }
    var conversations by remember { mutableStateOf<List<SocialConversation>>(emptyList()) }
    LaunchedEffect(Unit) {
        runCatching { repo.conversations() }.onSuccess { conversations = it }
        loading = false
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(tr("发送给好友")) },
        text = {
            when {
                loading -> Box(Modifier.fillMaxWidth().padding(NekoSpace.lg), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                conversations.isEmpty() -> Text(tr("还没有可以发消息的好友，先去「社区」关注或搜索朋友。"))
                else -> LazyColumn(Modifier.heightIn(max = 340.dp)) {
                    items(conversations, key = { it.id }) { conversation ->
                        val name = conversation.peer?.displayName ?: tr("用户")
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .clickable { onPick(conversation.peerId, name) }
                                .padding(horizontal = NekoSpace.xs, vertical = NekoSpace.sm),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                Icons.Filled.Person,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Spacer(Modifier.width(NekoSpace.sm))
                            Text(name, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text(tr("取消")) } }
    )
}

@Composable
private fun FilesTab(
    files: JsonArray,
    quota: JsonObject?,
    usage: JsonObject?,
    uploadProgress: Float?,
    onUpload: () -> Unit,
    onDelete: (String) -> Unit,
    onShare: (JsonObject) -> Unit
) {
    LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(NekoSpace.lg)) {
        item { QuotaHeader(quota, usage) }
        if (uploadProgress != null) {
            item {
                Column(Modifier.padding(top = NekoSpace.md)) {
                    Text(tr("上传中") + " " + ((uploadProgress * 100).toInt()) + "%", style = MaterialTheme.typography.labelMedium)
                    LinearProgressIndicator(progress = { uploadProgress }, modifier = Modifier.fillMaxWidth().height(6.dp))
                }
            }
        }
        if (files.isEmpty()) {
            item {
                Column(Modifier.fillMaxWidth().padding(top = 60.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(tr("还没有上传任何文件"), style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(NekoSpace.sm))
                    Text(tr("视频最多 50MB，图片 5MB，音乐 25MB，自定义文件 1GB"), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(NekoSpace.lg))
                    Button(onClick = onUpload) { Text(tr("上传文件")) }
                }
            }
        }
        items(files.toList()) { element ->
            val item = element as JsonObject
            FileRow(item, onDelete = { onDelete(item["id"]!!.jsonPrimitive.content) }, onShare = { onShare(item) })
        }
    }
}

@Composable
private fun FileRow(item: JsonObject, onDelete: () -> Unit, onShare: () -> Unit) {
    val name = item["name"]?.jsonPrimitive?.content ?: ""
    val size = item["size"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0L
    val created = item["created_at"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0L
    Card(
        modifier = Modifier.fillMaxWidth().padding(top = NekoSpace.sm),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)
    ) {
        Row(Modifier.padding(NekoSpace.md), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(name, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.SemiBold)
                Text(
                    formatBytes(size) + " · " + formatDate(created),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            IconButton(onClick = onShare) { Icon(Icons.Filled.Share, contentDescription = tr("分享")) }
            IconButton(onClick = onDelete) { Icon(Icons.Filled.Delete, contentDescription = tr("删除")) }
        }
    }
}

@Composable
private fun QuotaHeader(quota: JsonObject?, usage: JsonObject?) {
    val storageTotal = quota?.get("storageBytes")?.jsonPrimitive?.content?.toLongOrNull() ?: 0L
    val trafficTotal = quota?.get("trafficBytes")?.jsonPrimitive?.content?.toLongOrNull() ?: 0L
    val storageUsed = usage?.get("storage_bytes")?.jsonPrimitive?.content?.toLongOrNull() ?: 0L
    val trafficUsed = usage?.get("traffic_bytes")?.jsonPrimitive?.content?.toLongOrNull() ?: 0L
    val count = usage?.get("files_count")?.jsonPrimitive?.content?.toLongOrNull() ?: 0L

    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
        Column(Modifier.padding(NekoSpace.md)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(tr("存储"), style = MaterialTheme.typography.labelMedium)
                Text("${formatBytes(storageUsed)} / ${if (storageTotal > 0) formatBytes(storageTotal) else "∞"}")
            }
            LinearProgressIndicator(
                progress = { if (storageTotal > 0) (storageUsed.toFloat() / storageTotal).coerceIn(0f, 1f) else 0f },
                modifier = Modifier.fillMaxWidth().padding(top = 6.dp).height(6.dp)
            )
            Spacer(Modifier.height(NekoSpace.sm))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(tr("本月流量"), style = MaterialTheme.typography.labelMedium)
                Text("${formatBytes(trafficUsed)} / ${if (trafficTotal > 0) formatBytes(trafficTotal) else "∞"}")
            }
            LinearProgressIndicator(
                progress = { if (trafficTotal > 0) (trafficUsed.toFloat() / trafficTotal).coerceIn(0f, 1f) else 0f },
                modifier = Modifier.fillMaxWidth().padding(top = 6.dp).height(6.dp)
            )
            Spacer(Modifier.height(NekoSpace.sm))
            Text(tr("文件数") + " " + count, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun QuotaTab(quota: JsonObject?, usage: JsonObject?) {
    val rows = listOf(
        tr("总存储") to (quota?.get("storageBytes")?.jsonPrimitive?.content?.toLongOrNull()?.let(::formatBytes) ?: "∞"),
        tr("月流量") to (quota?.get("trafficBytes")?.jsonPrimitive?.content?.toLongOrNull()?.let(::formatBytes) ?: "∞"),
        tr("文件份数") to ((quota?.get("fileCount")?.jsonPrimitive?.content?.toIntOrNull() ?: 0).let { if (it > 0) it.toString() else tr("不限") }),
        tr("视频上限") to (quota?.get("maxVideo")?.jsonPrimitive?.content?.toLongOrNull()?.let(::formatBytes) ?: tr("不限")),
        tr("图片上限") to (quota?.get("maxImage")?.jsonPrimitive?.content?.toLongOrNull()?.let(::formatBytes) ?: tr("不限")),
        tr("音乐上限") to (quota?.get("maxAudio")?.jsonPrimitive?.content?.toLongOrNull()?.let(::formatBytes) ?: tr("不限")),
        tr("自定义上限") to (quota?.get("maxCustom")?.jsonPrimitive?.content?.toLongOrNull()?.let(::formatBytes) ?: tr("不限"))
    )
    LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(NekoSpace.lg)) {
        item { QuotaHeader(quota, usage) }
        item {
            Spacer(Modifier.height(NekoSpace.lg))
            Text(tr("额度规则"), style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(NekoSpace.sm))
        }
        items(rows) { (k, v) ->
            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(k, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(v, fontWeight = FontWeight.Medium)
            }
        }
        item {
            Spacer(Modifier.height(NekoSpace.lg))
            Text(
                tr("免费用户超过 180 天未登录会清理上传的文件（歌单、收藏、播放记录不受影响），清理前 7 天会在消息里提醒。分享和下载消耗分享者的流量，应用内下载减半。"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun SponsorTab(scope: kotlinx.coroutines.CoroutineScope, onChanged: () -> Unit) {
    var tiers by remember { mutableStateOf<List<Pair<String, JsonObject>>>(emptyList()) }
    var orders by remember { mutableStateOf<JsonArray?>(null) }
    val context = LocalContext.current
    var receiptFor by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        runCatching { CloudApi.pricing() }.onSuccess { body ->
            val map = body["tiers"] as? JsonObject
            tiers = map?.entries
                ?.filter { it.key != "free" }
                ?.mapNotNull { (key, value) -> (value as? JsonObject)?.let { key to it } }
                ?: emptyList()
        }
        runCatching { CloudApi.myOrders() }.onSuccess { orders = it["data"] as? JsonArray ?: (it["orders"] as? JsonArray) }
    }

    val receiptPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        val orderId = receiptFor
        if (uri != null && orderId != null) {
            scope.launch {
                val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                val mime = context.contentResolver.getType(uri) ?: "image/jpeg"
                if (bytes != null) {
                    runCatching { CloudApi.uploadReceipt(orderId, bytes, mime) }
                    onChanged()
                }
            }
        }
        receiptFor = null
    }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(NekoSpace.lg)) {
        item {
            Text(tr("赞赏 NekoPlayer"), style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.height(NekoSpace.xs))
            Text(
                tr("赞赏后不限文件份数、单文件大小，存储 32.5G / 月流量 50G，且文件永不清理。支付后上传截图，人工核对后开通。"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.height(NekoSpace.lg))
        }
        items(tiers) { (id, tier) ->
            val label = tier["label"]?.jsonPrimitive?.content ?: ""
            val price = tier["price"]?.jsonPrimitive?.content ?: ""
            Card(
                modifier = Modifier.fillMaxWidth().padding(bottom = NekoSpace.sm),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)
            ) {
                Row(Modifier.padding(NekoSpace.md), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(label, fontWeight = FontWeight.SemiBold)
                        Text("¥$price / " + tr("月"), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Button(onClick = {
                        scope.launch {
                            runCatching { CloudApi.createOrder(id, 1) }
                                .onSuccess { receiptFor = it["id"]?.jsonPrimitive?.content; receiptPicker.launch(arrayOf("image/*")) }
                            onChanged()
                        }
                    }) { Text(tr("去赞赏")) }
                }
            }
        }
        item {
            Spacer(Modifier.height(NekoSpace.lg))
            Text(tr("我的订单"), style = MaterialTheme.typography.titleMedium)
        }
        items((orders ?: JsonArray(emptyList())).toList()) { el ->
            val order = el as JsonObject
            val status = order["status"]?.jsonPrimitive?.content ?: ""
            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                Column {
                    Text(order["id"]?.jsonPrimitive?.content ?: "")
                    Text(
                        (order["tier"]?.jsonPrimitive?.content ?: "") + " × " + (order["months"]?.jsonPrimitive?.content ?: "") + " " + tr("个月"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text(orderStatusLabel(status), fontWeight = FontWeight.Medium)
                    if (status == "pending") {
                        TextButton(onClick = { receiptFor = order["id"]!!.jsonPrimitive.content; receiptPicker.launch(arrayOf("image/*")) }) {
                            Text(tr("上传凭证"))
                        }
                    }
                }
            }
        }
    }
}

private fun orderStatusLabel(status: String): String = when (status) {
    "pending" -> tr("待审核")
    "approved" -> tr("已开通")
    "rejected" -> tr("已驳回")
    else -> status
}

@Composable
private fun SklandGate(onBind: () -> Unit, modifier: Modifier = Modifier) {
    Box(modifier, contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(NekoSpace.xl)) {
            Icon(Icons.Outlined.Info, contentDescription = null, modifier = Modifier.size(40.dp))
            Spacer(Modifier.height(NekoSpace.md))
            Text(tr("云存储需要绑定森空岛账号"), style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(NekoSpace.sm))
            Text(
                tr("绑定后用于确认账号归属，不会读取你的游戏数据。"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.height(NekoSpace.lg))
            Button(onClick = onBind) { Text(tr("去绑定")) }
        }
    }
}

@Composable
private fun SklandBindDialog(onDismiss: () -> Unit, onBound: () -> Unit) {
    var sid by remember { mutableStateOf<String?>(null) }
    var url by remember { mutableStateOf<String?>(null) }
    var state by remember { mutableStateOf("loading") }
    var message by remember { mutableStateOf("") }

    LaunchedEffect(Unit) {
        runCatching { CloudApi.sklandStart() }
            .onSuccess { sid = it["sid"]?.jsonPrimitive?.content; url = it["url"]?.jsonPrimitive?.content; state = "waiting" }
            .onFailure { state = "error"; message = it.message ?: "" }
    }

    LaunchedEffect(sid) {
        val key = sid ?: return@LaunchedEffect
        while (true) {
            delay(2000)
            val res = runCatching { CloudApi.sklandPoll(key) }.getOrNull() ?: continue
            when (res["state"]?.jsonPrimitive?.content) {
                "waiting" -> state = "waiting"
                "scanned" -> state = "scanned"
                "ok" -> { state = "ok"; onBound(); return@LaunchedEffect }
                "expired" -> { state = "expired"; return@LaunchedEffect }
                "login_required" -> { state = "login_required"; return@LaunchedEffect }
            }
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(tr("绑定森空岛")) },
        text = {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                val bitmap = remember(url) { url?.let { qrBitmap(it) } }
                if (bitmap != null) {
                    Image(bitmap.asImageBitmap(), contentDescription = tr("二维码"), modifier = Modifier.size(200.dp), contentScale = ContentScale.Fit)
                } else {
                    CircularProgressIndicator(Modifier.size(40.dp))
                }
                Spacer(Modifier.height(NekoSpace.md))
                Text(
                    when (state) {
                        "scanned" -> tr("已扫码，请在手机上确认")
                        "expired" -> tr("二维码已失效，请重新打开")
                        "login_required" -> tr("请先在账户中心登录")
                        "error" -> message.ifBlank { tr("森空岛暂时不可用") }
                        else -> tr("打开森空岛 App 扫码")
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text(tr("关闭")) } }
    )
}

@Composable
private fun ShareDialog(item: JsonObject, onDismiss: () -> Unit, onShare: (String, Int) -> Unit) {
    var mode by remember { mutableStateOf("app") }
    var days by remember { mutableStateOf(7) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(tr("分享") + " " + (item["name"]?.jsonPrimitive?.content ?: "")) },
        text = {
            Column {
                Text(tr("分享方式"), style = MaterialTheme.typography.labelMedium)
                Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChipLike(selected = mode == "app", label = tr("应用内（流量减半）")) { mode = "app" }
                    FilterChipLike(selected = mode == "direct", label = tr("直链（免登录）")) { mode = "direct" }
                }
                Spacer(Modifier.height(NekoSpace.md))
                Text(tr("有效期") + " $days " + tr("天"), style = MaterialTheme.typography.labelMedium)
                Spacer(Modifier.height(4.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(1, 7, 30).forEach { d -> FilterChipLike(selected = days == d, label = "$d " + tr("天")) { days = d } }
                }
            }
        },
        confirmButton = { Button(onClick = { onShare(mode, days) }) { Text(tr("生成链接")) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(tr("取消")) } }
    )
}

@Composable
private fun FilterChipLike(selected: Boolean, label: String, onClick: () -> Unit) {
    FilledTonalButton(
        onClick = onClick,
        colors = androidx.compose.material3.ButtonDefaults.filledTonalButtonColors(
            containerColor = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainerHigh
        )
    ) { Text(label, style = MaterialTheme.typography.labelMedium) }
}

// ---------- 工具 ----------
private fun queryNameAndSize(context: Context, uri: Uri): Pair<String, Long> {
    var name = uri.lastPathSegment ?: "file"
    var size = 0L
    runCatching {
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
            if (cursor.moveToFirst()) {
                if (nameIdx >= 0) name = cursor.getString(nameIdx) ?: name
                if (sizeIdx >= 0) size = cursor.getLong(sizeIdx)
            }
        }
    }
    if (size == 0L) {
        size = runCatching {
            context.contentResolver.openInputStream(uri)?.use { it.available().toLong() } ?: 0L
        }.getOrDefault(0L)
    }
    return name to size
}

private fun guessCategory(name: String): String = when (name.substringAfterLast('.', "").lowercase()) {
    "mp4", "mkv", "webm", "mov", "avi" -> "video"
    "jpg", "jpeg", "png", "gif", "webp", "heic" -> "image"
    "mp3", "flac", "m4a", "wav", "ogg", "aac" -> "audio"
    else -> "custom"
}

fun formatBytes(bytes: Long): String {
    if (bytes <= 0) return "0B"
    val units = arrayOf("B", "KB", "MB", "GB", "TB")
    var value = bytes.toDouble()
    var index = 0
    while (value >= 1024 && index < units.lastIndex) {
        value /= 1024
        index++
    }
    return if (value >= 100 || index == 0) String.format("%.0f%s", value, units[index])
    else String.format("%.1f%s", value, units[index])
}

private fun formatDate(ms: Long): String {
    if (ms <= 0) return ""
    val fmt = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault())
    return fmt.format(java.util.Date(ms))
}

private fun qrBitmap(content: String, size: Int = 512): Bitmap {
    val matrix = QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, size, size)
    val pixels = IntArray(size * size)
    for (y in 0 until size) {
        for (x in 0 until size) {
            pixels[y * size + x] = if (matrix[x, y]) 0xFF000000.toInt() else 0xFFFFFFFF.toInt()
        }
    }
    return Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888).apply { setPixels(pixels, 0, size, 0, 0, size, size) }
}
