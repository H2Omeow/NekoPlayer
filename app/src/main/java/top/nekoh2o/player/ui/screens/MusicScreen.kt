package top.nekoh2o.player.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.PlaylistAdd
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Album
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Extension
import androidx.compose.material.icons.filled.OndemandVideo
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SearchOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import top.nekoh2o.player.data.model.AlbumItem
import top.nekoh2o.player.data.model.ArtistItem
import top.nekoh2o.player.data.model.PersonalizedItem
import top.nekoh2o.player.data.model.SearchType
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.data.plugins.PluginStore
import top.nekoh2o.player.ui.PlayerViewModel
import top.nekoh2o.player.ui.UiState
import top.nekoh2o.player.ui.a11y.clickableRow
import top.nekoh2o.player.ui.components.Artwork
import top.nekoh2o.player.ui.components.ChipRow
import top.nekoh2o.player.ui.components.DetailTopBar
import top.nekoh2o.player.ui.components.EmptyState
import top.nekoh2o.player.ui.components.ScreenHeader
import top.nekoh2o.player.ui.components.SectionHeader
import top.nekoh2o.player.ui.components.SongActions
import top.nekoh2o.player.ui.components.SongRow
import top.nekoh2o.player.ui.components.songKey
import top.nekoh2o.player.ui.theme.NekoDefaults
import top.nekoh2o.player.ui.theme.NekoRadius
import top.nekoh2o.player.ui.theme.NekoSpace

/** 音乐源选项：id 与显示名。 */
data class MusicSource(val id: String, val name: String)

/** 音乐页除歌曲操作外的回调。 */
class MusicCallbacks(
    val onSource: (String) -> Unit,
    val onQuery: (String) -> Unit,
    val onSearch: (String?) -> Unit,
    val onType: (SearchType) -> Unit,
    val onLoadMore: () -> Unit,
    val onOpenPlaylist: (Long) -> Unit,
    val onOpenArtist: (ArtistItem) -> Unit,
    val onOpenAlbum: (AlbumItem) -> Unit,
    val onOpenMv: () -> Unit,
    val onOpenPlugins: () -> Unit
)

@Composable
fun MusicScreen(vm: PlayerViewModel) {
    val state by vm.ui.collectAsState()
    val plugins by PluginStore.state.collectAsState()
    var managingPlugins by remember { mutableStateOf(false) }
    var detailArtist by remember { mutableStateOf<ArtistItem?>(null) }
    var detailAlbum by remember { mutableStateOf<AlbumItem?>(null) }
    var addTarget by remember { mutableStateOf<Song?>(null) }
    var showMv by remember { mutableStateOf(false) }
    val actions = remember(vm) { vm.songActions { addTarget = it } }

    LaunchedEffect(Unit) {
        if (state.recSongs.isEmpty() && state.recPlaylists.isEmpty()) vm.loadRecommend()
    }

    when {
        managingPlugins -> PluginManagerScreen(onBack = { managingPlugins = false })
        detailArtist != null -> detailArtist?.let { artist ->
            SongsDetailScreen(
                title = artist.name,
                artwork = artist.picUrl ?: artist.img1v1Url,
                artworkShape = CircleShape,
                subtitle = { count -> "$count 首热门歌曲" },
                load = { done -> vm.loadArtistSongs(artist.id, done) },
                key = artist.id,
                actions = actions,
                onBack = { detailArtist = null }
            )
        }
        detailAlbum != null -> detailAlbum?.let { album ->
            SongsDetailScreen(
                title = album.name,
                artwork = album.picUrl,
                artworkShape = RoundedCornerShape(NekoRadius.artwork),
                subtitle = { count -> listOfNotNull(album.artist?.name, "$count 首").joinToString(" · ") },
                load = { done -> vm.loadAlbumSongs(album.id, done) },
                key = album.id,
                actions = actions,
                onBack = { detailAlbum = null }
            )
        }
        else -> MusicContent(
            state = state,
            sources = listOf(MusicSource("netease", "网易云音乐"), MusicSource("kugou", "酷狗音乐")) +
                PluginStore.sources(plugins).map { MusicSource(it.id, it.name) },
            actions = actions,
            callbacks = remember(vm) {
                MusicCallbacks(
                    onSource = vm::switchMusicSource,
                    onQuery = vm::onQueryChange,
                    onSearch = { keyword -> if (keyword == null) vm.doSearch() else vm.doSearch(keyword) },
                    onType = vm::setSearchType,
                    onLoadMore = vm::loadMoreSearch,
                    onOpenPlaylist = vm::openPlaylist,
                    onOpenArtist = { detailArtist = it },
                    onOpenAlbum = { detailAlbum = it },
                    onOpenMv = { showMv = true },
                    onOpenPlugins = { managingPlugins = true }
                )
            }
        )
    }

    if (showMv) MvSheet(
        state.musicSource, state.query,
        onPauseMusic = { if (vm.ui.value.isPlaying) vm.togglePlay() },
        onDismiss = { showMv = false }
    )
    addTarget?.let { song -> AddToPlaylistDialog(vm, song) { addTarget = null } }
}

