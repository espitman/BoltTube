package ir.boum.bolttube.tv

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

private const val PREFS_NAME = "bolttube_tv_prefs"
private const val SERVER_URL_KEY = "server_url"
private const val DEFAULT_SERVER_URL = "http://10.0.2.2:9864"

class TvViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = MediaRepository()
    private val prefs = application.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val _uiState = MutableStateFlow(
        TvUiState(serverUrl = prefs.getString(SERVER_URL_KEY, DEFAULT_SERVER_URL).orEmpty()),
    )
    val uiState: StateFlow<TvUiState> = _uiState.asStateFlow()

    init {
        refreshAll()
    }

    fun refreshLibrary() {
        val serverUrl = _uiState.value.serverUrl.trim().ifBlank { DEFAULT_SERVER_URL }
        _uiState.value = _uiState.value.copy(loading = true, error = "", message = "Connecting to Mac app...")

        viewModelScope.launch(Dispatchers.IO) {
            runCatching {
                repository.fetchLibrary(serverUrl)
            }.onSuccess { items ->
                _uiState.value = _uiState.value.copy(
                    serverUrl = serverUrl,
                    library = items,
                    loading = false,
                    error = "",
                    message = if (items.isEmpty()) "Connected, but the library is empty." else "Library updated.",
                )
            }.onFailure { error ->
                _uiState.value = _uiState.value.copy(
                    loading = false,
                    error = error.message ?: "Could not load the Mac library.",
                    message = "",
                )
            }
        }
    }

    fun refreshChannels() {
        val serverUrl = _uiState.value.serverUrl.trim().ifBlank { DEFAULT_SERVER_URL }
        viewModelScope.launch(Dispatchers.IO) {
            runCatching {
                repository.fetchChannels(serverUrl)
            }.onSuccess { channels ->
                val selectedId = _uiState.value.selectedChannel?.id
                val selected = channels.firstOrNull { it.id == selectedId }
                _uiState.value = _uiState.value.copy(
                    serverUrl = serverUrl,
                    channels = channels,
                    selectedChannel = selected,
                )
                if (selected != null) {
                    loadChannelContent(selected)
                }
            }.onFailure { error ->
                _uiState.value = _uiState.value.copy(
                    error = error.message ?: "Could not load channels.",
                )
            }
        }
    }

    fun refreshAll() {
        _uiState.value = _uiState.value.copy(
            selectedChannel = null,
            channelContent = emptyList(),
            channelContentLoading = false,
            selectedPlaylist = null,
            playlistContent = emptyList(),
            playlistLoading = false,
        )
        refreshLibrary()
        refreshChannels()
    }

    fun selectChannel(channel: ChannelSummary) {
        _uiState.value = _uiState.value.copy(
            selectedChannel = channel,
            channelContent = emptyList(),
            channelContentLoading = true,
            selectedPlaylist = null,
            playlistContent = emptyList(),
            error = "",
        )
        loadChannelContent(channel)
    }

    fun clearSelectedChannel() {
        _uiState.value = _uiState.value.copy(
            selectedChannel = null,
            channelContent = emptyList(),
            channelContentLoading = false,
            selectedPlaylist = null,
            playlistContent = emptyList(),
        )
    }

    fun selectPlaylist(playlist: PlaylistSummary) {
        _uiState.value = _uiState.value.copy(
            selectedPlaylist = playlist,
            playlistContent = emptyList(),
            playlistLoading = true,
            error = "",
        )
        loadPlaylistContent(playlist)
    }

    fun clearSelectedPlaylist() {
        _uiState.value = _uiState.value.copy(
            selectedPlaylist = null,
            playlistContent = emptyList(),
            playlistLoading = false,
        )
    }

    private fun loadPlaylistContent(playlist: PlaylistSummary) {
        val serverUrl = _uiState.value.serverUrl.trim().ifBlank { DEFAULT_SERVER_URL }
        viewModelScope.launch(Dispatchers.IO) {
            runCatching {
                repository.fetchPlaylistItems(serverUrl, playlist.id)
            }.onSuccess { items ->
                if (_uiState.value.selectedPlaylist?.id != playlist.id) return@onSuccess
                _uiState.value = _uiState.value.copy(
                    playlistContent = items,
                    playlistLoading = false,
                    error = "",
                )
            }.onFailure { error ->
                if (_uiState.value.selectedPlaylist?.id != playlist.id) return@onFailure
                _uiState.value = _uiState.value.copy(
                    playlistContent = emptyList(),
                    playlistLoading = false,
                    error = error.message ?: "Could not load playlist items.",
                )
            }
        }
    }

    private fun loadChannelContent(channel: ChannelSummary) {
        val serverUrl = _uiState.value.serverUrl.trim().ifBlank { DEFAULT_SERVER_URL }
        viewModelScope.launch(Dispatchers.IO) {
            runCatching {
                repository.fetchChannelContent(serverUrl, channel.id)
            }.onSuccess { content ->
                if (_uiState.value.selectedChannel?.id != channel.id) return@onSuccess
                _uiState.value = _uiState.value.copy(
                    channelContent = content,
                    channelContentLoading = false,
                    error = "",
                )
            }.onFailure { error ->
                if (_uiState.value.selectedChannel?.id != channel.id) return@onFailure
                _uiState.value = _uiState.value.copy(
                    channelContent = emptyList(),
                    channelContentLoading = false,
                    error = error.message ?: "Could not load channel content.",
                )
            }
        }
    }

    fun saveServerUrl(url: String) {
        val normalized = url.trim().ifBlank { DEFAULT_SERVER_URL }.trimEnd('/')
        prefs.edit().putString(SERVER_URL_KEY, normalized).apply()
        _uiState.value = _uiState.value.copy(serverUrl = normalized, message = "Server updated.", error = "")
        refreshAll()
    }

    fun absoluteMediaUrl(relativeOrAbsolute: String): String {
        return if (relativeOrAbsolute.startsWith("http")) {
            relativeOrAbsolute
        } else {
            "${_uiState.value.serverUrl.trim().trimEnd('/')}$relativeOrAbsolute"
        }
    }

    override fun onCleared() {
        repository.close()
        super.onCleared()
    }
}
