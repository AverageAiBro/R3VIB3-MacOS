import AppKit
import SwiftUI
import Combine

final class ScreenshotClipboardWindowController: NSWindowController {
    private let model = ScreenshotStripModel()
    private var cancellable: AnyCancellable?
    private var latestItems: [ScreenshotItem] = []
    private let thumbnailWidth: CGFloat = ScreenshotStripLayout.thumbnailWidth
    private let thumbnailHeight: CGFloat = ScreenshotStripLayout.thumbnailHeight
    private let spacing: CGFloat = ScreenshotStripLayout.spacing
    private let padding: CGFloat = ScreenshotStripLayout.padding
    private let margin: CGFloat = ScreenshotStripLayout.margin

    init(appState: AppState) {
        let view = ScreenshotClipboardView(model: model).environmentObject(appState)
        let hosting = NSHostingController(rootView: view)
        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.nonactivatingPanel, .borderless]
        R3VTheme.configure(panel)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        super.init(window: panel)

        cancellable = appState.$screenshots
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                self?.update(with: items)
            }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        update(with: latestItems)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func update(with items: [ScreenshotItem]) {
        guard let screen = anchorScreen(for: items) ?? (NSScreen.main ?? NSScreen.screens.first) else { return }
        latestItems = items
        let ordered = items.sorted { $0.createdAt < $1.createdAt }
        let visibleCount = maxVisibleCount(for: screen)
        let visibleItems = Array(ordered.suffix(visibleCount))
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if visibleItems.count > model.items.count && !reduceMotion {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                model.items = visibleItems
            }
        } else {
            model.items = visibleItems
        }

        guard !visibleItems.isEmpty else {
            window?.orderOut(nil)
            return
        }

        let size = sizeForCount(visibleItems.count)
        let frame = frameForSize(size, in: screen)
        window?.setFrame(frame, display: true, animate: !reduceMotion)
        window?.orderFrontRegardless()
    }

    private func maxVisibleCount(for screen: NSScreen) -> Int {
        let availableWidth = screen.visibleFrame.width - (margin * 2)
        let itemWidth = thumbnailWidth + spacing
        let rawCount = Int((availableWidth + spacing) / max(itemWidth, 1))
        return max(rawCount, 1)
    }

    private func sizeForCount(_ count: Int) -> CGSize {
        let width = (padding * 2) + (CGFloat(count) * thumbnailWidth) + (CGFloat(max(count - 1, 0)) * spacing)
        let height = (padding * 2) + thumbnailHeight
        return CGSize(width: width, height: height)
    }

    private func frameForSize(_ size: CGSize, in screen: NSScreen) -> NSRect {
        let frame = screen.visibleFrame
        let x = frame.maxX - size.width - margin
        let y = frame.minY + margin
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func anchorScreen(for items: [ScreenshotItem]) -> NSScreen? {
        guard let latest = items.max(by: { $0.createdAt < $1.createdAt }) else { return nil }
        guard let screenFrame = latest.screenFrame else { return nil }
        return screenForFrame(screenFrame)
    }

    private func screenForFrame(_ frame: CGRect) -> NSScreen? {
        var bestScreen: NSScreen?
        var bestArea: CGFloat = 0
        for screen in NSScreen.screens {
            let intersection = frame.intersection(screen.frame)
            let area = max(intersection.width, 0) * max(intersection.height, 0)
            if area > bestArea {
                bestArea = area
                bestScreen = screen
            }
        }
        if bestArea > 0 {
            return bestScreen
        }
        return NSScreen.screens.first(where: { $0.frame.intersects(frame) })
    }
}
