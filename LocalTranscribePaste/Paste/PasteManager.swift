import Foundation
import AppKit
import Carbon

final class PasteManager {
    private let pasteboard: PasteboardWriting
    private let eventSender: KeyboardEventSending
    private let sleeper: SleepProviding
    private let logger: PasteLogging
    private let mainThread: MainThreadRunning
    private let typingQueue = DispatchQueue(label: "paste.typing", qos: .userInitiated)

    init(
        pasteboard: PasteboardWriting = SystemPasteboard(),
        eventSender: KeyboardEventSending = SystemKeyboardEventSender(),
        sleeper: SleepProviding = SystemSleeper(),
        logger: PasteLogging = DefaultPasteLogger(),
        mainThread: MainThreadRunning = MainThreadRunner()
    ) {
        self.pasteboard = pasteboard
        self.eventSender = eventSender
        self.sleeper = sleeper
        self.logger = logger
        self.mainThread = mainThread
    }

    func copyToClipboard(text: String) {
        pasteboard.copy(text: text)
    }

    func paste(text: String, mode: PasteMode) {
        if mode == .type {
            // Typing does not need the clipboard and must not block the UI for 20 ms per character.
            typingQueue.async { [self] in
                typeString(text)
                logger.logPasteExecuted()
            }
            return
        }
        let snapshot = pasteboard.snapshot()
        copyToClipboard(text: text)
        let writtenChangeCount = pasteboard.changeCount
        eventSender.sendPaste(modifier: mode == .cmdV ? .maskCommand : .maskControl)
        mainThread.runAfter(seconds: 0.25) { [pasteboard, snapshot] in
            guard pasteboard.changeCount == writtenChangeCount else { return }
            pasteboard.restore(snapshot)
        }
        logger.logPasteExecuted()
    }

    private func typeString(_ text: String) {
        for char in text {
            if char == "\n" {
                eventSender.sendKey(code: CGKeyCode(kVK_Return), shift: false)
                sleeper.sleep(microseconds: 20000)
                continue
            }
            if let mapping = keyCodeForCharacter(char) {
                eventSender.sendKey(code: mapping.code, shift: mapping.shift)
            } else {
                eventSender.sendUnicodeText(String(char))
            }
            sleeper.sleep(microseconds: 20000)
        }
    }

    private func keyCodeForCharacter(_ char: Character) -> (code: CGKeyCode, shift: Bool)? {
        let lower = String(char).lowercased()
        if let mapping = Self.characterMapping[char] { return mapping }
        if lower.count == 1, let key = lower.first, let code = Self.letterCodes[key] {
            return (CGKeyCode(code), String(char) != lower)
        }
        return nil
    }

    private static let letterCodes: [Character: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
            "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
            "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
            "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z
        ]
    private static let characterMapping: [Character: (CGKeyCode, Bool)] = [
            "0": (CGKeyCode(kVK_ANSI_0), false), "1": (CGKeyCode(kVK_ANSI_1), false),
            "2": (CGKeyCode(kVK_ANSI_2), false), "3": (CGKeyCode(kVK_ANSI_3), false),
            "4": (CGKeyCode(kVK_ANSI_4), false), "5": (CGKeyCode(kVK_ANSI_5), false),
            "6": (CGKeyCode(kVK_ANSI_6), false), "7": (CGKeyCode(kVK_ANSI_7), false),
            "8": (CGKeyCode(kVK_ANSI_8), false), "9": (CGKeyCode(kVK_ANSI_9), false),
            "\t": (CGKeyCode(kVK_Tab), false),
            " ": (CGKeyCode(kVK_Space), false),
            ".": (CGKeyCode(kVK_ANSI_Period), false),
            ",": (CGKeyCode(kVK_ANSI_Comma), false),
            "?": (CGKeyCode(kVK_ANSI_Slash), true),
            "/": (CGKeyCode(kVK_ANSI_Slash), false),
            "-": (CGKeyCode(kVK_ANSI_Minus), false),
            "_": (CGKeyCode(kVK_ANSI_Minus), true),
            "=": (CGKeyCode(kVK_ANSI_Equal), false),
            "+": (CGKeyCode(kVK_ANSI_Equal), true),
            "'": (CGKeyCode(kVK_ANSI_Quote), false),
            "\"": (CGKeyCode(kVK_ANSI_Quote), true),
            ";": (CGKeyCode(kVK_ANSI_Semicolon), false),
            ":": (CGKeyCode(kVK_ANSI_Semicolon), true),
            "[": (CGKeyCode(kVK_ANSI_LeftBracket), false),
            "{": (CGKeyCode(kVK_ANSI_LeftBracket), true),
            "]": (CGKeyCode(kVK_ANSI_RightBracket), false),
            "}": (CGKeyCode(kVK_ANSI_RightBracket), true),
            "\\": (CGKeyCode(kVK_ANSI_Backslash), false),
            "|": (CGKeyCode(kVK_ANSI_Backslash), true),
            "`": (CGKeyCode(kVK_ANSI_Grave), false),
            "~": (CGKeyCode(kVK_ANSI_Grave), true),
            "!": (CGKeyCode(kVK_ANSI_1), true),
            "@": (CGKeyCode(kVK_ANSI_2), true),
            "#": (CGKeyCode(kVK_ANSI_3), true),
            "$": (CGKeyCode(kVK_ANSI_4), true),
            "%": (CGKeyCode(kVK_ANSI_5), true),
            "^": (CGKeyCode(kVK_ANSI_6), true),
            "&": (CGKeyCode(kVK_ANSI_7), true),
            "*": (CGKeyCode(kVK_ANSI_8), true),
            "(": (CGKeyCode(kVK_ANSI_9), true),
            ")": (CGKeyCode(kVK_ANSI_0), true)
        ]
}
