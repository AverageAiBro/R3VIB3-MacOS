import Foundation
import Combine
import os
import AppKit
import Carbon
import CoreGraphics

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isRecording: Bool = false
    @Published var isTranscribing: Bool = false
    @Published var lastTranscript: String = ""
    @Published var lastAudioFileURL: URL?
    @Published var activeRecordingMode: RecordingMode = .none
    @Published var isPasteReady: Bool = false
    @Published var screenshots: [ScreenshotItem] = []

    let settings: SettingsStore
    let permissions: PermissionsManaging

    private let fileSystem: FileSystem
    private var ownedRecordings: Set<URL> = []
    private let audioCapture: AudioCapturing
    private let transcriptionManager: TranscriptionManaging
    private let pasteManager: PasteManaging
    private let screenshotStore: ScreenshotStoring
    private let screenshotSessionID: String
    private let windowPickerFactory: () -> WindowPickerController
    private var activeWindowPicker: WindowPickerController?
    private var isCapturingScreenshot = false
    private var hotkeyManager: HotkeyManaging
    private var holdHotkeyManager: HoldHotkeyManaging
    private let statusBarControllerFactory: (AppState) -> StatusBarControlling
    private let mainThread: MainThreadRunning
    private let notificationCenter: NotificationCenter
    private let screenshotSessionStart: Date

    lazy var statusBarController: StatusBarControlling = statusBarControllerFactory(self)

    private var cancellables = Set<AnyCancellable>()
    private var accessibilityObserver: Any?

    init(
        settings: SettingsStore = SettingsStore(),
        audioCapture: AudioCapturing = AudioCaptureManager(),
        transcriptionManager: TranscriptionManaging = TranscriptionManager(),
        pasteManager: PasteManaging = PasteManager(),
        screenshotStore: ScreenshotStoring? = nil,
        windowPickerFactory: @escaping () -> WindowPickerController = { WindowPickerController() },
        permissions: PermissionsManaging = PermissionsManager(),
        hotkeyManager: HotkeyManaging = HotkeyManager.shared,
        holdHotkeyManager: HoldHotkeyManaging = HoldHotkeyManager.shared,
        statusBarControllerFactory: @escaping (AppState) -> StatusBarControlling = { StatusBarController(appState: $0) },
        mainThread: MainThreadRunning = MainThreadRunner(),
        notificationCenter: NotificationCenter = .default,
        fileSystem: FileSystem = SystemFileSystem()
    ) {
        self.fileSystem = fileSystem
        self.settings = settings
        self.audioCapture = audioCapture
        self.transcriptionManager = transcriptionManager
        self.pasteManager = pasteManager
        self.screenshotSessionID = UUID().uuidString
        self.screenshotStore = screenshotStore ?? ScreenshotStore(sessionID: screenshotSessionID)
        self.windowPickerFactory = windowPickerFactory
        self.permissions = permissions
        self.hotkeyManager = hotkeyManager
        self.holdHotkeyManager = holdHotkeyManager
        self.statusBarControllerFactory = statusBarControllerFactory
        self.mainThread = mainThread
        self.notificationCenter = notificationCenter
        self.screenshotSessionStart = Date()
        configureHotkeys()
        observeSettings()
        screenshots = loadSessionScreenshots()
    }

    func start() {
        _ = statusBarController
        permissions.logCurrentStatus()
        if !permissions.isAccessibilityAuthorized {
            statusBarController.showMessage("Accessibility permission required. Open Permissions checklist from the menu bar to enable.")
        }
        accessibilityObserver = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.permissions.isAccessibilityAuthorized {
                self.holdHotkeyManager.restartIfNeeded()
            }
        }
    }

    private func configureHotkeys() {
        holdHotkeyManager.onToggle = { [weak self] in
            guard let self = self else { return }
            if self.settings.toggleHotkey.requiresEventTap {
                self.toggleDictation()
            }
        }
        holdHotkeyManager.onPasteKeystroke = { [weak self] keyCode, flags in
            self?.handlePasteKeystroke(keyCode: keyCode, flags: flags)
        }
        holdHotkeyManager.onPaste = { [weak self] in
            guard let self = self else { return }
            if self.settings.pasteHotkey.requiresEventTap {
                self.pasteLastTranscript()
            }
        }
        holdHotkeyManager.onScreenshot = { [weak self] in
            guard let self = self else { return }
            if self.settings.screenshotHotkey.requiresEventTap {
                self.captureWindowScreenshot()
            }
        }
        holdHotkeyManager.onHoldStart = { [weak self] in
            self?.startHoldRecording()
        }
        holdHotkeyManager.onHoldEnd = { [weak self] in
            self?.stopHoldRecording()
        }
        holdHotkeyManager.updateHotkeys(toggle: settings.toggleHotkey, paste: settings.pasteHotkey, hold: settings.holdHotkey, screenshot: settings.screenshotHotkey)
        holdHotkeyManager.start()

        hotkeyManager.onToggleDictation = { [weak self] in
            guard let self = self else { return }
            if !self.settings.toggleHotkey.requiresEventTap {
                self.toggleDictation()
            }
        }
        hotkeyManager.onPasteLastTranscript = { [weak self] in
            guard let self = self else { return }
            if !self.settings.pasteHotkey.requiresEventTap {
                self.pasteLastTranscript()
            }
        }
        hotkeyManager.onCaptureScreenshot = { [weak self] in
            guard let self = self else { return }
            if !self.settings.screenshotHotkey.requiresEventTap {
                self.captureWindowScreenshot()
            }
        }
        updateCarbonHotkeys()
    }

    private func observeSettings() {
        // @Published emits before SettingsStore is updated. Register the emitted value.
        settings.$toggleHotkey.removeDuplicates().dropFirst().sink { [weak self] hotkey in
            self?.holdHotkeyManager.updateToggleHotkey(hotkey)
            self?.updateCarbonHotkeys(toggle: hotkey)
        }.store(in: &cancellables)

        settings.$pasteHotkey.removeDuplicates().dropFirst().sink { [weak self] hotkey in
            self?.holdHotkeyManager.updatePasteHotkey(hotkey)
            self?.updateCarbonHotkeys(paste: hotkey)
        }.store(in: &cancellables)

        settings.$holdHotkey.removeDuplicates().dropFirst().sink { [weak self] hotkey in
            self?.holdHotkeyManager.updateHoldHotkey(hotkey)
        }.store(in: &cancellables)

        settings.$screenshotHotkey.removeDuplicates().dropFirst().sink { [weak self] hotkey in
            self?.holdHotkeyManager.updateScreenshotHotkey(hotkey)
            self?.updateCarbonHotkeys(screenshot: hotkey)
        }.store(in: &cancellables)
    }

    private func handlePasteKeystroke(keyCode: UInt32, flags: CGEventFlags) {
        guard isPasteReady else { return }
        guard keyCode == UInt32(kVK_ANSI_V) else { return }
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            isPasteReady = false
            statusBarController.clearPasteReadyIndicator()
        }
    }

    private func updateCarbonHotkeys(toggle: Hotkey? = nil, paste: Hotkey? = nil, screenshot: Hotkey? = nil) {
        let toggle = toggle ?? settings.toggleHotkey
        let paste = paste ?? settings.pasteHotkey
        let screenshot = screenshot ?? settings.screenshotHotkey
        hotkeyManager.registerHotkeys(
            toggle: toggle.requiresEventTap ? nil : toggle,
            paste: paste.requiresEventTap ? nil : paste,
            screenshot: screenshot.requiresEventTap ? nil : screenshot
        )
    }

    func toggleDictation() {
        mainThread.run { [weak self] in
            guard let self = self else { return }
            guard !self.isTranscribing else { return }
            if self.isRecording {
                self.stopRecordingAndTranscribe()
            } else {
                self.startRecording()
            }
        }
    }

    private func startRecording() {
        mainThread.run { [weak self] in
            guard let self = self else { return }
            guard self.permissions.isMicrophoneAuthorized else {
                self.statusBarController.showPermissions()
                Log.audio.warning("Microphone permission missing")
                return
            }
            self.isPasteReady = false
            self.statusBarController.clearPasteReadyIndicator()
            self.activeRecordingMode = .toggle
            do {
                try self.audioCapture.startRecording(
                    preferredDeviceUID: self.settings.inputDeviceUID,
                    preferredChannelIndex: self.settings.inputChannelIndex
                )
                self.isRecording = true
                self.statusBarController.updateRecordingIndicator(isRecording: true)
                Log.audio.info("Recording started")
            } catch {
                Log.audio.error("Failed to start recording: \(error.localizedDescription)")
                self.statusBarController.showMessage("Failed to start recording")
                self.activeRecordingMode = .none
            }
        }
    }

    private func stopRecordingAndTranscribe() {
        mainThread.run { [weak self] in
            guard let self = self else { return }
            do {
                let audioURL = try self.audioCapture.stopRecording()
                self.ownedRecordings.insert(audioURL)
                self.activeRecordingMode = .none
                self.isRecording = false
                self.statusBarController.updateRecordingIndicator(isRecording: false)
                Log.audio.info("Recording stopped")
                self.transcribe(audioURL: audioURL)
            } catch {
                self.isRecording = false
                self.statusBarController.updateRecordingIndicator(isRecording: false)
                Log.audio.error("Failed to stop recording: \(error.localizedDescription)")
                self.statusBarController.showMessage("Failed to stop recording")
                self.activeRecordingMode = .none
            }
        }
    }

    private func startHoldRecording() {
        mainThread.run { [weak self] in
            guard let self = self else { return }
            guard !self.isRecording, !self.isTranscribing else { return }
            guard self.permissions.isMicrophoneAuthorized else {
                self.statusBarController.showPermissions()
                return
            }
            self.isPasteReady = false
            self.statusBarController.clearPasteReadyIndicator()
            self.activeRecordingMode = .hold
            do {
                try self.audioCapture.startRecording(
                    preferredDeviceUID: self.settings.inputDeviceUID,
                    preferredChannelIndex: self.settings.inputChannelIndex
                )
                self.isRecording = true
                self.statusBarController.updateRecordingIndicator(isRecording: true)
                Log.audio.info("Recording started (hold)")
            } catch {
                Log.audio.error("Failed to start recording (hold): \(error.localizedDescription)")
                self.statusBarController.showMessage("Failed to start recording")
                self.activeRecordingMode = .none
            }
        }
    }

    private func stopHoldRecording() {
        mainThread.run { [weak self] in
            guard let self = self else { return }
            guard self.isRecording, self.activeRecordingMode == .hold else { return }
            self.stopRecordingAndTranscribe()
            self.activeRecordingMode = .none
        }
    }

    func transcribe(audioURL: URL) {
        guard !isTranscribing, !isRecording else { return }
        guard permissions.isMicrophoneAuthorized else {
            statusBarController.showPermissions()
            return
        }
        isPasteReady = false
        statusBarController.clearPasteReadyIndicator()
        isTranscribing = true
        if let previous = lastAudioFileURL, previous != audioURL {
            removeOwnedRecording(previous)
        }
        lastAudioFileURL = audioURL
        Log.transcription.info("Transcription started")
        transcriptionManager.transcribe(audioURL: audioURL, modelPath: settings.modelPath) { [weak self] result in
            self?.mainThread.run { [weak self] in
                guard let self = self else { return }
                self.isTranscribing = false
                switch result {
                case .success(let text):
                    self.lastTranscript = text
                    Log.transcription.info("Transcription completed")
                    if self.settings.autoCopyOnTranscription {
                        self.pasteManager.copyToClipboard(text: text)
                        Log.paste.info("Copied transcript to clipboard")
                    }
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.isPasteReady = true
                        self.statusBarController.showPasteReadyIndicator()
                    }
                    if self.settings.showTranscriptPopover {
                        self.statusBarController.showTranscript(text: text)
                    }
                case .failure(let error):
                    Log.transcription.error("Transcription failed: \(error.localizedDescription)")
                    self.statusBarController.showMessage(self.describeTranscriptionError(error))
                }
            }
        }
    }

    func retryTranscription() {
        guard let audioURL = lastAudioFileURL else {
            statusBarController.showMessage("No audio to retry")
            return
        }
        transcribe(audioURL: audioURL)
    }

    func pasteLastTranscript() {
        guard !lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusBarController.showMessage("No transcript")
            return
        }
        guard permissions.isAccessibilityAuthorized else {
            statusBarController.showPermissions()
            return
        }
        pasteManager.paste(text: lastTranscript, mode: settings.pasteMode)
        isPasteReady = false
        statusBarController.clearPasteReadyIndicator()
    }

    func captureWindowScreenshot() {
        guard activeWindowPicker == nil, !isCapturingScreenshot else { return }
        if !permissions.isScreenRecordingAuthorized {
            statusBarController.showMessage("Enable Screen Recording to capture windows.")
            permissions.requestScreenRecordingAccess()
            statusBarController.showPermissions()
            return
        }
        let picker = windowPickerFactory()
        activeWindowPicker = picker
        picker.beginSelection { [weak self] selection in
            guard let self = self else { return }
            self.activeWindowPicker = nil
            guard let selection else { return }
            self.isCapturingScreenshot = true
            Task { @MainActor in
                defer { self.isCapturingScreenshot = false }
                if await self.screenshotStore.capture(windowID: selection.windowID, screenFrameOverride: selection.screenFrame) != nil {
                    self.screenshots = self.loadSessionScreenshots()
                    self.statusBarController.showScreenshotClipboard()
                } else {
                    self.statusBarController.showMessage("Unable to capture window. Check Screen Recording access and choose the window again.")
                }
            }
        }
    }

    func deleteScreenshot(_ item: ScreenshotItem) {
        screenshotStore.delete(item)
        screenshots = loadSessionScreenshots()
    }

    func deleteScreenshots(_ items: [ScreenshotItem]) {
        for item in items {
            screenshotStore.delete(item)
        }
        screenshots = loadSessionScreenshots()
    }

    func copyLastTranscript() {
        guard !lastTranscript.isEmpty else { return }
        pasteManager.copyToClipboard(text: lastTranscript)
    }

    func clearTranscript() {
        guard !isTranscribing, !isRecording else { return }
        if let audioURL = lastAudioFileURL { removeOwnedRecording(audioURL) }
        lastTranscript = ""
        lastAudioFileURL = nil
        isPasteReady = false
        statusBarController.clearPasteReadyIndicator()
    }

    func shutdown() {
        if isRecording, let url = try? audioCapture.stopRecording() { ownedRecordings.insert(url) }
        for url in ownedRecordings { removeOwnedRecording(url) }
    }

    private func removeOwnedRecording(_ url: URL) {
        guard ownedRecordings.contains(url) else { return }
        do {
            try fileSystem.removeItem(at: url)
            ownedRecordings.remove(url)
        } catch {
            Log.audio.error("Unable to remove temporary recording: \(error.localizedDescription)")
        }
    }

    deinit {
        if let accessibilityObserver { notificationCenter.removeObserver(accessibilityObserver) }
        for url in ownedRecordings { try? fileSystem.removeItem(at: url) }
    }

    private func describeTranscriptionError(_ error: Error) -> String {
        if let error = error as? TranscriptionError {
            switch error {
            case .missingWhisperBinary:
                return "Whisper binary not found"
            case .missingModel:
                return "Whisper model not found"
            case .conversionFailed:
                return "Audio conversion failed"
            case .processFailed:
                return "Whisper process failed"
            case .emptyResult:
                return "No transcript produced"
            }
        }
        return "Transcription failed"
    }

    private func loadSessionScreenshots() -> [ScreenshotItem] {
        screenshotStore.load().filter { item in
            if let itemSessionID = item.sessionID {
                return itemSessionID == screenshotSessionID
            }
            return item.createdAt >= screenshotSessionStart
        }
    }
}

enum RecordingMode {
    case none
    case toggle
    case hold
}
