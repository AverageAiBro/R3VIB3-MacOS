import XCTest
@testable import R3VIB3

final class TranscriptionCleanupTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testResampledFileLivesUntilAsyncEngineCompletesThenIsRemoved() throws {
        for result: Result<String, Error> in [.success("Hello"), .failure(TranscriptionError.emptyResult)] {
            let source = root.appendingPathComponent(UUID().uuidString + ".caf")
            let resampled = root.appendingPathComponent(UUID().uuidString + ".wav")
            try Data().write(to: source)
            try Data().write(to: resampled)
            let started = expectation(description: "engine started")
            let completed = expectation(description: "completion")
            let engine = DeferredEngine(started: { started.fulfill() })
            let manager = TranscriptionManager(engine: engine, converter: FixedConverter(output: resampled))
            manager.transcribe(audioURL: source, modelPath: "model") { _ in
                XCTAssertFalse(FileManager.default.fileExists(atPath: resampled.path))
                XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
                completed.fulfill()
            }
            wait(for: [started], timeout: 3)
            XCTAssertTrue(FileManager.default.fileExists(atPath: resampled.path))
            engine.completion?(result)
            wait(for: [completed], timeout: 3)
        }
    }

    func testWhisperOutputRemovedAfterSuccessAndProcessFailure() throws {
        let model = root.appendingPathComponent("model.bin")
        try Data().write(to: model)
        for status: Int32 in [0, 1] {
            let runner = OutputProcess(status: status)
            let engine = WhisperCLITranscriber(fileSystem: TestFileSystem(root: root),
                bundle: TestBundle(), processRunner: runner)
            var result: Result<String, Error>?
            engine.transcribe(audioURL: root.appendingPathComponent("audio.wav"), modelPath: model.path) { result = $0 }
            XCTAssertNotNil(result)
            XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(runner.output).path))
            if status == 0 { XCTAssertEqual(try result?.get(), "Test transcript") }
            else { XCTAssertThrowsError(try result?.get()) }
        }
    }
}

private struct FixedConverter: AudioConverting {
    let output: URL
    func convertTo16kMonoPCM(inputURL: URL) throws -> URL { output }
}
private final class DeferredEngine: TranscriptionEngine {
    var completion: ((Result<String, Error>) -> Void)?
    let started: () -> Void
    init(started: @escaping () -> Void) { self.started = started }
    func transcribe(audioURL: URL, modelPath: String, completion: @escaping (Result<String, Error>) -> Void) {
        self.completion = completion
        started()
    }
}
private struct TestBundle: BundleProviding {
    var bundleIdentifier: String? { "test" }
    var bundlePath: String { "/test" }
    func url(forResource name: String, withExtension ext: String?, subdirectory: String?) -> URL? { URL(fileURLWithPath: "/usr/bin/true") }
}
private final class OutputProcess: ProcessRunning {
    let status: Int32
    var output: URL?
    init(status: Int32) { self.status = status }
    func run(executableURL: URL, arguments: [String]) throws -> ProcessResult {
        let index = arguments.firstIndex(of: "-of")!
        let url = URL(fileURLWithPath: arguments[index + 1]).appendingPathExtension("txt")
        try "Test transcript".write(to: url, atomically: true, encoding: .utf8)
        output = url
        return ProcessResult(terminationStatus: status, output: Data())
    }
}
