import SwiftUI
import AppKit
import AVKit
import WebKit

@MainActor
private enum DockProgressPresenter {
    static func update(stage: String, percent: Double) {
        let normalized = min(max(percent, 0), 100)
        let tile = NSApp.dockTile
        tile.contentView = DockProgressView(stage: stage, percent: normalized)
        tile.badgeLabel = "\(Int(normalized))%"
        tile.display()
    }

    static func clear() {
        let tile = NSApp.dockTile
        tile.contentView = nil
        tile.badgeLabel = nil
        tile.display()
    }

    static func bounce() {
        NSApp.requestUserAttention(.criticalRequest)
    }
}

private final class DockProgressView: NSView {
    private let stage: String
    private let percent: Double

    init(stage: String, percent: Double) {
        self.stage = stage
        self.percent = percent
        super.init(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bounds = self.bounds
        NSApp.applicationIconImage.draw(in: bounds)

        let barBackground = NSRect(x: 12, y: 12, width: bounds.width - 24, height: 14)
        let radius: CGFloat = 7
        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: barBackground, xRadius: radius, yRadius: radius).fill()

        let fillWidth = max(0, barBackground.width * CGFloat(percent / 100))
        if fillWidth > 0 {
            let fillRect = NSRect(x: barBackground.minX, y: barBackground.minY, width: fillWidth, height: barBackground.height)
            NSColor.systemBlue.setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
        }

        let label = "\(stage) \(Int(percent))%"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        NSString(string: label).draw(in: NSRect(x: 4, y: 31, width: bounds.width - 8, height: 18), withAttributes: attrs)
    }
}

enum AppTab {
    case home; case library; case playlists; case profile; case settings
}

extension Font {
    static func vazir(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return .custom("Vazirmatn", size: size).weight(weight)
    }
}

struct ContentView: View {
    @Bindable var controller: ServerController
    @State private var currentTab: AppTab = .home
    @State private var itemToDelete: MediaLibraryItem? = nil
    @State private var playingItem: MediaLibraryItem? = nil
    @State private var offloadedItemToDownload: MediaLibraryItem? = nil
    @State private var showDirectDownloadModal = false
    @State private var directDownloadMediaID = ""
    @State private var player: AVPlayer? = nil
    
    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var itemToAddToPlaylist: MediaLibraryItem? = nil
    
    @State private var playlistToEdit: Playlist? = nil
    @State private var editPlaylistName = ""
    @State private var playlistToDelete: Playlist? = nil

    @State private var showCreateChannel = false
    @State private var newChannelName = ""
    @State private var playlistToAddToChannel: Playlist? = nil
    @State private var channelToEdit: Channel? = nil
    @State private var editChannelName = ""
    @State private var channelToDelete: Channel? = nil

    private let slate900 = Color(red: 0.07, green: 0.09, blue: 0.15)
    private let slate600 = Color(red: 0.3, green: 0.35, blue: 0.45)
    private let accentRed = Color(red: 0.88, green: 0.3, blue: 0.3)
    private let accentBlue = Color(red: 0.12, green: 0.45, blue: 0.95)

