package ir.boum.bolttube.tv

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

private const val PREFS_NAME = "bolttube_tv_prefs"
private const val SERVER_URL_KEY = "server_url"
private const val DEFAULT_SERVER_URL = "http://10.0.2.2:9864"

class TvViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = MediaRepository()
    private val prefs = application.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private var liveSyncJob: Job? = null
    private var realtimeJob: Job? = null
    private var realtimeConnected = false
    private val realtimeCommands = MutableSharedFlow<String>(extraBufferCapacity = 32)
    private val json = Json { ignoreUnknownKeys = true }
    private val _uiState = MutableStateFlow(
        TvUiState(serverUrl = prefs.getString(SERVER_URL_KEY, DEFAULT_SERVER_URL).orEmpty()),
    )
    val uiState: StateFlow<TvUiState> = _uiState.asStateFlow()

    init {
        refreshAll()
        startRealtimeSocket()
        startLiveSync()
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

    private fun startLiveSync() {
        if (liveSyncJob?.isActive == true) return
        liveSyncJob = viewModelScope.launch(Dispatchers.IO) {
            while (true) {
                delay(1_500)
                silentRefreshLibrary()
                pollVisibleDownloadStatuses()
            }
        }
    }

    private fun startRealtimeSocket() {
        realtimeJob?.cancel()
        realtimeJob = viewModelScope.launch(Dispatchers.IO) {
            while (true) {
                val serverUrl = _uiState.value.serverUrl.trim().ifBlank { DEFAULT_SERVER_URL }
                runCatching {
                    realtimeConnected = false
                    repository.observeRealtime(serverUrl, realtimeCommands, ::handleRealtimeEvent)
                }
                realtimeConnected = false
                delay(1_500)
            }
        }
    }

    private suspend fun handleRealtimeEvent(event: JsonObject) {
        when (event["type"]?.jsonPrimitive?.contentOrNull) {
            "connected", "library_snapshot", "library_updated" -> {
                if (event["type"]?.jsonPrimitive?.contentOrNull == "connected") {
                    realtimeConnected = true
                }
                val itemsElement = event["items"] ?: return
                val items = json.decodeFromJsonElement(ListSerializer(MediaSummary.serializer()), itemsElement)
                _uiState.value = _uiState.value.copy(
                    library = items,
                    loading = false,
                    error = "",
                    message = if (event["type"]?.jsonPrimitive?.contentOrNull == "library_updated") "Library updated." else _uiState.value.message,
                )
            }
            "download_status" -> {
                val mediaId = event["mediaId"]?.jsonPrimitive?.contentOrNull ?: return
                val statusElement = event["status"] ?: return
                val status = json.decodeFromJsonElement<OffloadedDownloadStatus>(statusElement)
                val next = _uiState.value.downloadStatuses.toMutableMap()
                if (status.status == "idle" && status.fraction <= 0.0) {
                    next.remove(mediaId)
                } else {
                    next[mediaId] = status
                }
                _uiState.value = _uiState.value.copy(downloadStatuses = next)
            }
            "action_result" -> {
                val ok = event["ok"]?.jsonPrimitive?.contentOrNull == "true"
                _uiState.value = _uiState.value.copy(
                    message = if (ok) "Action completed." else "",
                    error = if (ok) "" else "Action failed.",
                )
            }
        }
    }

    private suspend fun silentRefreshLibrary() {
        val serverUrl = _uiState.value.serverUrl.trim().ifBlank { DEFAULT_SERVER_URL }
        runCatching {
            repository.fetchLibrary(serverUrl)
        }.onSuccess { items ->
            _uiState.value = _uiState.value.copy(
                serverUrl = serverUrl,
                library = items,
                loading = false,
                error = "",
            )
        }
    }

    private suspend fun pollVisibleDownloadStatuses() {
        val state = _uiState.value
        val serverUrl = state.serverUrl.trim().ifBlank { DEFAULT_SERVER_URL }
        val candidates = state.library.filter { !it.isDownloaded }
        if (candidates.isEmpty()) {
            if (state.downloadStatuses.isNotEmpty()) {
                _uiState.value = state.copy(downloadStatuses = emptyMap())
            }
            return
        }

        val candidateIds = candidates.mapTo(mutableSetOf()) { it.id }
        val nextStatuses = state.downloadStatuses.filterKeys { it in candidateIds }.toMutableMap()
        candidates.forEach { item ->
            runCatching {
                repository.fetchOffloadedDownloadStatus(serverUrl, item.id)
            }.onSuccess { status ->
                if (status.status in ACTIVE_DOWNLOAD_STATES || status.fraction > 0.0) {
                    nextStatuses[item.id] = status
                } else {
                    nextStatuses.remove(item.id)
                }
            }
        }
        if (nextStatuses != state.downloadStatuses) {
            _uiState.value = _uiState.value.copy(downloadStatuses = nextStatuses)
        }
    }

    fun deleteItem(mediaId: String) {
        val serverUrl = _uiState.value.serverUrl.trim().ifBlank { DEFAULT_SERVER_URL }
        _uiState.value = _uiState.value.copy(error = "", message = "Deleting video...")
        if (realtimeConnected && realtimeCommands.tryEmit(
                buildJsonObject {
                    put("type", "delete_item")
                    put("mediaId", mediaId)
                }.toString(),
            )
        ) return
        viewModelScope.launch(Dispatchers.IO) {
            runCatching {
                repository.deleteItem(serverUrl, mediaId)
            }.onSuccess { response ->
                if (response.status != "deleted") {
                    throw IllegalStateException("Could not delete the video.")
                }
                _uiState.value = _uiState.value.copy(error = "", message = "Video deleted.")
                refreshCurrentContext()
            }.onFailure { error ->
                _uiState.value = _uiState.value.copy(
                    error = error.message ?: "Could not delete the video.",
                    message = "",
                )
            }
        }
    }

    fun offloadItem(mediaId: String) {
        val serverUrl = _uiState.value.serverUrl.trim().ifBlank { DEFAULT_SERVER_URL }
        _uiState.value = _uiState.value.copy(error = "", message = "Offloading video...")
        if (realtimeConnected && realtimeCommands.tryEmit(
                buildJsonObject {
                    put("type", "offload_item")
                    put("mediaId", mediaId)
                }.toString(),
            )
        ) return
        viewModelScope.launch(Dispatchers.IO) {
            runCatching {
                repository.offloadItem(serverUrl, mediaId)
            }.onSuccess { response ->
                if (response.status != "offloaded") {
                    throw IllegalStateException("Could not offload the video.")
                }
                _uiState.value = _uiState.value.copy(error = "", message = "Video offloaded.")
                refreshCurrentContext()
            }.onFailure { error ->
                _uiState.value = _uiState.value.copy(
                    error = error.message ?: "Could not offload the video.",
                    message = "",
                )
            }
        }
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

    private fun refreshCurrentContext() {
        refreshLibrary()
        refreshChannels()
        _uiState.value.selectedPlaylist?.let(::loadPlaylistContent)
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
        startRealtimeSocket()
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
        liveSyncJob?.cancel()
        realtimeJob?.cancel()
        repository.close()
        super.onCleared()
    }

    companion object {
        private val ACTIVE_DOWNLOAD_STATES = setOf(
            "queued",
            "resolving",
            "converting",
            "ready",
            "downloading",
            "merging",
            "completed",
            "failed",
        )
    }
}
