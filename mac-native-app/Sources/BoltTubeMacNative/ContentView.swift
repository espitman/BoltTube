import SwiftUI

struct ContentView: View {
    @Bindable var controller: ServerController

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            downloadSection
            shareSection
            librarySection
            logsSection
        }
        .padding(24)
        .task {
            await controller.refreshLibrary()
        }
        .onChange(of: controller.videoURL) { _, _ in
            controller.scheduleQualityRefresh()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("BoltTube Mac")
                    .font(.largeTitle.weight(.bold))
                Text("Paste a YouTube link, download it on your Mac, keep a local library, and share the library with the Android app.")
                    .foregroundStyle(.secondary)
                Text(controller.statusLine)
                    .font(.headline)
                    .foregroundStyle(controller.isShareServerRunning ? .green : .secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text("Share URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(controller.serverURLDisplay)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Text(controller.lanURLDisplay)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    private var downloadSection: some View {
        GroupBox("Download On Mac") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    TextField("https://www.youtube.com/watch?v=...", text: $controller.videoURL)
                        .textFieldStyle(.roundedBorder)

                    Button("Download") {
                        Task { await controller.downloadVideo() }
                    }
                    .disabled(controller.isBusy || controller.videoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Text("لینک را پیست کن و دانلود بزن. اپ روی خود مک دانلود می‌کند و به library اضافه می‌کند.")
                    .foregroundStyle(.secondary)

                if controller.isResolvingQualities {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("در حال گرفتن کیفیت‌ها...")
                            .foregroundStyle(.secondary)
                    }
                } else if !controller.formats.isEmpty {
                    Picker("کیفیت", selection: $controller.selectedFormatID) {
                        ForEach(controller.formats) { format in
                            Text("\(format.title) • \(format.details)")
                                .tag(format.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 520)
                }

                if !controller.lastDownloadedFileName.isEmpty {
                    Text("آخرین دانلود: \(controller.lastDownloadedFileName)")
                        .font(.headline)
                }

                if controller.isDownloading {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: controller.downloadProgress, total: 1.0)
                        Text(controller.downloadProgressText)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    Text("Library Folder")
                        .frame(width: 120, alignment: .leading)
                    Text(controller.downloadDirectory.path)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    Button("Choose Folder") {
                        controller.chooseDownloadDirectory()
                    }
                    Button("Open Folder") {
                        controller.openDownloadDirectory()
                    }
                    if controller.isBusy {
                        ProgressView()
                    }
                    Spacer()
                }
            }
            .padding(.top, 6)
        }
    }

    private var shareSection: some View {
        GroupBox("Share Library To Phone") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("Port")
                        .frame(width: 120, alignment: .leading)
                    TextField("9864", text: $controller.portText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 140)
                    Spacer()
                }

                HStack(spacing: 12) {
                    Button("Start Share Server") {
                        Task { await controller.startShareServer() }
                    }
                    .disabled(controller.isBusy || controller.isShareServerRunning)

                    Button("Stop Share Server") {
                        controller.stopShareServer()
                    }
                    .disabled(!controller.isShareServerRunning)

                    Button("Health Check") {
                        Task { await controller.checkHealth() }
                    }
                    .disabled(controller.isBusy)

                    Spacer()
                }

                Text("این بخش فقط برای نمایش library روی اپ اندروید است. دانلود از همین اپ مک انجام می‌شود.")
                    .foregroundStyle(.secondary)

                if !controller.lastHealthMessage.isEmpty {
                    Text(controller.lastHealthMessage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 6)
        }
    }

    private var librarySection: some View {
        GroupBox("Local Library") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(controller.libraryItems.count) item(s)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh Library") {
                        Task { await controller.refreshLibrary() }
                    }
                    .disabled(controller.isBusy)
                }

                List(controller.libraryItems) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.fileName)
                            .font(.headline)
                        Text("\(item.size) • \(item.createdAt)")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                        Text(item.streamUrl)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 180)
            }
            .padding(.top, 6)
        }
    }

    private var logsSection: some View {
        GroupBox("Logs") {
            ScrollView {
                Text(controller.logText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.top, 6)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(maxHeight: .infinity)
    }
}
