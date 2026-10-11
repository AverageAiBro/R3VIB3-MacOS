import Foundation
import AVFoundation

protocol AudioConverting {
    func convertTo16kMonoPCM(inputURL: URL) throws -> URL
}

final class AVAudioConverterService: AudioConverting {
    // Memory use is independent of recording duration.
    private static let bufferFrames: AVAudioFrameCount = 4096
    private let fileSystem: FileSystem
    private let uuidProvider: UUIDProviding
    private let logger: TranscriptionLogging

    init(
        fileSystem: FileSystem = SystemFileSystem(),
        uuidProvider: UUIDProviding = SystemUUIDProvider(),
        logger: TranscriptionLogging = DefaultTranscriptionLogger()
    ) {
        self.fileSystem = fileSystem
        self.uuidProvider = uuidProvider
        self.logger = logger
    }

    func convertTo16kMonoPCM(inputURL: URL) throws -> URL {
        let input = try AVAudioFile(forReading: inputURL, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard input.length > 0 else { throw TranscriptionError.emptyResult }
        let inputFormat = input.processingFormat
        guard let monoFormat = AVAudioFormat(standardFormatWithSampleRate: inputFormat.sampleRate, channels: 1),
              let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: monoFormat, to: outputFormat),
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: Self.bufferFrames),
              let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: Self.bufferFrames),
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: Self.bufferFrames) else {
            throw TranscriptionError.conversionFailed
        }

        let channel = try loudestChannel(in: input, buffer: inputBuffer)
        input.framePosition = 0
        logger.logInputAudio(sampleRate: inputFormat.sampleRate, channels: inputFormat.channelCount,
                             frames: AVAudioFrameCount(clamping: input.length))
        let outputURL = fileSystem.temporaryDirectory
            .appendingPathComponent("ltp_resampled_\(uuidProvider.makeUUID().uuidString).wav")
        var succeeded = false
        defer {
            if !succeeded { try? fileSystem.removeItem(at: outputURL) }
        }
        let output = try AVAudioFile(forWriting: outputURL, settings: outputFormat.settings,
                                     commonFormat: .pcmFormatInt16, interleaved: true)
        var readError: Error?
        var totalFrames: Int64 = 0
        var peak: Float = 0
        let provideInput: AVAudioConverterInputBlock = { requestedFrames, status in
            do {
                guard input.framePosition < input.length else {
                    status.pointee = .endOfStream
                    return nil
                }
                let remaining = AVAudioFrameCount(clamping: input.length - input.framePosition)
                try input.read(into: inputBuffer, frameCount: min(requestedFrames, Self.bufferFrames, remaining))
                guard inputBuffer.frameLength > 0 else {
                    status.pointee = .endOfStream
                    return nil
                }
                monoBuffer.frameLength = inputBuffer.frameLength
                monoBuffer.floatChannelData![0].update(from: inputBuffer.floatChannelData![channel],
                                                      count: Int(inputBuffer.frameLength))
                status.pointee = .haveData
                return monoBuffer
            } catch {
                readError = error
                status.pointee = .endOfStream
                return nil
            }
        }

        while true {
            outputBuffer.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: provideInput)
            if let readError { throw readError }
            if let error { throw error }
            guard status != .error else { throw TranscriptionError.conversionFailed }
            if outputBuffer.frameLength > 0 {
                try output.write(from: outputBuffer)
                totalFrames += Int64(outputBuffer.frameLength)
                let samples = outputBuffer.int16ChannelData![0]
                for index in 0..<Int(outputBuffer.frameLength) {
                    peak = max(peak, abs(Float(samples[index])) / 32768)
                }
            }
            if status == .endOfStream { break }
        }
        guard totalFrames > 0 else { throw TranscriptionError.emptyResult }
        logger.logResampledAudio(frames: AVAudioFrameCount(clamping: totalFrames), peak: peak)
        succeeded = true
        return outputURL
    }

    private func loudestChannel(in file: AVAudioFile, buffer: AVAudioPCMBuffer) throws -> Int {
        let channelCount = Int(file.processingFormat.channelCount)
        guard channelCount > 1 else { return 0 }
        // Preserve the existing loudest-channel behavior without keeping the recording in memory.
        var peaks = [Float](repeating: 0, count: channelCount)
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: Self.bufferFrames)
            guard buffer.frameLength > 0 else { break }
            for channel in 0..<channelCount {
                let samples = buffer.floatChannelData![channel]
                for frame in 0..<Int(buffer.frameLength) {
                    peaks[channel] = max(peaks[channel], abs(samples[frame]))
                }
            }
        }
        let selected = peaks.indices.max(by: { peaks[$0] < peaks[$1] }) ?? 0
        logger.logChannelPeaks(peaks: peaks, selectedChannel: selected)
        return selected
    }
}

protocol TranscriptionLogging {
    func logInputAudio(sampleRate: Double, channels: UInt32, frames: AVAudioFrameCount)
    func logChannelPeaks(peaks: [Float], selectedChannel: Int)
    func logResampledAudio(frames: AVAudioFrameCount, peak: Float)
}

struct DefaultTranscriptionLogger: TranscriptionLogging {
    func logInputAudio(sampleRate: Double, channels: UInt32, frames: AVAudioFrameCount) {
        Log.transcription.info("Input audio: sr=\(sampleRate, privacy: .public) ch=\(channels, privacy: .public) frames=\(frames, privacy: .public)")
    }

    func logChannelPeaks(peaks: [Float], selectedChannel: Int) {
        Log.transcription.info("Channel peaks: \(peaks, privacy: .public) using=\(selectedChannel, privacy: .public)")
    }

    func logResampledAudio(frames: AVAudioFrameCount, peak: Float) {
        Log.transcription.info("Resampled audio: frames=\(frames, privacy: .public) peak=\(peak, privacy: .public)")
    }
}
