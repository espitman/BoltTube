package ir.boum.bolttube

import android.app.Application
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

private const val PREFS_NAME = "bolttube_prefs"
private const val SAVED_URL_KEY = "saved_url"
private const val SAVED_SERVER_URL_KEY = "saved_server_url"
private const val DEFAULT_SERVER_URL = "http://10.0.2.2:9864"

enum class BridgeStatus {
    Idle,
    Resolving,
    Downloading,
    Refreshing,
    Failed,
}

@Serializable
data class ResolveRequest(val url: String)

@Serializable
data class DownloadRequest(val url: String, val formatId: String)

@Serializable
data class RemoteFormat(
    val id: String,
    val title: String,
    val details: String,
)

@Serializable
data class ResolveResponse(
    val title: String = "",
    val formats: List<RemoteFormat> = emptyList(),
)

@Serializable
data class DownloadResponse(
    val id: String,
    val streamUrl: String,
    val fileName: String,
)

@Serializable
data class MediaSummary(
    val id: String,
    val fileName: String,
    val streamUrl: String,
    val size: String,
    val createdAt: String,
)

@Serializable
data class MediaLibraryResponse(
    val items: List<MediaSummary> = emptyList(),
)

data class BridgeUiState(
    val serverUrl: String = DEFAULT_SERVER_URL,
    val url: String = "",
    val title: String = "",
    val status: BridgeStatus = BridgeStatus.Idle,
    val message: String = "",
    val savedMessage: String = "",
    val formats: List<RemoteFormat> = emptyList(),
    val selectedFormatId: String = "best",
    val library: List<MediaSummary> = emptyList(),
    val currentStreamUrl: String = "",
)

class MainViewModel(application: Application) : AndroidViewModel(application) {

    private val prefs = application.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val json = Json {
        ignoreUnknownKeys = true
    }
    private val httpClient = HttpClient(OkHttp) {
        install(ContentNegotiation) {
            json(json)
        }
    }

    var uiState by mutableStateOf(
        BridgeUiState(
            serverUrl = prefs.getString(SAVED_SERVER_URL_KEY, DEFAULT_SERVER_URL).orEmpty(),
            url = prefs.getString(SAVED_URL_KEY, "").orEmpty(),
        ),
    )
        private set

    fun onServerUrlChanged(value: String) {
        uiState = uiState.copy(serverUrl = value, savedMessage = "")
    }

    fun onUrlChanged(value: String) {
        uiState = uiState.copy(url = value, savedMessage = "")
    }

    fun saveInputs() {
        val normalizedServer = uiState.serverUrl.trim().trimEnd('/')
        val normalizedUrl = uiState.url.trim()
        prefs.edit()
            .putString(SAVED_SERVER_URL_KEY, normalizedServer)
            .putString(SAVED_URL_KEY, normalizedUrl)
            .apply()
        uiState = uiState.copy(
            serverUrl = normalizedServer,
            url = normalizedUrl,
            savedMessage = "Server and video URL saved.",
        )
    }

    fun resolveFormats() {
        val url = uiState.url.trim()
        if (url.isBlank()) {
            uiState = uiState.copy(status = BridgeStatus.Failed, message = "Enter a YouTube URL first.")
            return
        }

        uiState = uiState.copy(
            status = BridgeStatus.Resolving,
            message = "Asking the Mac server for available formats...",
        )

        viewModelScope.launch(Dispatchers.IO) {
            runCatching {
                val response = httpClient.post("${serverBaseUrl()}/api/resolve") {
                    contentType(ContentType.Application.Json)
                    setBody(ResolveRequest(url))
                }.body<ResolveResponse>()

                uiState = uiState.copy(
                    title = response.title,
                    formats = response.formats,
                    selectedFormatId = response.formats.firstOrNull()?.id ?: "best",
                    status = BridgeStatus.Idle,
                    message = "Formats loaded from the Mac server.",
                )
            }.onFailure { error ->
                uiState = uiState.copy(
                    status = BridgeStatus.Failed,
                    message = error.message ?: "Could not connect to the Mac server.",
                )
            }
        }
    }

    fun selectFormat(id: String) {
        uiState = uiState.copy(selectedFormatId = id)
    }

    fun startDownloadOnMac() {
        val url = uiState.url.trim()
        if (url.isBlank()) {
            uiState = uiState.copy(status = BridgeStatus.Failed, message = "Enter a YouTube URL first.")
            return
        }

        uiState = uiState.copy(
            status = BridgeStatus.Downloading,
            message = "The Mac server is downloading the selected format...",
        )

        viewModelScope.launch(Dispatchers.IO) {
            runCatching {
                val response = httpClient.post("${serverBaseUrl()}/api/download") {
                    contentType(ContentType.Application.Json)
                    setBody(DownloadRequest(url = url, formatId = uiState.selectedFormatId))
                }.body<DownloadResponse>()

                refreshLibraryInternal()
                uiState = uiState.copy(
                    currentStreamUrl = absoluteMediaUrl(response.streamUrl),
                    status = BridgeStatus.Idle,
                    message = "Downloaded on Mac. Ready to play on the phone.",
                )
            }.onFailure { error ->
                uiState = uiState.copy(
                    status = BridgeStatus.Failed,
                    message = error.message ?: "The Mac server could not download the video.",
                )
            }
        }
    }

    fun refreshLibrary() {
        uiState = uiState.copy(
            status = BridgeStatus.Refreshing,
            message = "Refreshing the Mac library...",
        )
        viewModelScope.launch(Dispatchers.IO) {
            runCatching {
                refreshLibraryInternal()
                uiState = uiState.copy(
                    status = BridgeStatus.Idle,
                    message = "Library refreshed.",
                )
            }.onFailure { error ->
                uiState = uiState.copy(
                    status = BridgeStatus.Failed,
                    message = error.message ?: "Could not refresh the Mac library.",
                )
            }
        }
    }

    fun playItem(item: MediaSummary) {
        uiState = uiState.copy(
            currentStreamUrl = absoluteMediaUrl(item.streamUrl),
            message = "Playing ${item.fileName}",
        )
    }

    private suspend fun refreshLibraryInternal() {
        val response = httpClient.get("${serverBaseUrl()}/api/items").body<MediaLibraryResponse>()
        uiState = uiState.copy(library = response.items)
    }

    private fun absoluteMediaUrl(relativeOrAbsolute: String): String {
        return if (relativeOrAbsolute.startsWith("http")) relativeOrAbsolute else "${serverBaseUrl()}$relativeOrAbsolute"
    }

    private fun serverBaseUrl(): String {
        return uiState.serverUrl.trim().ifBlank { DEFAULT_SERVER_URL }.trimEnd('/')
    }

    override fun onCleared() {
        httpClient.close()
        super.onCleared()
    }
}
