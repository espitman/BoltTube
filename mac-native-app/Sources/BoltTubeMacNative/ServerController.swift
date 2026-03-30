import AppKit
import Foundation
import Observation

struct MediaLibraryItem: Codable, Identifiable, Hashable {
    let id: String
    let fileName: String
    let streamUrl: String
    let size: String
    let createdAt: String
}

struct MediaLibraryResponse: Codable {
    let items: [MediaLibraryItem]
}

struct DownloadResponse: Codable {
    let id: String
    let streamUrl: String
    let fileName: String
}

private final class DownloadStreamState: @unchecked Sendable {
    private let lock = NSLock()
    private var stderrBuffer = ""
    private var didResume = false

    func append(text: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        stderrBuffer.append(text)
        let lines = stderrBuffer.components(separatedBy: "\n")
        stderrBuffer = lines.last ?? ""
        return Array(lines.dropLast()).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func takeRemainder() -> String {
        lock.lock()
        defer { lock.unlock() }
        let remainder = stderrBuffer
        stderrBuffer = ""
        return remainder
    }

    func markResumed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if didResume {
            return false
        }
        didResume = true
        return true
    }
}

struct RemoteFormat: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let details: String
    let filesize: String
}

struct ResolveResponse: Codable {
    let title: String
    let thumbnailUrl: String
    let durationSeconds: Int
    let formats: [RemoteFormat]
}

@Observable
@MainActor
final class ServerController {
    var videoURL = ""
    var resolvedTitle = ""
    var resolvedThumbnailUrl = ""
    var resolvedDurationSeconds: Int = 0
    var lastDownloadedFileName = ""
    var formats: [RemoteFormat] = []
    var selectedFormatID = "best"
    var libraryItems: [MediaLibraryItem] = []

    var portText = "9864"
    var isShareServerRunning = false
    var isBusy = false
    var isResolvingQualities = false
    var isDownloading = false
    var downloadProgress: Double = 0
    var downloadProgressText = ""
    var logText = "Ready.\n"
    var lastHealthMessage = ""
    var downloadDirectory: URL

    private var shareServerProcess: Process?
    private var shareServerOutputPipe: Pipe?
    private var qualityRefreshTask: Task<Void, Never>?

    init() {
        let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Movies/BoltTubeNative", directoryHint: .isDirectory)
        self.downloadDirectory = defaultDirectory
        ensureDirectoryExists(defaultDirectory)
    }

    var statusLine: String {
        isShareServerRunning ? "Share server is running" : "Share server is stopped"
    }

    var serverURLDisplay: String {
        "http://127.0.0.1:\(normalizedPort)"
    }

    var lanURLDisplay: String {
        "http://\(localIPAddress() ?? "YOUR-MAC-IP"):\(normalizedPort)"
    }

