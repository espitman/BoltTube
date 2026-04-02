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
    val sourceUrl: String,
    val createdAt: String,
    val duration: Int,
    val isOffloaded: Boolean,
) : TvRowItem

@Serializable
data class RemoteFormat(
    val id: String,
    val title: String,
    val details: String = "",
    val filesize: String = "",
)

@Serializable
data class ResolveResponse(
    val title: String = "",
    @SerialName("thumbnail_url")
    val thumbnailUrl: String = "",
    @SerialName("duration_seconds")
    val durationSeconds: Int = 0,
    val formats: List<RemoteFormat> = emptyList(),
    @SerialName("media_id")
    val mediaId: String = "",
    @SerialName("resolved_client")
    val resolvedClient: String = "",
)

@Serializable
data class OffloadedDownloadStatus(
    @SerialName("mediaId")
    val mediaId: String = "",
    val status: String = "idle",
    val fraction: Double = 0.0,
    @SerialName("downloadedBytes")
    val downloadedBytes: Double = 0.0,
    @SerialName("totalBytes")
    val totalBytes: Double = 0.0,
    @SerialName("speedBytesPerSecond")
    val speedBytesPerSecond: Double = 0.0,
    val error: String = "",
    val title: String = "",
    @SerialName("thumbnailUrl")
    val thumbnailUrl: String = "",
    @SerialName("sourceUrl")
    val sourceUrl: String = "",
    @SerialName("fileName")
    val fileName: String = "",
    @SerialName("streamUrl")
    val streamUrl: String = "",
)

@Serializable
data class ActionStatusResponse(
    val status: String = "",
)

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
