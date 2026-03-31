package ir.boum.bolttube.tv

import kotlinx.serialization.Serializable

private const val DEFAULT_SERVER_URL = "http://10.0.2.2:9864"

@Serializable
data class MediaSummary(
    val id: String,
    val fileName: String,
    val streamUrl: String,
    val size: String,
    val createdAt: String,
    val thumbnailUrl: String? = null,
)

@Serializable
data class MediaLibraryResponse(
    val items: List<MediaSummary> = emptyList(),
)

sealed interface TvRowItem {
    val id: String
}

data class ActionItem(
    override val id: String,
    val title: String,
    val subtitle: String,
) : TvRowItem

data class VideoItem(
    override val id: String,
    val title: String,
    val subtitle: String,
    val thumbnailUrl: String?,
    val streamUrl: String,
) : TvRowItem

data class TvUiState(
    val serverUrl: String = DEFAULT_SERVER_URL,
    val library: List<MediaSummary> = emptyList(),
    val loading: Boolean = false,
    val message: String = "",
    val error: String = "",
)
