import XCTest
import Carbon
import CoreGraphics
@testable import R3VIB3

final class AppStateTests: XCTestCase {
    private var root: URL!
    private var settings: SettingsStore!
    private var audio: TestCapture!
    private var transcription: TestTranscription!
    private var hotkeys: TestHotkeys!
    private var hold: TestHoldHotkeys!
    private var status: TestStatus!
    private var app: AppState!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        settings = SettingsStore(defaults: MemoryDefaults(), fileSystem: TestFileSystem(root: root), deviceProvider: NoAudioDevices())
        audio = TestCapture(url: root.appendingPathComponent("recording.caf"))
        transcription = TestTranscription()
        hotkeys = TestHotkeys()
        hold = TestHoldHotkeys()
        status = TestStatus()
        let status = status!
        app = AppState(settings: settings, audioCapture: audio, transcriptionManager: transcription,
            pasteManager: TestPaste(), screenshotStore: EmptyScreenshots(), permissions: TestPermissions(),
            hotkeyManager: hotkeys, holdHotkeyManager: hold, statusBarControllerFactory: { _ in status },
            mainThread: ImmediateMain(), fileSystem: TestFileSystem(root: root))
    }
    override func tearDownWithError() throws {
        app = nil
        try FileManager.default.removeItem(at: root)
    }

    func testNewHotkeyIsRegisteredImmediatelyIncludingEventTapTransition() {
        let newKey = Hotkey(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(controlKey | shiftKey))
        settings.toggleHotkey = newKey
        XCTAssertEqual(hotkeys.toggle, newKey)
        XCTAssertEqual(hold.toggle, newKey)
        settings.toggleHotkey = Hotkey(keyCode: 0, modifiers: 0, usesFunction: true, isFunctionOnly: true)
        XCTAssertNil(hotkeys.toggle)
        XCTAssertEqual(hotkeys.paste, settings.pasteHotkey)
        settings.pasteHotkey = newKey
        XCTAssertEqual(hotkeys.paste, newKey)
        settings.screenshotHotkey = newKey
        XCTAssertEqual(hotkeys.screenshot, newKey)
    }

    func testRecordingRetryAndClearCannotOverlapTranscription() {
        app.toggleDictation()
        XCTAssertTrue(app.isRecording)
        app.toggleDictation()
        XCTAssertTrue(app.isTranscribing)
        XCTAssertFalse(app.isRecording)
        XCTAssertEqual(app.activeRecordingMode, .none)
        app.toggleDictation()
        hold.onHoldStart?()
        app.retryTranscription()
        app.clearTranscript()
        XCTAssertEqual(audio.starts, 1)
        XCTAssertEqual(transcription.calls, 1)
        XCTAssertNotNil(app.lastAudioFileURL)
        transcription.completion?(.success("A finished transcript"))
        XCTAssertFalse(app.isTranscribing)
        XCTAssertEqual(app.lastTranscript, "A finished transcript")
        XCTAssertTrue(app.isPasteReady)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.url.path), "Keep the source for Retry")
        app.clearTranscript()
        XCTAssertTrue(app.lastTranscript.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.url.path))
    }

    func testStartFailureResetsModeAndAllowsAnotherAttempt() {
        audio.failStart = true
        app.toggleDictation()
        XCTAssertFalse(app.isRecording)
        XCTAssertEqual(app.activeRecordingMode, .none)
        audio.failStart = false
        app.toggleDictation()
        XCTAssertTrue(app.isRecording)
    }

    func testClearingExternalTranscriptionDoesNotDeleteSource() throws {
        let source = root.appendingPathComponent("external.wav")
        try Data().write(to: source)
        app.transcribe(audioURL: source)
        transcription.completion?(.failure(TranscriptionError.emptyResult))
        app.clearTranscript()
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testSettingsSubscriptionsDoNotRetainAppState() {
        weak let weakApp = app
        app = nil
        XCTAssertNil(weakApp)
    }
}

