package ir.boum.bolttube.tv

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.websocket.WebSockets
import io.ktor.client.plugins.websocket.webSocket
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import io.ktor.websocket.Frame
import io.ktor.websocket.readText
import io.ktor.websocket.send
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

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
        install(WebSockets)
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

    suspend fun deleteItem(serverUrl: String, mediaId: String): ActionStatusResponse {
        val normalized = serverUrl.trim().trimEnd('/')
        return client.post("$normalized/api/delete") {
            contentType(ContentType.Application.Json)
            setBody(mapOf("id" to mediaId))
        }.body()
    }

    suspend fun offloadItem(serverUrl: String, mediaId: String): ActionStatusResponse {
        val normalized = serverUrl.trim().trimEnd('/')
        return client.post("$normalized/api/offload") {
            contentType(ContentType.Application.Json)
            setBody(mapOf("id" to mediaId))
        }.body()
    }

    suspend fun observeRealtime(
        serverUrl: String,
        outgoingCommands: Flow<String>,
        onEvent: suspend (JsonObject) -> Unit,
    ) {
        val wsUrl = serverUrl.trim().trimEnd('/')
            .replaceFirst("https://", "wss://")
            .replaceFirst("http://", "ws://") + "/ws"
        client.webSocket(urlString = wsUrl) {
            send(buildJsonObject { put("type", "hello") }.toString())
            coroutineScope {
                val sender = launch {
                    outgoingCommands.collect { command ->
                        send(command)
                    }
                }
                try {
                    for (frame in incoming) {
                        if (frame is Frame.Text) {
                            val payload = json.parseToJsonElement(frame.readText()) as? JsonObject ?: continue
                            onEvent(payload)
                        }
                    }
                } finally {
                    sender.cancel()
                }
            }
        }
    }

    suspend fun sendPlaybackProgress(serverUrl: String, mediaId: String, positionMs: Long, durationMs: Long) {
        val normalized = serverUrl.trim().trimEnd('/')
        client.post("$normalized/api/playback-progress") {
            contentType(ContentType.Application.Json)
            setBody(
                mapOf(
                    "mediaId" to mediaId,
                    "positionMs" to positionMs,
                    "durationMs" to durationMs,
                ),
            )
        }
    }

    fun close() {
        client.close()
    }
}
