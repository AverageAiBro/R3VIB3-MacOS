import SwiftUI

struct PermissionsView: View {
    private let permissions: PermissionsManaging
    private let holdHotkeyManager: HoldHotkeyManaging
    private let bundle: BundleProviding
    @State private var micAuthorized: Bool
    @State private var accessibilityAuthorized: Bool
    @State private var screenRecordingAuthorized: Bool

    init(
        permissions: PermissionsManaging,
        holdHotkeyManager: HoldHotkeyManaging = HoldHotkeyManager.shared,
        bundle: BundleProviding = MainBundleProvider()
    ) {
        self.permissions = permissions
        self.holdHotkeyManager = holdHotkeyManager
        self.bundle = bundle
        _micAuthorized = State(initialValue: permissions.isMicrophoneAuthorized)
        _accessibilityAuthorized = State(initialValue: permissions.isAccessibilityAuthorized)
        _screenRecordingAuthorized = State(initialValue: permissions.isScreenRecordingAuthorized)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ready when you are").font(.title2.weight(.semibold))
                    Text("Enable access for the features you want to use.")
                        .foregroundColor(.secondary)
                }
                permissionRow("Microphone", detail: "Record your voice for local transcription.", symbol: "mic",
                              authorized: micAuthorized) {
                    permissions.requestMicrophoneAccess { granted in
                        refresh()
                        if !granted { permissions.openMicrophoneSettings() }
                    }
                }
                permissionRow("Accessibility", detail: "Use global shortcuts and paste into other apps.", symbol: "keyboard",
                              authorized: accessibilityAuthorized) {
                    permissions.requestAccessibilityAccess()
                    refresh()
                }
                permissionRow("Screen Recording", detail: "Capture a window. Optional for dictation.", symbol: "rectangle.dashed",
                              authorized: screenRecordingAuthorized) {
                    permissions.requestScreenRecordingAccess()
                    refresh()
                    if !permissions.isScreenRecordingAuthorized { permissions.openScreenRecordingSettings() }
                }
                HStack {
                    Text("Status updates when you return to R3VIB3.")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Refresh", action: refresh)
                }
                DisclosureGroup("Troubleshooting") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Manage access in System Settings → Privacy & Security. Restart R3VIB3 if macOS asks you to.")
                        if let id = bundle.bundleIdentifier { Text("Bundle: \(id)") }
                        Text(bundle.bundlePath).textSelection(.enabled)
                    }
                    .font(.caption).foregroundColor(.secondary)
                    .padding(.top, 8)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 560, minHeight: 510)
        .r3vTheme(window: true)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func permissionRow(_ title: String, detail: String, symbol: String,
                               authorized: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundColor(.accentColor).frame(width: 26)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            if authorized {
                Label("Enabled", systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundColor(.green)
            } else {
                Button("Enable…", action: action).accessibilityLabel("Enable \(title)")
            }
        }
        .padding(16)
        .background(R3VTheme.canvas, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }

    private func refresh() {
        micAuthorized = permissions.isMicrophoneAuthorized
        accessibilityAuthorized = permissions.isAccessibilityAuthorized
        screenRecordingAuthorized = permissions.isScreenRecordingAuthorized
        if accessibilityAuthorized { holdHotkeyManager.restartIfNeeded() }
    }
}