@Composable
fun MusicContent(
    state: UiState,
    sources: List<MusicSource>,
    actions: SongActions,
    callbacks: MusicCallbacks
) {
    val hasMv = state.musicSource in listOf("netease", "kugou") || state.musicSource.startsWith("animemusic-")
    // 当前分类没有结果但有歌曲结果时仍显示歌曲结果，与切换分类前一致
    val resultType = when {
        state.searchType == SearchType.ARTIST && state.artistResults.isNotEmpty() -> SearchType.ARTIST
        state.searchType == SearchType.ALBUM && state.albumResults.isNotEmpty() -> SearchType.ALBUM
        state.results.isNotEmpty() -> SearchType.SONG
        else -> null
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = NekoSpace.xl)) {
        item {
            ScreenHeader("音乐") {
                if (hasMv) IconButton(onClick = callbacks.onOpenMv) {
                    Icon(Icons.Filled.OndemandVideo, contentDescription = "MV")
                }
                IconButton(onClick = callbacks.onOpenPlugins) {
                    Icon(Icons.Filled.Extension, contentDescription = "音源与订阅")
                }
            }
        }
        item {
            ChipRow(
                items = sources,
                selected = sources.firstOrNull { it.id == state.musicSource },
                label = { it.name },
                onSelect = { callbacks.onSource(it.id) },
                modifier = Modifier.padding(bottom = NekoSpace.sm)
            )
        }
        item {
            SearchField(
                query = state.query,
                placeholder = "搜索${state.searchType.label}",
                onQuery = callbacks.onQuery,
                onSearch = { callbacks.onSearch(null) },
                modifier = Modifier.padding(horizontal = NekoSpace.lg, vertical = NekoSpace.xs)
            )
        }
        if (state.suggestions.isNotEmpty()) item {
            Suggestions(state.suggestions) { callbacks.onSearch(it) }
        }
        item {
            ChipRow(
                items = SearchType.entries,
                selected = state.searchType,
                label = { it.label },
                onSelect = callbacks.onType,
                modifier = Modifier.padding(vertical = NekoSpace.sm)
            )
        }
        if (state.searching || state.recLoading) item {
            LinearProgressIndicator(Modifier.fillMaxWidth().padding(horizontal = NekoSpace.lg))
        }
        when {
            resultType != null -> searchResults(resultType, state, actions, callbacks)
            !state.searching -> recommendations(state, actions, callbacks)
        }
    }
}

@Composable
private fun SearchField(
    query: String,
    placeholder: String,
    onQuery: (String) -> Unit,
    onSearch: () -> Unit,
    modifier: Modifier = Modifier
) {
    OutlinedTextField(
        value = query,
        onValueChange = onQuery,
        modifier = modifier.fillMaxWidth(),
        placeholder = { Text(placeholder) },
        leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
        trailingIcon = {
            if (query.isNotEmpty()) IconButton(onClick = { onQuery("") }) {
                Icon(Icons.Filled.Close, contentDescription = "清空")
            }
        },
        singleLine = true,
        shape = RoundedCornerShape(50),
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        keyboardActions = KeyboardActions(onSearch = { onSearch() }),
        colors = NekoDefaults.textFieldColors()
    )
}

