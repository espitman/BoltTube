import SwiftUI
import AVKit

enum AppTab {
    case home; case library; case playlists; case profile; case settings
}

extension Font {
    static func vazir(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if NSFont(name: "Vazirmatn", size: size) != nil {
            return .custom("Vazirmatn", size: size).weight(weight)
        } else if NSFont(name: "Vazir", size: size) != nil {
            return .custom("Vazir", size: size).weight(weight)
        }
        return .system(size: size, weight: weight)
    }
}

struct ContentView: View {
    @Bindable var controller: ServerController
    @State private var currentTab: AppTab = .home
    @State private var itemToDelete: MediaLibraryItem? = nil
    @State private var playingItem: MediaLibraryItem? = nil
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
        .task { await controller.refreshLibrary(); await controller.refreshPlaylists(); await controller.refreshChannels() }
        .onChange(of: controller.videoURL) { _, _ in controller.scheduleQualityRefresh() }
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
                            TextField("Paste YouTube video link here...", text: Bindable(controller).videoURL).textFieldStyle(.plain).font(.vazir(size: 14)).foregroundStyle(slate900).padding(.horizontal, 20).padding(.vertical, 14).onSubmit { controller.scheduleQualityRefresh() }
                            Button { if let s = NSPasteboard.general.string(forType: .string) { controller.videoURL = s.trimmingCharacters(in: .whitespacesAndNewlines); controller.scheduleQualityRefresh() } } label: { Text("Paste").font(.vazir(size: 14, weight: .bold)).foregroundStyle(Color.white).padding(.horizontal, 28).padding(.vertical, 14) }.buttonStyle(.plain).background(accentRed)
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
                            RecentCardCompact(controller: controller, item: item, onPlay: { playingItem = item }, onDelete: { itemToDelete = item })
                                .contextMenu {
                                    Button { Task { await controller.refreshMetadata(id: item.id) } } label: { Label("Refresh Metadata", systemImage: "arrow.clockwise").font(.vazir(size: 13)) }
                                    Button { itemToAddToPlaylist = item } label: { Label("Add to Playlist", systemImage: "plus.circle").font(.vazir(size: 13)) }
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
                        VideoCard(item: item, controller: controller, onPlay: { playingItem = item }, onDelete: { itemToDelete = item })
                            .contextMenu {
                                Button { Task { await controller.refreshMetadata(id: item.id) } } label: { Label("Refresh Metadata", systemImage: "arrow.clockwise").font(.vazir(size: 13)) }
                                Button { itemToAddToPlaylist = item } label: { Label("Add to Playlist", systemImage: "plus.circle").font(.vazir(size: 13)) }
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
                                Button { editPlaylistName = playlist.name; playlistToEdit = playlist } label: { Label("Rename", systemImage: "pencil").font(.vazir(size: 13)) }
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
                        PlaylistCard(playlist: Playlist(id: channel.id, name: channel.name, thumbnailUrl: channel.thumbnailUrl, createdAt: channel.createdAt, itemCount: channel.playlistCount)) // Reusing visual
                            .onTapGesture { controller.selectedChannel = channel; Task { await controller.fetchChannelContent(id: channel.id) } }
                            .contextMenu {
                                Button { editChannelName = channel.name; channelToEdit = channel } label: { Label("Rename", systemImage: "pencil").font(.vazir(size: 13)) }
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
                                Text(playlist.name).font(.vazir(size: 28, weight: .black)).foregroundStyle(Color.white)
                            }
                            Spacer()
                        }.padding(28).padding(.bottom, 4)
                    }.frame(maxWidth: .infinity).clipped()

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 24)], spacing: 32) {
                        ForEach(controller.playlistItems) { item in VideoCard(item: item, controller: controller, onPlay: { playingItem = item }, onDelete: { itemToDelete = item }) }
                    }.padding(.horizontal, 40).padding(.vertical, 40)
                }
            }
        }
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
                                Text(channel.name).font(.vazir(size: 28, weight: .black)).foregroundStyle(Color.white)
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
                                            Text(section.playlist.name).font(.vazir(size: 20, weight: .bold)).foregroundStyle(slate900)
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
                                                VideoCard(item: item, controller: controller, onPlay: { playingItem = item }, onDelete: { itemToDelete = item })
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
                    if controller.isResolvingQualities { RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.08)).frame(width: 200, height: 112).shimmering() }
                    else if controller.resolvedThumbnailUrl.isEmpty { RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [Color(white: 0.18), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)).frame(width: 200, height: 112).overlay { Image(systemName: "play.fill").foregroundStyle(Color.white.opacity(0.15)).font(.system(size: 28)) } }
                    else { AsyncImage(url: URL(string: controller.resolvedThumbnailUrl)) { phase in if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill).frame(width: 200, height: 112).clipped() } else { Color.gray.opacity(0.08).overlay { ProgressView().scaleEffect(0.8) } } }.frame(width: 200, height: 112) }
                }
                if controller.resolvedDurationSeconds > 0 { Text(String(format: "%d:%02d", controller.resolvedDurationSeconds/60, controller.resolvedDurationSeconds%60)).font(.vazir(size: 11, weight: .bold)).padding(.horizontal, 8).padding(.vertical, 4).background(Color.black.opacity(0.75)).foregroundStyle(Color.white).clipShape(RoundedRectangle(cornerRadius: 6)).padding(8) }
            }.clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 6) { if controller.isResolvingQualities && controller.resolvedTitle.isEmpty { VStack(alignment: .leading, spacing: 8) { RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.1)).frame(maxWidth: .infinity).frame(height: 20).shimmering(); RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.08)).frame(width: 160).frame(height: 14).shimmering() } } else { Text(controller.resolvedTitle.isEmpty ? "Ready" : controller.resolvedTitle).font(.vazir(size: 18, weight: .bold)).foregroundStyle(slate900).lineLimit(2) } }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func downloadControls() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Quality").font(.vazir(size: 13, weight: .bold)).foregroundStyle(slate600)
                if controller.isResolvingQualities { HStack(spacing: 8) { ForEach(0..<4, id: \.self) { i in RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)).frame(width: CGFloat(50 + i * 10), height: 44).shimmering() } } }
                else { ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(controller.formats) { f in let isS = controller.selectedFormatID == f.id; Button { controller.selectedFormatID = f.id } label: { VStack(spacing: 2) { Text(f.title).font(.vazir(size: 13, weight: isS ? .black : .bold)).foregroundStyle(isS ? Color.white : slate900); if !f.filesize.isEmpty { Text(f.filesize).font(.vazir(size: 10, weight: .medium)).foregroundStyle(isS ? Color.white.opacity(0.8) : slate600) } }.padding(.horizontal, 14).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 8).fill(isS ? accentBlue : Color.white).overlay(RoundedRectangle(cornerRadius: 8).stroke(isS ? accentBlue : slate900.opacity(0.12), lineWidth: 1))) }.buttonStyle(.plain) } } } }
            }
            if controller.isDownloading { HStack(spacing: 12) { VStack(alignment: .leading, spacing: 6) { HStack { Text(controller.downloadProgressText).font(.vazir(size: 10, weight: .bold)).foregroundStyle(slate600).lineLimit(1); Spacer(); Text("\(Int(controller.downloadProgress * 100))%").font(.vazir(size: 11, weight: .black)).foregroundStyle(accentBlue) }; GeometryReader { gp in ZStack(alignment: .leading) { Capsule().fill(slate900.opacity(0.05)).frame(height: 6); Capsule().fill(accentBlue).frame(width: gp.size.width * controller.downloadProgress, height: 6) } }.frame(height: 6) }; Button { controller.cancelDownload() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(Color.red.opacity(0.8)) }.buttonStyle(.plain) }.padding(.horizontal, 16).padding(.vertical, 8).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(slate900.opacity(0.1), lineWidth: 1)) }
            else { Button { Task { await controller.downloadVideo() } } label: { HStack(spacing: 8) { Image(systemName: "arrow.down"); Text("Download") }.font(.vazir(size: 14, weight: .bold)).foregroundStyle(Color.white).frame(maxWidth: .infinity).frame(height: 46).background(controller.isResolvingQualities || controller.formats.isEmpty ? Color.gray.opacity(0.1) : accentBlue).clipShape(RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain) }
        }
    }

    private func playerOverlay() -> some View {
        ZStack {
            Color.black.opacity(0.4).background(.ultraThinMaterial).ignoresSafeArea().onTapGesture { closePlayer() }
            VStack {
                if let p = player {
                    VideoPlayer(player: p)
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

struct SidebarIconButton: View {
    let icon: String; let isSelected: Bool; let action: () -> Void
    var body: some View { Image(systemName: icon).font(.system(size: 24)).foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.2)).frame(width: 44, height: 44).background(isSelected ? Color.white.opacity(0.12) : Color.clear).clipShape(RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle()).onTapGesture { action() } }
}

struct VideoCard: View {
    let item: MediaLibraryItem; var controller: ServerController; let onPlay: () -> Void; let onDelete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onPlay) {
                ZStack { if let thumb = item.thumbnailUrl, !thumb.isEmpty { AsyncImage(url: URL(string: thumb)) { phase in if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) } else { Color.black.overlay { ProgressView().scaleEffect(0.5) } } } } else { Color.black.overlay { Image(systemName: "play.fill").foregroundStyle(Color.white.opacity(0.2)).font(.system(size: 32)) } } }.frame(height: 140).clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: Color.black.opacity(0.1), radius: 8, y: 4)
                .overlay(alignment: .bottomTrailing) { if item.duration > 0 { Text(formatDuration(item.duration)).font(.vazir(size: 11, weight: .bold)).padding(.horizontal, 8).padding(.vertical, 4).background(Color.black.opacity(0.8)).foregroundStyle(Color.white).clipShape(RoundedRectangle(cornerRadius: 6)).padding(8) } }
                .overlay { if controller.refreshingIDs.contains(item.id) { ZStack { Color.black.opacity(0.4); ProgressView().controlSize(.small).tint(Color.white).scaleEffect(0.8) }.clipShape(RoundedRectangle(cornerRadius: 12)) } }
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) { Text(item.title).font(.vazir(size: 14, weight: .bold)).foregroundStyle(Color(red: 0.07, green: 0.09, blue: 0.15)).lineLimit(2) }.padding(.horizontal, 4)
        }
    }
    private func formatDuration(_ s: Int) -> String { String(format: "%d:%02d", s/60, s%60) }
}

