import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import ScreenCaptureKit

struct ScreenshotItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let createdAt: Date
    let screenFrame: CGRect?
    let sessionID: String?

    static func == (lhs: ScreenshotItem, rhs: ScreenshotItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

protocol ScreenshotStoring {
    func load() -> [ScreenshotItem]
    @MainActor func capture(windowID: CGWindowID, screenFrameOverride: CGRect?) async -> ScreenshotItem?
    func delete(_ item: ScreenshotItem)
    func pruneIfNeeded(keepLast: Int)
}

final class ScreenshotStore: ScreenshotStoring {
    private let fileSystem: FileSystem
    private let uuidProvider: UUIDProviding
    private let processRunner: ProcessRunning
    private let maxItems: Int
    private let sessionID: String?
    private let imageCapture: (CGWindowID) async throws -> CGImage

    init(
        fileSystem: FileSystem = SystemFileSystem(),
        uuidProvider: UUIDProviding = SystemUUIDProvider(),
        processRunner: ProcessRunning = SystemProcessRunner(),
        maxItems: Int = 10,
        sessionID: String? = nil,
        imageCapture: @escaping (CGWindowID) async throws -> CGImage = ScreenshotStore.captureImage
    ) {
        self.fileSystem = fileSystem
        self.uuidProvider = uuidProvider
        self.processRunner = processRunner
        self.maxItems = maxItems
        self.sessionID = sessionID
        self.imageCapture = imageCapture
    }

    func load() -> [ScreenshotItem] {
        let directory = screenshotsDirectory()
        guard let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        return items.compactMap { url in
            guard url.pathExtension.lowercased() == "png" else { return nil }
            let values = try? url.resourceValues(forKeys: [.creationDateKey])
            let createdAt = values?.creationDate ?? Date.distantPast
            // UUIDs contain hyphens; the final component is only twelve characters.
            guard let id = UUID(uuidString: String(url.deletingPathExtension().lastPathComponent.suffix(36))) else {
                return nil
            }
            let metadata = readMetadataFull(for: url)
            return ScreenshotItem(
                id: id,
                url: url,
                createdAt: createdAt,
                screenFrame: metadata?.screenFrame.cgRect,
                sessionID: metadata?.sessionID
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    @MainActor func capture(windowID: CGWindowID, screenFrameOverride: CGRect?) async -> ScreenshotItem? {
        guard windowID != 0 else { return nil }
        let id = uuidProvider.makeUUID()
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let filename = "screenshot-\(timestamp)-\(id.uuidString).png"
        let url = screenshotsDirectory().appendingPathComponent(filename)
        let windowBounds = windowBoundsForWindow(windowID)
        let screenFrame = screenFrameOverride ?? windowBounds.flatMap { screenFrameForWindowBounds($0) }

        do {
            let image = try await imageCapture(windowID)
            guard !Task.isCancelled, writePNG(cgImage: image, to: url) else { return nil }
            writeMetadata(for: url, screenFrame: screenFrame)
            pruneIfNeeded(keepLast: maxItems)
            let createdAt = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            return ScreenshotItem(id: id, url: url, createdAt: createdAt, screenFrame: screenFrame, sessionID: sessionID)
        } catch {
            Log.screenshots.error("Window capture failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func delete(_ item: ScreenshotItem) {
        try? fileSystem.removeItem(at: item.url)
        try? fileSystem.removeItem(at: metadataURL(for: item.url))
    }

    func pruneIfNeeded(keepLast: Int) {
        let items = load()
        guard items.count > keepLast else { return }
        let toDelete = items.suffix(from: keepLast)
        for item in toDelete {
            delete(item)
        }
    }

    private func screenshotsDirectory() -> URL {
        let appSupport = fileSystem.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("R3VIB3/Screenshots", isDirectory: true)
        if !fileSystem.fileExists(atPath: dir.path) {
            try? fileSystem.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func writePNG(cgImage: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        return CGImageDestinationFinalize(destination)
    }

    private struct ScreenshotMetadata: Codable {
        let screenFrame: ScreenshotRect
        let sessionID: String?
    }

    private struct ScreenshotRect: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(_ rect: CGRect) {
            x = Double(rect.origin.x)
            y = Double(rect.origin.y)
            width = Double(rect.size.width)
            height = Double(rect.size.height)
        }

        var cgRect: CGRect {
            CGRect(x: x, y: y, width: width, height: height)
        }
    }

    private func metadataURL(for screenshotURL: URL) -> URL {
        screenshotURL.deletingPathExtension().appendingPathExtension("meta.json")
    }

    private func writeMetadata(for screenshotURL: URL, screenFrame: CGRect?) {
        guard let screenFrame else { return }
        let metadata = ScreenshotMetadata(screenFrame: ScreenshotRect(screenFrame), sessionID: sessionID)
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: metadataURL(for: screenshotURL), options: [.atomic])
    }

    private func readMetadataFull(for screenshotURL: URL) -> ScreenshotMetadata? {
        let url = metadataURL(for: screenshotURL)
        guard let data = try? Data(contentsOf: url),
              let metadata = try? JSONDecoder().decode(ScreenshotMetadata.self, from: data) else {
            return nil
        }
        return metadata
    }

    private func readMetadata(for screenshotURL: URL) -> CGRect? {
        readMetadataFull(for: screenshotURL)?.screenFrame.cgRect
    }

    static func captureImage(windowID: CGWindowID) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = max(1, Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded()))
        config.height = max(1, Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded()))
        config.ignoreShadowsSingleWindow = true
        config.ignoreGlobalClipSingleWindow = true
        config.showsCursor = false
        config.capturesAudio = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private func screenFrameForWindowBounds(_ windowBounds: CGRect) -> CGRect? {
        screenForWindowBounds(windowBounds)?.frame
    }

    private func screenForWindowBounds(_ windowBounds: CGRect) -> NSScreen? {
        let appKitBounds = appKitBounds(for: windowBounds)
        var bestScreen: NSScreen?
        var bestArea: CGFloat = 0
        for screen in NSScreen.screens {
            let intersection = appKitBounds.intersection(screen.frame)
            let area = max(intersection.width, 0) * max(intersection.height, 0)
            if area > bestArea {
                bestArea = area
                bestScreen = screen
            }
        }
        if bestArea > 0 {
            return bestScreen
        }
        return NSScreen.screens.first(where: { $0.frame.intersects(appKitBounds) })
    }

    private func appKitBounds(for cgBounds: CGRect) -> CGRect {
        let primaryHeight = primaryScreenHeight()
        return CGRect(
            x: cgBounds.origin.x,
            y: primaryHeight - cgBounds.origin.y - cgBounds.height,
            width: cgBounds.width,
            height: cgBounds.height
        )
    }

    private func primaryScreenHeight() -> CGFloat {
        if let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) {
            return primary.frame.height
        }
        if let main = NSScreen.main {
            return main.frame.height
        }
        return 0
    }

    private func windowBoundsForWindow(_ windowID: CGWindowID) -> CGRect? {
        let options: CGWindowListOption = [.optionIncludingWindow]
        guard let infoList = CGWindowListCopyWindowInfo(options, windowID) as? [[String: Any]] else {
            return nil
        }
        for info in infoList {
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            if bounds.isNull || bounds.isEmpty { continue }
            return bounds
        }
        return nil
    }

}