@Composable
private fun Suggestions(suggestions: List<String>, onPick: (String) -> Unit) {
    Surface(
        modifier = Modifier.fillMaxWidth().padding(horizontal = NekoSpace.lg, vertical = NekoSpace.xs),
        shape = RoundedCornerShape(NekoRadius.card),
        color = MaterialTheme.colorScheme.surfaceContainer
    ) {
        Column(Modifier.padding(vertical = NekoSpace.xs)) {
            suggestions.forEach { suggestion ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clickableRow(rowLabel = suggestion, actionLabel = "搜索") { onPick(suggestion) }
                        .heightIn(min = 48.dp)
                        .padding(horizontal = NekoSpace.lg),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(NekoSpace.md)
                ) {
                    Icon(
                        Icons.Filled.Search, contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp)
                    )
                    Text(suggestion, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

private fun LazyListScope.searchResults(
    type: SearchType,
    state: UiState,
    actions: SongActions,
    callbacks: MusicCallbacks
) {
    when (type) {
        SearchType.ARTIST -> items(state.artistResults, key = { "artist:${it.id}" }) { artist ->
            MediaRow(
                artwork = artist.picUrl ?: artist.img1v1Url,
                shape = CircleShape,
                placeholder = Icons.Filled.Person,
                title = artist.name,
                subtitle = null,
                actionLabel = "查看歌手"
            ) { callbacks.onOpenArtist(artist) }
        }
        SearchType.ALBUM -> items(state.albumResults, key = { "album:${it.id}" }) { album ->
            MediaRow(
                artwork = album.picUrl,
                shape = RoundedCornerShape(NekoRadius.cover),
                placeholder = Icons.Filled.Album,
                title = album.name,
                subtitle = album.artist?.name,
                actionLabel = "查看专辑"
            ) { callbacks.onOpenAlbum(album) }
        }
        SearchType.SONG -> items(state.results, key = { "song:" + songKey(it) }) { song ->
            SongRow(
                song = song,
                isFav = actions.isFav(song),
                onPlay = { actions.play(song) },
                onFav = { actions.toggleFav(song) },
                onAdd = { actions.queue(song) },
                onAddToPlaylist = { actions.addToPlaylist(song) },
                modifier = Modifier.animateItem()
            )
        }
    }
    val count = when (type) {
        SearchType.ARTIST -> state.artistResults.size
        SearchType.ALBUM -> state.albumResults.size
        SearchType.SONG -> state.results.size
    }
    if (state.hasMore && count > 0) item(key = "load_more") {
        LaunchedEffect(count) { callbacks.onLoadMore() }
        Box(Modifier.fillMaxWidth().padding(NekoSpace.lg), Alignment.Center) {
            CircularProgressIndicator(Modifier.size(28.dp), strokeWidth = 3.dp)
        }
    }
}

private fun LazyListScope.recommendations(state: UiState, actions: SongActions, callbacks: MusicCallbacks) {
    if (state.recPlaylists.isNotEmpty()) {
        item {
            SectionHeader("推荐歌单", Modifier.padding(start = NekoSpace.lg, end = NekoSpace.lg, top = NekoSpace.md, bottom = NekoSpace.sm))
        }
        item {
            LazyRow(
                contentPadding = PaddingValues(horizontal = NekoSpace.lg),
                horizontalArrangement = Arrangement.spacedBy(NekoSpace.md)
            ) {
                items(state.recPlaylists, key = { it.id }) { playlist ->
                    PlaylistCard(playlist) { callbacks.onOpenPlaylist(playlist.id) }
                }
            }
        }
    }
    item {
        SectionHeader("推荐歌曲", Modifier.padding(start = NekoSpace.lg, end = NekoSpace.lg, top = NekoSpace.xl, bottom = NekoSpace.xs))
    }
    if (state.recSongs.isEmpty() && !state.recLoading) item {
        EmptyState(
            icon = Icons.Filled.SearchOff,
            title = "暂时没有推荐",
            description = "试试搜索歌曲、歌手或专辑。"
        )
    }
    items(state.recSongs, key = { "rec:" + songKey(it) }) { song ->
        SongRow(
            song = song,
            isFav = actions.isFav(song),
            onPlay = { actions.play(song) },
            onFav = { actions.toggleFav(song) },
            onAdd = { actions.queue(song) },
            onAddToPlaylist = { actions.addToPlaylist(song) }
        )
    }
}

@Composable
private fun PlaylistCard(playlist: PersonalizedItem, onClick: () -> Unit) {
    Column(
        Modifier
            .width(128.dp)
            .clickableRow(rowLabel = playlist.name, actionLabel = "打开歌单", onClick = onClick)
    ) {
        Artwork(playlist.picUrl, size = 128.dp, shape = RoundedCornerShape(NekoRadius.card), thumbnail = 300)
        Text(
            playlist.name,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.padding(top = NekoSpace.sm)
        )
    }
}

/** 歌手 / 专辑等非歌曲条目的列表行。 */
@Composable
private fun MediaRow(
    artwork: String?,
    shape: Shape,
    placeholder: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String?,
    actionLabel: String,
    onClick: () -> Unit
) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickableRow(rowLabel = listOfNotNull(title, subtitle).joinToString("，"), actionLabel = actionLabel, onClick = onClick)
            .padding(horizontal = NekoSpace.lg, vertical = NekoSpace.sm),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(NekoSpace.md)
    ) {
        Artwork(artwork, size = 52.dp, shape = shape, placeholder = placeholder)
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (subtitle != null) {
                Text(
                    subtitle, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1
                )
            }
        }
    }
}

/** 歌手 / 专辑详情：大封面、标题、播放全部，下面是歌曲列表。 */
@Composable
private fun SongsDetailScreen(
    title: String,
    artwork: String?,
    artworkShape: Shape,
    subtitle: (Int) -> String,
    load: ((List<Song>) -> Unit) -> Unit,
    key: Long,
    actions: SongActions,
    onBack: () -> Unit
) {
    var songs by remember(key) { mutableStateOf<List<Song>?>(null) }
    LaunchedEffect(key) { load { songs = it } }
    SongsDetailContent(title, artwork, artworkShape, songs, subtitle, actions, onBack)
}

@Composable
fun SongsDetailContent(
    title: String,
    artwork: String?,
    artworkShape: Shape,
    songs: List<Song>?,
    subtitle: (Int) -> String,
    actions: SongActions,
    onBack: () -> Unit,
    artworkSize: Dp = 168.dp
) {
    Column(Modifier.fillMaxSize()) {
        DetailTopBar(title, onBack)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = NekoSpace.xl)) {
            item {
                Column(
                    Modifier.fillMaxWidth().padding(horizontal = NekoSpace.lg, vertical = NekoSpace.sm),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(NekoSpace.xs)
                ) {
                    Artwork(artwork, size = artworkSize, shape = artworkShape, thumbnail = 400)
                    Spacer(Modifier.height(NekoSpace.sm))
                    Text(title, style = MaterialTheme.typography.titleLarge, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    if (songs != null) {
                        Text(
                            subtitle(songs.size), style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    if (!songs.isNullOrEmpty()) {
                        Button(onClick = { actions.playAll(songs) }, modifier = Modifier.padding(top = NekoSpace.sm)) {
                            Icon(Icons.Filled.PlayArrow, contentDescription = null)
                            Spacer(Modifier.width(NekoSpace.xs))
                            Text("播放全部")
                        }
                    }
                }
            }
            when {
                songs == null -> item {
                    Box(Modifier.fillMaxWidth().padding(NekoSpace.xxl), Alignment.Center) { CircularProgressIndicator() }
                }
                songs.isEmpty() -> item { EmptyState(icon = Icons.Filled.SearchOff, title = "暂无歌曲") }
                else -> items(songs, key = { songKey(it) }) { song ->
                    SongRow(
                        song = song,
                        isFav = actions.isFav(song),
                        onPlay = { actions.play(song) },
                        onFav = { actions.toggleFav(song) },
                        onAdd = { actions.queue(song) },
                        onAddToPlaylist = { actions.addToPlaylist(song) }
                    )
                }
            }
        }
    }
}

@Composable
fun AddToPlaylistDialog(vm: PlayerViewModel, song: Song, onDismiss: () -> Unit) {
    val state by vm.ui.collectAsState()
    var creating by remember { mutableStateOf(false) }
    var newName by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("添加到歌单") },
        text = {
            Column {
                ListItem(
                    headlineContent = { Text("播放队列") },
                    leadingContent = { Icon(Icons.Filled.Add, null) },
                    colors = ListItemDefaults.colors(containerColor = androidx.compose.ui.graphics.Color.Transparent),
                    modifier = Modifier.clickable { vm.addToQueue(song); onDismiss() }
                )
                ListItem(
                    headlineContent = { Text("新建歌单…") },
                    leadingContent = { Icon(Icons.AutoMirrored.Filled.PlaylistAdd, null) },
                    colors = ListItemDefaults.colors(containerColor = androidx.compose.ui.graphics.Color.Transparent),
                    modifier = Modifier.clickable { creating = true }
                )
                if (state.playlists.isNotEmpty()) HorizontalDivider(Modifier.padding(vertical = NekoSpace.xs))
                state.playlists.forEachIndexed { i, pl ->
                    ListItem(
                        headlineContent = { Text(pl.name) },
                        supportingContent = { Text("${pl.songs.size} 首") },
                        leadingContent = { Artwork(pl.songs.firstOrNull()?.pc, size = 40.dp) },
                        colors = ListItemDefaults.colors(containerColor = androidx.compose.ui.graphics.Color.Transparent),
                        modifier = Modifier.clickable { vm.addToPlaylist(i, song); onDismiss() }
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss, colors = NekoDefaults.textButtonColors()) { Text("关闭") }
        }
    )

    if (creating) {
        AlertDialog(
            onDismissRequest = { creating = false },
            title = { Text("新建歌单") },
            text = {
                OutlinedTextField(
                    value = newName, onValueChange = { newName = it },
                    singleLine = true, label = { Text("歌单名称") },
                    colors = NekoDefaults.textFieldColors()
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        if (newName.isNotBlank()) {
                            vm.createPlaylist(newName.trim())
                            val idx = vm.ui.value.playlists.lastIndex
                            if (idx >= 0) vm.addToPlaylist(idx, song)
                        }
                        newName = ""; creating = false; onDismiss()
                    }
                ) { Text("创建并添加") }
            },
            dismissButton = {
                TextButton(
                    onClick = { creating = false },
                    colors = NekoDefaults.textButtonColors()
                ) { Text("取消") }
            }
        )
    }
}
