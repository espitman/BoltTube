import AppKit
import Foundation
import Observation
import IOKit.pwr_mgt

#if SWIFT_PACKAGE
private let appResourceBundle = Bundle.module
#else
private let appResourceBundle = Bundle.main
#endif

private func bundledResourceURL(named name: String, withExtension ext: String) -> URL? {
    if let direct = appResourceBundle.url(forResource: name, withExtension: ext) { return direct }
    if let nested = appResourceBundle.url(forResource: name, withExtension: ext, subdirectory: "Resources") { return nested }
    return nil
}

struct MediaLibraryItem: Codable, Identifiable, Hashable {
    let id: String; let fileName: String; let streamUrl: String; let size: String; let createdAt: String; let thumbnailUrl: String?; let duration: Int; let sourceUrl: String; let title: String
}

struct Playlist: Codable, Identifiable, Hashable {
    let id: Int; let name: String; let thumbnailUrl: String?; let createdAt: String; let itemCount: Int
}

struct Channel: Codable, Identifiable, Hashable {
    let id: Int; let name: String; let thumbnailUrl: String?; let createdAt: String; let playlistCount: Int
}
struct ChannelResponse: Codable { let items: [Channel] }
struct PlaylistResponse: Codable { let items: [Playlist] }
struct MediaLibraryResponse: Codable { let items: [MediaLibraryItem] }
struct DownloadResponse: Codable { let id: String; let streamUrl: String; let fileName: String }

private final class DownloadStreamState: @unchecked Sendable {
    private let lock = NSLock(); private var stderrBuffer = ""; private var didResume = false
    func append(text: String) -> [String] { lock.lock(); defer { lock.unlock() }; stderrBuffer.append(text); let lines = stderrBuffer.components(separatedBy: "\n"); stderrBuffer = lines.last ?? ""; return Array(lines.dropLast()).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    func takeRemainder() -> String { lock.lock(); defer { lock.unlock() }; let remainder = stderrBuffer; stderrBuffer = ""; return remainder }
    func markResumed() -> Bool { lock.lock(); defer { lock.unlock() }; if didResume { return false }; didResume = true; return true }
}

struct RemoteFormat: Codable, Identifiable, Hashable { let id: String; let title: String; let details: String; let filesize: String }
struct DownloadTask: Identifiable, Hashable { let id: String; let title: String; var status: String; var progress: Double }
struct ResolveResponse: Codable { let title: String; let thumbnailUrl: String; let durationSeconds: Int; let formats: [RemoteFormat] }
struct HealthResponse: Codable { let status: String; let port: Int; let downloadDir: String }

@Observable
@MainActor
final class ServerController {
    var videoURL = ""; var resolvedTitle = ""; var resolvedThumbnailUrl = ""; var resolvedDurationSeconds: Int = 0; var lastDownloadedFileName = ""; var formats: [RemoteFormat] = []; var selectedFormatID = "best"
    var libraryItems: [MediaLibraryItem] = []; var playlists: [Playlist] = []; var channels: [Channel] = []; var refreshingIDs: Set<String> = []; var logs: String = ""
    var selectedPlaylist: Playlist? = nil; var playlistItems: [MediaLibraryItem] = []; var isFetchingPlaylistItems = false
    var selectedChannel: Channel? = nil; var channelPlaylists: [Playlist] = []; var isFetchingChannelPlaylists = false
    var activeManagementTab: Int = 0 // 0: Playlists, 1: Channels

    var portText = "9864"; var isShareServerRunning = false; var isBusy = false; var isResolvingQualities = false; var isDownloading = false; var downloadProgress: Double = 0; var downloadProgressText = ""; var logText = "Ready.\n"; var lastHealthMessage = ""; var downloadDirectory: URL
    private var shareServerProcess: Process?; private var shareServerOutputPipe: Pipe?; private var qualityRefreshTask: Task<Void, Never>?; private var sleepAssertionID: IOPMAssertionID = 0; private var activeDownloadProcess: Process?; private var activeDownloadTempName: String = ""; private var lastProgressBytes: Double = 0; private var lastProgressTime: Date = Date()