    func chooseDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            downloadDirectory = url
            ensureDirectoryExists(url)
            appendLog("Library folder set to \(url.path)")
            Task { await refreshLibrary() }
        }
    }

    func openDownloadDirectory() {
        ensureDirectoryExists(downloadDirectory)
        NSWorkspace.shared.open(downloadDirectory)
    }

    func pasteFromClipboard() {
        if let value = NSPasteboard.general.string(forType: .string) {
            videoURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
            scheduleQualityRefresh()
        }
    }

    func scheduleQualityRefresh() {
        qualityRefreshTask?.cancel()

        let trimmedURL = videoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedURL.isEmpty {
            resolvedTitle = ""
            formats = []
            selectedFormatID = "best"
            return
        }

        qualityRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(600))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.resolveQualities(for: trimmedURL)
        }
    }

    func downloadVideo() async {
        guard !isBusy else { return }
        guard await ensurePythonReady() else { return }

        let url = videoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        isBusy = true
        isDownloading = true
        downloadProgress = 0
        downloadProgressText = "Starting download..."
        defer { isBusy = false }
        defer { isDownloading = false }

        do {
            appendLog("Downloading on Mac...")
            let data = try await runDownloadCommand(
                arguments: [
                    bridgeScriptURL.path,
                    "download-progress",
                    "--download-dir", downloadDirectory.path,
                    "--url", url,
                    "--format-id", selectedFormatID,
                ]
            )
            let response = try JSONDecoder().decode(DownloadResponse.self, from: data)
            lastDownloadedFileName = response.fileName
            downloadProgress = 1
            downloadProgressText = "Download complete"
            appendLog("Saved \(response.fileName)")
            await refreshLibrary()
        } catch {
            appendLog("Download failed: \(error.localizedDescription)")
            downloadProgressText = "Download failed"
        }
    }

    func refreshLibrary() async {
        do {
            let data = try await runJSONCommand(
                arguments: [
                    bridgeScriptURL.path,
                    "list",
                    "--download-dir", downloadDirectory.path,
                ],
                logOutput: false
            )
            let response = try JSONDecoder().decode(MediaLibraryResponse.self, from: data)
            libraryItems = response.items
        } catch {
            appendLog("Library refresh failed: \(error.localizedDescription)")
        }
    }

    func startShareServer() async {
        guard !isShareServerRunning, !isBusy else { return }
        guard await ensurePythonReady() else { return }

        isBusy = true
        defer { isBusy = false }

        ensureDirectoryExists(downloadDirectory)

        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = venvPythonURL
        process.arguments = [
            bridgeScriptURL.path,
            "serve",
            "--port", normalizedPort,
            "--download-dir", downloadDirectory.path,
        ]
        process.environment = mergedEnvironment(extra: [
            "PYTHONUNBUFFERED": "1",
        ])
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                self?.isShareServerRunning = false
                self?.appendLog("Share server exited with code \(process.terminationStatus).")
            }
        }

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.appendLog(text.trimmingCharacters(in: .newlines))
            }
        }

        do {
            appendLog("Starting share server...")
            try process.run()
            shareServerProcess = process
            shareServerOutputPipe = outputPipe
            isShareServerRunning = true
            try await Task.sleep(for: .seconds(1))
            await checkHealth()
        } catch {
            appendLog("Failed to start share server: \(error.localizedDescription)")
            outputPipe.fileHandleForReading.readabilityHandler = nil
            shareServerProcess = nil
            shareServerOutputPipe = nil
        }
    }

    func stopShareServer() {
        shareServerOutputPipe?.fileHandleForReading.readabilityHandler = nil
        shareServerProcess?.terminate()
        shareServerProcess = nil
        shareServerOutputPipe = nil
        isShareServerRunning = false
        appendLog("Share server stop requested.")
    }

    func checkHealth() async {
        guard let url = URL(string: "\(serverURLDisplay)/health") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard
                let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode)
            else {
                lastHealthMessage = "Health check failed."
                appendLog(lastHealthMessage)
                return
            }

            let decoded = try JSONDecoder().decode(HealthResponse.self, from: data)
            lastHealthMessage = "Share server OK on port \(decoded.port). Library: \(decoded.downloadDir)"
            appendLog(lastHealthMessage)
        } catch {
            lastHealthMessage = "Health check failed: \(error.localizedDescription)"
            appendLog(lastHealthMessage)
        }
    }

    private func ensurePythonReady() async -> Bool {
        if FileManager.default.fileExists(atPath: venvPythonURL.path) {
            return true
        }
        appendLog("Python environment missing. Preparing it automatically...")
        await installPythonEnvironment()
        return FileManager.default.fileExists(atPath: venvPythonURL.path)
    }

    private func installPythonEnvironment() async {
        do {
            ensureDirectoryExists(appSupportDirectory)
            ensureDirectoryExists(downloadDirectory)

            if !FileManager.default.fileExists(atPath: venvPythonURL.path) {
                appendLog("Creating Python virtual environment...")
                try await runCommand(
                    executable: URL(fileURLWithPath: "/usr/bin/python3"),
                    arguments: ["-m", "venv", venvDirectory.path]
                )
            }

            appendLog("Installing pytubefix...")
            try await runCommand(
                executable: venvPipURL,
                arguments: ["install", "-r", requirementsURL.path]
            )
            appendLog("Python environment is ready.")
        } catch {
            appendLog("Python setup failed: \(error.localizedDescription)")
        }
    }

    private func resolveQualities(for url: String) async {
        guard await ensurePythonReady() else { return }

        isResolvingQualities = true
        defer { isResolvingQualities = false }

        do {
            let data = try await runJSONCommand(
                arguments: [
                    bridgeScriptURL.path,
                    "resolve",
                    "--download-dir", downloadDirectory.path,
                    "--url", url,
                ],
                logOutput: false
            )
            let response = try JSONDecoder().decode(ResolveResponse.self, from: data)
            guard videoURL.trimmingCharacters(in: .whitespacesAndNewlines) == url else { return }
            resolvedTitle = response.title
            resolvedThumbnailUrl = response.thumbnailUrl
            resolvedDurationSeconds = response.durationSeconds
            formats = response.formats
            selectedFormatID = response.formats.last?.id ?? "best"
        } catch {
            appendLog("Quality load failed: \(error.localizedDescription)")
        }
    }

    private var normalizedPort: String {
        let digits = portText.filter(\.isNumber)
        return digits.isEmpty ? "9864" : digits
    }

    private var appSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/BoltTubeMacNative", directoryHint: .isDirectory)
    }

    private var venvDirectory: URL {
        appSupportDirectory.appending(path: ".venv", directoryHint: .isDirectory)
    }

    private var venvPythonURL: URL {
        venvDirectory.appending(path: "bin/python3", directoryHint: .notDirectory)
    }

    private var venvPipURL: URL {
        venvDirectory.appending(path: "bin/pip", directoryHint: .notDirectory)
    }

    private var requirementsURL: URL {
        guard let url = Bundle.module.url(forResource: "requirements", withExtension: "txt") else {
            fatalError("Missing requirements.txt resource")
        }
        return url
    }

    private var bridgeScriptURL: URL {
        guard let url = Bundle.module.url(forResource: "bridge_server", withExtension: "py") else {
            fatalError("Missing bridge_server.py resource")
        }
        return url
    }

    private func runJSONCommand(arguments: [String], logOutput: Bool = true) async throws -> Data {
        try await Task.detached(priority: .userInitiated) { [venvPythonURL] in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = venvPythonURL
            process.arguments = arguments
            process.environment = Self.staticMergedEnvironment(extra: [
                "PYTHONUNBUFFERED": "1",
            ])
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            let outputData = try outputPipe.fileHandleForReading.readToEnd() ?? Data()
            let errorData = try errorPipe.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorText = String(data: errorData, encoding: .utf8) ?? "Unknown Python error"
                throw NSError(
                    domain: "BoltTubeMacNative",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: errorText]
                )
            }

            if logOutput, let errorText = String(data: errorData, encoding: .utf8), !errorText.isEmpty {
                await MainActor.run {
                    self.appendLog(errorText.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }

            return outputData
        }.value
    }

    private func runDownloadCommand(arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let state = DownloadStreamState()

            process.executableURL = venvPythonURL
            process.arguments = arguments
            process.environment = mergedEnvironment(extra: [
                "PYTHONUNBUFFERED": "1",
            ])
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                let lines = state.append(text: text)
                for line in lines {
                    DispatchQueue.main.async { [weak self] in
                        self?.handleDownloadProgressLine(line)
                    }
                }
            }

            process.terminationHandler = { process in
                errorPipe.fileHandleForReading.readabilityHandler = nil
                do {
                    let outputData = try outputPipe.fileHandleForReading.readToEnd() ?? Data()
                    let errorData = try errorPipe.fileHandleForReading.readToEnd() ?? Data()
                    let remainder = state.takeRemainder()
                    if !remainder.isEmpty {
                        DispatchQueue.main.async { [weak self] in
                            self?.handleDownloadProgressLine(remainder)
                        }
                    }
                    if process.terminationStatus != 0 {
                        let errorText = String(data: errorData, encoding: .utf8) ?? "Unknown download error"
                        if state.markResumed() {
                            continuation.resume(throwing: NSError(
                                domain: "BoltTubeMacNative",
                                code: Int(process.terminationStatus),
                                userInfo: [NSLocalizedDescriptionKey: errorText]
                            ))
                        }
                        return
                    }
                    if state.markResumed() {
                        continuation.resume(returning: outputData)
                    }
                } catch {
                    if state.markResumed() {
                        continuation.resume(throwing: error)
                    }
                }
            }

            do {
                try process.run()
            } catch {
                if state.markResumed() {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runCommand(executable: URL, arguments: [String]) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = Self.staticMergedEnvironment()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()

            let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()

            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                await MainActor.run {
                    self.appendLog(text.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }

            if process.terminationStatus != 0 {
                throw NSError(
                    domain: "BoltTubeMacNative",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "Command failed: \(arguments.joined(separator: " "))"]
                )
            }
        }.value
    }

    private func mergedEnvironment(extra: [String: String] = [:]) -> [String: String] {
        Self.staticMergedEnvironment(extra: extra)
    }

    nonisolated private static func staticMergedEnvironment(extra: [String: String] = [:]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        extra.forEach { environment[$0.key] = $0.value }
        return environment
    }

    private func ensureDirectoryExists(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func appendLog(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        logText.append("\(trimmed)\n")
    }

    private func handleDownloadProgressLine(_ line: String) {
        guard let data = line.data(using: .utf8) else {
            appendLog(line)
            return
        }

        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = payload["event"] as? String else {
            appendLog(line)
            return
        }

        switch event {
        case "starting":
            let title = payload["title"] as? String ?? "video"
            downloadProgress = 0
            downloadProgressText = "Starting \(title)"
        case "progress":
            let fraction = payload["fraction"] as? Double ?? 0
            let downloadedBytes = payload["downloadedBytes"] as? Double ?? 0
            let totalBytes = payload["totalBytes"] as? Double ?? 0
            downloadProgress = min(max(fraction, 0), 1)
            if totalBytes > 0 {
                downloadProgressText = "\(Int(downloadProgress * 100))% • \(formatBytes(downloadedBytes)) / \(formatBytes(totalBytes))"
            } else {
                downloadProgressText = "\(Int(downloadProgress * 100))%"
            }
        case "merging":
            downloadProgress = 1
            downloadProgressText = "Merging video and audio..."
        default:
            appendLog(line)
        }
    }

    private func formatBytes(_ value: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(value))
    }

    private func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddress = ifaddr else {
            return nil
        }

        defer { freeifaddrs(ifaddr) }

        for pointer in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let family = interface.ifa_addr.pointee.sa_family
            let name = String(cString: interface.ifa_name)

            guard family == UInt8(AF_INET), name != "lo0" else {
                continue
            }

            var hostName = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostName,
                socklen_t(hostName.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            let bytes = hostName.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            address = String(decoding: bytes, as: UTF8.self)
            if address != nil {
                break
            }
        }

        return address
    }
}

private struct HealthResponse: Decodable {
    let status: String
    let port: Int
    let downloadDir: String
}
