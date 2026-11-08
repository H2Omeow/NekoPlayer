package top.nekoh2o.player.ui.viewmodel

import top.nekoh2o.player.i18n.NekoI18n.tr

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import top.nekoh2o.player.data.model.AlbumItem
import top.nekoh2o.player.data.model.ArtistItem
import top.nekoh2o.player.data.model.PersonalizedItem
import top.nekoh2o.player.data.model.SearchType
import top.nekoh2o.player.data.model.Song
import top.nekoh2o.player.data.repo.KugouRepository
import top.nekoh2o.player.data.repo.MusicRepository
import top.nekoh2o.player.data.plugins.PluginMusicRepository
import top.nekoh2o.player.data.plugins.PluginStore
import kotlinx.coroutines.CancellationException

/**
 * 搜索功能 ViewModel
 * 负责：关键词搜索、搜索建议、推荐歌单/歌曲
 */
class SearchViewModel(app: Application) : AndroidViewModel(app) {

    private val repo = MusicRepository()
    private val kgRepo = KugouRepository()
    private val pluginRepo = PluginMusicRepository()

    private var suggestJob: Job? = null
    private var searchOffset = 0
    private var searchKeyword = ""
    private var searchLoading = false
    private var pluginPage = 1

    /**
     * 搜索建议（防抖 300ms）
     */
    fun getSuggestions(
        query: String,
        musicSource: String,
        onResult: (List<String>) -> Unit
    ) {
        suggestJob?.cancel()
        if (query.trim().length < 2) {
            onResult(emptyList())
            return
        }
        suggestJob = viewModelScope.launch {
            delay(300)
            val suggestions = if (musicSource == "kugou") {
                runCatching { kgRepo.searchSuggest(query.trim()) }.getOrDefault(emptyList())
            } else if (PluginStore.isPluginSource(musicSource)) {
                emptyList()
            } else {
                runCatching { repo.suggest(query.trim()) }.getOrDefault(emptyList())
            }
            onResult(suggestions)
        }
    }

    /**
     * 执行搜索
     */
    suspend fun search(
        keyword: String,
        searchType: SearchType,
        musicSource: String
    ): SearchResult {
        val kw = keyword.trim()
        if (kw.isEmpty()) return SearchResult()

        searchKeyword = kw
        searchOffset = 0
        pluginPage = 1

        if (PluginStore.isPluginSource(musicSource)) {
            if (searchType != SearchType.SONG) return SearchResult(error = tr("此音源仅支持单曲搜索"))
            return try {
                val result = pluginRepo.search(musicSource, kw, pluginPage)
                SearchResult(songs = result.songs, hasMore = result.hasMore)
            } catch (failure: CancellationException) { throw failure }
            catch (failure: Exception) { SearchResult(error = failure.message ?: tr("音源搜索失败")) }
        }

        return when (searchType) {
            SearchType.SONG -> {
                val list = if (musicSource == "kugou") {
                    runCatching { kgRepo.search(kw, 1) }.getOrDefault(emptyList())
                } else {
                    runCatching { repo.search(kw, 0) }.getOrDefault(emptyList())
                }
                searchOffset = list.size
                SearchResult(songs = list, hasMore = list.size >= 30)
            }
            SearchType.ARTIST -> {
                val list = runCatching { repo.searchArtist(kw, 0) }.getOrDefault(emptyList())
                searchOffset = list.size
                SearchResult(artists = list, hasMore = list.size >= 30)
            }
            SearchType.ALBUM -> {
                val list = runCatching { repo.searchAlbum(kw, 0) }.getOrDefault(emptyList())
                searchOffset = list.size
                SearchResult(albums = list, hasMore = list.size >= 30)
            }
        }
    }

    /**
     * 加载更多搜索结果
     */
    suspend fun loadMore(
        searchType: SearchType,
        musicSource: String,
        hasMore: Boolean
    ): SearchResult {
        if (searchLoading || !hasMore || searchKeyword.isEmpty()) {
            return SearchResult()
        }

        searchLoading = true
        return try {
            if (PluginStore.isPluginSource(musicSource)) {
                val result = pluginRepo.search(musicSource, searchKeyword, pluginPage + 1)
                pluginPage += 1
                return SearchResult(songs = result.songs, hasMore = result.hasMore)
            }
            when (searchType) {
                SearchType.SONG -> {
                    val more = if (musicSource == "kugou") {
                        val page = (searchOffset / 30) + 1
                        runCatching { kgRepo.search(searchKeyword, page) }.getOrDefault(emptyList())
                    } else {
                        runCatching { repo.search(searchKeyword, searchOffset) }.getOrDefault(emptyList())
                    }
                    searchOffset += more.size
                    SearchResult(songs = more, hasMore = more.size >= 30)
                }
                SearchType.ARTIST -> {
                    val more = runCatching { repo.searchArtist(searchKeyword, searchOffset) }
                        .getOrDefault(emptyList())
                    searchOffset += more.size
                    SearchResult(artists = more, hasMore = more.size >= 30)
                }
                SearchType.ALBUM -> {
                    val more = runCatching { repo.searchAlbum(searchKeyword, searchOffset) }
                        .getOrDefault(emptyList())
                    searchOffset += more.size
                    SearchResult(albums = more, hasMore = more.size >= 30)
                }
            }
        } catch (failure: CancellationException) { throw failure }
        catch (failure: Exception) { SearchResult(error = failure.message ?: tr("加载音源失败")) }
        finally {
            searchLoading = false
        }
    }

    /**
     * 加载推荐歌单和歌曲
     */
    suspend fun loadRecommendations(musicSource: String): RecommendResult {
        if (PluginStore.isPluginSource(musicSource)) return RecommendResult()
        return if (musicSource == "kugou") {
            val songs = runCatching { kgRepo.getRecommendSongs() }.getOrDefault(emptyList())
            RecommendResult(songs = songs)
        } else {
            val playlists = runCatching { repo.personalizedPlaylists() }.getOrDefault(emptyList())
            val songs = runCatching { repo.recommendSongs() }.getOrDefault(emptyList())
            RecommendResult(playlists = playlists, songs = songs)
        }
    }

    /**
     * 获取歌手热门歌曲
     */
    suspend fun getArtistTopSongs(artistId: Long): List<Song> {
        return runCatching { repo.artistTopSongs(artistId) }.getOrDefault(emptyList())
    }

    /**
     * 获取专辑详情
     */
    suspend fun getAlbumDetail(albumId: Long): List<Song> {
        return runCatching { repo.albumSongs(albumId) }.getOrDefault(emptyList())
    }

    /**
     * 获取歌单详情
     */
    suspend fun getPlaylistDetail(playlistId: Long): List<Song> {
        return runCatching { repo.playlistTracks(playlistId) }.getOrDefault(emptyList())
    }
}

/**
 * 搜索结果
 */
data class SearchResult(
    val songs: List<Song> = emptyList(),
    val artists: List<ArtistItem> = emptyList(),
    val albums: List<AlbumItem> = emptyList(),
    val hasMore: Boolean = false,
    val error: String? = null
)

/**
 * 推荐结果
 */
data class RecommendResult(
    val playlists: List<PersonalizedItem> = emptyList(),
    val songs: List<Song> = emptyList()
)
