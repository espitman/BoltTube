package ir.boum.bolttube.tv

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.get
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json

class MediaRepository {
    private val json = Json { ignoreUnknownKeys = true }
    private val client = HttpClient(OkHttp) {
        install(ContentNegotiation) {
            json(json)
        }
    }

    suspend fun fetchLibrary(serverUrl: String): List<MediaSummary> {
        val normalized = serverUrl.trim().trimEnd('/')
        return client.get("$normalized/api/items").body<MediaLibraryResponse>().items
    }

    suspend fun fetchChannels(serverUrl: String): List<ChannelSummary> {
        val normalized = serverUrl.trim().trimEnd('/')
        return client.get("$normalized/api/channels").body<ChannelResponse>().items
    }

    suspend fun fetchChannelContent(serverUrl: String, channelId: Int): List<ChannelSection> {
        val normalized = serverUrl.trim().trimEnd('/')
        return client.get("$normalized/api/channels/$channelId/content").body<ChannelContentResponse>().content
    }

    suspend fun fetchPlaylistItems(serverUrl: String, playlistId: Int): List<MediaSummary> {
        val normalized = serverUrl.trim().trimEnd('/')
        return client.get("$normalized/api/playlists/$playlistId/items").body<MediaLibraryResponse>().items
    }

    fun close() {
        client.close()
    }
}
