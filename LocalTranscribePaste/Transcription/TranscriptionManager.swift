import Foundation
import AVFoundation

final class TranscriptionManager {
    private let engine: TranscriptionEngine
    private let converter: AudioConverting
    private let fileSystem: FileSystem
    private let queue: DispatchQueue

    init(
        engine: TranscriptionEngine = WhisperCLITranscriber(),
        converter: AudioConverting = AVAudioConverterService(),
        fileSystem: FileSystem = SystemFileSystem(),
        queue: DispatchQueue = DispatchQueue(label: "transcription.queue", qos: .userInitiated)
    ) {
        self.engine = engine
        self.converter = converter
        self.queue = queue
        self.fileSystem = fileSystem
    }

    func transcribe(audioURL: URL, modelPath: String, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            do {
                let resampledURL = try self.converter.convertTo16kMonoPCM(inputURL: audioURL)
                self.engine.transcribe(audioURL: resampledURL, modelPath: modelPath) { result in
                    // Engines may complete asynchronously; retain the WAV until completion.
                    if resampledURL != audioURL {
                        try? self.fileSystem.removeItem(at: resampledURL)
                    }
                    completion(result)
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
}