    init() {
        let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Movies/BoltTubeNative", directoryHint: .isDirectory); self.downloadDirectory = defaultDirectory; ensureDirectoryExists(defaultDirectory)
        Task { await startShareServer(); await refreshLibrary(); await refreshPlaylists(); await refreshChannels() }
    }

    var statusLine: String { isShareServerRunning ? "Share server is running" : "Share server is stopped" }
    var serverURLDisplay: String { "http://127.0.0.1:\(normalizedPort)" }
    var lanURLDisplay: String { "http://\(localIPAddress() ?? "YOUR-MAC-IP"):\(normalizedPort)" }

    func refreshChannels() async {
        guard let url = URL(string: "\(serverURLDisplay)/api/channels") else { return }
        do { 
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let r = response as? HTTPURLResponse, (200..<300).contains(r.statusCode) else { return }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let decoded = try decoder.decode(ChannelResponse.self, from: data)
            channels = decoded.items
            appendLog("Channels refreshed: \(channels.count) items.")
        } catch { 
            appendLog("Channels refresh failed: \(error.localizedDescription)")
            print("Decoding Error: \(error)")
        }
    }

    func createChannel(name: String) async {
        guard let url = URL(string: "\(serverURLDisplay)/api/channels/create") else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.addValue("application/json", forHTTPHeaderField: "Content-Type"); let body = ["name": name]; request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do { 
            let (data, response) = try await URLSession.shared.data(for: request)
            if let r = response as? HTTPURLResponse { appendLog("Create channel response: \(r.statusCode)") }
            await refreshChannels() 
        } catch { 
            appendLog("Create channel failed: \(error.localizedDescription)") 
        }
    }

    func deleteChannel(id: Int) async {
        guard let url = URL(string: "\(serverURLDisplay)/api/channels/delete") else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.addValue("application/json", forHTTPHeaderField: "Content-Type"); let body = ["id": id]; request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do { _ = try await URLSession.shared.data(for: request); await refreshChannels() } catch { appendLog("Delete channel failed.") }
    }

    func updateChannel(id: Int, name: String) async {
        guard let url = URL(string: "\(serverURLDisplay)/api/channels/update") else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.addValue("application/json", forHTTPHeaderField: "Content-Type"); let body: [String: Any] = ["id": id, "name": name]; request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do { _ = try await URLSession.shared.data(for: request); await refreshChannels() } catch { appendLog("Update channel failed.") }
    }

    func addPlaylistToChannel(channelID: Int, playlistID: Int) async {
        guard let url = URL(string: "\(serverURLDisplay)/api/channels/add") else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.addValue("application/json", forHTTPHeaderField: "Content-Type"); let body: [String: Any] = ["channelId": channelID, "playlistId": playlistID]; request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do { _ = try await URLSession.shared.data(for: request); await refreshChannels() } catch { appendLog("Add playlist to channel failed.") }
    }