    var body: some View {
        GeometryReader { proxy in
            let _ = print("DEBUG: body re-render, currentTab=\(currentTab), items=\(controller.libraryItems.count)")
            let metrics = LayoutMetrics(containerWidth: proxy.size.width)
            HStack(spacing: 0) {
                sidebar(metrics: metrics)
                ZStack {
                    if currentTab == .home { HStack(spacing: 0) { mainPanel(metrics: metrics); rightRail(metrics: metrics) } }
                    else if currentTab == .library { libraryGrid(metrics: metrics) }
                    else if currentTab == .playlists { managementContainer(metrics: metrics) }
                    else { placeholderView(title: "Coming Soon") }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay { if let _ = playingItem { playerOverlay() } }
        .sheet(item: $offloadedItemToDownload) { item in OffloadedDownloadModal(controller: controller, item: item) }
        .sheet(isPresented: $showDirectDownloadModal) { FreightpassDownloadModal(controller: controller, videoURL: controller.videoURL, mediaID: directDownloadMediaID) }
        .sheet(item: $itemToAddToPlaylist) { item in AddToPlaylistModal(controller: controller, item: item) }
        .sheet(item: $playlistToAddToChannel) { playlist in AddToChannelModal(controller: controller, playlist: playlist) }
        .sheet(isPresented: $showCreatePlaylist) { DialogModalView(title: "New Playlist", text: $newPlaylistName, onConfirm: { Task { await controller.createPlaylist(name: newPlaylistName); newPlaylistName = "" } }) }
        .sheet(item: $playlistToEdit) { p in DialogModalView(title: "Rename Playlist", text: $editPlaylistName, onConfirm: { Task { await controller.updatePlaylist(id: p.id, name: editPlaylistName) } }) }
        .sheet(isPresented: $showCreateChannel) { DialogModalView(title: "New Channel", text: $newChannelName, onConfirm: { Task { await controller.createChannel(name: newChannelName); newChannelName = "" } }) }
        .sheet(item: $channelToEdit) { c in DialogModalView(title: "Rename Channel", text: $editChannelName, onConfirm: { Task { await controller.updateChannel(id: c.id, name: editChannelName) } }) }
        .animation(.spring(duration: 0.4, bounce: 0.1), value: currentTab)
        .animation(.spring(duration: 0.4, bounce: 0.1), value: controller.activeManagementTab)
        .animation(.spring(duration: 0.5, bounce: 0.1), value: playingItem)
        .onChange(of: playingItem) { _, v in if let i = v { player = AVPlayer(url: controller.localURL(for: i)); player?.play() } else { player?.pause(); player = nil } }
        .frame(minWidth: 1080, minHeight: 535).background(Color(red: 0.98, green: 0.98, blue: 1.0)).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)).ignoresSafeArea()
        .task { 
            print("DEBUG: Final task refresh triggered.")
            await controller.refreshLibrary()
            await controller.refreshPlaylists()
            await controller.refreshChannels() 
        }
        .onChange(of: controller.videoURL) { _, _ in controller.scheduleMetadataRefresh() }
        .alert("Confirm Action", isPresented: Binding(get: { itemToDelete != nil || playlistToDelete != nil || channelToDelete != nil }, set: { if !$0 { itemToDelete = nil; playlistToDelete = nil; channelToDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let i = itemToDelete { Task { await controller.deleteItem(id: i.id); itemToDelete = nil } }
                else if let p = playlistToDelete { Task { await controller.deletePlaylist(id: p.id); playlistToDelete = nil } }
                else if let c = channelToDelete { Task { await controller.deleteChannel(id: c.id); channelToDelete = nil } }
            }; Button("Cancel", role: .cancel) { itemToDelete = nil; playlistToDelete = nil; channelToDelete = nil }
        } message: { Text("Are you sure? This action is permanent.").font(.vazir(size: 13)) }
    }

    // MARK: - Sidebar
    private func sidebar(metrics: LayoutMetrics) -> some View {
        VStack(spacing: 32) {
            Circle().fill(accentRed).frame(width: 50, height: 50).overlay { Image(systemName: "bolt.fill").foregroundStyle(Color.white).font(.system(size: 20)) }.shadow(color: accentRed.opacity(0.3), radius: 10, y: 5).padding(.top, 44)
            VStack(spacing: 28) {
                SidebarIconButton(icon: "house.fill", isSelected: currentTab == .home) { currentTab = .home }
                SidebarIconButton(icon: "video.fill", isSelected: currentTab == .library) { currentTab = .library }
                SidebarIconButton(icon: "square.stack.3d.down.right.fill", isSelected: currentTab == .playlists) { currentTab = .playlists }
                SidebarIconButton(icon: "person.fill", isSelected: currentTab == .profile) { currentTab = .profile }
                SidebarIconButton(icon: "gearshape.fill", isSelected: currentTab == .settings) { currentTab = .settings }
            }
            Spacer()
        }.frame(width: 100).background(slate900).overlay(alignment: .trailing) { Divider().opacity(0.1) }
    }

    // MARK: - View Panels
    private func mainPanel(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) { Text("BoltTube").font(.vazir(size: 20, weight: .bold)).foregroundStyle(slate900); Text("Import").font(.vazir(size: 20, weight: .medium)).foregroundStyle(slate600) }.padding(.horizontal, 40).padding(.top, 40).padding(.bottom, 48)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 36) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Add New Video").font(.vazir(size: 14, weight: .bold)).foregroundStyle(slate900)
                        HStack(spacing: 0) {
                            TextField("Paste YouTube video link here...", text: Bindable(controller).videoURL).textFieldStyle(.plain).font(.vazir(size: 14)).foregroundStyle(slate900).padding(.horizontal, 20).padding(.vertical, 14).onSubmit { controller.scheduleMetadataRefresh() }
                            Button { controller.pasteFromClipboard() } label: { Text("Paste").font(.vazir(size: 14, weight: .bold)).foregroundStyle(Color.white).padding(.horizontal, 28).padding(.vertical, 14).background(accentRed).contentShape(Rectangle()) }.buttonStyle(.plain)
                        }.background(Color.white).clipShape(RoundedRectangle(cornerRadius: 12)).overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.1), lineWidth: 1) }
                    }
                    previewArea(); downloadControls()
                }.padding(.horizontal, 40)
            }
        }.frame(width: 730).background(Color(red: 0.98, green: 0.98, blue: 1.0))
    }

    private func rightRail(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Recent Downloads").font(.vazir(size: 15, weight: .bold)).foregroundStyle(slate900)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(controller.libraryItems.prefix(5)) { item in
                            RecentCardCompact(controller: controller, item: item, onPlay: { openLibraryItem(item) }, onDelete: { itemToDelete = item })
                                .contextMenu {
                                    Button { Task { await controller.refreshMetadata(id: item.id) } } label: { Label("Refresh Metadata", systemImage: "arrow.clockwise").font(.vazir(size: 13)) }
                                    if let source = item.sourceUrl, !source.isEmpty {
                                        Button { controller.openSourceInChrome(source) } label: { Label("Open on YouTube (Chrome)", systemImage: "safari").font(.vazir(size: 13)) }
                                    }
                                    Button { itemToAddToPlaylist = item } label: { Label("Add to Playlist", systemImage: "plus.circle").font(.vazir(size: 13)) }
                                    Button { Task { await controller.importDownloadedFile(for: item) } } label: { Label("Import Downloaded File", systemImage: "square.and.arrow.down").font(.vazir(size: 13)) }
                                    if item.isDownloaded ?? true {
                                        Button { Task { await controller.offloadItem(id: item.id) } } label: { Label("Offload (Keep Info)", systemImage: "arrow.down.to.line.circle").font(.vazir(size: 13)) }
                                    }
                                    Divider(); Button(role: .destructive) { itemToDelete = item } label: { Label("Delete", systemImage: "trash").font(.vazir(size: 13)) }
                                }
                        }
                    }
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 6) { Text("REMOTE ACCESS").font(.vazir(size: 9, weight: .bold)).foregroundStyle(slate600.opacity(0.4)).kerning(0.5); Text(controller.lanURLDisplay).font(.vazir(size: 12, weight: .bold)).foregroundStyle(accentBlue) }.padding(.horizontal, 8).padding(.bottom, 24)
        }.frame(width: 250).padding(.horizontal, 24).padding(.top, 40).background(Color.white).overlay(alignment: .leading) { Divider().opacity(0.1) }
    }

    private func libraryGrid(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
                HStack { Text("Your Library").font(.vazir(size: 24, weight: .bold)).foregroundStyle(slate900); Spacer(); Text("\(controller.libraryItems.count) Videos").font(.vazir(size: 14, weight: .medium)).foregroundStyle(slate600) }.padding(.horizontal, 40).padding(.top, 40).padding(.bottom, 32)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 24)], spacing: 32) {
                    ForEach(controller.libraryItems) { item in
                        let _ = print("DEBUG: Rendering item \(item.id)")
                        VideoCard(item: item, controller: controller, 
                                 onPlay: { openLibraryItem(item) }, 
                                 onDelete: { itemToDelete = item })
                            .contextMenu {
                                Button { Task { await controller.refreshMetadata(id: item.id) } } label: { Label("Refresh Metadata", systemImage: "arrow.clockwise").font(.vazir(size: 13)) }
                                if let source = item.sourceUrl, !source.isEmpty {
                                    Button { controller.openSourceInChrome(source) } label: { Label("Open on YouTube (Chrome)", systemImage: "safari").font(.vazir(size: 13)) }
                                }
                                Button { itemToAddToPlaylist = item } label: { Label("Add to Playlist", systemImage: "plus.circle").font(.vazir(size: 13)) }
                                Button { Task { await controller.importDownloadedFile(for: item) } } label: { Label("Import Downloaded File", systemImage: "square.and.arrow.down").font(.vazir(size: 13)) }
                                if item.isDownloaded ?? true {
                                    Button { Task { await controller.offloadItem(id: item.id) } } label: { Label("Offload (Keep Info)", systemImage: "arrow.down.to.line.circle").font(.vazir(size: 13)) }
                                }
                                Divider(); Button(role: .destructive) { itemToDelete = item } label: { Label("Delete", systemImage: "trash").font(.vazir(size: 13)) }
                            }
                    }
                }.padding(.horizontal, 40).padding(.bottom, 40)
            }
        }.background(Color(red: 0.98, green: 0.98, blue: 1.0))
    }
    
    private func managementContainer(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 24) {
                    Button { controller.activeManagementTab = 0 } label: { Text("Channels").font(.vazir(size: 24, weight: .bold)).foregroundStyle(controller.activeManagementTab == 0 ? slate900 : slate600.opacity(0.4)) }.buttonStyle(.plain)
                    Button { controller.activeManagementTab = 1 } label: { Text("Playlists").font(.vazir(size: 24, weight: .bold)).foregroundStyle(controller.activeManagementTab == 1 ? slate900 : slate600.opacity(0.4)) }.buttonStyle(.plain)
                }
                Spacer()
                Button { if controller.activeManagementTab == 0 { showCreateChannel = true } else { showCreatePlaylist = true } } label: { HStack { Image(systemName: "plus"); Text(controller.activeManagementTab == 0 ? "New Channel" : "New Playlist") }.font(.vazir(size: 13, weight: .bold)).foregroundStyle(Color.white).padding(.horizontal, 16).padding(.vertical, 8).background(accentBlue).clipShape(Capsule()) }.buttonStyle(.plain)
            }.padding(.horizontal, 40).padding(.top, 40).padding(.bottom, 32)
            
            ZStack {
                if controller.activeManagementTab == 0 {
                    if let channel = controller.selectedChannel { channelDetailView(channel: channel) }
                    else { channelsGrid(metrics: metrics) }
                } else {
                    if let playlist = controller.selectedPlaylist { playlistDetailView(playlist: playlist) }
                    else { playlistsGrid(metrics: metrics) }
                }
            }
        }.background(Color(red: 0.98, green: 0.98, blue: 1.0))
    }

    private func playlistsGrid(metrics: LayoutMetrics) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            if controller.playlists.isEmpty {
                VStack(spacing: 20) { Image(systemName: "music.note.list").font(.system(size: 60)).foregroundStyle(slate600.opacity(0.1)); Text("No playlists yet").font(.vazir(size: 16, weight: .medium)).foregroundStyle(slate600.opacity(0.4)); Button("Create your first playlist") { showCreatePlaylist = true }.font(.vazir(size: 14)).buttonStyle(.link) }.frame(maxWidth: .infinity).padding(.top, 100)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 24)], spacing: 32) {
                    ForEach(controller.playlists) { playlist in
                        PlaylistCard(playlist: playlist)
                            .onTapGesture { controller.selectedPlaylist = playlist; Task { await controller.fetchPlaylistItems(id: playlist.id) } }
                            .contextMenu {
                                Button { editPlaylistName = playlist.name ?? ""; playlistToEdit = playlist } label: { Label("Rename", systemImage: "pencil").font(.vazir(size: 13)) }
                                Button { playlistToAddToChannel = playlist } label: { Label("Add to Channel", systemImage: "plus.square.on.square").font(.vazir(size: 13)) }
                                Divider(); Button(role: .destructive) { playlistToDelete = playlist } label: { Label("Delete", systemImage: "trash").font(.vazir(size: 13)) }
                            }
                    }
                }.padding(.horizontal, 40).padding(.bottom, 40)
            }
        }
    }

    private func channelsGrid(metrics: LayoutMetrics) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            if controller.channels.isEmpty {
                VStack(spacing: 20) { Image(systemName: "square.grid.2x2").font(.system(size: 60)).foregroundStyle(slate600.opacity(0.1)); Text("No channels yet").font(.vazir(size: 16, weight: .medium)).foregroundStyle(slate600.opacity(0.4)); Button("Create your first channel") { showCreateChannel = true }.font(.vazir(size: 14)).buttonStyle(.link) }.frame(maxWidth: .infinity).padding(.top, 100)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 24)], spacing: 32) {
                    ForEach(controller.channels) { channel in
                        PlaylistCard(playlist: Playlist(id: channel.id, name: channel.name ?? "", thumbnailUrl: channel.thumbnailUrl, createdAt: channel.createdAt ?? "", itemCount: channel.playlistCount)) // Reusing visual
                            .onTapGesture { controller.selectedChannel = channel; Task { await controller.fetchChannelContent(id: channel.id) } }
                            .contextMenu {
                                Button { editChannelName = channel.name ?? ""; channelToEdit = channel } label: { Label("Rename", systemImage: "pencil").font(.vazir(size: 13)) }
                                Divider(); Button(role: .destructive) { channelToDelete = channel } label: { Label("Delete", systemImage: "trash").font(.vazir(size: 13)) }
                            }
                    }
                }.padding(.horizontal, 40).padding(.bottom, 40)
            }
        }
    }

    private func playlistDetailView(playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Compact Header Banner (Inline)
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(colors: [accentRed.opacity(0.8), accentRed], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .frame(height: 140)
                            .overlay { 
                                if let thumb = playlist.thumbnailUrl, !thumb.isEmpty {
                                    AsyncImage(url: URL(string: thumb)) { phase in 
                                        if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
                                    }.opacity(0.2).blendMode(.overlay)
                                }
                            }
                        
                        HStack(spacing: 20) {
                            Button { controller.selectedPlaylist = nil; controller.playlistItems = [] } label: { 
                                Image(systemName: "arrow.left").font(.vazir(size: 16, weight: .bold)).foregroundStyle(Color.white).padding(12).background(Color.black.opacity(0.3)).clipShape(Circle()) 
                            }.buttonStyle(.plain)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("PLAYLIST").font(.vazir(size: 10, weight: .black)).foregroundStyle(Color.white.opacity(0.6)).kerning(1)
                                Text(playlist.name ?? "Untitled").font(.vazir(size: 28, weight: .black)).foregroundStyle(Color.white)
                            }
                            Spacer()
                        }.padding(28).padding(.bottom, 4)
                    }.frame(maxWidth: .infinity).clipped()

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 24)], spacing: 32) {
                        ForEach(controller.playlistItems) { item in 
                            videoCardWithMenu(item: item, playlistID: playlist.id)
                        }
                    }.padding(.horizontal, 40).padding(.vertical, 40)
                }
            }
        }
    }

    @ViewBuilder
    private func videoCardWithMenu(item: MediaLibraryItem, playlistID: Int? = nil) -> some View {
        VideoCard(item: item, controller: controller, 
                 onPlay: { openLibraryItem(item) }, 
                 onDelete: { 
                     if let pid = playlistID { Task { await controller.removeFromPlaylist(playlistID: pid, mediaID: item.id) } }
                     else { itemToDelete = item }
                 })
            .contextMenu {
                Button { Task { await controller.refreshMetadata(id: item.id) } } label: { Label("Refresh Metadata", systemImage: "arrow.clockwise").font(.vazir(size: 13)) }
                if let source = item.sourceUrl, !source.isEmpty {
                    Button { controller.openSourceInChrome(source) } label: { Label("Open on YouTube (Chrome)", systemImage: "safari").font(.vazir(size: 13)) }
                }
                Button { itemToAddToPlaylist = item } label: { Label("Add to Playlist", systemImage: "plus.circle").font(.vazir(size: 13)) }
                Button { Task { await controller.importDownloadedFile(for: item) } } label: { Label("Import Downloaded File", systemImage: "square.and.arrow.down").font(.vazir(size: 13)) }
                if item.isDownloaded ?? true {
                    Button { Task { await controller.offloadItem(id: item.id) } } label: { Label("Offload (Keep Info)", systemImage: "arrow.down.to.line.circle").font(.vazir(size: 13)) }
                }
                if let pid = playlistID {
                    Divider(); Button(role: .destructive) { Task { await controller.removeFromPlaylist(playlistID: pid, mediaID: item.id) } } label: { Label("Remove from Playlist", systemImage: "trash").font(.vazir(size: 13)) }
                } else {
                    Divider(); Button(role: .destructive) { itemToDelete = item } label: { Label("Delete", systemImage: "trash").font(.vazir(size: 13)) }
                }
            }
            .frame(maxWidth: .infinity)
    }

    private func channelDetailView(channel: Channel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Compact Header Banner (Inline Title)
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(colors: [accentBlue.opacity(0.8), accentBlue], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .frame(height: 140)
                            .overlay { 
                                if let thumb = channel.thumbnailUrl, !thumb.isEmpty {
                                    AsyncImage(url: URL(string: thumb)) { phase in 
                                        if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
                                    }.opacity(0.2).blendMode(.overlay)
                                }
                            }
                        
                        HStack(spacing: 20) {
                            Button { controller.selectedChannel = nil; controller.channelContent = [] } label: { 
                                Image(systemName: "arrow.left").font(.vazir(size: 16, weight: .bold)).foregroundStyle(Color.white).padding(12).background(Color.black.opacity(0.3)).clipShape(Circle()) 
                            }.buttonStyle(.plain)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("CHANNEL").font(.vazir(size: 10, weight: .black)).foregroundStyle(Color.white.opacity(0.6)).kerning(1)
                                Text(channel.name ?? "Untitled").font(.vazir(size: 28, weight: .black)).foregroundStyle(Color.white)
                            }
                            Spacer()
                        }.padding(28).padding(.bottom, 4)
                    }.frame(maxWidth: .infinity).clipped()

                    VStack(spacing: 48) {
                        if controller.isFetchingChannelContent { ProgressView().padding(.top, 100) }
                        else if controller.channelContent.isEmpty { Text("No content in this channel").font(.vazir(size: 16)).foregroundStyle(slate600.opacity(0.4)).padding(.top, 100) }
                        else {
                            ForEach(controller.channelContent) { section in
                                VStack(alignment: .leading, spacing: 18) {
                                    HStack(alignment: .bottom) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(section.playlist.name ?? "Untitled").font(.vazir(size: 20, weight: .bold)).foregroundStyle(slate900)
                                            Rectangle().fill(accentBlue).frame(width: 32, height: 3).contentShape(Rectangle())
                                        }
                                        Spacer()
                                        Button { 
                                            controller.selectedPlaylist = section.playlist
                                            controller.selectedChannel = nil
                                            controller.activeManagementTab = 1
                                            Task { await controller.fetchPlaylistItems(id: section.playlist.id) }
                                        } label: { Text("See All").font(.vazir(size: 12, weight: .bold)).foregroundStyle(accentBlue).padding(.horizontal, 14).padding(.vertical, 7).background(accentBlue.opacity(0.1)).clipShape(Capsule()) }.buttonStyle(.plain)
                                    }.padding(.horizontal, 40)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 24) {
                                        ForEach(section.items) { item in 
                                            videoCardWithMenu(item: item)
                                                .frame(width: 240)
                                        }
                                        }.padding(.horizontal, 40)
                                    }
                                }
                            }
                        }
                    }.padding(.vertical, 40)
                }
            }
        }
    }

    private func previewArea() -> some View {
        HStack(spacing: 24) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if controller.isResolvingMetadata { RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.08)).frame(width: 200, height: 112).shimmering() }
                    else if controller.resolvedThumbnailUrl.isEmpty { RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [Color(white: 0.18), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)).frame(width: 200, height: 112).overlay { Image(systemName: "play.fill").foregroundStyle(Color.white.opacity(0.15)).font(.system(size: 28)) } }
                    else { AsyncImage(url: URL(string: controller.resolvedThumbnailUrl)) { phase in if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill).frame(width: 200, height: 112).clipped() } else { Color.gray.opacity(0.08).overlay { ProgressView().scaleEffect(0.8) } } }.frame(width: 200, height: 112) }
                }
                if controller.resolvedDurationSeconds > 0 { Text(String(format: "%d:%02d", controller.resolvedDurationSeconds/60, controller.resolvedDurationSeconds%60)).font(.vazir(size: 11, weight: .bold)).padding(.horizontal, 8).padding(.vertical, 4).background(Color.black.opacity(0.75)).foregroundStyle(Color.white).clipShape(RoundedRectangle(cornerRadius: 6)).padding(8) }
            }.clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 6) { if controller.isResolvingMetadata && controller.resolvedTitle.isEmpty { VStack(alignment: .leading, spacing: 8) { RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.1)).frame(maxWidth: .infinity).frame(height: 20).shimmering(); RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.08)).frame(width: 160).frame(height: 14).shimmering() } } else { Text(controller.resolvedTitle.isEmpty ? "Ready" : controller.resolvedTitle).font(.vazir(size: 18, weight: .bold)).foregroundStyle(slate900).lineLimit(2) } }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func downloadControls() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ready to import").font(.vazir(size: 13, weight: .bold)).foregroundStyle(slate600)
                Text("Paste only loads metadata. Quality selection happens after you press Download.").font(.vazir(size: 12, weight: .medium)).foregroundStyle(slate600.opacity(0.85))
            }
            if controller.isDownloading { HStack(spacing: 12) { VStack(alignment: .leading, spacing: 6) { HStack { Text(controller.downloadProgressText).font(.vazir(size: 10, weight: .bold)).foregroundStyle(slate600).lineLimit(1); Spacer(); Text("\(Int(controller.downloadProgress * 100))%").font(.vazir(size: 11, weight: .black)).foregroundStyle(accentBlue) }; GeometryReader { gp in ZStack(alignment: .leading) { Capsule().fill(slate900.opacity(0.05)).frame(height: 6); Capsule().fill(accentBlue).frame(width: gp.size.width * controller.downloadProgress, height: 6) } }.frame(height: 6) }; Button { controller.cancelDownload() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(Color.red.opacity(0.8)) }.buttonStyle(.plain) }.padding(.horizontal, 16).padding(.vertical, 8).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(slate900.opacity(0.1), lineWidth: 1)) }
            else {
                HStack(spacing: 12) {
                    Button {
                        Task {
                            guard let mediaID = await controller.ensureOffloadedItemForDirectDownload() else { return }
                            directDownloadMediaID = mediaID
                            showDirectDownloadModal = true
                        }
                    } label: { HStack(spacing: 8) { Image(systemName: "arrow.down"); Text("Download") }.font(.vazir(size: 14, weight: .bold)).foregroundStyle(Color.white).frame(maxWidth: .infinity).frame(height: 46).background(controller.isResolvingMetadata || controller.resolvedTitle.isEmpty ? Color.gray.opacity(0.1) : accentBlue).clipShape(RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
                    Button { Task { await controller.addOffloadedVideo() } } label: {
                        HStack(spacing: 8) {
                            if controller.isAddingOffloaded {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "tray.and.arrow.down")
                            }
                            Text(controller.isAddingOffloaded ? "Adding..." : "Add Offloaded")
                        }
                        .font(.vazir(size: 14, weight: .bold))
                        .foregroundStyle(slate900)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(slate900.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.isResolvingMetadata || controller.resolvedTitle.isEmpty || controller.isAddingOffloaded)
                }
            }
        }
    }

    private func playerOverlay() -> some View {
        ZStack {
            Color.black.opacity(0.4).background(.ultraThinMaterial).ignoresSafeArea().onTapGesture { closePlayer() }
            VStack {
                if let p = player {
                    DesktopVideoPlayer(player: p)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .topTrailing) {
                            Button { closePlayer() } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Color.white.opacity(0.7))
                                    .padding(16)
                            }.buttonStyle(.plain)
                        }
                }
            }
            .frame(width: 800, height: 480)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.3), radius: 30)
        }
    }

    private func placeholderView(title: String) -> some View { VStack { Text(title).font(.vazir(size: 24, weight: .bold)).foregroundStyle(slate600.opacity(0.4)) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
    private func closePlayer() { playingItem = nil; player?.pause(); player = nil }
    private func openLibraryItem(_ item: MediaLibraryItem) {
        if item.isDownloaded ?? true {
            playingItem = item
        } else {
            offloadedItemToDownload = item
        }
    }
}

struct DesktopVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

struct FreightpassDownloadModal: View {
    @Environment(\.dismiss) private var dismiss
    var controller: ServerController
    let videoURL: String
    let mediaID: String
    private let modalBackground = Color(red: 0.067, green: 0.094, blue: 0.153)

    var body: some View {
        FreightpassWebView(url: URL(string: "https://clickapi.net/")!, videoURL: videoURL) { fileURL in
            Task {
                await controller.importDownloadedFile(at: fileURL, sourceURL: videoURL, mediaID: mediaID)
                DockProgressPresenter.clear()
                dismiss()
            }
        }
            .frame(width: 601, height: 614)
            .background(modalBackground)
            .overlay(alignment: .topTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .padding(10)
                }
                .buttonStyle(.plain)
            }
        .frame(width: 601)
        .background(modalBackground)
        .onDisappear { DockProgressPresenter.clear() }
    }
}

