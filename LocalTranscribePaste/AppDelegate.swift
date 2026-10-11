import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppState.shared.statusBarController.showSettings() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.shutdown()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.start()
        if !UserDefaults.standard.bool(forKey: "didShowPermissions") {
            UserDefaults.standard.set(true, forKey: "didShowPermissions")
            AppState.shared.statusBarController.showPermissions()
        }
    }
}
