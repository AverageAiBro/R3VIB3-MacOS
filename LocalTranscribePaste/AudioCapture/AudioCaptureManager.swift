import Foundation
import AVFoundation

final class AudioCaptureManager {
    private let fileSystem: FileSystem
    private let uuidProvider: UUIDProviding
    private let recorderFactory: AudioRecorderFactory
    private let audioFileReader: AudioFileReading
    private let logger: AudioCaptureLogging

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var isRecording = false

    init(
        fileSystem: FileSystem = SystemFileSystem(),
        uuidProvider: UUIDProviding = SystemUUIDProvider(),
        recorderFactory: AudioRecorderFactory = AVAudioRecorderFactory(),
        audioFileReader: AudioFileReading = SystemAudioFileReader(),
        logger: AudioCaptureLogging = DefaultAudioCaptureLogger()
    ) {
        self.fileSystem = fileSystem
        self.uuidProvider = uuidProvider
        self.recorderFactory = recorderFactory
        self.audioFileReader = audioFileReader
        self.logger = logger
    }

    func startRecording(preferredDeviceUID: String?, preferredChannelIndex: Int) throws {
        guard !isRecording else { return }

        let tempURL = fileSystem.temporaryDirectory
            .appendingPathComponent("ltp_recording_\(uuidProvider.makeUUID().uuidString).caf")
        recordingURL = tempURL
        defer {
            if !isRecording {
                recorder = nil
                recordingURL = nil
                try? fileSystem.removeItem(at: tempURL)
            }
        }

        do {
            try startRecorder(at: tempURL, sampleRate: 44100)
        } catch {
            logger.logRecorderStartFailed(sampleRate: 44100, error: error)
            try startRecorder(at: tempURL, sampleRate: 48000)
        }

        isRecording = true
        logger.logRecordingStart(url: tempURL)
    }

    func stopRecording() throws -> URL {
        guard isRecording else { throw AudioCaptureError.notRecording }
        recorder?.stop()
        recorder = nil
        isRecording = false
        guard let url = recordingURL else {
            throw AudioCaptureError.missingRecording
        }
        recordingURL = nil

        do {
            let info = try audioFileReader.readInfo(url: url)
            logger.logRecordingStop(frameLength: info.frameLength, duration: info.durationSeconds)
        } catch {
            logger.logRecordingReadFailed(error: error)
        }

        return url
    }
}

private extension AudioCaptureManager {
    func startRecorder(at url: URL, sampleRate: Double) throws {
        if fileSystem.fileExists(atPath: url.path) {
            try? fileSystem.removeItem(at: url)
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let recorder = try recorderFactory.makeRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw AudioCaptureError.recorderFailed
        }
        self.recorder = recorder
    }
}

enum AudioCaptureError: Error {
    case notRecording
    case missingRecording
    case recorderFailed
}