struct PlaylistCard: View {
    let playlist: Playlist
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack { if let thumb = playlist.thumbnailUrl, !thumb.isEmpty { AsyncImage(url: URL(string: thumb)) { phase in if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) } else { Color.gray.opacity(0.1).overlay { Image(systemName: "music.note.list").foregroundStyle(Color.gray.opacity(0.3)).font(.system(size: 30)) } } } } else { Color.gray.opacity(0.1).overlay { Image(systemName: "music.note.list").foregroundStyle(Color.gray.opacity(0.3)).font(.system(size: 30)) } } }.frame(height: 120).clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: Color.black.opacity(0.05), radius: 10, y: 5)
            VStack(alignment: .leading, spacing: 2) { Text(playlist.name).font(.vazir(size: 14, weight: .bold)).foregroundStyle(Color(red: 0.07, green: 0.09, blue: 0.15)).lineLimit(1); Text("\(playlist.itemCount) Videos").font(.vazir(size: 12, weight: .medium)).foregroundStyle(Color.gray.opacity(0.6)) }.padding(.horizontal, 4)
        }.contentShape(Rectangle())
    }
}

struct RecentCardCompact: View {
    var controller: ServerController; let item: MediaLibraryItem; let onPlay: () -> Void; let onDelete: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) { ZStack { if let thumb = item.thumbnailUrl, !thumb.isEmpty { AsyncImage(url: URL(string: thumb)) { phase in if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) } else { Color.gray.opacity(0.1) } } } else { RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)) } }.frame(width: 80, height: 50).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(alignment: .bottomTrailing) { if item.duration > 0 { Text(formatDuration(item.duration)).font(.vazir(size: 8, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 2).background(Color.black.opacity(0.8)).foregroundStyle(Color.white).clipShape(RoundedRectangle(cornerRadius: 4)).padding(4) } } }.buttonStyle(.plain)
            Button(action: onPlay) { Text(item.title).font(.vazir(size: 12, weight: .semibold)).foregroundStyle(Color(red: 0.1, green: 0.15, blue: 0.25)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
            Button { onDelete() } label: { Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(Color.red.opacity(0.7)).padding(6) }.buttonStyle(.plain)
        }.padding(.vertical, 4)
    }
    private func formatDuration(_ s: Int) -> String { String(format: "%d:%02d", s/60, s%60) }
}

