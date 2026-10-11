import AppKit
import SwiftUI

final class RecordingIndicatorWindowController: NSWindowController {
    private var hostingView: NSHostingView<RecordingIndicatorView>?
    private var mode: IndicatorMode = .recording

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 44),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        R3VTheme.configure(panel)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel)
        let view = RecordingIndicatorView(mode: mode)
        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hosting
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor)
        ])
        hostingView = hosting
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(mode: IndicatorMode = .recording) {
        guard let window = window else { return }
        update(mode: mode)
        positionWindow(window)
        window.orderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func update(mode: IndicatorMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        hostingView?.rootView = RecordingIndicatorView(mode: mode)
        if let window = window {
            let size = sizeForMode(mode)
            window.setFrame(NSRect(origin: window.frame.origin, size: size), display: false)
        }
    }

    private func positionWindow(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = sizeForMode(mode)
        let width = size.width
        let height = size.height
        let x = frame.midX - width / 2
        let y = frame.minY + 12
        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
    }

    private func sizeForMode(_ mode: IndicatorMode) -> CGSize {
        switch mode {
        case .recording:
            return CGSize(width: 160, height: 44)
        case .pasteReady, .transcribing:
            return CGSize(width: 180, height: 44)
        }
    }
}
