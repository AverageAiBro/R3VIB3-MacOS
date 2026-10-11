import SwiftUI
import AppKit
import ImageIO

enum ScreenshotStripLayout {
    static let thumbnailWidth: CGFloat = 125
    static let thumbnailHeight: CGFloat = 99
    static let spacing: CGFloat = 12
    static let padding: CGFloat = 8
    static let margin: CGFloat = 16
    static let cornerRadius: CGFloat = 10
}

// Decode once at preview resolution, off the main thread. Original files remain untouched for dragging.
// NSCache is thread-safe; cached images are immutable after publication.
final class ScreenshotPreviewCache: @unchecked Sendable {
    static let shared = ScreenshotPreviewCache()
    static let maxPixelSize = 384
    private let cache = NSCache<NSURL, NSImage>()
    private let queue = DispatchQueue(label: "screenshots.previews", qos: .userInitiated)

    init() {
        cache.countLimit = 24
        cache.totalCostLimit = 12 * 1024 * 1024
    }

    func cachedImage(for url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }

    func image(for url: URL) async -> NSImage? {
        if let image = cachedImage(for: url) { return image }
        return await withCheckedContinuation { continuation in
            queue.async {
                if let image = self.cachedImage(for: url) {
                    continuation.resume(returning: image)
                    return
                }
                let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
                guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: Self.maxPixelSize,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else {
                    continuation.resume(returning: nil)
                    return
                }
                let image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
                self.cache.setObject(image, forKey: url as NSURL, cost: thumbnail.bytesPerRow * thumbnail.height)
                continuation.resume(returning: image)
            }
        }
    }
}

final class ScreenshotStripModel: ObservableObject {
    @Published var items: [ScreenshotItem] = []
}

struct ScreenshotClipboardView: View {
    @ObservedObject var model: ScreenshotStripModel
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: Set<UUID> = []

    var body: some View {
        HStack(spacing: ScreenshotStripLayout.spacing) {
            ForEach(model.items) { item in
                let draggedItems = dragItems(for: item)
                ScreenshotThumbnail(
                    item: item,
                    isSelected: selection.contains(item.id),
                    onTap: { toggleSelection(for: item) },
                    onClose: { appState.deleteScreenshot(item) },
                    dragItems: {
                        draggedItems.map { DragSourceItem(url: $0.url, previewImage: ScreenshotPreviewCache.shared.cachedImage(for: $0.url)) }
                    },
                    onDragEnded: { success in
                        if success { appState.deleteScreenshots(draggedItems) }
                    }
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .padding(ScreenshotStripLayout.padding)
        .glassEffect(R3VTheme.glass, in: RoundedRectangle(cornerRadius: 20))
        .r3vTheme()
        .onChange(of: model.items) { newValue in
            selection.formIntersection(newValue.map(\.id))
        }
    }

    private func toggleSelection(for item: ScreenshotItem) {
        if selection.contains(item.id) { selection.remove(item.id) }
        else { selection.insert(item.id) }
    }

    private func dragItems(for item: ScreenshotItem) -> [ScreenshotItem] {
        guard selection.contains(item.id) else { return [item] }
        return model.items.filter { selection.contains($0.id) }
    }
}

private struct ScreenshotThumbnail: View {
    let item: ScreenshotItem
    let isSelected: Bool
    let onTap: () -> Void
    let onClose: () -> Void
    let dragItems: () -> [DragSourceItem]
    let onDragEnded: (Bool) -> Void
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            R3VTheme.canvas
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "photo").foregroundColor(.secondary)
            }
        }
        .frame(width: ScreenshotStripLayout.thumbnailWidth, height: ScreenshotStripLayout.thumbnailHeight)
        .clipShape(RoundedRectangle(cornerRadius: ScreenshotStripLayout.cornerRadius))
        .overlay(DragSourceOverlay(onTap: onTap, dragItems: dragItems, onDragEnded: onDragEnded))
        .overlay(RoundedRectangle(cornerRadius: ScreenshotStripLayout.cornerRadius)
            .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            .allowsHitTesting(false))
        .overlay(alignment: .bottomLeading) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor)
                    .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                    .padding(6).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .glassEffect(R3VTheme.glass.interactive(), in: Circle())
            }
            .buttonStyle(.plain).padding(5)
            .accessibilityLabel("Remove screenshot")
            .help("Remove screenshot")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screenshot from \(item.createdAt.formatted(date: .omitted, time: .shortened))")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAction(named: "Toggle selection", onTap)
        .task(id: item.url) {
            let loaded = await ScreenshotPreviewCache.shared.image(for: item.url)
            if !Task.isCancelled { image = loaded }
        }
    }
}
