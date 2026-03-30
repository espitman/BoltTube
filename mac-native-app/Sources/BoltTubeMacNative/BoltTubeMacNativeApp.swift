import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.toolbar = nil
            window.titlebarSeparatorStyle = .none
            window.isMovableByWindowBackground = true
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct BoltTubeMacNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var serverController = ServerController()

    var body: some Scene {
        WindowGroup {
            ContentView(controller: serverController)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
