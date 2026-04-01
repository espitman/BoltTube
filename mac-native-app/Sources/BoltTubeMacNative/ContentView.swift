import SwiftUI
import AVKit

enum AppTab {
    case home
    case library
    case profile
    case settings
}

struct ContentView: View {
    var controller: ServerController
    @State private var currentTab: AppTab = .home
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
                sidebar(metrics: metrics)
                
                ZStack {
                    if currentTab == .home {
                        HStack(spacing: 0) {
                            mainPanel(metrics: metrics)
                            rightRail(metrics: metrics)
                        }
                    } else if currentTab == .library {
                        libraryGrid(metrics: metrics)
                    } else {
                        placeholderView(title: "Coming Soon")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay {
            if let _ = playingItem {
                playerOverlay()
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.1), value: currentTab)
        .animation(.spring(duration: 0.5, bounce: 0.1), value: playingItem)
        .onChange(of: playingItem) { _, newValue in
            if let item = newValue {
                player = AVPlayer(url: controller.localURL(for: item))
                player?.play()
            } else {
                player?.pause()
                player = nil
            }
        }
        .frame(minWidth: 1080, minHeight: 480)
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
                if let item = itemToDelete { deleteItem(item) }
            }
            Button("Cancel", role: .cancel) { itemToDelete = nil }
        } message: {
            Text("This will permanently delete \"\(itemToDelete?.title ?? "")\" from disk.")
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

    // MARK: - Sidebar
    private func sidebar(metrics: LayoutMetrics) -> some View {
        VStack(spacing: 32) {
            Circle()
                .fill(accentRed)
                .frame(width: 50, height: 50)
                .overlay { Image(systemName: "bolt.fill").foregroundStyle(.white).font(.system(size: 20)) }
                .shadow(color: accentRed.opacity(0.3), radius: 10, y: 5)
                .padding(.top, 44)
            
            VStack(spacing: 28) {
                SidebarIconButton(icon: "house.fill", isSelected: currentTab == .home) { currentTab = .home }
                SidebarIconButton(icon: "video.fill", isSelected: currentTab == .library) { currentTab = .library }
                SidebarIconButton(icon: "person.fill", isSelected: currentTab == .profile) { currentTab = .profile }
                SidebarIconButton(icon: "gearshape.fill", isSelected: currentTab == .settings) { currentTab = .settings }
            }
            Spacer()
        }
        .frame(width: 100)
        .background(slate900)
        .overlay(alignment: .trailing) { Divider().opacity(0.1) }
    }

    // MARK: - View Panels
    private func mainPanel(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("BoltTube").font(.system(size: 20, weight: .bold)).foregroundStyle(slate900)
                Text("Import").font(.system(size: 20, weight: .medium)).foregroundStyle(slate600)
            }
            .padding(.horizontal, 40).padding(.top, 40).padding(.bottom, 48)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 36) {
                    // Input
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Add New Video").font(.system(size: 14, weight: .bold)).foregroundStyle(slate900)
                        HStack(spacing: 0) {
                            TextField("Paste YouTube video link here...", text: Bindable(controller).videoURL)
                                .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(slate900).padding(.horizontal, 20).padding(.vertical, 14).onSubmit { controller.scheduleQualityRefresh() }
                            Button { if let s = NSPasteboard.general.string(forType: .string) { controller.videoURL = s.trimmingCharacters(in: .whitespacesAndNewlines); controller.scheduleQualityRefresh() } } label: {
                                Text("Paste").font(.system(size: 14, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 28).padding(.vertical, 14).contentShape(Rectangle())
                            }.buttonStyle(.plain).background(accentRed)
                        }.background(Color.white).clipShape(RoundedRectangle(cornerRadius: 12)).overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.1), lineWidth: 1) }
                    }

                    // Preview Area
                    previewArea()

                    // Quality & Download
                    downloadControls()
                }
                .padding(.horizontal, 40)
            }
        }
        .frame(width: 730)
        .background(Color(red: 0.98, green: 0.98, blue: 1.0))
    }

    private func rightRail(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Recent Downloads").font(.system(size: 15, weight: .bold)).foregroundStyle(slate900)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(controller.libraryItems.prefix(5)) { item in
                            RecentCardCompact(controller: controller, item: item, onPlay: { playingItem = item }, onDelete: { itemToDelete = item })
                                .contextMenu {
                                    Button { Task { await controller.refreshMetadata(id: item.id) } } label: { Label("Refresh Metadata", systemImage: "arrow.clockwise") }
                                    Divider()
                                    Button(role: .destructive) { itemToDelete = item } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    }
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Text("REMOTE ACCESS").font(.system(size: 9, weight: .bold)).foregroundStyle(slate600.opacity(0.4)).kerning(0.5)
                Text(controller.lanURLDisplay).font(.system(size: 12, weight: .bold)).foregroundStyle(accentBlue)
            }.padding(.horizontal, 8).padding(.bottom, 24)
        }
        .frame(width: 250).padding(.horizontal, 24).padding(.top, 40).background(Color.white).overlay(alignment: .leading) { Divider().opacity(0.1) }
    }

    private func libraryGrid(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Your Library").font(.system(size: 24, weight: .bold)).foregroundStyle(slate900)
                Spacer()
                Text("\(controller.libraryItems.count) Videos").font(.system(size: 14, weight: .medium)).foregroundStyle(slate600)
            }
            .padding(.horizontal, 40).padding(.top, 40).padding(.bottom, 32)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 24)], spacing: 32) {
                    ForEach(controller.libraryItems) { item in
                        VideoCard(item: item, controller: controller, onPlay: { playingItem = item }, onDelete: { itemToDelete = item })
                            .contextMenu {
                                Button { Task { await controller.refreshMetadata(id: item.id) } } label: { Label("Refresh Metadata", systemImage: "arrow.clockwise") }
                                Divider()
                                Button(role: .destructive) { itemToDelete = item } label: { Label("Delete", systemImage: "trash") } 
                            }
                    }
                }
                .padding(.horizontal, 40).padding(.bottom, 40)
            }
        }
        .background(Color(red: 0.98, green: 0.98, blue: 1.0))
    }

    // MARK: - Helper Subviews
    private func previewArea() -> some View {
        HStack(spacing: 24) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if controller.isResolvingQualities { RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.08)).frame(width: 200, height: 112).shimmering() }
                    else if controller.resolvedThumbnailUrl.isEmpty { RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [Color(white: 0.18), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)).frame(width: 200, height: 112).overlay { Image(systemName: "play.fill").foregroundStyle(.white.opacity(0.15)).font(.system(size: 28)) } }
                    else {
                        AsyncImage(url: URL(string: controller.resolvedThumbnailUrl)) { phase in
                            if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill).frame(width: 200, height: 112).clipped() }
                            else { Color.gray.opacity(0.08).overlay { ProgressView().scaleEffect(0.8) } }
                        }.frame(width: 200, height: 112)
                    }
                }
                if controller.resolvedDurationSeconds > 0 {
                    Text(String(format: "%d:%02d", controller.resolvedDurationSeconds/60, controller.resolvedDurationSeconds%60)).font(.system(size: 11, weight: .bold)).padding(.horizontal, 8).padding(.vertical, 4).background(.black.opacity(0.75)).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 6)).padding(8)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: .black.opacity(0.06), radius: 10, y: 4)
            
            VStack(alignment: .leading, spacing: 6) {
                if controller.isResolvingQualities && controller.resolvedTitle.isEmpty {
                    VStack(alignment: .leading, spacing: 8) { RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.1)).frame(maxWidth: .infinity).frame(height: 20).shimmering(); RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.08)).frame(width: 160).frame(height: 14).shimmering() }
                } else {
                    Text(controller.resolvedTitle.isEmpty ? "Ready for download" : controller.resolvedTitle).font(.system(size: 18, weight: .bold)).foregroundStyle(slate900).lineLimit(2)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func downloadControls() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Quality").font(.system(size: 13, weight: .bold)).foregroundStyle(slate600)
                if controller.isResolvingQualities { HStack(spacing: 8) { ForEach(0..<4, id: \.self) { i in RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)).frame(width: CGFloat(50 + i * 10), height: 44).shimmering() } } }
                else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(controller.formats) { format in
                                let isSelected = controller.selectedFormatID == format.id
                                Button { controller.selectedFormatID = format.id } label: {
                                    VStack(spacing: 2) { Text(format.title).font(.system(size: 13, weight: isSelected ? .black : .bold)).foregroundStyle(isSelected ? .white : slate900); if !format.filesize.isEmpty { Text(format.filesize).font(.system(size: 10, weight: .medium)).foregroundStyle(isSelected ? .white.opacity(0.8) : slate600) } }.padding(.horizontal, 14).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? accentBlue : Color.white).overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? accentBlue : slate900.opacity(0.12), lineWidth: 1)))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            if controller.isDownloading {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) { HStack { Text(controller.downloadProgressText).font(.system(size: 10, weight: .bold)).foregroundStyle(slate600).lineLimit(1); Spacer(); Text("\(Int(controller.downloadProgress * 100))%").font(.system(size: 11, weight: .black)).foregroundStyle(accentBlue) }; GeometryReader { gp in ZStack(alignment: .leading) { Capsule().fill(slate900.opacity(0.05)).frame(height: 6); Capsule().fill(accentBlue).frame(width: gp.size.width * controller.downloadProgress, height: 6) } }.frame(height: 6) }
                    Button { controller.cancelDownload() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(Color.red.opacity(0.8)) }.buttonStyle(.plain)
                }.padding(.horizontal, 16).padding(.vertical, 8).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(slate900.opacity(0.1), lineWidth: 1))
            } else {
                Button { Task { await controller.downloadVideo() } } label: { HStack(spacing: 8) { Image(systemName: "arrow.down"); Text("Download") }.font(.system(size: 14, weight: .bold)).foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 46).background(controller.isResolvingQualities || controller.formats.isEmpty ? Color.gray.opacity(0.1) : accentBlue).clipShape(RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
            }
        }
    }

    private func playerOverlay() -> some View {
        ZStack {
            Color.black.opacity(0.3).background(.ultraThinMaterial).ignoresSafeArea().onTapGesture { closePlayer() }
            VStack(spacing: 0) {
                if let p = player {
                    VideoPlayer(player: p).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(alignment: .topTrailing) {
                        Button { closePlayer() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 24)).foregroundStyle(.white.opacity(0.7)).padding(16) }.buttonStyle(.plain)
                    }
                }
            }.frame(width: 800, height: 480).background(Color.black).clipShape(RoundedRectangle(cornerRadius: 16)).shadow(color: .black.opacity(0.3), radius: 30)
        }
    }

    private func placeholderView(title: String) -> some View {
        VStack { Text(title).font(.system(size: 24, weight: .bold)).foregroundStyle(slate600.opacity(0.4)) }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Components
struct SidebarIconButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Image(systemName: icon).font(.system(size: 24)).foregroundStyle(isSelected ? .white : .white.opacity(0.2)).frame(width: 44, height: 44).background(isSelected ? Color.white.opacity(0.12) : .clear).clipShape(RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle()).onTapGesture { action() }
    }
}