struct AddToPlaylistModal: View {
    @Environment(\.dismiss) var dismiss; var controller: ServerController; let item: MediaLibraryItem
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Add to Playlist").font(.vazir(size: 16, weight: .bold)); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14)).foregroundStyle(Color.gray) }.buttonStyle(.plain) }.padding(24); Divider()
            ScrollView { VStack(spacing: 8) { if controller.playlists.isEmpty { Text("No playlists found").font(.vazir(size: 14)).foregroundStyle(Color.gray).padding(40) } else { ForEach(controller.playlists) { p in Button { Task { await controller.addToPlaylist(playlistID: p.id, mediaID: item.id); dismiss() } } label: { HStack(spacing: 12) { ZStack { if let thumb = p.thumbnailUrl, !thumb.isEmpty { AsyncImage(url: URL(string: thumb)) { phase in if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) } else { Color.gray.opacity(0.1) } } } else { Color.gray.opacity(0.1) } }.frame(width: 40, height: 30).clipShape(RoundedRectangle(cornerRadius: 4)); Text(p.name).font(.vazir(size: 14, weight: .medium)).foregroundStyle(Color(red: 0.07, green: 0.09, blue: 0.15)); Spacer(); Image(systemName: "plus.circle").foregroundStyle(Color.blue) }.padding(.horizontal, 20).padding(.vertical, 12).background(Color.black.opacity(0.02)).clipShape(RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain) } } }.padding(24) }
        }.frame(width: 320, height: 400).background(Color.white)
    }
}