    func chooseDownloadDirectory() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false; panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url { downloadDirectory = url; ensureDirectoryExists(url); appendLog("Library folder set to \(url.path)"); Task { await refreshLibrary() } }
    }
    func openDownloadDirectory() { ensureDirectoryExists(downloadDirectory); NSWorkspace.shared.open(downloadDirectory) }
    func pasteFromClipboard() {
        let pb = NSPasteboard.general; let value = pb.string(forType: .string) ?? pb.string(forType: .URL) ?? pb.string(forType: NSPasteboard.PasteboardType("public.url"))
        if let value = value { let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines); appendLog("Pasted: \(trimmed.prefix(60))..."); videoURL = trimmed; scheduleQualityRefresh() }
    }
    func scheduleQualityRefresh() {
        qualityRefreshTask?.cancel(); let trimmedURL = videoURL.trimmingCharacters(in: .whitespacesAndNewlines); if trimmedURL.isEmpty { resolvedTitle = ""; formats = []; selectedFormatID = "best"; return }
        qualityRefreshTask = Task { [weak self] in do { try await Task.sleep(for: .milliseconds(600)) } catch { return }; guard !Task.isCancelled else { return }; await self?.resolveQualities(for: trimmedURL) }
    }
    func downloadVideo() async {
        guard !isBusy else { return }
        guard await ensurePythonReady() else { return }
        let url = videoURL.trimmingCharacters(in: .whitespacesAndNewlines); guard !url.isEmpty else { return }
        isBusy = true; isDownloading = true; downloadProgress = 0; downloadProgressText = "Starting download..."
        defer { isBusy = false; isDownloading = false }
        do {
            let data = try await runDownloadCommand(arguments: [bridgeScriptURL.path, "download-progress", "--download-dir", downloadDirectory.path, "--url", url, "--format-id", selectedFormatID])
            let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; let response = try decoder.decode(DownloadResponse.self, from: data)
            lastDownloadedFileName = response.fileName; downloadProgress = 1; downloadProgressText = "Download complete"; appendLog("Saved \(response.fileName)"); await refreshLibrary(); videoURL = ""; resolvedTitle = ""; resolvedThumbnailUrl = ""; resolvedDurationSeconds = 0; formats = []; selectedFormatID = "best"
        } catch { appendLog("Download failed: \(error.localizedDescription)"); downloadProgressText = "Download failed" }
    }

    func cancelDownload() {
        if let process = activeDownloadProcess { let pid = process.processIdentifier; process.terminate(); _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/pkill"), arguments: ["-TERM", "-P", "\(pid)"]) }
        activeDownloadProcess = nil; let tempName = activeDownloadTempName
        if !tempName.isEmpty { let fm = FileManager.default; if let files = try? fm.contentsOfDirectory(atPath: downloadDirectory.path) { for file in files where file.hasPrefix(tempName) { let url = downloadDirectory.appendingPathComponent(file); try? fm.removeItem(at: url); appendLog("Cleaned up partial file: \(file)") } } }
        activeDownloadTempName = ""; isDownloading = false; isBusy = false; downloadProgress = 0; downloadProgressText = "Cancelled"
    }

    func deleteItem(id: String) async {
        guard let url = URL(string: "\(serverURLDisplay)/api/delete") else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); let body: [String: String] = ["id": id]; request.httpBody = try? JSONEncoder().encode(body)
        do { let (_, response) = try await URLSession.shared.data(for: request); guard let r = response as? HTTPURLResponse, (200..<300).contains(r.statusCode) else { return }; appendLog("Deleted item: \(id)"); await refreshLibrary() } catch { appendLog("Network error during delete.") }
    }

    func refreshMetadata(id: String) async {
        guard let url = URL(string: "\(serverURLDisplay)/api/refresh-metadata") else { return }; _ = await MainActor.run { refreshingIDs.insert(id) }
        defer { Task { _ = await MainActor.run { refreshingIDs.remove(id) } } }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); let body: [String: String] = ["id": id]; request.httpBody = try? JSONEncoder().encode(body)
        do { appendLog("Refreshing metadata for \(id)..."); let (_, response) = try await URLSession.shared.data(for: request); guard let r = response as? HTTPURLResponse, (200..<300).contains(r.statusCode) else { return }; appendLog("Metadata refreshed."); await refreshLibrary() } catch { appendLog("Refresh failed.") }
    }

    func localURL(for item: MediaLibraryItem) -> URL { return URL(string: "\(lanURLDisplay)\(item.streamUrl)")! }
    func refreshLibrary() async {
        do { let data = try await runJSONCommand(arguments: [bridgeScriptURL.path, "list", "--download-dir", downloadDirectory.path], logOutput: false); let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; let decoded = try decoder.decode(MediaLibraryResponse.self, from: data); libraryItems = decoded.items } catch { appendLog("Library refresh failed.") }
    }

    func refreshPlaylists() async {
        guard let url = URL(string: "\(serverURLDisplay)/api/playlists") else { return }
        do { let (data, response) = try await URLSession.shared.data(from: url); guard let r = response as? HTTPURLResponse, (200..<300).contains(r.statusCode) else { return }; let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; let decoded = try decoder.decode(PlaylistResponse.self, from: data); playlists = decoded.items } catch { appendLog("Playlists refresh failed.") }
    }

    func fetchPlaylistItems(id: Int) async {
        guard let url = URL(string: "\(serverURLDisplay)/api/playlists/\(id)/items") else { return }
        isFetchingPlaylistItems = true; defer { isFetchingPlaylistItems = false }
        do { let (data, response) = try await URLSession.shared.data(from: url); guard let r = response as? HTTPURLResponse, (200..<300).contains(r.statusCode) else { return }; let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; let decoded = try decoder.decode(MediaLibraryResponse.self, from: data); playlistItems = decoded.items } catch { appendLog("Fetch playlist items failed.") }
    }

    func createPlaylist(name: String) async {
        guard let url = URL(string: "\(serverURLDisplay)/api/playlists/create") else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.addValue("application/json", forHTTPHeaderField: "Content-Type"); let body = ["name": name]; request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do { _ = try await URLSession.shared.data(for: request); await refreshPlaylists() } catch { appendLog("Create playlist failed.") }
    }

    func addToPlaylist(playlistID: Int, mediaID: String) async {
        guard let url = URL(string: "\(serverURLDisplay)/api/playlists/add") else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.addValue("application/json", forHTTPHeaderField: "Content-Type"); let body: [String: Any] = ["playlistId": playlistID, "mediaId": mediaID]; request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do { _ = try await URLSession.shared.data(for: request); await refreshPlaylists() } catch { appendLog("Add to playlist failed.") }
    }

    func updatePlaylist(id: Int, name: String) async {
        guard let url = URL(string: "\(serverURLDisplay)/api/playlists/update") else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.addValue("application/json", forHTTPHeaderField: "Content-Type"); let body: [String: Any] = ["id": id, "name": name]; request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do { _ = try await URLSession.shared.data(for: request); await refreshPlaylists() } catch { appendLog("Update playlist failed.") }
    }

    func deletePlaylist(id: Int) async {
        guard let url = URL(string: "\(serverURLDisplay)/api/playlists/delete") else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.addValue("application/json", forHTTPHeaderField: "Content-Type"); let body = ["id": id]; request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do { _ = try await URLSession.shared.data(for: request); await refreshPlaylists() } catch { appendLog("Delete playlist failed.") }
    }

    func startShareServer() async {
        guard !isShareServerRunning else { return }
        guard !isBusy else { return }
        guard await ensurePythonReady() else { return }
        isBusy = true; defer { isBusy = false }; ensureDirectoryExists(downloadDirectory)
        let process = Process(); let outputPipe = Pipe(); process.executableURL = venvPythonURL; process.arguments = [bridgeScriptURL.path, "serve", "--port", normalizedPort, "--download-dir", downloadDirectory.path]; process.environment = mergedEnvironment(extra: ["PYTHONUNBUFFERED": "1"]); process.standardOutput = outputPipe; process.standardError = outputPipe
        process.terminationHandler = { _ in Task { @MainActor in self.isShareServerRunning = false; self.appendLog("Share server exited.") } }
        outputPipe.fileHandleForReading.readabilityHandler = { handle in let data = handle.availableData; guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }; Task { @MainActor in self.appendLog(text.trimmingCharacters(in: .newlines)) } }
        do { appendLog("Starting share server..."); try process.run(); shareServerProcess = process; shareServerOutputPipe = outputPipe; isShareServerRunning = true; _ = IOPMAssertionCreateWithDescription(kIOPMAssertionTypeNoIdleSleep as CFString, "BoltTube Bridge Server Running" as CFString, nil, nil, nil, 0, nil, &sleepAssertionID); try await Task.sleep(for: .seconds(2)); await checkHealth() } catch { appendLog("Failed to start server."); outputPipe.fileHandleForReading.readabilityHandler = nil; shareServerProcess = nil; shareServerOutputPipe = nil }
    }

    func stopShareServer() { shareServerOutputPipe?.fileHandleForReading.readabilityHandler = nil; shareServerProcess?.terminate(); shareServerProcess = nil; shareServerOutputPipe = nil; isShareServerRunning = false; if sleepAssertionID != 0 { IOPMAssertionRelease(sleepAssertionID); sleepAssertionID = 0 } }
    func checkHealth() async { guard let url = URL(string: "\(serverURLDisplay)/health") else { return }; do { let (data, _) = try await URLSession.shared.data(from: url); let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; let decoded = try decoder.decode(HealthResponse.self, from: data); lastHealthMessage = "Share server OK on port \(decoded.port)."; appendLog(lastHealthMessage) } catch { lastHealthMessage = "Health check failed."; appendLog(lastHealthMessage) } }
    private func ensurePythonReady() async -> Bool { if FileManager.default.fileExists(atPath: venvPythonURL.path) { return true }; appendLog("Preparing Python..."); await installPythonEnvironment(); return FileManager.default.fileExists(atPath: venvPythonURL.path) }
    private func installPythonEnvironment() async { do { ensureDirectoryExists(appSupportDirectory); ensureDirectoryExists(downloadDirectory); if !FileManager.default.fileExists(atPath: venvPythonURL.path) { try await runCommand(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-m", "venv", venvDirectory.path]) }; try await runCommand(executable: venvPipURL, arguments: ["install", "-r", requirementsURL.path]); appendLog("Python ready.") } catch { appendLog("Python setup failed.") } }
    private func resolveQualities(for url: String) async { guard await ensurePythonReady() else { return }; isResolvingQualities = true; defer { isResolvingQualities = false }; do { let data = try await runJSONCommand(arguments: [bridgeScriptURL.path, "resolve", "--download-dir", downloadDirectory.path, "--url", url], logOutput: false); let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; let response = try decoder.decode(ResolveResponse.self, from: data); guard videoURL.trimmingCharacters(in: .whitespacesAndNewlines) == url else { return }; resolvedTitle = response.title; resolvedThumbnailUrl = response.thumbnailUrl; resolvedDurationSeconds = response.durationSeconds; formats = response.formats; selectedFormatID = response.formats.last?.id ?? "best" } catch { appendLog("Quality load failed.") } }
    private var normalizedPort: String { let digits = portText.filter(\.isNumber); return digits.isEmpty ? "9864" : digits }
    private var appSupportDirectory: URL { FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/BoltTubeMacNative", directoryHint: .isDirectory) }
    private var venvDirectory: URL { appSupportDirectory.appending(path: ".venv", directoryHint: .isDirectory) }
    private var venvPythonURL: URL { venvDirectory.appending(path: "bin/python3", directoryHint: .notDirectory) }
    private var venvPipURL: URL { venvDirectory.appending(path: "bin/pip", directoryHint: .notDirectory) }
    private var requirementsURL: URL { guard let url = bundledResourceURL(named: "requirements", withExtension: "txt") else { fatalError() }; return url }
    private var bridgeScriptURL: URL { guard let url = bundledResourceURL(named: "bridge_server", withExtension: "py") else { fatalError() }; return url }
    private func runJSONCommand(arguments: [String], logOutput: Bool = true) async throws -> Data { try await Task.detached { [venvPythonURL] in let process = Process(); let outputPipe = Pipe(); let errorPipe = Pipe(); process.executableURL = venvPythonURL; process.arguments = arguments; process.environment = Self.staticMergedEnvironment(extra: ["PYTHONUNBUFFERED": "1"]); process.standardOutput = outputPipe; process.standardError = errorPipe; try process.run(); let outputData = try outputPipe.fileHandleForReading.readToEnd() ?? Data(); process.waitUntilExit(); if process.terminationStatus != 0 { throw NSError(domain: "BoltTube", code: Int(process.terminationStatus)) }; return outputData }.value }
    private func runDownloadCommand(arguments: [String]) async throws -> Data { try await withCheckedThrowingContinuation { continuation in let process = Process(); let outputPipe = Pipe(); let errorPipe = Pipe(); let state = DownloadStreamState(); process.executableURL = venvPythonURL; process.arguments = arguments; process.environment = mergedEnvironment(extra: ["PYTHONUNBUFFERED": "1"]); process.standardOutput = outputPipe; process.standardError = errorPipe; errorPipe.fileHandleForReading.readabilityHandler = { handle in let data = handle.availableData; guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }; let lines = state.append(text: text); Task { @MainActor [weak self] in for l in lines { self?.handleDownloadProgressLine(l) } } }; process.terminationHandler = { _ in Task { @MainActor [weak self] in self?.activeDownloadProcess = nil; self?.isDownloading = false; do { let d = try outputPipe.fileHandleForReading.readToEnd() ?? Data(); if state.markResumed() { continuation.resume(returning: d) } } catch { if state.markResumed() { continuation.resume(throwing: error) } } } }; do { try process.run(); Task { @MainActor [weak self] in self?.activeDownloadProcess = process } } catch { if state.markResumed() { continuation.resume(throwing: error) } } } }
    private func runCommand(executable: URL, arguments: [String]) async throws { try await Task.detached { let process = Process(); let pipe = Pipe(); process.executableURL = executable; process.arguments = arguments; process.environment = Self.staticMergedEnvironment(); process.standardOutput = pipe; process.standardError = pipe; try process.run(); process.waitUntilExit(); if process.terminationStatus != 0 { throw NSError(domain: "BoltTube", code: Int(process.terminationStatus)) } }.value }
    private func mergedEnvironment(extra: [String: String] = [:]) -> [String: String] { Self.staticMergedEnvironment(extra: extra) }
    nonisolated private static func staticMergedEnvironment(extra: [String: String] = [:]) -> [String: String] { var environment = ProcessInfo.processInfo.environment; environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"; extra.forEach { environment[$0.key] = $0.value }; return environment }
    private func ensureDirectoryExists(_ url: URL) { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    private func appendLog(_ message: String) { let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines); guard !trimmed.isEmpty else { return }; logText.append("\(trimmed)\n") }
    private func handleDownloadProgressLine(_ line: String) { guard let data = line.data(using: .utf8) else { return }; if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let event = json["event"] as? String { if event == "progress", let frac = json["fraction"] as? Double { downloadProgress = frac; downloadProgressText = "\(Int(frac * 100))%" } else if event == "starting" { appendLog("Starting..."); if let t = json["tempName"] as? String { activeDownloadTempName = t } } else if event == "merging" { downloadProgressText = "Merging..."; appendLog("Processing final file...") } } }
    private func localIPAddress() -> String? { var address: String?; var ifaddr: UnsafeMutablePointer<ifaddrs>?; if getifaddrs(&ifaddr) == 0 { var ptr = ifaddr; while ptr != nil { defer { ptr = ptr?.pointee.ifa_next }; let i = ptr?.pointee; if i?.ifa_addr.pointee.sa_family == UInt8(AF_INET) { let n = String(cString: i!.ifa_name); if n == "en0" || n == "en1" { var h = [CChar](repeating: 0, count: Int(NI_MAXHOST)); getnameinfo(i!.ifa_addr, socklen_t(i!.ifa_addr.pointee.sa_len), &h, socklen_t(h.count), nil, socklen_t(0), NI_NUMERICHOST); address = String(decoding: h.filter { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) } } }; freeifaddrs(ifaddr) }; return address }
}
