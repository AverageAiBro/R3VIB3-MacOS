import XCTest
import AVFoundation
@testable import R3VIB3

final class AudioConversionTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testResamplesAcrossManyChunksAndPreservesDuration() throws {
        for rate in [44100.0, 48000.0] {
            let source = try makeAudio(sampleRate: rate, channels: 1, seconds: 12.37)
            let output = try AVAudioConverterService().convertTo16kMonoPCM(inputURL: source)
            defer { try? FileManager.default.removeItem(at: output) }
            let file = try AVAudioFile(forReading: output)
            XCTAssertEqual(file.fileFormat.sampleRate, 16000)
            XCTAssertEqual(file.fileFormat.channelCount, 1)
            XCTAssertEqual(file.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int, 16)
            XCTAssertEqual(Double(file.length), 12.37 * 16000, accuracy: 2)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1024))
            try file.read(into: buffer)
            let peak = (0..<Int(buffer.frameLength)).map { abs(buffer.floatChannelData![0][$0]) }.max()!
            XCTAssertGreaterThan(peak, 0.4)
        }
    }

    func testSelectsAudibleStereoChannelWithoutFormatMismatch() throws {
        let source = try makeAudio(sampleRate: 48000, channels: 2, seconds: 1.23)
        let output = try AVAudioConverterService().convertTo16kMonoPCM(inputURL: source)
        defer { try? FileManager.default.removeItem(at: output) }
        let file = try AVAudioFile(forReading: output)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16000))
        try file.read(into: buffer)
        let peak = (0..<Int(buffer.frameLength)).map { abs(buffer.floatChannelData![0][$0]) }.max()!
        XCTAssertGreaterThan(peak, 0.4, "The silent left channel must not replace the audible right channel")
    }

    func testEmptyAudioFailsExplicitly() throws {
        let source = try makeAudio(sampleRate: 44100, channels: 1, seconds: 0)
        XCTAssertThrowsError(try AVAudioConverterService().convertTo16kMonoPCM(inputURL: source)) { error in
            guard case TranscriptionError.emptyResult = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    private func makeAudio(sampleRate: Double, channels: AVAudioChannelCount, seconds: Double) throws -> URL {
        let url = directory.appendingPathComponent(UUID().uuidString + ".caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels))
        var fileSettings = format.settings
        fileSettings[AVLinearPCMIsNonInterleaved] = false
        let file = try AVAudioFile(forWriting: url, settings: fileSettings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
        var written = 0
        let frames = Int(sampleRate * seconds)
        while written < frames {
            let count = min(4096, frames - written)
            buffer.frameLength = AVAudioFrameCount(count)
            for channel in 0..<Int(channels) {
                for frame in 0..<count {
                    buffer.floatChannelData![channel][frame] = channel == Int(channels) - 1
                        ? Float(sin(Double(written + frame) * 2 * .pi * 440 / sampleRate)) * 0.5 : 0
                }
            }
            try file.write(from: buffer)
            written += count
        }
        return url
    }
}