struct FreightpassWebView: NSViewRepresentable {
    let url: URL
    let videoURL: String
    let onDownloadComplete: (URL) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "bolttubeProgress")
        contentController.addUserScript(WKUserScript(source: Self.widgetScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.videoURL = videoURL
        context.coordinator.onDownloadComplete = onDownloadComplete
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(Self.widgetHTML(for: videoURL), baseURL: url)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onDownloadComplete = onDownloadComplete
        guard context.coordinator.videoURL != videoURL else { return }
        context.coordinator.videoURL = videoURL
        webView.loadHTMLString(Self.widgetHTML(for: videoURL), baseURL: url)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "bolttubeProgress")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandler {
        var videoURL = ""
        var onDownloadComplete: ((URL) -> Void)?
        private var downloadDestinations: [ObjectIdentifier: URL] = [:]
        private var lastDockStage = ""
        private var lastDockPercent = -1
        private var didBounceForReady = false
        private var didBounceForDownloadComplete = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let requestURL = navigationAction.request.url {
                print("DEBUG: Blocked ClickAPI popup: \(requestURL.absoluteString)")
            }
            return nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
            } else if navigationAction.targetFrame?.isMainFrame == true, let requestURL = navigationAction.request.url, !Self.isAllowedModalURL(requestURL) {
                print("DEBUG: Blocked ClickAPI external navigation: \(requestURL.absoluteString)")
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
            if navigationResponse.canShowMIMEType {
                decisionHandler(.allow)
            } else {
                decisionHandler(.download)
            }
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
            let fallbackName = response.suggestedFilename ?? "BoltTube-download"
            let filename = suggestedFilename.isEmpty ? fallbackName : suggestedFilename
            let destination = Self.uniqueDownloadURL(for: filename)
            downloadDestinations[ObjectIdentifier(download)] = destination
            print("DEBUG: ClickAPI widget saving download to \(destination.path)")
            completionHandler(destination)
        }

        func downloadDidFinish(_ download: WKDownload) {
            let key = ObjectIdentifier(download)
            guard let destination = downloadDestinations.removeValue(forKey: key) else {
                print("DEBUG: ClickAPI widget download finished without destination.")
                return
            }
            print("DEBUG: ClickAPI widget download finished: \(destination.path)")
            DockProgressPresenter.update(stage: "Done", percent: 100)
            if !didBounceForDownloadComplete {
                didBounceForDownloadComplete = true
                DockProgressPresenter.bounce()
            }
            onDownloadComplete?(destination)
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
            print("DEBUG: ClickAPI widget download failed: \(error.localizedDescription)")
            DockProgressPresenter.clear()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "bolttubeProgress",
                  let payload = message.body as? [String: Any],
                  let stage = payload["stage"] as? String,
                  let percent = payload["percent"] as? Double else {
                return
            }
            let rounded = Int(percent.rounded())
            guard stage != lastDockStage || rounded != lastDockPercent else { return }
            lastDockStage = stage
            lastDockPercent = rounded
            print("DEBUG: ClickAPI progress \(stage) \(rounded)%")
            DockProgressPresenter.update(stage: stage, percent: percent)
            if stage == "Ready", !didBounceForReady {
                didBounceForReady = true
                DockProgressPresenter.bounce()
            }
            if (stage == "Done" || stage == "Downloading") && rounded >= 100 && !didBounceForDownloadComplete {
                didBounceForDownloadComplete = true
                DockProgressPresenter.bounce()
            }
        }

        private static func uniqueDownloadURL(for filename: String) -> URL {
            let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
            let sanitized = filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "BoltTube-download.mp4" : filename
            let base = (sanitized as NSString).deletingPathExtension
            let ext = (sanitized as NSString).pathExtension
            var candidate = downloadsDirectory.appendingPathComponent(sanitized)
            var counter = 2
            while FileManager.default.fileExists(atPath: candidate.path) {
                let nextName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
                candidate = downloadsDirectory.appendingPathComponent(nextName)
                counter += 1
            }
            return candidate
        }

        private static func isAllowedModalURL(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return true }
            return host == "clickapi.net" || host.hasSuffix(".clickapi.net") || host == "api.cdnframe.com" || host.hasSuffix(".api.cdnframe.com")
        }
    }

    private static func widgetHTML(for videoURL: String) -> String {
        let sourceURL = widgetURL(for: videoURL).absoluteString
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body {
              width: 100%;
              height: 100%;
              margin: 0;
              padding: 0;
              overflow-x: hidden;
              overflow-y: auto;
              background: #111827;
            }
            #widgetPlusApi {
              display: block;
              width: 100%;
              min-height: 100%;
              border: none;
              background: #111827;
            }
          </style>
        </head>
        <body>
          <iframe id="widgetPlusApi" src="\(sourceURL)" width="100%" height="100%" allowtransparency="true" scrolling="yes" style="border:none"></iframe>
        </body>
        </html>
        """
    }

    private static func widgetURL(for videoURL: String) -> URL {
        var components = URLComponents(string: "https://clickapi.net/api/widgetplus")!
        components.queryItems = [URLQueryItem(name: "url", value: videoURL)]
        return components.url ?? URL(string: "https://clickapi.net/api/widgetplus")!
    }

    private static let widgetScript = """
    (() => {
      if (window.__bolttubeProgressScannerInstalled) return;
      window.__bolttubeProgressScannerInstalled = true;

      const postProgress = (() => {
        let lastPayload = '';
        return (stage, percent) => {
          if (!Number.isFinite(percent)) return;
          const normalized = Math.max(0, Math.min(100, percent));
          const payload = JSON.stringify({ stage, percent: normalized });
          if (payload === lastPayload) return;
          lastPayload = payload;
          window.webkit?.messageHandlers?.bolttubeProgress?.postMessage({ stage, percent: normalized });
        };
      })();

      const getText = () => (document.body?.innerText || document.documentElement?.innerText || '').replace(/\\s+/g, ' ').trim();

      const detectStage = (text) => {
        const lower = text.toLowerCase();
        if (lower.includes('download complete')) return 'Done';
        if (lower.includes('downloading') || lower.includes('save again')) return 'Downloading';
        if (lower.includes('ready for download')) return 'Ready';
        if (lower.includes('converting') || lower.includes('conversion') || lower.includes('preparing') || lower.includes('initializing') || lower.includes('total progress') || lower.includes('processing')) return 'Converting';
        if (lower.includes('download')) return 'Downloading';
        return 'Working';
      };

      const readNumericPercent = (value) => {
        if (value == null) return null;
        const parsed = Number.parseFloat(String(value).replace('%', '').trim());
        if (!Number.isFinite(parsed)) return null;
        return Math.max(0, Math.min(100, parsed));
      };

      const collectElementPercents = () => {
        const values = [];
        document.querySelectorAll('progress').forEach((element) => {
          const value = Number.parseFloat(element.getAttribute('value') || element.value);
          const max = Number.parseFloat(element.getAttribute('max') || element.max || '100') || 100;
          if (Number.isFinite(value)) values.push(Math.max(0, Math.min(100, value / max * 100)));
        });
        document.querySelectorAll('[aria-valuenow]').forEach((element) => {
          const value = readNumericPercent(element.getAttribute('aria-valuenow'));
          const max = readNumericPercent(element.getAttribute('aria-valuemax')) || 100;
          if (value != null) values.push(Math.max(0, Math.min(100, value / max * 100)));
        });
        document.querySelectorAll('[style*="%"]').forEach((element) => {
          const style = element.getAttribute('style') || '';
          const match = style.match(/(?:width|transform)[^;]*?([0-9]{1,3}(?:\\.[0-9]+)?)%/i);
          if (match) {
            const value = readNumericPercent(match[1]);
            if (value != null) values.push(value);
          }
        });
        return values;
      };

      const collectTextPercents = (text) => {
        const values = [];
        const matches = text.matchAll(/([0-9]{1,3}(?:\\.[0-9]+)?)\\s*%/g);
        for (const match of matches) {
          const value = readNumericPercent(match[1]);
          if (value != null) values.push(value);
        }
        return values;
      };

      const clickDownloadNowIfReady = () => {
        if (sessionStorage.getItem('bolttubeAutoClickedDownloadNow') === '1') return;
        const controls = Array.from(document.querySelectorAll('button, a, input[type="button"], input[type="submit"], [role="button"]'));
        const downloadButton = controls.find((element) => {
          const text = ((element.innerText || element.value || element.getAttribute('aria-label') || '') + '').replace(/\\s+/g, ' ').trim().toLowerCase();
          return text === 'download now' || text === 'download' || text.includes('download now');
        });
        if (!downloadButton) return;
        sessionStorage.setItem('bolttubeAutoClickedDownloadNow', '1');
        window.setTimeout(() => downloadButton.click(), 120);
      };

      const scanProgress = () => {
        const text = getText();
        const stage = detectStage(text);
        if (stage === 'Ready' || stage === 'Done') {
          postProgress(stage, 100);
          if (stage === 'Ready') clickDownloadNowIfReady();
          return;
        }
        const percents = [...collectElementPercents(), ...collectTextPercents(text)];
        if (!percents.length) return;
        const percent = stage === 'Downloading' ? percents[percents.length - 1] : Math.max(...percents);
        postProgress(stage, percent);
      };

      const scheduleScan = (() => {
        let pending = false;
        return () => {
          if (pending) return;
          pending = true;
          window.setTimeout(() => {
            pending = false;
            scanProgress();
          }, 120);
        };
      })();

      scanProgress();
      window.setInterval(scanProgress, 650);
      new MutationObserver(scheduleScan).observe(document.documentElement, {
        childList: true,
        subtree: true,
        characterData: true,
        attributes: true,
        attributeFilter: ['style', 'class', 'value', 'aria-valuenow', 'aria-valuemax']
      });

      document.addEventListener('contextmenu', (event) => event.preventDefault(), true);
      document.addEventListener('selectstart', (event) => event.preventDefault(), true);
      document.addEventListener('dragstart', (event) => event.preventDefault(), true);
      document.addEventListener('click', (event) => {
        const target = event.target?.closest?.('a, button, input[type="button"], input[type="submit"], [role="button"]');
        if (!target) return;
        const text = ((target.innerText || target.value || target.getAttribute('aria-label') || '') + '').trim().toLowerCase();
        if (text.includes('download')) {
          event.preventDefault();
          sessionStorage.setItem('bolttubeUserDownloadClick', '1');
          document.body.classList.remove('bolttube-waiting');
          document.documentElement.classList.remove('bolttube-page-loading');
        }
      }, true);
      document.addEventListener('submit', (event) => {
        const submitter = event.submitter;
        const text = ((submitter?.innerText || submitter?.value || submitter?.getAttribute?.('aria-label') || '') + '').trim().toLowerCase();
        if (text.includes('download')) {
          event.preventDefault();
        }
        sessionStorage.setItem('bolttubeUserDownloadClick', '1');
        document.body.classList.remove('bolttube-waiting');
        document.documentElement.classList.remove('bolttube-page-loading');
      }, true);
    })();
    """

    private static func customScript(for videoURL: String) -> String {
        let encodedURL = (try? String(data: JSONEncoder().encode(videoURL), encoding: .utf8)) ?? "\"\""
        return """
    (() => {
      const bolttubeVideoURL = \(encodedURL);
      const styleID = 'bolttube-freightpass-custom-style';
      document.getElementById(styleID)?.remove();
      const style = document.createElement('style');
      style.id = styleID;
      style.textContent = `
        * {
          -webkit-user-select: none !important;
          user-select: none !important;
          -webkit-touch-callout: none !important;
        }
        html, body {
          background: #111827 !important;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif !important;
          margin: 0 !important;
          padding: 0 !important;
          max-width: 100% !important;
          overflow-x: hidden !important;
        }
        body {
          margin: 0 !important;
          padding: 0 !important;
          overflow-x: hidden !important;
        }
        #__nuxt,
        #__nuxt > div,
        .bg-gradient-to-r,
        .h-screen {
          background: #111827 !important;
          max-width: 100% !important;
          overflow-x: hidden !important;
        }
        header, nav {
          border-bottom: 1px solid rgba(15, 23, 42, 0.08) !important;
          box-shadow: none !important;
        }
        input, textarea, select {
          border-radius: 10px !important;
          border-color: rgba(15, 23, 42, 0.14) !important;
          box-shadow: none !important;
        }
        button, a[role="button"], input[type="submit"] {
          border-radius: 10px !important;
        }
        .container, main, section {
          max-width: 601px !important;
          margin-left: 0 !important;
          margin-right: 0 !important;
        }
        body.bolttube-home #text,
        body.bolttube-home #footer,
        body.bolttube-home center,
        body.bolttube-home #header,
        body.bolttube-home #logo {
          display: none !important;
        }
        body.bolttube-waiting > *:not(#bolttube-freightpass-loader) {
          visibility: hidden !important;
        }
        #bolttube-freightpass-loader {
          position: fixed !important;
          inset: 0 !important;
          z-index: 2147483647 !important;
          display: none !important;
          align-items: center !important;
          justify-content: center !important;
          background: #111827 !important;
          color: #f8fafc !important;
          font: 700 14px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif !important;
        }
        body.bolttube-waiting #bolttube-freightpass-loader {
          display: flex !important;
        }
        body.bolttube-convert,
        body.bolttube-convert * {
          max-width: 100% !important;
          box-sizing: border-box !important;
        }
        body.bolttube-convert,
        body.bolttube-convert > *,
        body.bolttube-convert .convert-iframe,
        body.bolttube-convert .convert-iframe * {
          background-color: #111827 !important;
        }
        body.bolttube-convert > * {
          margin-left: 0 !important;
          margin-right: 0 !important;
          padding-left: 0 !important;
          padding-right: 0 !important;
        }
        body.bolttube-convert .convert-iframe {
          margin: 0 !important;
          padding: 0 !important;
          width: 100% !important;
          max-width: 100% !important;
          overflow-x: hidden !important;
        }
        body.bolttube-convert .convert-iframe center {
          display: none !important;
        }
      `;
      document.head.appendChild(style);
      document.addEventListener('contextmenu', (event) => event.preventDefault(), true);
      document.addEventListener('selectstart', (event) => event.preventDefault(), true);
      document.addEventListener('dragstart', (event) => event.preventDefault(), true);
      document.addEventListener('click', (event) => {
        const target = event.target?.closest?.('a, button, input[type="button"], input[type="submit"], [role="button"]');
        if (!target) return;
        const text = ((target.innerText || target.value || target.getAttribute('aria-label') || '') + '').trim().toLowerCase();
        if (text.includes('download')) {
          event.preventDefault();
          sessionStorage.setItem('bolttubeUserDownloadClick', '1');
          document.body.classList.remove('bolttube-waiting');
          document.documentElement.classList.remove('bolttube-page-loading');
        }
      }, true);
      document.addEventListener('submit', (event) => {
        const submitter = event.submitter;
        const text = ((submitter?.innerText || submitter?.value || submitter?.getAttribute?.('aria-label') || '') + '').trim().toLowerCase();
        if (text.includes('download')) {
          event.preventDefault();
        }
        sessionStorage.setItem('bolttubeUserDownloadClick', '1');
        document.body.classList.remove('bolttube-waiting');
        document.documentElement.classList.remove('bolttube-page-loading');
      }, true);

      const preventDownloadRefresh = (root = document) => {
        const controls = Array.from(root.querySelectorAll('button, input[type="button"], input[type="submit"], a[role="button"], [role="button"]'));
        controls.forEach((element) => {
          const text = ((element.innerText || element.value || element.getAttribute('aria-label') || '') + '').trim().toLowerCase();
          if (!text.includes('download')) return;
          if (element.tagName === 'BUTTON' || element.tagName === 'INPUT') {
            element.setAttribute('type', 'button');
          }
          element.addEventListener('click', () => {
            sessionStorage.setItem('bolttubeUserDownloadClick', '1');
          }, { capture: true });
        });
      };

      document.getElementById('bolttube-freightpass-loader')?.remove();
      const loader = document.createElement('div');
      loader.id = 'bolttube-freightpass-loader';
      loader.textContent = 'Preparing converter...';
      document.body.appendChild(loader);

      document.body.classList.remove('bolttube-home', 'bolttube-convert', 'bolttube-waiting');
      const path = window.location.pathname.replace(/\\/+$/, '/');
      const isConvert = path === '/convert/' || path.startsWith('/convert/');
      const routeName = path.split('/').filter(Boolean)[0] || '';
      const isClickAPIFrame = routeName === 'mp3' || routeName === 'mp4';

      if (isClickAPIFrame) {
        document.body.classList.add('bolttube-convert', 'bolttube-waiting');
        var attempts = 0;
        const showClickAPIFrame = () => {
          attempts += 1;
          preventDownloadRefresh(document);
          document.documentElement.style.setProperty('overflow-x', 'hidden', 'important');
          document.documentElement.style.setProperty('background-color', '#111827', 'important');
          document.body.style.setProperty('overflow-x', 'hidden', 'important');
          document.body.style.setProperty('margin', '0', 'important');
          document.body.style.setProperty('padding', '0', 'important');
          document.body.style.setProperty('background-color', '#111827', 'important');
          document.querySelectorAll('#__nuxt, #__nuxt > div, .bg-gradient-to-r, .h-screen').forEach((element) => {
            element.style.setProperty('background', '#111827', 'important');
            element.style.setProperty('max-width', '100%', 'important');
            element.style.setProperty('overflow-x', 'hidden', 'important');
          });
          const visibleText = (document.body.innerText || '').toLowerCase();
          const hasConverterContent = visibleText.includes('download') || visibleText.includes('preparing') || visibleText.includes('mp4') || visibleText.includes('error');
          if (!hasConverterContent && attempts < 60) {
            window.setTimeout(showClickAPIFrame, 150);
            return;
          }
          document.body.classList.remove('bolttube-waiting');
          document.documentElement.classList.remove('bolttube-page-loading');
        };
        showClickAPIFrame();
      } else if (isConvert) {
        document.body.classList.add('bolttube-convert');
        var attempts = 0;
        const showConvertFrame = () => {
          attempts += 1;
          const keep = document.querySelector('.convert-iframe');
          if (!keep) {
            if (attempts < 40) window.setTimeout(showConvertFrame, 150);
            return;
          }
          document.querySelectorAll('body *').forEach((element) => {
            const shouldKeep = element === keep || element.contains(keep) || keep.contains(element) || element.id === 'bolttube-freightpass-loader';
            element.style.setProperty('display', shouldKeep ? '' : 'none', 'important');
            element.style.setProperty('visibility', shouldKeep ? 'visible' : 'hidden', 'important');
            if (shouldKeep) {
              element.style.setProperty('background-color', '#111827', 'important');
              element.style.setProperty('max-width', '100%', 'important');
              element.style.setProperty('box-sizing', 'border-box', 'important');
            }
          });
          keep.style.setProperty('display', 'block', 'important');
          keep.style.setProperty('visibility', 'visible', 'important');
          keep.style.setProperty('width', '100%', 'important');
          keep.style.setProperty('max-width', '100%', 'important');
          keep.style.setProperty('margin', '0', 'important');
          keep.style.setProperty('padding', '0', 'important');
          keep.style.setProperty('background-color', '#111827', 'important');
          keep.style.setProperty('overflow-x', 'hidden', 'important');
          keep.style.setProperty('min-height', '520px', 'important');
          keep.querySelectorAll('center').forEach((element) => {
            element.style.setProperty('display', 'none', 'important');
          });
          preventDownloadRefresh(keep);
          const mp4Targets = Array.from(keep.querySelectorAll('button, a, input[type="button"], input[type="submit"], [role="button"], label'));
          const mp4Button = mp4Targets.find((element) => {
            const text = ((element.innerText || element.value || element.getAttribute('aria-label') || '') + '').trim().toLowerCase();
            return text === 'mp4' || text.includes('mp4');
          });
          const alreadySelectedFormat = sessionStorage.getItem('bolttubeMP4Clicked') === '1' || sessionStorage.getItem('bolttubeUserDownloadClick') === '1';
          if (mp4Button && !mp4Button.dataset.bolttubeClicked && !alreadySelectedFormat) {
            mp4Button.dataset.bolttubeClicked = 'true';
            sessionStorage.setItem('bolttubeMP4Clicked', '1');
            window.setTimeout(() => mp4Button.click(), 150);
          }
          document.documentElement.style.setProperty('overflow-x', 'hidden', 'important');
          document.documentElement.style.setProperty('background-color', '#111827', 'important');
          document.body.style.setProperty('overflow-x', 'hidden', 'important');
          document.body.style.setProperty('margin', '0', 'important');
          document.body.style.setProperty('padding', '0', 'important');
          document.body.style.setProperty('background-color', '#111827', 'important');
          document.body.classList.remove('bolttube-waiting');
          document.documentElement.classList.remove('bolttube-page-loading');
        };
        showConvertFrame();
      } else {
        document.body.classList.add('bolttube-home');
        if (bolttubeVideoURL.trim().length > 0) {
          document.body.classList.add('bolttube-waiting');
          var attempts = 0;
          const tryConvert = () => {
            attempts += 1;
            const inputs = Array.from(document.querySelectorAll('input, textarea'));
            const input = inputs.find((element) => {
              const placeholder = (element.getAttribute('placeholder') || '').toLowerCase();
              return placeholder.includes('enter keywords') || placeholder.includes('youtube url');
            }) || inputs.find((element) => ['text', 'search', 'url', ''].includes((element.getAttribute('type') || '').toLowerCase()));

            if (!input) {
              if (attempts < 20) window.setTimeout(tryConvert, 250);
              return;
            }

            input.focus();
            input.value = bolttubeVideoURL;
            input.dispatchEvent(new Event('input', { bubbles: true }));
            input.dispatchEvent(new Event('change', { bubbles: true }));

            const buttons = Array.from(document.querySelectorAll('button, input[type="submit"], a'));
            const convertButton = buttons.find((element) => {
              const text = ((element.innerText || element.value || element.getAttribute('aria-label') || '') + '').trim().toLowerCase();
              return text.includes('convert');
            }) || document.querySelector('button[type="submit"], input[type="submit"]');

            if (convertButton) {
              window.setTimeout(() => convertButton.click(), 250);
            } else if (attempts < 20) {
              window.setTimeout(tryConvert, 250);
            }
          };
          window.setTimeout(tryConvert, 350);
        } else {
          document.body.classList.remove('bolttube-waiting');
          document.documentElement.classList.remove('bolttube-page-loading');
        }
      }
    })();
    """
    }
}

struct DialogModalView: View {
    @Environment(\.dismiss) var dismiss; let title: String; @Binding var text: String; let onConfirm: () -> Void
    private let slate900 = Color(red: 0.07, green: 0.09, blue: 0.15)
    private let accentBlue = Color(red: 0.12, green: 0.45, blue: 0.95)

    var body: some View {
        VStack(spacing: 24) {
            Text(title).font(.vazir(size: 18, weight: .bold)).foregroundStyle(slate900)
            TextField("Name...", text: $text).textFieldStyle(.plain).font(.vazir(size: 14)).foregroundStyle(slate900).padding(12).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 8)).overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.1)) }
            HStack(spacing: 12) {
                Button { onConfirm(); dismiss() } label: { 
                    Text("Confirm").font(.vazir(size: 13, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 10).background(accentBlue).foregroundStyle(Color.white).clipShape(RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
                }.buttonStyle(.plain)
                
                Button { dismiss() } label: { 
                    Text("Cancel").font(.vazir(size: 13, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 10).background(Color.gray.opacity(0.1)).foregroundStyle(slate900).clipShape(RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }.padding(32).frame(width: 350).background(Color.white)
    }
}

struct OffloadedDownloadModal: View {
    @Environment(\.dismiss) var dismiss
    var controller: ServerController
    let item: MediaLibraryItem
    @State private var didPrepare = false

    private let slate900 = Color(red: 0.07, green: 0.09, blue: 0.15)
    private let slate600 = Color(red: 0.3, green: 0.35, blue: 0.45)
    private let accentBlue = Color(red: 0.12, green: 0.45, blue: 0.95)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Download Offloaded Video").font(.vazir(size: 18, weight: .black)).foregroundStyle(slate900)
                    Text("Choose a quality and start the download").font(.vazir(size: 11, weight: .medium)).foregroundStyle(slate600)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(slate600.opacity(0.7))
                }
                .buttonStyle(.plain)
                .disabled(controller.isDownloading)
            }

            HStack(spacing: 16) {
                ZStack(alignment: .bottomTrailing) {
                    if controller.isResolvingQualities {
                        RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.08)).frame(width: 220, height: 124).overlay { ProgressView() }
                    } else if let thumb = item.thumbnailUrl, !thumb.isEmpty {
                        AsyncImage(url: URL(string: thumb)) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill).frame(width: 220, height: 124).clipped()
                            } else {
                                Color.gray.opacity(0.08).overlay { ProgressView().scaleEffect(0.8) }
                            }
                        }
                        .frame(width: 220, height: 124)
                    } else {
                        RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.08)).frame(width: 220, height: 124)
                    }

                    if (item.duration ?? 0) > 0 {
                        Text(formatDuration(item.duration))
                            .font(.vazir(size: 11, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.75))
                            .foregroundStyle(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    Text(controller.resolvedTitle.isEmpty ? (item.title ?? "Untitled") : controller.resolvedTitle)
                        .font(.vazir(size: 16, weight: .bold))
                        .foregroundStyle(slate900)
                        .lineLimit(3)
                    if controller.isResolvingQualities {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading available qualities...").font(.vazir(size: 12, weight: .medium)).foregroundStyle(slate600)
                        }
                    } else if controller.formats.isEmpty {
                        Text("No quality options found yet").font(.vazir(size: 12, weight: .medium)).foregroundStyle(slate600)
                    } else {
                        Text("Available qualities").font(.vazir(size: 12, weight: .bold)).foregroundStyle(slate600)
                    }
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Quality").font(.vazir(size: 13, weight: .bold)).foregroundStyle(slate600)
                if controller.isResolvingQualities {
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)).frame(width: CGFloat(50 + i * 10), height: 42).shimmering()
                        }
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(controller.formats) { format in
                                let isSelected = controller.selectedFormatID == format.id
                                Button { controller.selectedFormatID = format.id } label: {
                                    VStack(spacing: 2) {
                                        Text(format.title).font(.vazir(size: 13, weight: isSelected ? .black : .bold)).foregroundStyle(isSelected ? Color.white : slate900)
                                        if !format.filesize.isEmpty {
                                            Text(format.filesize).font(.vazir(size: 10, weight: .medium)).foregroundStyle(isSelected ? Color.white.opacity(0.8) : slate600)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? accentBlue : Color.white).overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? accentBlue : slate900.opacity(0.12), lineWidth: 1)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            if controller.isDownloading || !controller.downloadProgressText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack(spacing: 8) {
                            if controller.isDownloading {
                                ProgressView().controlSize(.small)
                            }
                            Text(controller.downloadProgressText.isEmpty ? "Preparing download..." : controller.downloadProgressText).font(.vazir(size: 11, weight: .bold)).foregroundStyle(slate600)
                        }
                        Spacer()
                        if controller.isDownloading {
                            Text("\(Int(controller.downloadProgress * 100))%").font(.vazir(size: 11, weight: .black)).foregroundStyle(accentBlue)
                        }
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(slate900.opacity(0.05)).frame(height: 6)
                            Capsule().fill(accentBlue).frame(width: geometry.size.width * controller.downloadProgress, height: 6)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(slate900.opacity(0.1), lineWidth: 1))
            }

            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Text("Cancel").font(.vazir(size: 13, weight: .bold)).frame(maxWidth: .infinity).frame(height: 44).background(Color.gray.opacity(0.1)).foregroundStyle(slate900).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(controller.isDownloading)

                Button {
                    dismiss()
                    Task {
                        _ = await controller.downloadVideo(existingMediaID: item.id)
                    }
                } label: {
                    HStack(spacing: 8) {
                        if controller.isDownloading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.down")
                        }
                        Text(controller.isDownloading ? "Downloading..." : "Start Download")
                    }
                    .font(.vazir(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(controller.isResolvingQualities || controller.formats.isEmpty ? Color.gray.opacity(0.1) : accentBlue)
                    .foregroundStyle(controller.isResolvingQualities || controller.formats.isEmpty ? slate600.opacity(0.5) : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(controller.isResolvingQualities || controller.formats.isEmpty || controller.isDownloading)
            }
        }
        .padding(28)
        .frame(width: 640)
        .background(Color(red: 0.98, green: 0.98, blue: 1.0))
        .task {
            if !didPrepare, let sourceURL = item.sourceUrl, !sourceURL.isEmpty {
                didPrepare = true
                controller.prepareOffloadedDownload(url: sourceURL)
                controller.prepareDownloadSelection()
            }
        }
    }

    private func formatDuration(_ seconds: Int?) -> String {
        let total = seconds ?? 0
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct DirectDownloadModal: View {
    @Environment(\.dismiss) var dismiss
    var controller: ServerController
    @State private var didPrepare = false

    private let slate900 = Color(red: 0.07, green: 0.09, blue: 0.15)
    private let slate600 = Color(red: 0.3, green: 0.35, blue: 0.45)
    private let accentBlue = Color(red: 0.12, green: 0.45, blue: 0.95)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Download Video").font(.vazir(size: 18, weight: .black)).foregroundStyle(slate900)
                    Text("Choose a quality and start the download").font(.vazir(size: 11, weight: .medium)).foregroundStyle(slate600)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(slate600.opacity(0.7))
                }
                .buttonStyle(.plain)
                .disabled(controller.isDownloading)
            }

            HStack(spacing: 16) {
                ZStack(alignment: .bottomTrailing) {
                    if controller.resolvedThumbnailUrl.isEmpty {
                        RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.08)).frame(width: 220, height: 124)
                    } else {
                        AsyncImage(url: URL(string: controller.resolvedThumbnailUrl)) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill).frame(width: 220, height: 124).clipped()
                            } else {
                                Color.gray.opacity(0.08).overlay { ProgressView().scaleEffect(0.8) }
                            }
                        }
                        .frame(width: 220, height: 124)
                    }

                    if controller.resolvedDurationSeconds > 0 {
                        Text(String(format: "%d:%02d", controller.resolvedDurationSeconds / 60, controller.resolvedDurationSeconds % 60))
                            .font(.vazir(size: 11, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.75))
                            .foregroundStyle(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    Text(controller.resolvedTitle.isEmpty ? "Untitled" : controller.resolvedTitle)
                        .font(.vazir(size: 16, weight: .bold))
                        .foregroundStyle(slate900)
                        .lineLimit(3)
                    if controller.isResolvingQualities {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading available qualities...").font(.vazir(size: 12, weight: .medium)).foregroundStyle(slate600)
                        }
                    } else if controller.formats.isEmpty {
                        Text("No quality options found yet").font(.vazir(size: 12, weight: .medium)).foregroundStyle(slate600)
                    } else {
                        Text("Available qualities").font(.vazir(size: 12, weight: .bold)).foregroundStyle(slate600)
                    }
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Quality").font(.vazir(size: 13, weight: .bold)).foregroundStyle(slate600)
                if controller.isResolvingQualities {
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)).frame(width: CGFloat(50 + i * 10), height: 42).shimmering()
                        }
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(controller.formats) { format in
                                let isSelected = controller.selectedFormatID == format.id
                                Button { controller.selectedFormatID = format.id } label: {
                                    VStack(spacing: 2) {
                                        Text(format.title).font(.vazir(size: 13, weight: isSelected ? .black : .bold)).foregroundStyle(isSelected ? Color.white : slate900)
                                        if !format.filesize.isEmpty {
                                            Text(format.filesize).font(.vazir(size: 10, weight: .medium)).foregroundStyle(isSelected ? Color.white.opacity(0.8) : slate600)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? accentBlue : Color.white).overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? accentBlue : slate900.opacity(0.12), lineWidth: 1)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Text("Cancel").font(.vazir(size: 13, weight: .bold)).frame(maxWidth: .infinity).frame(height: 44).background(Color.gray.opacity(0.1)).foregroundStyle(slate900).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(controller.isDownloading)

                Button {
                    dismiss()
                    Task {
                        _ = await controller.downloadVideo()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if controller.isDownloading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.down")
                        }
                        Text(controller.isDownloading ? "Downloading..." : "Start Download")
                    }
                    .font(.vazir(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(controller.isResolvingQualities || controller.formats.isEmpty ? Color.gray.opacity(0.1) : accentBlue)
                    .foregroundStyle(controller.isResolvingQualities || controller.formats.isEmpty ? slate600.opacity(0.5) : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(controller.isResolvingQualities || controller.formats.isEmpty || controller.isDownloading)
            }
        }
        .padding(28)
        .frame(width: 640)
        .background(Color(red: 0.98, green: 0.98, blue: 1.0))
        .task {
            if !didPrepare {
                didPrepare = true
                controller.prepareDownloadSelection()
            }
        }
    }
}

struct SidebarIconButton: View {
    let icon: String; let isSelected: Bool; let action: () -> Void
    var body: some View { Image(systemName: icon).font(.system(size: 24)).foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.2)).frame(width: 44, height: 44).background(isSelected ? Color.white.opacity(0.12) : Color.clear).clipShape(RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle()).onTapGesture { action() } }
}

struct VideoCard: View {
    let item: MediaLibraryItem; var controller: ServerController; let onPlay: () -> Void; let onDelete: () -> Void
    private let slate900 = Color(red: 0.07, green: 0.09, blue: 0.15)
    private let slate600 = Color(red: 0.3, green: 0.35, blue: 0.45)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onPlay) {
                ZStack { if let thumb = item.thumbnailUrl, !thumb.isEmpty { AsyncImage(url: URL(string: thumb)) { phase in if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) } else { Color.black.overlay { ProgressView().scaleEffect(0.5) } } } } else { Color.black.overlay { Image(systemName: "play.fill").foregroundStyle(Color.white.opacity(0.2)).font(.system(size: 32)) } } 
                    if !(item.isDownloaded ?? true) {
                        Color.white.opacity(0.6)
                        Image(systemName: "icloud.and.arrow.down").font(.system(size: 32)).foregroundStyle(slate900).opacity(0.8)
                    }
                }.frame(height: 140).clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: Color.black.opacity(0.1), radius: 8, y: 4)
                .overlay(alignment: .bottomTrailing) { if (item.duration ?? 0) > 0 { Text(formatDuration(item.duration)).font(.vazir(size: 11, weight: .bold)).padding(.horizontal, 8).padding(.vertical, 4).background(Color.black.opacity(0.8)).foregroundStyle(Color.white).clipShape(RoundedRectangle(cornerRadius: 6)).padding(8) } }
                .overlay { if controller.refreshingIDs.contains(item.id) { ZStack { Color.black.opacity(0.4); ProgressView().controlSize(.small).tint(Color.white).scaleEffect(0.8) }.clipShape(RoundedRectangle(cornerRadius: 12)) } }
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) { Text(item.title ?? "Untitled").font(.vazir(size: 14, weight: .bold)).foregroundStyle(Color(red: 0.07, green: 0.09, blue: 0.15).opacity((item.isDownloaded ?? true) ? 1.0 : 0.5)).lineLimit(2) }.padding(.horizontal, 4)
        }
    }
    private func formatDuration(_ s: Int?) -> String { let ss = s ?? 0; return String(format: "%d:%02d", ss/60, ss%60) }
}

struct PlaylistCard: View {
    let playlist: Playlist
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack { if let thumb = playlist.thumbnailUrl, !thumb.isEmpty { AsyncImage(url: URL(string: thumb)) { phase in if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) } else { Color.gray.opacity(0.1).overlay { Image(systemName: "music.note.list").foregroundStyle(Color.gray.opacity(0.3)).font(.system(size: 30)) } } } } else { Color.gray.opacity(0.1).overlay { Image(systemName: "music.note.list").foregroundStyle(Color.gray.opacity(0.3)).font(.system(size: 30)) } } }.frame(height: 120).clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: Color.black.opacity(0.05), radius: 10, y: 5)
            VStack(alignment: .leading, spacing: 2) { Text(playlist.name ?? "Untitled").font(.vazir(size: 14, weight: .bold)).foregroundStyle(Color(red: 0.07, green: 0.09, blue: 0.15)).lineLimit(1); Text("\(playlist.itemCount) Videos").font(.vazir(size: 12, weight: .medium)).foregroundStyle(Color.gray.opacity(0.6)) }.padding(.horizontal, 4)
        }.contentShape(Rectangle())
    }
}

struct RecentCardCompact: View {
    var controller: ServerController; let item: MediaLibraryItem; let onPlay: () -> Void; let onDelete: () -> Void
    private let slate900 = Color(red: 0.07, green: 0.09, blue: 0.15)
    private let slate600 = Color(red: 0.3, green: 0.35, blue: 0.45)

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) { ZStack { if let thumb = item.thumbnailUrl, !thumb.isEmpty { AsyncImage(url: URL(string: thumb)) { phase in if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) } else { Color.gray.opacity(0.1) } } } else { RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)) } 
                if !(item.isDownloaded ?? true) {
                    Color.white.opacity(0.5)
                    Image(systemName: "cloud").font(.system(size: 14)).foregroundStyle(slate900).opacity(0.6)
                }
            }.frame(width: 80, height: 50).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(alignment: .bottomTrailing) { if (item.duration ?? 0) > 0 { Text(formatDuration(item.duration)).font(.vazir(size: 8, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 2).background(Color.black.opacity(0.8)).foregroundStyle(Color.white).clipShape(RoundedRectangle(cornerRadius: 4)).padding(4) } } }.buttonStyle(.plain)
            Button(action: onPlay) { Text(item.title ?? "Untitled").font(.vazir(size: 12, weight: .semibold)).foregroundStyle(Color(red: 0.1, green: 0.15, blue: 0.25).opacity((item.isDownloaded ?? true) ? 1.0 : 0.5)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
            Button { onDelete() } label: { Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(Color.red.opacity(0.7)).padding(6) }.buttonStyle(.plain)
        }.padding(.vertical, 4)
    }
    private func formatDuration(_ s: Int?) -> String { let ss = s ?? 0; return String(format: "%d:%02d", ss/60, ss%60) }
}

struct AddToPlaylistModal: View {
    @Environment(\.dismiss) var dismiss; var controller: ServerController; let item: MediaLibraryItem
    private let slate900 = Color(red: 0.07, green: 0.09, blue: 0.15)
    private let slate600 = Color(red: 0.3, green: 0.35, blue: 0.45)
    
    var body: some View {
        VStack(spacing: 0) {
            HStack { 
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add to Playlist").font(.vazir(size: 18, weight: .black)).foregroundStyle(slate900)
                    Text("Choose a collection for this video").font(.vazir(size: 11, weight: .medium)).foregroundStyle(slate600)
                }
                Spacer()
                Button { dismiss() } label: { 
                    Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(Color.gray.opacity(0.3)) 
                }.buttonStyle(.plain) 
            }.padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)
            
            Divider().opacity(0.1)
            
            ScrollView { 
                VStack(spacing: 10) { 
                    if controller.playlists.isEmpty { 
                        VStack(spacing: 12) {
                            Image(systemName: "music.note.list").font(.system(size: 32)).foregroundStyle(Color.gray.opacity(0.2))
                            Text("No playlists found").font(.vazir(size: 14)).foregroundStyle(slate600.opacity(0.6))
                        }.padding(80) 
                    } else { 
                        ForEach(controller.playlists) { p in 
                            Button { Task { await controller.addToPlaylist(playlistID: p.id, mediaID: item.id); dismiss() } } label: { 
                                HStack(spacing: 14) { 
                                    ZStack { 
                                        if let thumb = p.thumbnailUrl, !thumb.isEmpty { 
                                            AsyncImage(url: URL(string: thumb)) { phase in 
                                                if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) } 
                                                else { Color.gray.opacity(0.1) } 
                                            } 
                                        } else { Color.gray.opacity(0.1).overlay { Image(systemName: "music.note.list").font(.system(size: 12)).foregroundStyle(Color.gray.opacity(0.4)) } } 
                                    }.frame(width: 48, height: 36).clipShape(RoundedRectangle(cornerRadius: 8)).shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.name ?? "Untitled").font(.vazir(size: 15, weight: .bold)).foregroundStyle(slate900)
                                        Text("\(p.itemCount) Videos").font(.vazir(size: 11, weight: .medium)).foregroundStyle(slate600.opacity(0.7))
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").foregroundStyle(Color.blue.opacity(0.8)).font(.system(size: 18))
                                }.padding(.horizontal, 16).padding(.vertical, 14).background(Color.black.opacity(0.02)).clipShape(RoundedRectangle(cornerRadius: 12)) 
                            }.buttonStyle(.plain) 
                        } 
                    } 
                }.padding(28).padding(.top, -12)
            }
        }.frame(width: 420, height: 500).background(Color.white)
    }
}

struct AddToChannelModal: View {
    @Environment(\.dismiss) var dismiss; var controller: ServerController; let playlist: Playlist
    private let slate900 = Color(red: 0.07, green: 0.09, blue: 0.15)
    private let slate600 = Color(red: 0.3, green: 0.35, blue: 0.45)

    var body: some View {
        VStack(spacing: 0) {
            HStack { 
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add to Channel").font(.vazir(size: 18, weight: .black)).foregroundStyle(slate900)
                    Text("Categorize this collection").font(.vazir(size: 11, weight: .medium)).foregroundStyle(slate600)
                }
                Spacer()
                Button { dismiss() } label: { 
                    Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(Color.gray.opacity(0.3)) 
                }.buttonStyle(.plain) 
            }.padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)
            
            Divider().opacity(0.1)
            
            ScrollView { 
                VStack(spacing: 10) { 
                    if controller.channels.isEmpty { 
                        VStack(spacing: 12) {
                            Image(systemName: "rectangle.stack.badge.person.crop").font(.system(size: 32)).foregroundStyle(Color.gray.opacity(0.2))
                            Text("No channels found").font(.vazir(size: 14)).foregroundStyle(slate600.opacity(0.6))
                        }.padding(80) 
                    } else { 
                        ForEach(controller.channels) { c in 
                            Button { Task { await controller.addPlaylistToChannel(channelID: c.id, playlistID: playlist.id); dismiss() } } label: { 
                                HStack(spacing: 14) { 
                                    ZStack { 
                                        if let thumb = c.thumbnailUrl, !thumb.isEmpty { 
                                            AsyncImage(url: URL(string: thumb)) { phase in 
                                                if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) } 
                                                else { Color.gray.opacity(0.1) } 
                                            } 
                                        } else { Color.gray.opacity(0.1).overlay { Image(systemName: "person.2.fill").font(.system(size: 12)).foregroundStyle(Color.gray.opacity(0.4)) } } 
                                    }.frame(width: 48, height: 36).clipShape(RoundedRectangle(cornerRadius: 8)).shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.name ?? "Untitled").font(.vazir(size: 15, weight: .bold)).foregroundStyle(slate900)
                                        Text("\(c.playlistCount) Playlists").font(.vazir(size: 11, weight: .medium)).foregroundStyle(slate600.opacity(0.7))
                                    }
                                    Spacer()
                                    Image(systemName: "plus.app.fill").foregroundStyle(Color.blue.opacity(0.8)).font(.system(size: 18))
                                }.padding(.horizontal, 16).padding(.vertical, 14).background(Color.black.opacity(0.02)).clipShape(RoundedRectangle(cornerRadius: 12)) 
                            }.buttonStyle(.plain) 
                        } 
                    } 
                }.padding(28).padding(.top, -12) 
            }
        }.frame(width: 420, height: 500).background(Color.white)
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.5
    func body(content: Content) -> some View {
        content.overlay(
            LinearGradient(gradient: Gradient(colors: [Color.clear, Color.white.opacity(0.45), Color.clear]), startPoint: .init(x: phase, y: 0.5), endPoint: .init(x: phase + 0.8, y: 0.5))
                .blendMode(.plusLighter)
        )
        .onAppear { withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1.5 } }
    }
}

extension View { func shimmering() -> some View { modifier(ShimmerModifier()) } }
private struct LayoutMetrics { let containerWidth: CGFloat }
