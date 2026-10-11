import XCTest
import Carbon
import AppKit
@testable import R3VIB3

final class PasteTests: XCTestCase {
    func testTypedPasteUsesActualKeyCodesPreservesUnicodeAndDoesNotTouchClipboard() {
        let completed = expectation(description: "typed paste finished")
        let board = TestPasteboard()
        let sender = TestEventSender()
        let sleeper = TestSleeper()
        let manager = PasteManager(pasteboard: board, eventSender: sender, sleeper: sleeper,
                                   logger: CompletedPaste { completed.fulfill() })
        manager.paste(text: "AbZ019\né🙂", mode: .type)
        wait(for: [completed], timeout: 3)
        XCTAssertEqual(sender.keys.map(\.0), [kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_Z, kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_9, kVK_Return].map(CGKeyCode.init))
        XCTAssertEqual(sender.keys.map(\.1), [true, false, true, false, false, false, false])
        XCTAssertEqual(sender.unicode, ["é", "🙂"])
        XCTAssertEqual(sleeper.calls, 9)
        XCTAssertFalse(sleeper.sleptOnMainThread)
        XCTAssertEqual(board.copyCount, 0)
        XCTAssertEqual(board.snapshotCount, 0)
        XCTAssertEqual(board.restores, 0)
    }

    func testPasteRestoresClipboardUsingActualChangeCount() {
        let board = TestPasteboard()
        let main = DeferredMain()
        let sender = TestEventSender()
        let manager = PasteManager(pasteboard: board, eventSender: sender, mainThread: main)
        manager.paste(text: "hello", mode: .ctrlV)
        XCTAssertEqual(sender.modifiers, [.maskControl])
        XCTAssertEqual(board.restores, 0)
        main.scheduled?()
        XCTAssertEqual(board.restores, 1)
    }

    func testPasteDoesNotOverwriteNewClipboardContent() {
        let board = TestPasteboard()
        let main = DeferredMain()
        let manager = PasteManager(pasteboard: board, eventSender: TestEventSender(), mainThread: main)
        manager.paste(text: "hello", mode: .cmdV)
        board.copy(text: "new user content")
        main.scheduled?()
        XCTAssertEqual(board.restores, 0)
    }
}
private final class TestPasteboard: PasteboardWriting {
    var changeCount = 0
    var copyCount = 0
    var snapshotCount = 0
    var restores = 0
    func copy(text: String) { copyCount += 1; changeCount += 2 }
    func snapshot() -> PasteboardSnapshot { snapshotCount += 1; return PasteboardSnapshot(items: []) }
    func restore(_ snapshot: PasteboardSnapshot) { restores += 1 }
}
private final class TestEventSender: KeyboardEventSending {
    var keys: [(CGKeyCode, Bool)] = []
    var unicode: [String] = []
    var modifiers: [CGEventFlags] = []
    func sendPaste(modifier: CGEventFlags) { modifiers.append(modifier) }
    func sendKey(code: CGKeyCode, shift: Bool) { keys.append((code, shift)) }
    func sendUnicodeText(_ text: String) { unicode.append(text) }
}
private final class TestSleeper: SleepProviding {
    var calls = 0
    var sleptOnMainThread = false
    func sleep(microseconds: useconds_t) {
        calls += 1
        sleptOnMainThread = sleptOnMainThread || Thread.isMainThread
    }
}
private struct CompletedPaste: PasteLogging {
    let completed: () -> Void
    func logPasteExecuted() { completed() }
}
private final class DeferredMain: MainThreadRunning {
    var scheduled: (() -> Void)?
    func run(_ block: @escaping () -> Void) { block() }
    func runAfter(seconds: TimeInterval, _ block: @escaping () -> Void) { scheduled = block }
}
