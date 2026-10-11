import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    init(appState: AppState = AppState.shared) {
        let view = SettingsView(
            settings: appState.settings,
            permissions: appState.permissions,
            statusBarController: appState.statusBarController
        )
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.contentView = hosting
        window.title = "R3VIB3 Settings"
        window.setContentSize(NSSize(width: 800, height: 560))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.minSize = NSSize(width: 760, height: 520)
        window.setFrameAutosaveName("R3VIB3Settings")
        window.isReleasedWhenClosed = false
        R3VTheme.configure(window, fullSizeContent: true)
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class PermissionsWindowController: NSWindowController {
    init(appState: AppState = AppState.shared) {
        let view = PermissionsView(permissions: appState.permissions)
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.contentView = hosting
        window.title = "R3VIB3 Permissions"
        window.setContentSize(NSSize(width: 560, height: 530))
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        R3VTheme.configure(window, fullSizeContent: true)
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
