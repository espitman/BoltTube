import AppKit
import SwiftUI

private let fixedWindowSize = NSSize(width: 1020, height: 546)

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.delegate = self
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.toolbar = nil
            window.titlebarSeparatorStyle = .none
            window.isMovableByWindowBackground = true
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.remove(.fullScreenAllowsTiling)
            window.minSize = fixedWindowSize
            window.maxSize = fixedWindowSize
            window.showsResizeIndicator = false
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            window.standardWindowButton(.zoomButton)?.isHidden = true
            let currentOrigin = window.frame.origin
            window.setFrame(NSRect(origin: currentOrigin, size: fixedWindowSize), display: true)
            DispatchQueue.main.async {
                window.setFrame(NSRect(origin: currentOrigin, size: fixedWindowSize), display: true)
            }
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        fixedWindowSize
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
        .defaultSize(width: fixedWindowSize.width, height: fixedWindowSize.height)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
