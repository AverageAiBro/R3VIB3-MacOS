import Foundation

final class WhisperCLITranscriber: TranscriptionEngine {
    private let fileSystem: FileSystem
    private let uuidProvider: UUIDProviding
    private let bundle: BundleProviding
    private let processRunner: ProcessRunning
    private let logger: WhisperLogging

    init(
        fileSystem: FileSystem = SystemFileSystem(),
        uuidProvider: UUIDProviding = SystemUUIDProvider(),
        bundle: BundleProviding = MainBundleProvider(),
        processRunner: ProcessRunning = SystemProcessRunner(),
        logger: WhisperLogging = DefaultWhisperLogger()
    ) {
        self.fileSystem = fileSystem
        self.uuidProvider = uuidProvider
        self.bundle = bundle
        self.processRunner = processRunner
        self.logger = logger
    }

    func transcribe(audioURL: URL, modelPath: String, completion: @escaping (Result<String, Error>) -> Void) {
        let whisperURL = bundle.url(forResource: "whisper-cli", withExtension: nil, subdirectory: nil)
            ?? bundle.url(forResource: "whisper-cli", withExtension: nil, subdirectory: "whisper")
        guard let whisperURL else {
            completion(.failure(TranscriptionError.missingWhisperBinary))
            return
        }
        guard fileSystem.fileExists(atPath: modelPath) else {
            completion(.failure(TranscriptionError.missingModel))
            return
        }
        ensureExecutable(url: whisperURL)

        let outputBase = fileSystem.temporaryDirectory
            .appendingPathComponent("ltp_out_\(uuidProvider.makeUUID().uuidString)")
        let outputTextURL = outputBase.appendingPathExtension("txt")
        defer { try? fileSystem.removeItem(at: outputTextURL) }

        let arguments = ["-m", modelPath, "-f", audioURL.path, "-otxt", "-of", outputBase.path]

        do {
            let result = try processRunner.run(executableURL: whisperURL, arguments: arguments)
            if result.terminationStatus != 0 {
                let message = String(data: result.output, encoding: .utf8) ?? "whisper-cli failed"
                completion(.failure(TranscriptionError.processFailed(message)))
                return
            }

            if let outputText = try? String(contentsOf: outputTextURL), !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                completion(.success(outputText.trimmingCharacters(in: .whitespacesAndNewlines)))
                return
            }

            let stdout = String(data: result.output, encoding: .utf8) ?? ""
            let parsed = WhisperTranscriptParser.parse(output: stdout)
            if parsed.isEmpty {
                completion(.failure(TranscriptionError.emptyResult))
            } else {
                completion(.success(parsed))
            }
        } catch {
            completion(.failure(error))
        }
    }

    private func ensureExecutable(url: URL) {
        let path = url.path
        guard fileSystem.fileExists(atPath: path), fileSystem.isExecutableFile(atPath: path) == false else { return }
        do {
            var attributes = try fileSystem.attributesOfItem(atPath: path)
            let current = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o644
            let updated = NSNumber(value: current | 0o111)
            attributes[.posixPermissions] = updated
            try fileSystem.setAttributes(attributes, ofItemAtPath: path)
        } catch {
            logger.logExecutableMarkFailed(error: error)
        }
    }

}
