package ir.boum.bolttube.tv

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json

class MediaRepository {
    private val json = Json { ignoreUnknownKeys = true }
    private val client = HttpClient(OkHttp) {
        engine {
            config {
                connectTimeout(20, java.util.concurrent.TimeUnit.SECONDS)
                readTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
                writeTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
                callTimeout(35, java.util.concurrent.TimeUnit.SECONDS)
            }
        }
        install(HttpTimeout) {
            requestTimeoutMillis = 35_000
            connectTimeoutMillis = 20_000
            socketTimeoutMillis = 30_000
        }
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

    suspend fun resolveOffloaded(serverUrl: String, mediaId: String): ResolveResponse {
        val normalized = serverUrl.trim().trimEnd('/')
        return client.post("$normalized/api/offloaded/resolve") {
            contentType(ContentType.Application.Json)
            setBody(mapOf("id" to mediaId))
        }.body()
    }

    suspend fun startOffloadedDownload(
        serverUrl: String,
        mediaId: String,
        formatId: String,
        preferredClient: String,
    ): OffloadedDownloadStatus {
        val normalized = serverUrl.trim().trimEnd('/')
        return client.post("$normalized/api/offloaded/download") {
            contentType(ContentType.Application.Json)
            setBody(
                mapOf(
                    "id" to mediaId,
                    "formatId" to formatId,
                    "preferredClient" to preferredClient,
                ),
            )
        }.body()
    }

    suspend fun fetchOffloadedDownloadStatus(serverUrl: String, mediaId: String): OffloadedDownloadStatus {
        val normalized = serverUrl.trim().trimEnd('/')
        return client.get("$normalized/api/offloaded/download-status/$mediaId").body()
    }

    fun close() {
        client.close()
    }
}
