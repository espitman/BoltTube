package ir.boum.bolttube.server

import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.Application
import io.ktor.server.application.call
import io.ktor.server.application.install
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.plugins.callloging.CallLogging
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.plugins.cors.routing.CORS
import io.ktor.server.plugins.partialcontent.PartialContent
import io.ktor.server.request.receive
import io.ktor.server.response.respond
import io.ktor.server.response.respondFile
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.routing
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.time.Instant
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

private const val SERVER_PORT = 9864
private val json = Json {
    ignoreUnknownKeys = true
    prettyPrint = true
}

fun main() {
    embeddedServer(Netty, port = SERVER_PORT, host = "0.0.0.0") {
        boltTubeModule()
    }.start(wait = true)
}

fun Application.boltTubeModule() {
    install(CallLogging)
    install(ContentNegotiation) {
        json(json)
    }
    install(CORS) {
        anyHost()
        allowHeader(HttpHeaders.ContentType)
    }
    install(PartialContent)

    val service = MediaBridgeService()

    routing {
        get("/health") {
            call.respond(HealthResponse(status = "ok", port = SERVER_PORT))
        }

        post("/api/resolve") {
            val request = call.receive<ResolveRequest>()
            call.respond(service.resolve(request.url))
        }

        post("/api/download") {
            val request = call.receive<DownloadRequest>()
            call.respond(service.download(request))
        }

        get("/api/items") {
            call.respond(MediaLibraryResponse(items = service.listItems()))
        }

        get("/media/{id}") {
            val id = call.parameters["id"].orEmpty()
            val item = service.findItem(id)
            if (item == null || !item.file.exists()) {
                call.respond(HttpStatusCode.NotFound, ErrorResponse(error = "Media not found"))
                return@get
            }
            call.respondFile(item.file)
        }
    }
}

private class MediaBridgeService {
    private val downloadsDir = File(System.getProperty("user.home"), "Movies/BoltTube").apply { mkdirs() }
    private val items = ConcurrentHashMap<String, MediaItem>()

    fun resolve(url: String): ResolveResponse {
        val output = runCommand(
            listOf(
                ytDlpBinary(),
                "--cookies-from-browser", "chrome",
                "--no-playlist",
                "--dump-single-json",
                url,
            ),
        )

        val payload = json.decodeFromString(VideoInfo.serializer(), output)
        val formats = payload.formats
            .filter { it.formatId.isNotBlank() && it.ext == "mp4" && it.vcodec != "none" }
            .sortedByDescending { it.height ?: 0 }
            .map { format ->
                RemoteFormat(
                    id = format.formatId,
                    title = buildString {
                        append(format.height?.let { "${it}p" } ?: "MP4")
                        format.fps?.let { append(" ${it}fps") }
                    }.trim(),
                    details = listOfNotNull(
                        format.formatNote?.takeIf(String::isNotBlank),
                        format.filesize?.let(::readableSize),
                    ).joinToString(" • ").ifBlank { "MP4 stream" },
                )
            }
            .distinctBy { it.id }

        return ResolveResponse(
            title = payload.title,
            formats = listOf(
                RemoteFormat(
                    id = "best",
                    title = "Best",
                    details = "Best merged result available",
                ),
                RemoteFormat(
                    id = "safe",
                    title = "Safe MP4",
                    details = "Most compatible single-file MP4 fallback",
                ),
            ) + formats,
        )
    }

    fun download(request: DownloadRequest): DownloadResponse {
        val uuid = UUID.randomUUID().toString()
        val fileId = "${safeName(request.url)}-$uuid"
        val file = File(downloadsDir, "$fileId.mp4")
        val format = when (request.formatId) {
            "best" -> "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"
            "safe" -> "best[ext=mp4]/best"
            else -> request.formatId
        }

        runCommand(
            listOf(
                ytDlpBinary(),
                "--cookies-from-browser", "chrome",
                "--no-playlist",
                "-f", format,
                "-o", file.absolutePath,
                request.url,
            ),
        )

        val item = MediaItem(
            id = fileId,
            sourceUrl = request.url,
            file = file,
            createdAt = Instant.now().toString(),
        )
        items[fileId] = item

        return DownloadResponse(
            id = fileId,
            streamUrl = "/media/$fileId",
            fileName = file.name,
        )
    }

    fun listItems(): List<MediaSummary> {
        syncDiskLibrary()
        return items.values
            .sortedByDescending { it.createdAt }
            .map { item ->
                MediaSummary(
                    id = item.id,
                    fileName = item.file.name,
                    streamUrl = "/media/${item.id}",
                    size = readableSize(item.file.length()),
                    createdAt = item.createdAt,
                )
            }
    }

    fun findItem(id: String): MediaItem? {
        syncDiskLibrary()
        return items[id]
    }

    private fun syncDiskLibrary() {
        downloadsDir.listFiles()
            ?.filter { it.isFile && it.extension.equals("mp4", ignoreCase = true) }
            ?.forEach { file ->
                items.computeIfAbsent(file.nameWithoutExtension) {
                    MediaItem(
                        id = file.nameWithoutExtension,
                        sourceUrl = "",
                        file = file,
                        createdAt = Instant.ofEpochMilli(file.lastModified()).toString(),
                    )
                }
            }
    }

    private fun runCommand(command: List<String>): String {
        val process = ProcessBuilder(command)
            .directory(downloadsDir)
            .redirectErrorStream(true)
            .start()
        val output = process.inputStream.bufferedReader().readText()
        val exitCode = process.waitFor()
        if (exitCode != 0) {
            error(output.ifBlank { "Command failed: ${command.joinToString(" ")}" })
        }
        return output
    }

    private fun ytDlpBinary(): String {
        return listOf(
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "yt-dlp",
        ).firstOrNull { candidate ->
            if (candidate.contains("/")) File(candidate).exists() else true
        } ?: "yt-dlp"
    }

    private fun safeName(url: String): String {
        return url.hashCode().toString().replace("-", "m")
    }

    private fun readableSize(bytes: Long): String {
        if (bytes <= 0L) return ""
        val mb = bytes / (1024f * 1024f)
        return if (mb >= 1024f) {
            String.format("%.2f GB", mb / 1024f)
        } else {
            String.format("%.1f MB", mb)
        }
    }
}

@Serializable
data class ResolveRequest(val url: String)

@Serializable
data class DownloadRequest(val url: String, val formatId: String)

@Serializable
data class ResolveResponse(
    val title: String = "",
    val formats: List<RemoteFormat> = emptyList(),
)

@Serializable
data class RemoteFormat(
    val id: String,
    val title: String,
    val details: String,
)

@Serializable
data class DownloadResponse(
    val id: String,
    val streamUrl: String,
    val fileName: String,
)

@Serializable
data class HealthResponse(
    val status: String,
    val port: Int,
)

@Serializable
data class ErrorResponse(
    val error: String,
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
    val items: List<MediaSummary>,
)

@Serializable
data class VideoInfo(
    val title: String = "",
    val formats: List<VideoFormatInfo> = emptyList(),
)

@Serializable
data class VideoFormatInfo(
    @SerialName("format_id")
    val formatId: String = "",
    val ext: String? = null,
    val height: Int? = null,
    val fps: Int? = null,
    @SerialName("format_note")
    val formatNote: String? = null,
    val filesize: Long? = null,
    val vcodec: String? = null,
)

private data class MediaItem(
    val id: String,
    val sourceUrl: String,
    val file: File,
    val createdAt: String,
)