private final class TestCapture: AudioCapturing {
    let url: URL
    var starts = 0
    var failStart = false
    init(url: URL) { self.url = url }
    func startRecording(preferredDeviceUID: String?, preferredChannelIndex: Int) throws {
        starts += 1
        if failStart { throw AudioCaptureError.recorderFailed }
        try Data().write(to: url)
    }
    func stopRecording() throws -> URL { url }
}
private final class TestTranscription: TranscriptionManaging {
    var calls = 0
    var completion: ((Result<String, Error>) -> Void)?
    func transcribe(audioURL: URL, modelPath: String, completion: @escaping (Result<String, Error>) -> Void) {
        calls += 1
        self.completion = completion
    }
}
private struct TestPaste: PasteManaging {
    func copyToClipboard(text: String) {}
    func paste(text: String, mode: PasteMode) {}
}
private struct EmptyScreenshots: ScreenshotStoring {
    func load() -> [ScreenshotItem] { [] }
    @MainActor func capture(windowID: CGWindowID, screenFrameOverride: CGRect?) async -> ScreenshotItem? { nil }
    func delete(_ item: ScreenshotItem) {}
    func pruneIfNeeded(keepLast: Int) {}
}
private final class TestHotkeys: HotkeyManaging {
    var onToggleDictation: (() -> Void)?
    var onPasteLastTranscript: (() -> Void)?
    var onCaptureScreenshot: (() -> Void)?
    var toggle: Hotkey?
    var paste: Hotkey?
    var screenshot: Hotkey?
    func registerHotkeys(toggle: Hotkey?, paste: Hotkey?, screenshot: Hotkey?) {
        self.toggle = toggle; self.paste = paste; self.screenshot = screenshot
    }
}
private final class TestHoldHotkeys: HoldHotkeyManaging {
    var onToggle: (() -> Void)?
    var onPaste: (() -> Void)?
    var onHoldStart: (() -> Void)?
    var onHoldEnd: (() -> Void)?
    var onScreenshot: (() -> Void)?
    var onPasteKeystroke: ((UInt32, CGEventFlags) -> Void)?
    var toggle: Hotkey?
    func updateHotkeys(toggle: Hotkey, paste: Hotkey, hold: Hotkey, screenshot: Hotkey) { self.toggle = toggle }
    func updateHoldHotkey(_ hotkey: Hotkey) {}
    func updateToggleHotkey(_ hotkey: Hotkey) { toggle = hotkey }
    func updatePasteHotkey(_ hotkey: Hotkey) {}
    func updateScreenshotHotkey(_ hotkey: Hotkey) {}
    func start() {}
    func restartIfNeeded() {}
}
private final class TestStatus: StatusBarControlling {
    func updateRecordingIndicator(isRecording: Bool) {}
    func showPasteReadyIndicator() {}
    func clearPasteReadyIndicator() {}
    func showTranscript(text: String) {}
    func showMessage(_ message: String) {}
    func showPermissions() {}
    func showSettings() {}
    func showScreenshotClipboard() {}
}
private struct TestPermissions: PermissionsManaging {
    var isMicrophoneAuthorized: Bool { true }
    var isAccessibilityAuthorized: Bool { true }
    var isScreenRecordingAuthorized: Bool { true }
    var microphoneStatus: MicrophoneAuthorizationStatus { .authorized }
    func requestMicrophoneAccess(completion: @escaping (Bool) -> Void) { completion(true) }
    func openMicrophoneSettings() {}
    func requestAccessibilityAccess() {}
    func requestScreenRecordingAccess() {}
    func openScreenRecordingSettings() {}
    func resetAccessibilityPermissionIfNeeded() {}
    func logCurrentStatus() {}
}
private struct ImmediateMain: MainThreadRunning {
    func run(_ block: @escaping () -> Void) { block() }
    func runAfter(seconds: TimeInterval, _ block: @escaping () -> Void) { block() }
}
