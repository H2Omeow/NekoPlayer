package top.nekoh2o.player.ui.screens.video

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.SearchOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import top.nekoh2o.player.data.bilibili.VideoItem
import top.nekoh2o.player.data.repo.VideoRepository
import top.nekoh2o.player.ui.theme.NekoSpace
import top.nekoh2o.player.i18n.NekoI18n.tr

private val ORDER_LABELS = listOf(tr("综合") to "totalrank", tr("最多播放") to "click", tr("最新发布") to "pubdate", tr("最多弹幕") to "dm")

@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun VideoSearchScreen(
    initialQuery: String,
    repo: VideoRepository,
    onBack: () -> Unit,
    onOpenVideo: (String) -> Unit
) {
    var query by remember { mutableStateOf(initialQuery) }
    var submitted by remember { mutableStateOf(initialQuery) }
    var order by remember { mutableStateOf("totalrank") }
    var results by remember { mutableStateOf<List<VideoItem>>(emptyList()) }
    var page by remember { mutableIntStateOf(1) }
    var hasMore by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var hotWords by remember { mutableStateOf<List<String>>(emptyList()) }
    val scope = rememberCoroutineScope()
    val keyboard = LocalSoftwareKeyboardController.current
    val focus = remember { FocusRequester() }

    suspend fun load(reset: Boolean) {
        loading = true
        error = null
        val target = if (reset) 1 else page + 1
        runCatching { repo.search(submitted, target, order) }
            .onSuccess { r ->
                results = if (reset) r.items else (results + r.items).distinctBy { it.bvid }
                page = target
                hasMore = r.hasMore && r.items.isNotEmpty()
            }
            .onFailure { error = it.message ?: tr("搜索失败") }
        loading = false
    }

    LaunchedEffect(Unit) {
        if (initialQuery.isBlank()) {
            hotWords = runCatching { repo.searchSquare() }.getOrDefault(emptyList())
        }
    }
    LaunchedEffect(submitted, order) {
        if (submitted.isNotBlank()) load(true)
    }

    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        Row(
            Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(horizontal = NekoSpace.sm, vertical = NekoSpace.sm),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.Filled.ArrowBack, tr("返回"), tint = MaterialTheme.colorScheme.onSurface)
            }
            TextField(
                value = query,
                onValueChange = { query = it },
                placeholder = { Text(tr("搜索视频、UP 主，或直接粘贴 BV 号"), style = MaterialTheme.typography.bodySmall) },
                leadingIcon = { Icon(Icons.Filled.Search, null, tint = MaterialTheme.colorScheme.onSurfaceVariant) },
                trailingIcon = {
                    if (query.isNotEmpty()) {
                        IconButton(onClick = { query = "" }) {
                            Icon(Icons.Filled.Close, tr("清除"), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                },
                singleLine = true,
                shape = RoundedCornerShape(50),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                    unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                    focusedIndicatorColor = androidx.compose.ui.graphics.Color.Transparent,
                    unfocusedIndicatorColor = androidx.compose.ui.graphics.Color.Transparent
                ),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = {
                    submitted = query.trim()
                    keyboard?.hide()
                }),
                modifier = Modifier.weight(1f).focusRequester(focus)
            )
        }

        LazyColumn(Modifier.fillMaxSize()) {
            if (submitted.isBlank()) {
                if (hotWords.isNotEmpty()) {
                    item {
                        Column(Modifier.padding(horizontal = NekoSpace.lg, vertical = NekoSpace.sm)) {
                            SectionHeader(tr("B 站热搜"))
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                hotWords.forEach { word ->
                                    Text(
                                        word,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                        modifier = Modifier
                                            .clip(RoundedCornerShape(50))
                                            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                                            .clickable { query = word; submitted = word }
                                            .padding(horizontal = 12.dp, vertical = 8.dp)
                                    )
                                }
                            }
                        }
                    }
                }
                item {
                    VideoEmptyState(
                        icon = Icons.Outlined.SearchOff,
                        title = tr("搜点什么"),
                        message = tr("支持关键词、UP 主名，也可以直接粘贴 BV 号")
                    )
                }
            } else {
                item {
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .padding(horizontal = NekoSpace.lg, vertical = 4.dp),
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        ORDER_LABELS.forEach { (label, value) ->
                            Text(
                                label,
                                style = MaterialTheme.typography.labelLarge,
                                color = if (order == value) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                                fontWeight = if (order == value) FontWeight.SemiBold else FontWeight.Normal,
                                modifier = Modifier
                                    .clip(RoundedCornerShape(8.dp))
                                    .clickable { order = value }
                                    .padding(horizontal = 10.dp, vertical = 8.dp)
                            )
                        }
                    }
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.15f))
                }
                items(results, key = { it.bvid }) { item ->
                    VideoListRow(
                        item,
                        onClick = { onOpenVideo(item.bvid) },
                        modifier = Modifier.padding(horizontal = NekoSpace.lg)
                    )
                }
                item {
                    Box(Modifier.fillMaxWidth().padding(NekoSpace.lg), contentAlignment = Alignment.Center) {
                        when {
                            loading -> CircularProgressIndicator(
                                color = MaterialTheme.colorScheme.primary,
                                strokeWidth = 2.dp,
                                modifier = Modifier.size(22.dp)
                            )
                            error != null -> TextButton(onClick = { scope.launch { load(true) } }) {
                                Text("加载失败，点击重试：$error")
                            }
                            results.isEmpty() -> Text(
                                tr("没有找到相关视频"),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            hasMore -> TextButton(onClick = { scope.launch { load(false) } }) { Text(tr("加载更多")) }
                            else -> Text(
                                tr("— 已经到底啦 —"),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }
        }
    }
}
