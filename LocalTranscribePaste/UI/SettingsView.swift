import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case general = "General"
        case dictation = "Dictation"
        case shortcuts = "Shortcuts"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .dictation: return "waveform"
            case .shortcuts: return "keyboard"
            }
        }
        var subtitle: String {
            switch self {
            case .general: return "Make R3VIB3 work the way you do."
            case .dictation: return "Your voice, transcribed on your Mac."
            case .shortcuts: return "Keep your hands on the keyboard."
            }
        }
    }

    private let deviceProvider: AudioDeviceProviding
    private let launchAtLoginManager: LaunchAtLoginManaging
    private let permissions: PermissionsManaging
    private let statusBarController: StatusBarControlling
    @ObservedObject private var settings: SettingsStore
    @State private var page: Page = .general
    @State private var launchAtLoginEnabled: Bool
    @State private var inputName = "System default"
    @State private var modelExists = false

    init(
        settings: SettingsStore,
        permissions: PermissionsManaging,
        statusBarController: StatusBarControlling,
        deviceProvider: AudioDeviceProviding = SystemAudioDeviceProvider(),
        launchAtLoginManager: LaunchAtLoginManaging = LaunchAtLoginManager.shared
    ) {
        self._settings = ObservedObject(wrappedValue: settings)
        self.permissions = permissions
        self.statusBarController = statusBarController
        self.deviceProvider = deviceProvider
        self.launchAtLoginManager = launchAtLoginManager
        _launchAtLoginEnabled = State(initialValue: launchAtLoginManager.isEnabled())
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 23, weight: .medium))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("R3VIB3").font(.title3.weight(.semibold))
                        Text("Local dictation").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                VStack(spacing: 6) {
                    ForEach(Page.allCases) { item in
                        Button { page = item } label: {
                            Label(item.rawValue, systemImage: item.symbol)
                                .font(.system(size: 13, weight: page == item ? .semibold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14).padding(.vertical, 11)
                                .background(page == item ? R3VTheme.selection : .clear, in: Capsule())
                                .overlay(Capsule().strokeBorder(.white.opacity(page == item ? 0.12 : 0), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(page == item ? .isSelected : [])
                    }
                }
                Spacer()
                Label("Private by design", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
                Button { statusBarController.showPermissions() } label: {
                    Label("Permissions…", systemImage: "key")
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16).padding(.top, 28).padding(.bottom, 22)
            .frame(width: 204)
            .background(.black.opacity(0.12))
            Rectangle().fill(.white.opacity(0.07)).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(page.rawValue).font(.system(size: 26, weight: .semibold))
                    Text(page.subtitle).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 24)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) { pageContent }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 28).padding(.bottom, 28)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 760, idealWidth: 800, minHeight: 520, idealHeight: 560)
        .r3vTheme(window: true)
        .onAppear { refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
        }
        .onChange(of: settings.modelPath) { _ in refreshModelStatus() }
    }

    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(R3VTheme.canvas, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .general:
            settingsCard("Clipboard") {
                Text("Paste with").font(.callout)
                Picker("Paste with", selection: $settings.pasteMode) {
                    Text("⌘V · Mac").tag(PasteMode.cmdV)
                    Text("⌃V · Remote").tag(PasteMode.ctrlV)
                    Text("Type text").tag(PasteMode.type)
                }
                .pickerStyle(.segmented).labelsHidden()
                Toggle("Copy completed transcripts", isOn: $settings.autoCopyOnTranscription).toggleStyle(.switch)
                Toggle("Show transcript after dictation", isOn: $settings.showTranscriptPopover).toggleStyle(.switch)
                Text("Use ⌃V for remote desktops, or Type text when clipboard paste is unavailable.")
                    .font(.caption).foregroundColor(.secondary)
            }
            settingsCard("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLoginEnabled },
                    set: { newValue in
                        _ = launchAtLoginManager.setEnabled(newValue)
                        launchAtLoginEnabled = launchAtLoginManager.isEnabled()
                    }
                ))
                .toggleStyle(.switch)
                .disabled(!launchAtLoginManager.isSupported)
                if !launchAtLoginManager.isSupported {
                    Text("Requires macOS 13 or later.").font(.caption).foregroundColor(.secondary)
                }
            }
        case .dictation:
            settingsCard("Microphone") {
                HStack {
                    Label(inputName, systemImage: "mic")
                    Spacer()
                    Button("Refresh") { refreshInput() }
                }
                Text("Recording uses the input selected in macOS System Settings → Sound → Input.")
                    .font(.caption).foregroundColor(.secondary)
            }
            settingsCard("Transcription model") {
                HStack {
                    TextField("Choose a whisper.cpp model (.bin)", text: $settings.modelPath)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .help(settings.modelPath)
                        .accessibilityLabel("Transcription model path")
                    Button("Choose…", action: chooseModel)
                }
                Label(modelExists ? "Model available" : "Choose an existing model to start dictating",
                      systemImage: modelExists ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.caption)
                    .foregroundColor(modelExists ? .secondary : .orange)
                Text("Audio is processed locally. Your recordings aren't sent to a server.")
                    .font(.caption).foregroundColor(.secondary)
            }
        case .shortcuts:
            settingsCard("Dictation") {
                shortcutRow("Start / stop dictation", hotkey: $settings.toggleHotkey)
                shortcutRow("Hold to dictate", hotkey: $settings.holdHotkey)
                shortcutRow("Paste last transcript", hotkey: $settings.pasteHotkey)
            }
            settingsCard("Screenshots") {
                shortcutRow("Capture a window", hotkey: $settings.screenshotHotkey)
            }
            Text("Choose Record, then press your shortcut. Press Escape to cancel.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private func shortcutRow(_ title: String, hotkey: Binding<Hotkey>) -> some View {
        HStack {
            Text(title)
            Spacer()
            HotkeyRecorderView(hotkey: hotkey, permissions: permissions, statusBarController: statusBarController)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(title)
        }
    }

    private func refreshStatus() {
        launchAtLoginEnabled = launchAtLoginManager.isEnabled()
        refreshInput()
        refreshModelStatus()
    }

    private func refreshInput() {
        let defaultID = deviceProvider.defaultInputDeviceID()
        inputName = deviceProvider.inputDevices().first { $0.deviceID == defaultID }?.name ?? "System default"
    }

    private func refreshModelStatus() {
        var isDirectory: ObjCBool = false
        modelExists = FileManager.default.fileExists(atPath: settings.modelPath, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    private func chooseModel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "bin")].compactMap { $0 }
        if panel.runModal() == .OK, let url = panel.url { settings.modelPath = url.path }
    }
}
