import AppKit
import SwiftUI
import Combine

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private weak var appState: AppState?
    private let recordingIndicator = RecordingIndicatorWindowController()
    private var indicatorMode: IndicatorMode?
    private var cancellables = Set<AnyCancellable>()
    private var transcriptItem: NSMenuItem?

    private var toggleItem: NSMenuItem?
    private var pasteItem: NSMenuItem?
    private var settingsWindow: SettingsWindowController?
    private var permissionsWindow: PermissionsWindowController?
    private var screenshotClipboardWindow: ScreenshotClipboardWindowController?

    init(appState: AppState) {
        self.appState = appState
        super.init()
        setupStatusItem()
        setupMenu()
        setupApplicationMenu()
        appState.$isTranscribing.removeDuplicates().sink { [weak self] transcribing in
            guard let self else { return }
            if transcribing {
                self.indicatorMode = .transcribing
                self.recordingIndicator.show(mode: .transcribing)
            } else if self.indicatorMode == .transcribing {
                self.indicatorMode = nil
                self.recordingIndicator.hide()
            }
        }.store(in: &cancellables)
    }

    func updateRecordingIndicator(isRecording: Bool) {
        statusItem.button?.contentTintColor = isRecording ? .systemRed : nil
        statusItem.button?.toolTip = isRecording ? "R3VIB3 — Recording" : "R3VIB3"
        toggleItem?.title = isRecording ? "Stop dictation" : "Start dictation"
        if isRecording {
            popover.performClose(nil)
            indicatorMode = .recording
            recordingIndicator.show(mode: .recording)
        } else if indicatorMode == .recording {
            indicatorMode = nil
            recordingIndicator.hide()
        }
    }

    func showPasteReadyIndicator() {
        indicatorMode = .pasteReady
        recordingIndicator.show(mode: .pasteReady)
    }

    func clearPasteReadyIndicator() {
        guard indicatorMode == .pasteReady else { return }
        indicatorMode = nil
        recordingIndicator.hide()
    }

    func showTranscript(text: String) {
        showPopover(content: TranscriptPopoverView(text: text, isMessageOnly: false))
    }

    func showMessage(_ message: String) {
        showPopover(content: TranscriptPopoverView(text: message, isMessageOnly: true))
    }

    func showPermissions() {
        if permissionsWindow == nil {
            if let appState = appState {
                permissionsWindow = PermissionsWindowController(appState: appState)
            }
        }
        permissionsWindow?.showWindow(nil)
        permissionsWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings() {
        if settingsWindow == nil {
            if let appState = appState {
                settingsWindow = SettingsWindowController(appState: appState)
            }
        }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showScreenshotClipboard() {
        if screenshotClipboardWindow == nil {
            if let appState = appState {
                screenshotClipboardWindow = ScreenshotClipboardWindowController(appState: appState)
            }
        }
        screenshotClipboardWindow?.show()
    }

    private func setupStatusItem() {
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "R3VIB3")
        statusItem.button?.toolTip = "R3VIB3"
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard let appState else { return }
        toggleItem?.title = appState.isTranscribing ? "Transcribing…" : (appState.isRecording ? "Stop dictation" : "Start dictation")
        toggleItem?.isEnabled = !appState.isTranscribing
        pasteItem?.isEnabled = !appState.lastTranscript.isEmpty && !appState.isRecording && !appState.isTranscribing
        transcriptItem?.isEnabled = !appState.lastTranscript.isEmpty
    }

    private func setupApplicationMenu() {
        // A single AppKit settings controller serves both the status item and standard shortcuts.
        let menuBar = NSMenu()
        let appItem = NSMenuItem(title: "R3VIB3", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "R3VIB3")
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit R3VIB3", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        menuBar.addItem(appItem)

        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"),
                                     ("Copy", "copy:", "c"), ("Paste", "paste:", "v"),
                                     ("Select All", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        editItem.submenu = editMenu
        menuBar.addItem(editItem)
        NSApp.mainMenu = menuBar
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let toggle = NSMenuItem(title: "Start dictation", action: #selector(toggleDictation), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        toggleItem = toggle

        let transcript = NSMenuItem(title: "Show transcript", action: #selector(openTranscript), keyEquivalent: "")
        transcript.target = self
        menu.addItem(transcript)
        transcriptItem = transcript

        let paste = NSMenuItem(title: "Paste last transcript", action: #selector(pasteLast), keyEquivalent: "")
        paste.target = self
        menu.addItem(paste)
        pasteItem = paste

        menu.addItem(NSMenuItem.separator())
        let capture = NSMenuItem(title: "Capture window screenshot", action: #selector(captureScreenshot), keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)

        let clipboard = NSMenuItem(title: "Screenshot clipboard", action: #selector(showScreenshotClipboardPanel), keyEquivalent: "")
        clipboard.target = self
        menu.addItem(clipboard)

        menu.addItem(NSMenuItem.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let permissions = NSMenuItem(title: "Permissions…", action: #selector(openPermissions), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit R3VIB3", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func showPopover<Content: View>(content: Content) {
        guard let button = statusItem.button else { return }
        guard let appState = appState else { return }
        let hosting = NSHostingController(rootView: content.environmentObject(appState))
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = hosting
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc private func toggleDictation() {
        appState?.toggleDictation()
    }

    @objc private func pasteLast() {
        appState?.pasteLastTranscript()
    }

    @objc private func openTranscript() {
        guard let appState else { return }
        showTranscript(text: appState.lastTranscript)
    }

    @objc private func captureScreenshot() {
        appState?.captureWindowScreenshot()
    }

    @objc private func showScreenshotClipboardPanel() {
        showScreenshotClipboard()
    }

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func openPermissions() {
        showPermissions()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
