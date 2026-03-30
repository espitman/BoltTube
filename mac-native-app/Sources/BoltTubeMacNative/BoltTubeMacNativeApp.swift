import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}

@main
struct BoltTubeMacNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var serverController = ServerController()

    var body: some Scene {
        WindowGroup {
            ContentView(controller: serverController)
                .frame(minWidth: 900, minHeight: 620)
        }
    }
}