struct AddToChannelModal: View {
    @Environment(\.dismiss) var dismiss; var controller: ServerController; let playlist: Playlist
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Add to Channel").font(.vazir(size: 16, weight: .bold)); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14)).foregroundStyle(Color.gray) }.buttonStyle(.plain) }.padding(24); Divider()
            ScrollView { VStack(spacing: 8) { if controller.channels.isEmpty { Text("No channels found").font(.vazir(size: 14)).foregroundStyle(Color.gray).padding(40) } else { ForEach(controller.channels) { c in Button { Task { await controller.addPlaylistToChannel(channelID: c.id, playlistID: playlist.id); dismiss() } } label: { HStack(spacing: 12) { ZStack { if let thumb = c.thumbnailUrl, !thumb.isEmpty { AsyncImage(url: URL(string: thumb)) { phase in if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) } else { Color.gray.opacity(0.1) } } } else { Color.gray.opacity(0.1) } }.frame(width: 40, height: 30).clipShape(RoundedRectangle(cornerRadius: 4)); Text(c.name).font(.vazir(size: 14, weight: .medium)).foregroundStyle(Color(red: 0.07, green: 0.09, blue: 0.15)); Spacer(); Image(systemName: "plus.square.fill").foregroundStyle(Color.blue) }.padding(.horizontal, 20).padding(.vertical, 12).background(Color.black.opacity(0.02)).clipShape(RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain) } } }.padding(24) }
        }.frame(width: 320, height: 400).background(Color.white)
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
