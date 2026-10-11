import SwiftUI
import AppKit
import Carbon

struct HotkeyRecorderView: View {
    private let permissions: PermissionsManaging
    private let statusBarController: StatusBarControlling
    private let mainThread: MainThreadRunning
    @Binding var hotkey: Hotkey
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var flagsMonitor: Any?
    @State private var recorderTap: HotkeyRecorderTap?
    @State private var lastFlags: NSEvent.ModifierFlags = []
    @State private var fnCommitWorkItem: DispatchWorkItem?
    @State private var sawKeyDown = false

    private var recordButtonTitle: String {
        isRecording ? "Press shortcut" : "Record"
    }

    init(
        hotkey: Binding<Hotkey>,
        permissions: PermissionsManaging,
        statusBarController: StatusBarControlling,
        mainThread: MainThreadRunning = MainThreadRunner()
    ) {
        self._hotkey = hotkey
        self.permissions = permissions
        self.statusBarController = statusBarController
        self.mainThread = mainThread
    }

    var body: some View {
        HStack {
            Text(hotkey.displayString())
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                .frame(minWidth: 125, alignment: .trailing)
            Button(recordButtonTitle) {
                toggleRecording()
            }
        }
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        if !permissions.isAccessibilityAuthorized {
            permissions.requestAccessibilityAccess()
            statusBarController.showPermissions()
        }
        isRecording = true
        sawKeyDown = false
        startFlagsTap()
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let flags = event.modifierFlags.intersection([.control, .option, .shift, .command, .function])
            lastFlags = flags
            if flags == [.function] {
                scheduleFnOnlyCommit()
            } else {
                cancelFnOnlyCommit()
            }
            return event
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            sawKeyDown = true
            cancelFnOnlyCommit()
            let base = event.modifierFlags.intersection([.control, .option, .shift, .command])
            let fnFlag = lastFlags.intersection([.function])
            let modifiers = base.union(fnFlag)
            let carbon = modifiers.toCarbonFlags()
            let usesFunction = modifiers.contains(.function)
            hotkey = Hotkey(keyCode: UInt32(event.keyCode), modifiers: carbon, usesFunction: usesFunction, isFunctionOnly: false)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
        if let flagsMonitor = flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
        }
        monitor = nil
        flagsMonitor = nil
        recorderTap?.stop()
        recorderTap = nil
        cancelFnOnlyCommit()
        lastFlags = []
        isRecording = false
    }

    private func scheduleFnOnlyCommit() {
        guard isRecording, !sawKeyDown else { return }
        cancelFnOnlyCommit()
        let workItem = DispatchWorkItem {
            guard isRecording, !sawKeyDown else { return }
            hotkey = Hotkey(keyCode: 0, modifiers: 0, usesFunction: true, isFunctionOnly: true)
            stopRecording()
        }
        fnCommitWorkItem = workItem
        mainThread.runAfter(seconds: 0.25) {
            if workItem.isCancelled { return }
            workItem.perform()
        }
    }

    private func cancelFnOnlyCommit() {
        fnCommitWorkItem?.cancel()
        fnCommitWorkItem = nil
    }

    private func startFlagsTap() {
        guard recorderTap == nil else { return }
        let tap = HotkeyRecorderTap { flags in
            let mapped = NSEvent.ModifierFlags(from: flags)
            lastFlags = mapped
            if mapped == [.function] {
                scheduleFnOnlyCommit()
            } else {
                cancelFnOnlyCommit()
            }
        }
        if tap.start() {
            recorderTap = tap
        }
    }
}

private extension NSEvent.ModifierFlags {
    func toCarbonFlags() -> UInt32 {
        var flags: UInt32 = 0
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }

    init(from cgFlags: CGEventFlags) {
        self = []
        if cgFlags.contains(.maskControl) { insert(.control) }
        if cgFlags.contains(.maskAlternate) { insert(.option) }
        if cgFlags.contains(.maskShift) { insert(.shift) }
        if cgFlags.contains(.maskCommand) { insert(.command) }
        if cgFlags.contains(.maskSecondaryFn) { insert(.function) }
    }
}

final class HotkeyRecorderTap {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let onFlagsChanged: (CGEventFlags) -> Void

    init(onFlagsChanged: @escaping (CGEventFlags) -> Void) {
        self.onFlagsChanged = onFlagsChanged
    }

    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
            let recorder = Unmanaged<HotkeyRecorderTap>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .flagsChanged {
                recorder.onFlagsChanged(event.flags)
            }
            return Unmanaged.passUnretained(event)
        }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .listenOnly,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: callback,
                                          userInfo: userInfo) else {
            return false
        }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        tap = nil
    }
}
