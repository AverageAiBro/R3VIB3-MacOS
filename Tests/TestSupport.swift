import Foundation
import CoreAudio
@testable import R3VIB3

final class TestFileSystem: FileSystem {
    let root: URL
    private let underlying = SystemFileSystem()
    init(root: URL) { self.root = root }
    var temporaryDirectory: URL { root }
    func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] { [root] }
    func fileExists(atPath path: String) -> Bool { underlying.fileExists(atPath: path) }
    func isExecutableFile(atPath path: String) -> Bool { underlying.isExecutableFile(atPath: path) }
    func removeItem(at url: URL) throws { try underlying.removeItem(at: url) }
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws { try underlying.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories) }
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] { try underlying.attributesOfItem(atPath: path) }
    func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws { try underlying.setAttributes(attributes, ofItemAtPath: path) }
}

struct NoAudioDevices: AudioDeviceProviding {
    func inputDevices() -> [AudioInputDevice] { [] }
    func defaultInputDeviceID() -> AudioDeviceID? { nil }
    func deviceID(forUID uid: String) -> AudioDeviceID? { nil }
    func builtInMicrophoneDeviceID() -> AudioDeviceID? { nil }
    func deviceUID(deviceID: AudioDeviceID) -> String? { nil }
    func inputChannelCount(deviceID: AudioDeviceID) -> Int { 0 }
}

final class MemoryDefaults: KeyValueStoring {
    var values: [String: Any] = [:]
    func string(forKey key: String) -> String? { values[key] as? String }
    func data(forKey key: String) -> Data? { values[key] as? Data }
    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}
