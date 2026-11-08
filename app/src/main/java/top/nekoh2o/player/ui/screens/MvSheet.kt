package top.nekoh2o.player.ui.screens

import top.nekoh2o.player.i18n.NekoI18n.tr

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.view.WindowManager
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import top.nekoh2o.player.data.repo.MusicVideo
import top.nekoh2o.player.data.repo.MvRepository

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MvSheet(source: String, initialQuery: String, onPauseMusic: () -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val repo = remember { MvRepository() }
    var query by remember { mutableStateOf(initialQuery) }
    var videos by remember { mutableStateOf<List<MusicVideo>>(emptyList()) }
    var url by remember { mutableStateOf<String?>(null) }
    var selected by remember { mutableStateOf<MusicVideo?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }
    var page by remember { mutableIntStateOf(1) }
    var more by remember { mutableStateOf(false) }
    val player = remember { ExoPlayer.Builder(context).build() }
    DisposableEffect(player) { onDispose { player.release() } }
    LaunchedEffect(url) { url?.let { onPauseMusic(); player.setMediaItem(MediaItem.fromUri(it)); player.prepare(); player.playWhenReady = true } }
    fun search(next: Boolean = false) {
        if (query.isBlank() || loading) return
        scope.launch {
            loading = true; error = null
            try {
                val currentPage = if (next) page + 1 else 1
                val found = withContext(Dispatchers.IO) { repo.search(source, query.trim(), currentPage) }
                videos = (if (next) videos + found else found).distinctBy { it.source + ":" + it.id }
                page = currentPage; more = found.size >= 30
            } catch (problem: Exception) { error = tr("内置插件 MV 搜索失败，请稍后重试") }
            finally { loading = false }
        }
    }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().padding(16.dp).heightIn(max = 700.dp)) {
            Text("MV", style = MaterialTheme.typography.headlineSmall)
            Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                OutlinedTextField(query, { query = it }, Modifier.weight(1f), singleLine = true, label = { Text(tr("搜索 MV")) })
                TextButton(onClick = { search() }, enabled = !loading) { Text(tr("搜索")) }
            }
            selected?.let { Text(it.title, Modifier.padding(vertical = 8.dp)) }
            if (url != null) AndroidView(factory = { PlayerView(it).apply { this.player = player; useController = true } },
                modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f), onRelease = { it.player = null })
            if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            LazyColumn(Modifier.fillMaxWidth().weight(1f, fill = false)) {
                items(videos, key = { it.source + ":" + it.id }) { video ->
                    TextButton(onClick = {
                        scope.launch {
                            loading = true; error = null
                            try { url = withContext(Dispatchers.IO) { repo.url(video) } ?: throw IllegalStateException(); selected = video }
                            catch (problem: Exception) { error = tr("暂无可播放 MV 链接") }
                            finally { loading = false }
                        }
                    }, enabled = !loading) { Column(Modifier.fillMaxWidth()) { Text(video.title); Text(video.artist, style = MaterialTheme.typography.bodySmall) } }
                }
                if (more) item { TextButton(onClick = { search(true) }, enabled = !loading) { Text(tr("加载更多")) } }
            }
        }
    }
}
