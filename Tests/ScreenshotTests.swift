import XCTest
import AppKit
import ImageIO
@testable import R3VIB3

final class ScreenshotTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    @MainActor
    func testAsyncCapturePersistsOriginalPixelsMetadataAndPrunes() async throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 200,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let image = try XCTUnwrap(bitmap.cgImage)
        let store = ScreenshotStore(fileSystem: TestFileSystem(root: root), maxItems: 1, sessionID: "test-session") { id in
            XCTAssertEqual(id, 42)
            await Task.yield()
            return image
        }
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let firstResult = await store.capture(windowID: 42, screenFrameOverride: frame)
        let first = try XCTUnwrap(firstResult)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(first.url as CFURL, nil))
        let pixels = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(pixels.width, 320)
        XCTAssertEqual(pixels.height, 200)
        XCTAssertEqual(store.load().first?.screenFrame, frame)
        XCTAssertEqual(store.load().first?.sessionID, "test-session")
        let secondResult = await store.capture(windowID: 42, screenFrameOverride: frame)
        let second = try XCTUnwrap(secondResult)
        XCTAssertEqual(store.load().map(\.id), [second.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.deletingPathExtension().appendingPathExtension("meta.json").path))
    }

    @MainActor
    func testFailedAsyncCaptureDoesNotLeaveFilesAndZeroWindowIsRejected() async throws {
        var calls = 0
        let store = ScreenshotStore(fileSystem: TestFileSystem(root: root)) { _ in
            calls += 1
            throw CocoaError(.fileNoSuchFile)
        }
        let invalid = await store.capture(windowID: 0, screenFrameOverride: nil)
        XCTAssertNil(invalid)
        XCTAssertEqual(calls, 0)
        let failed = await store.capture(windowID: 42, screenFrameOverride: nil)
        XCTAssertNil(failed)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(store.load().isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("R3VIB3/Screenshots").path)
        XCTAssertTrue(files.isEmpty)
    }

    func testReloadPreservesIdentityAndDeletionKeepsOtherItemsStable() throws {
        let store = ScreenshotStore(fileSystem: TestFileSystem(root: root))
        let directory = root.appendingPathComponent("R3VIB3/Screenshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ids = [UUID(), UUID()]
        for id in ids {
            try Data().write(to: directory.appendingPathComponent("screenshot-2026-10-10T12-00-00Z-\(id.uuidString).png"))
        }
        let first = store.load()
        XCTAssertEqual(Set(first.map(\.id)), Set(ids))
        XCTAssertEqual(Set(store.load().map(\.id)), Set(ids))
        let removed = try XCTUnwrap(first.first)
        store.delete(removed)
        XCTAssertEqual(Set(store.load().map(\.id)), Set(ids).subtracting([removed.id]))
    }

    func testLargeImageIsDownsampledAndCached() async throws {
        let url = root.appendingPathComponent("large.png")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4000, pixelsHigh: 2400,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        let cache = ScreenshotPreviewCache()
        let loaded = await cache.image(for: url)
        let image = try XCTUnwrap(loaded)
        let representation = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertLessThanOrEqual(max(representation.width, representation.height), ScreenshotPreviewCache.maxPixelSize)
        let again = await cache.image(for: url)
        XCTAssertTrue(image === again)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let original = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(original[kCGImagePropertyPixelWidth] as? Int, 4000)
    }
}
