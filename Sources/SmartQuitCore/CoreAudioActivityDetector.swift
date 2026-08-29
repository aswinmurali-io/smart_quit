// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

import CoreAudio
import Foundation

/// Finds the processes playing audio, through CoreAudio's process objects.
///
/// CoreAudio has exposed a per-process view of the audio system since macOS
/// 14.2: every process that has ever opened the audio HAL appears in
/// `kAudioHardwarePropertyProcessObjectList`, and each one reports whether it
/// is rendering output at this moment. That is a direct answer to "is this app
/// playing something", where the alternatives — the now-playing info from the
/// private MediaRemote framework, or parsing `pmset -g assertions` — are
/// respectively unshippable and a guess.
///
/// No permission is required: output activity is not treated as private the way
/// microphone input is.
public final class CoreAudioActivityDetector: AudioActivityDetecting {
    public init() {}

    public func pidsPlayingAudio() -> Set<pid_t> {
        var playing: Set<pid_t> = []

        for object in processObjects() {
            guard isRunningOutput(object), let pid = pid(of: object) else { continue }
            playing.insert(pid)
        }

        return playing
    }

    // MARK: - CoreAudio

    /// Every process CoreAudio knows about, playing or not.
    private func processObjects() -> [AudioObjectID] {
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
            Log.audio.debug("Could not size the CoreAudio process list")
            return []
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var objects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else {
            Log.audio.debug("Could not read the CoreAudio process list")
            return []
        }

        return objects
    }

    private func isRunningOutput(_ object: AudioObjectID) -> Bool {
        // A process that has stopped playing stays in the list with this
        // property false, so absence of output is reported, not implied.
        read(kAudioProcessPropertyIsRunningOutput, from: object, as: UInt32.self).map { $0 != 0 }
            ?? false
    }

    private func pid(of object: AudioObjectID) -> pid_t? {
        read(kAudioProcessPropertyPID, from: object, as: pid_t.self).flatMap { $0 > 0 ? $0 : nil }
    }

    private func read<T>(
        _ selector: AudioObjectPropertySelector,
        from object: AudioObjectID,
        as type: T.Type
    ) -> T? {
        var address = Self.address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }

        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, value) == noErr else {
            return nil
        }
        return value.pointee
    }

    private static func address(
        _ selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
