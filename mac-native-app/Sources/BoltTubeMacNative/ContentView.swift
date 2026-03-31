import SwiftUI
import AVKit

struct ContentView: View {
    @Bindable var controller: ServerController
    @State private var itemToDelete: MediaLibraryItem? = nil
    @State private var playingItem: MediaLibraryItem? = nil
    @State private var player: AVPlayer? = nil

    private let slate900 = Color(red: 0.07, green: 0.09, blue: 0.15)
    private let slate600 = Color(red: 0.3, green: 0.35, blue: 0.45)
    private let accentRed = Color(red: 0.88, green: 0.3, blue: 0.3)
    private let accentBlue = Color(red: 0.12, green: 0.45, blue: 0.95)

    var body: some View {
        GeometryReader { proxy in
            let metrics = LayoutMetrics(containerWidth: proxy.size.width)

            HStack(spacing: 0) {
                mainPanel(metrics: metrics)
                rightRail(metrics: metrics)
            }
        }
        .overlay {
            if let item = playingItem {
                ZStack {
                    Color.black.opacity(0.3)
                        .background(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .onTapGesture { closePlayer() }

                    VStack(spacing: 0) {
                        if let p = player {
                            VideoPlayer(player: p)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .topTrailing) {
                                    Button { closePlayer() } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 24))
                                            .foregroundStyle(.white.opacity(0.7))
                                            .padding(16)
                                    }
                                    .buttonStyle(.plain)
                                }
                        }
                    }
                    .frame(width: 800, height: 480)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.3), radius: 30)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.1), value: playingItem)
        .onChange(of: playingItem) { old, newValue in
            if let item = newValue {
                let url = controller.localURL(for: item)
                player = AVPlayer(url: url)
                player?.play()
            } else {
                player?.pause()
                player = nil
            }
        }
        .frame(minWidth: 980, minHeight: 480)
        .background(Color(red: 0.98, green: 0.98, blue: 1.0))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .ignoresSafeArea()
        .task { await controller.refreshLibrary() }
        .onChange(of: controller.videoURL) { _, _ in
            controller.scheduleQualityRefresh()
        }
        .alert("Delete File?", isPresented: Binding(
            get: { itemToDelete != nil },
            set: { if !$0 { itemToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    deleteItem(item)
                }
            }
            Button("Cancel", role: .cancel) { itemToDelete = nil }
        } message: {
            Text("This will permanently delete \"\(itemToDelete?.fileName ?? "")\" from disk.")
        }
    }

    private func deleteItem(_ item: MediaLibraryItem) {
        Task {
            await controller.deleteItem(id: item.id)
            itemToDelete = nil
        }
    }

    private func closePlayer() {
        playingItem = nil
        player?.pause()
        player = nil
    }

    // MARK: - Main Panel
    private func mainPanel(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accentRed).frame(width: 40, height: 40)
                    Image(systemName: "play.fill").foregroundStyle(.white).font(.system(size: 14))
                }
                HStack(spacing: 4) {
                    Text("BoltTube").font(.system(size: 20, weight: .bold)).foregroundStyle(slate900)
                    Text("Import").font(.system(size: 20, weight: .medium)).foregroundStyle(slate600)
                }
            }
            .padding(.horizontal, 40).padding(.top, 40).padding(.bottom, 48)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 36) {

                    // URL Input
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Add New Video")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(slate900)

                        HStack(spacing: 0) {
                            TextField("Paste YouTube video link here...", text: $controller.videoURL)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14))
                                .foregroundStyle(slate900)
                                .padding(.horizontal, 20).padding(.vertical, 14)
                                .onSubmit { controller.scheduleQualityRefresh() }

                            Button {
                                if let s = NSPasteboard.general.string(forType: .string) {
                                    controller.videoURL = s.trimmingCharacters(in: .whitespacesAndNewlines)
                                    controller.scheduleQualityRefresh()
                                }
                            } label: {
                                Text("Paste")
                                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                    .padding(.horizontal, 28).padding(.vertical, 14)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).background(accentRed)
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.1), lineWidth: 1) }
                    }

                    // Preview (skeleton or real)
                    HStack(spacing: 24) {
                        ZStack(alignment: .bottomTrailing) {
                            Group {
                                if controller.isResolvingQualities {
                                    // Skeleton thumbnail
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.08))
                                        .frame(width: 200, height: 112)
                                        .shimmering()
                                } else if controller.resolvedThumbnailUrl.isEmpty {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(LinearGradient(colors: [Color(white: 0.18), Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
                                        .frame(width: 200, height: 112)
                                        .overlay {
                                            Image(systemName: "play.fill")
                                                .foregroundStyle(.white.opacity(0.15))
                                                .font(.system(size: 28))
                                        }
                                } else {
                                    AsyncImage(url: URL(string: controller.resolvedThumbnailUrl)) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable().aspectRatio(contentMode: .fill)
                                                .frame(width: 200, height: 112).clipped()
                                        case .failure: Color.gray.opacity(0.15)
                                        default:
                                            Color.gray.opacity(0.08)
                                                .overlay { ProgressView().scaleEffect(0.8) }
                                        }
                                    }
                                    .frame(width: 200, height: 112)
                                }
                            }

                            if controller.resolvedDurationSeconds > 0 {
                                let m = controller.resolvedDurationSeconds / 60
                                let s = controller.resolvedDurationSeconds % 60
                                Text(String(format: "%d:%02d", m, s))
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(.black.opacity(0.75)).foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .padding(8)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)

                        VStack(alignment: .leading, spacing: 6) {
                            if controller.isResolvingQualities && controller.resolvedTitle.isEmpty {
                                // Skeleton title
                                VStack(alignment: .leading, spacing: 8) {
                                    RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.1))
                                        .frame(maxWidth: .infinity).frame(height: 20).shimmering()
                                    RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.08))
                                        .frame(width: 160).frame(height: 14).shimmering()
                                }
                            } else {
                                Text(controller.resolvedTitle.isEmpty ? "Ready for download" : controller.resolvedTitle)
                                    .font(.system(size: 18, weight: .bold)).foregroundStyle(slate900).lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Quality + Download
                    VStack(alignment: .leading, spacing: 16) {

                        // Quality chips
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Quality")
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(slate600)

                            if controller.isResolvingQualities {
                                // Skeleton chips
                                HStack(spacing: 8) {
                                    ForEach(0..<4, id: \.self) { i in
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.gray.opacity(0.1))
                                            .frame(width: CGFloat(50 + i * 10), height: 44)
                                            .shimmering()
                                    }
                                }
                            } else if controller.formats.isEmpty {
                                Text("Paste a link to see quality options")
                                    .font(.system(size: 13)).foregroundStyle(slate600.opacity(0.6))
                                    .frame(height: 44)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(controller.formats) { format in
                                            let isSelected = controller.selectedFormatID == format.id
                                            Button(action: { controller.selectedFormatID = format.id }) {
                                                VStack(spacing: 2) {
                                                    Text(format.title)
                                                        .font(.system(size: 13, weight: isSelected ? .black : .bold))
                                                        .foregroundStyle(isSelected ? .white : slate900)
                                                    if !format.filesize.isEmpty {
                                                        Text(format.filesize)
                                                            .font(.system(size: 10, weight: .medium))
                                                            .foregroundStyle(isSelected ? .white.opacity(0.8) : slate600)
                                                    }
                                                }
                                                .padding(.horizontal, 14).padding(.vertical, 8)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(isSelected ? accentBlue : Color.white)
                                                        .overlay(RoundedRectangle(cornerRadius: 8)
                                                            .stroke(isSelected ? accentBlue : slate900.opacity(0.12), lineWidth: 1))
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }

                        // Download / Progress Section
                        let isReady = !controller.formats.isEmpty && !controller.isResolvingQualities && !controller.isDownloading

                        if controller.isDownloading {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(controller.downloadProgressText.isEmpty ? "Downloading..." : controller.downloadProgressText)
                                            .font(.system(size: 10, weight: .bold)).foregroundStyle(slate600)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(Int(controller.downloadProgress * 100))%")
                                            .font(.system(size: 11, weight: .black)).foregroundStyle(accentBlue)
                                    }
                                    
                                    GeometryReader { gp in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(slate900.opacity(0.05)).frame(height: 6)
                                            Capsule().fill(accentBlue)
                                                .frame(width: gp.size.width * controller.downloadProgress, height: 6)
                                        }
                                    }.frame(height: 6)
                                }
                                
                                Button(action: { controller.cancelDownload() }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color.red.opacity(0.8))
                                        .symbolRenderingMode(.hierarchical)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(slate900.opacity(0.1), lineWidth: 1))
                        } else {
                            Button(action: { Task { await controller.downloadVideo() } }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.down")
                                    Text("Download")
                                }
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(isReady ? .white : Color.gray)
                                .frame(maxWidth: .infinity).frame(height: 46)
                                .background(isReady ? accentBlue : Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .disabled(!isReady)
                        }
                    }
                }
                .padding(.horizontal, 40)
            }
        }
    }

    // MARK: - Right Rail
    private func rightRail(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Recent Downloads")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(slate900)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(controller.libraryItems.prefix(10)) { item in
                            RecentCardCompact(
                                title: item.fileName,
                                thumbnailUrl: item.thumbnailUrl,
                                onPlay: { playingItem = item },
                                onDelete: { itemToDelete = item }
                            )
                        }

                        if controller.libraryItems.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "tray").font(.system(size: 24))
                                    .foregroundStyle(slate600.opacity(0.3))
                                Text("No downloads yet").font(.system(size: 12))
                                    .foregroundStyle(slate600.opacity(0.5))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                        }
                    }
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Text("REMOTE ACCESS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(slate600.opacity(0.4))
                    .kerning(0.5)
                
                Text(controller.lanURLDisplay)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accentBlue)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 24)
        }
        .frame(width: 250)
        .padding(.horizontal, 24).padding(.top, 40)
        .background(Color.white)
        .overlay(alignment: .leading) { Divider() }
    }
}

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.5

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .white.opacity(0.45), .clear]),
                    startPoint: .init(x: phase, y: 0.5),
                    endPoint: .init(x: phase + 0.8, y: 0.5)
                )
                .blendMode(.plusLighter)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Components

struct RecentCardCompact: View {
    let title: String
    let thumbnailUrl: String?
    let onPlay: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                ZStack {
                    if let thumb = thumbnailUrl, !thumb.isEmpty {
                        AsyncImage(url: URL(string: thumb)) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            case .failure:
                                Color.gray.opacity(0.1)
                                    .overlay { Image(systemName: "play.slash.fill").font(.system(size: 10)).foregroundStyle(.gray) }
                            default:
                                Color.gray.opacity(0.05)
                            }
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.1))
                            .overlay {
                                Image(systemName: "play.fill").foregroundStyle(.gray).font(.system(size: 11))
                            }
                    }
                    
                    // Small play badge
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.8))
                        .shadow(radius: 2)
                }
                .frame(width: 68, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button(action: onPlay) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.1, green: 0.15, blue: 0.25))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.red.opacity(0.7))
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

private struct LayoutMetrics {
    let containerWidth: CGFloat
}
