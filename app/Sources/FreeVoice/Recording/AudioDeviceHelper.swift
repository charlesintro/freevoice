// =============================================================================
// AudioDeviceHelper.swift — CoreAudio device enumeration
// =============================================================================
//
// Lists audio input devices and resolves device UIDs to AudioDeviceIDs.
// Used by RecordingController for per-app input device selection and by
// PreferencesWindowController to populate the microphone picker.
// =============================================================================

import CoreAudio
import Foundation

enum AudioDeviceHelper {

    struct InputDevice {
        let name: String
        let uid: String
    }

    // MARK: - List all audio input devices

    /// Returns all audio devices that have at least one input channel,
    /// sorted by name. Empty UID is reserved for "System Default".
    static func listInputDevices() -> [InputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        ) == noErr, dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return [] }

        return deviceIDs.compactMap { deviceID -> InputDevice? in
            guard hasInputChannels(deviceID) else { return nil }
            guard let uid  = stringProperty(deviceID, kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(deviceID, kAudioDevicePropertyDeviceNameCFString)
            else { return nil }
            return InputDevice(name: name, uid: uid)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Resolve UID → AudioDeviceID

    /// Returns the AudioDeviceID matching the given UID, or nil if not found.
    /// Uses safe device iteration rather than AudioValueTranslation to avoid
    /// pointer-lifetime warnings.
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        ) == noErr, dataSize > 0 else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return nil }

        return deviceIDs.first { stringProperty($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    // MARK: - Private helpers

    private static func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope:    kAudioDevicePropertyScopeInput,
            mElement:  kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size > 0 else { return false }

        let bufferListPtr = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferListPtr.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPtr) == noErr
        else { return false }

        let bufferList = bufferListPtr.load(as: AudioBufferList.self)
        let buffers = UnsafeBufferPointer<AudioBuffer>(
            start: bufferListPtr.advanced(by: MemoryLayout<UInt32>.size).assumingMemoryBound(to: AudioBuffer.self),
            count: Int(bufferList.mNumberBuffers)
        )
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    /// Reads a CFString property from a CoreAudio device.
    /// Uses Unmanaged<CFString> to correctly express ownership to Swift's
    /// type system and avoid "Forming UnsafeMutableRawPointer" warnings.
    private static func stringProperty(_ deviceID: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var ref: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &ref) == noErr
        else { return nil }
        return ref?.takeRetainedValue() as String?
    }
}
