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
        refreshLibrary()
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

    fun saveServerUrl(url: String) {
        val normalized = url.trim().ifBlank { DEFAULT_SERVER_URL }.trimEnd('/')
        prefs.edit().putString(SERVER_URL_KEY, normalized).apply()
        _uiState.value = _uiState.value.copy(serverUrl = normalized, message = "Server updated.", error = "")
        refreshLibrary()
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