struct VideoCard: View {
    let item: MediaLibraryItem
    var controller: ServerController
    let onPlay: () -> Void
    let onDelete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onPlay) {
                ZStack {
                    if let thumb = item.thumbnailUrl, !thumb.isEmpty {
                        AsyncImage(url: URL(string: thumb)) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color.black.overlay { ProgressView().scaleEffect(0.5) }
                            }
                        }
                    } else {
                        Color.black.overlay { Image(systemName: "play.fill").foregroundStyle(.white.opacity(0.2)).font(.system(size: 32)) }
                    }
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                .overlay(alignment: .bottomTrailing) {
                    if item.duration > 0 {
                        Text(formatDuration(item.duration))
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.8)).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(8)
                            .zIndex(10)
                    }
                }
                .overlay {
                    if controller.refreshingIDs.contains(item.id) {
                        ZStack {
                            Color.black.opacity(0.4)
                            ProgressView().controlSize(.small).tint(.white).scaleEffect(0.8)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.system(size: 14, weight: .bold)).foregroundStyle(Color(red: 0.07, green: 0.09, blue: 0.15)).lineLimit(2)
            }.padding(.horizontal, 4)
        }
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct RecentCardCompact: View {
    var controller: ServerController
    let item: MediaLibraryItem
    let onPlay: () -> Void
    let onDelete: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                ZStack {
                    if let thumb = item.thumbnailUrl, !thumb.isEmpty {
                        AsyncImage(url: URL(string: thumb)) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color.gray.opacity(0.1)
                            }
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1))
                    }
                }
                .frame(width: 80, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottomTrailing) {
                    if item.duration > 0 {
                        Text(formatDuration(item.duration))
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(.black.opacity(0.8)).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(4)
                            .zIndex(10)
                    }
                }
                .overlay {
                    if controller.refreshingIDs.contains(item.id) {
                        ZStack {
                            Color.black.opacity(0.4)
                            ProgressView().controlSize(.small).tint(.white).scaleEffect(0.6)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }.buttonStyle(.plain)
            Button(action: onPlay) {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.1, green: 0.15, blue: 0.25))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            Button { onDelete() } label: { Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(Color.red.opacity(0.7)).padding(6) }.buttonStyle(.plain)
        }.padding(.vertical, 4)
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.5
    func body(content: Content) -> some View {
        content.overlay(LinearGradient(gradient: Gradient(colors: [.clear, .white.opacity(0.45), .clear]), startPoint: .init(x: phase, y: 0.5), endPoint: .init(x: phase + 0.8, y: 0.5)).blendMode(.plusLighter)).onAppear { withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1.5 } }
    }
}
extension View { func shimmering() -> some View { modifier(ShimmerModifier()) } }
private struct LayoutMetrics { let containerWidth: CGFloat }
