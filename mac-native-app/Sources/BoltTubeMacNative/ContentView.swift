import SwiftUI

struct ContentView: View {
    @Bindable var controller: ServerController

    private let navItems: [SidebarItem] = [
        .init(title: "Home", symbol: "house"),
        .init(title: "Downloads", symbol: "arrow.down.to.line"),
        .init(title: "Videos", symbol: "play.rectangle"),
        .init(title: "Audio", symbol: "music.note"),
        .init(title: "Settings", symbol: "gearshape"),
    ]

    private let slate900 = Color(red: 0.07, green: 0.09, blue: 0.15)
    private let slate600 = Color(red: 0.3, green: 0.35, blue: 0.45)
    private let accentRed = Color(red: 0.88, green: 0.3, blue: 0.3)
    private let accentBlue = Color(red: 0.12, green: 0.45, blue: 0.95)

    var body: some View {
        GeometryReader { proxy in
            let metrics = LayoutMetrics(containerWidth: proxy.size.width)

            HStack(spacing: 0) {
                sidebar(metrics: metrics)
                
                mainPanel(metrics: metrics)
                
                rightRail(metrics: metrics)
            }
        }
        .frame(minWidth: 1100, minHeight: 750)
        .background(Color(red: 0.98, green: 0.98, blue: 1.0))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .ignoresSafeArea()
        .task {
            await controller.refreshLibrary()
        }
        .onChange(of: controller.videoURL) { _, _ in
            controller.scheduleQualityRefresh()
        }
    }

    // MARK: - Sidebar
    private func sidebar(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Profile
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "person.fill")
                            .foregroundStyle(slate600)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Ali Rezai")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(slate900)
                    Text("ali.rezai@gmail.com")
                        .font(.system(size: 11))
                        .foregroundStyle(slate600)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            .padding(.bottom, 48)

            // Nav
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(navItems.enumerated()), id: \.offset) { index, item in
                    let isSelected = index == 0
                    HStack(spacing: 12) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 16))
                            .frame(width: 20)
                        Text(item.title)
                            .font(.system(size: 14, weight: isSelected ? .bold : .semibold))
                    }
                    .foregroundStyle(isSelected ? accentBlue : slate600)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        ZStack(alignment: .leading) {
                            if isSelected {
                                accentBlue.opacity(0.06)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                
                                Rectangle()
                                    .fill(accentBlue)
                                    .frame(width: 3, height: 20)
                                    .clipShape(Capsule())
                                    .padding(.leading, 1)
                            }
                        }
                    )
                    .padding(.horizontal, 12)
                }
            }

            Spacer()

            // Premium
            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(.orange)
                Text("BoltTube Premium")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(slate900)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.gray.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .frame(width: 240)
        .background(Color.white)
        .overlay(alignment: .trailing) { Divider() }
    }

    // MARK: - Main Panel
    private func mainPanel(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // App Bar
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accentRed)
                        .frame(width: 40, height: 40)
                    Image(systemName: "play.fill")
                        .foregroundStyle(.white)
                        .font(.system(size: 14))
                }

                HStack(spacing: 4) {
                    Text("BoltTube")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(slate900)
                    Text("Import")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(slate600)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 40)
            .padding(.bottom, 48)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 44) {
                    // Composer
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Add New Video")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(slate900)
                        
                        HStack(spacing: 0) {
                            TextField("Paste YouTube video link here...", text: $controller.videoURL)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                            
                            Button("Analyze") {
                                controller.pasteFromClipboard()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 16)
                            .background(accentRed)
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                        }
                    }

                    // Preview
                    HStack(spacing: 28) {
                        ThumbnailBox(controller: controller)
                            .frame(width: 220, height: 124)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: .black.opacity(0.05), radius: 10, y: 5)

                        VStack(alignment: .leading, spacing: 10) {
                            Text(controller.resolvedTitle.isEmpty ? "Video Title Placeholder" : controller.resolvedTitle)
                                .font(.system(size: 22, weight: .black))
                                .foregroundStyle(slate900)
                                .lineLimit(2)
                            
                            HStack(spacing: 8) {
                                Circle().fill(Color.gray.opacity(0.2)).frame(width: 18, height: 18)
                                Text("Wanderlust Channel")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(slate600)
                            }
                        }
                    }

                    // Settings Group
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(spacing: 32) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Quality Preference")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(slate600)
                                
                                Picker("", selection: $controller.selectedFormatID) {
                                    if controller.formats.isEmpty {
                                        Text("Best Available").tag("best")
                                    } else {
                                        ForEach(controller.formats) { format in
                                            Text(format.title).tag(format.id)
                                        }
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .frame(width: 220)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay { RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08)) }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Action")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(slate600)
                                
                                Button(action: { Task { await controller.downloadVideo() } }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.down")
                                        Text("Start Import")
                                    }
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 32)
                                    .padding(.vertical, 12)
                                    .background(accentBlue)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Progress
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Active Task Status")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(slate600)
                                Spacer()
                                Text("\(Int(controller.downloadProgress * 100))%")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(accentBlue)
                            }

                            GeometryReader { gp in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.gray.opacity(0.1)).frame(height: 10)
                                    Capsule()
                                        .fill(accentBlue)
                                        .frame(width: gp.size.width * controller.downloadProgress, height: 10)
                                }
                            }
                            .frame(height: 10)

                            Text("Processing: \(controller.isDownloading ? "Active Link Analysis" : "Idle Management")")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(slate600)
                        }
                        .padding(24)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.02), radius: 10, y: 5)
                    }
                }
                .padding(.horizontal, 40)
            }
        }
    }

    // MARK: - Right Rail
    private func rightRail(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            // Recent Section
            VStack(alignment: .leading, spacing: 20) {
                Text("Recent Downloads")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(slate900)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        ForEach(controller.libraryItems.prefix(10)) { item in
                            RecentCardCompact(title: item.fileName)
                        }
                        
                        if controller.libraryItems.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "tray")
                                    .font(.system(size: 24))
                                    .foregroundStyle(slate600.opacity(0.3))
                                Text("No downloads yet")
                                    .font(.system(size: 12))
                                    .foregroundStyle(slate600.opacity(0.5))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                }
            }

            // Activity Log
            VStack(alignment: .leading, spacing: 18) {
                Text("Activity Log")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(slate900)

                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(slate900).frame(width: 32, height: 32)
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Task Updated")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(slate900)
                        Text(controller.isDownloading ? "Download active" : "Waiting for link")
                            .font(.system(size: 11))
                            .foregroundStyle(slate600)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Spacer()
        }
        .frame(width: 300)
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .background(Color.white)
        .overlay(alignment: .leading) { Divider() }
    }
}

// MARK: - Components

struct ThumbnailBox: View {
    let controller: ServerController
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: [Color(white: 0.2), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
            
            Text("12:45")
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.8))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(10)
        }
    }
}

struct RecentCardCompact: View {
    let title: String
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.1))
                .frame(width: 80, height: 50)
                .overlay {
                    Image(systemName: "play.fill").foregroundStyle(.gray).font(.system(size: 12))
                }
            
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 0.1, green: 0.15, blue: 0.25))
                .lineLimit(2)
            
            Spacer()
        }
    }
}

private struct LayoutMetrics {
    let containerWidth: CGFloat
}

private struct SidebarItem {
    let title: String
    let symbol: String
}
