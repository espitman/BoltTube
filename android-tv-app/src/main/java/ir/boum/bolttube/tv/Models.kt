package ir.boum.bolttube.tv

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

private const val DEFAULT_SERVER_URL = "http://10.0.2.2:9864"

@Serializable
data class MediaSummary(
    val id: String,
    @SerialName("file_name")
    val fileName: String,
    val title: String = "",
    @SerialName("stream_url")
    val streamUrl: String,
    val size: String,
    @SerialName("created_at")
    val createdAt: String,
    @SerialName("thumbnail_url")
    val thumbnailUrl: String? = null,
    @SerialName("source_url")
    val sourceUrl: String = "",
    @SerialName("is_downloaded")
    val isDownloaded: Boolean = true,
    val duration: Int = 0,
)

@Serializable
data class MediaLibraryResponse(
    val items: List<MediaSummary> = emptyList(),
)

@Serializable
data class ChannelSummary(
    val id: Int,
    val name: String,
    @SerialName("thumbnail_url")
    val thumbnailUrl: String? = null,
    @SerialName("created_at")
    val createdAt: String,
    @SerialName("playlist_count")
    val playlistCount: Int = 0,
)

@Serializable
data class ChannelResponse(
    val items: List<ChannelSummary> = emptyList(),
)

@Serializable
data class PlaylistSummary(
    val id: Int,
    val name: String,
    @SerialName("thumbnail_url")
    val thumbnailUrl: String? = null,
    @SerialName("created_at")
    val createdAt: String,
    @SerialName("item_count")
    val itemCount: Int = 0,
)

@Serializable
data class ChannelSection(
    val playlist: PlaylistSummary,
    val items: List<MediaSummary> = emptyList(),
)

@Serializable
data class ChannelContentResponse(
    val content: List<ChannelSection> = emptyList(),
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
    val createdAt: String,
    val duration: Int,
    val isOffloaded: Boolean,
) : TvRowItem

@Serializable
data class PlaylistItemsResponse(
    val items: List<MediaSummary> = emptyList(),
)

data class TvUiState(
    val serverUrl: String = DEFAULT_SERVER_URL,
    val library: List<MediaSummary> = emptyList(),
    val channels: List<ChannelSummary> = emptyList(),
    val selectedChannel: ChannelSummary? = null,
    val channelContent: List<ChannelSection> = emptyList(),
    val channelContentLoading: Boolean = false,
    val selectedPlaylist: PlaylistSummary? = null,
    val playlistContent: List<MediaSummary> = emptyList(),
    val playlistLoading: Boolean = false,
    val loading: Boolean = false,
    val message: String = "",
    val error: String = "",
)
