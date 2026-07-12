import AudioToolbox
import CoreAudio
import Foundation
import GetOudioCore

enum RecordingDeviceError: LocalizedError {
    case deviceNotFound(String)
    case property(OSStatus)

    var errorDescription: String? {
        switch self {
        case .deviceNotFound(let uid): return "找不到音频设备：\(uid)"
        case .property(let status): return "Core Audio 操作失败（\(status)）"
        }
    }
}

struct RecordingDeviceService {
    static func devices() -> [AudioDeviceDescriptor] {
        deviceIDs().compactMap(descriptor).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func descriptor(uid: String) -> AudioDeviceDescriptor? {
        guard let id = try? deviceID(uid: uid) else { return nil }
        return descriptor(id)
    }

    static func isAlive(uid: String) -> Bool {
        guard let id = try? deviceID(uid: uid) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    static func deviceID(uid: String) throws -> AudioDeviceID {
        guard let deviceID = deviceIDs().first(where: {
            stringProperty($0, selector: kAudioDevicePropertyDeviceUID) == uid
        }) else {
            throw RecordingDeviceError.deviceNotFound(uid)
        }
        return deviceID
    }

    static func defaultOutputDeviceID() throws -> AudioDeviceID {
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        )
        guard status == noErr else { throw RecordingDeviceError.property(status) }
        return id
    }

    static func defaultOutputDeviceUID() throws -> String {
        guard let descriptor = descriptor(try defaultOutputDeviceID()) else {
            throw RecordingDeviceError.deviceNotFound("default output")
        }
        return descriptor.uid
    }

    static func setDefaultOutputDevice(uid: String) throws {
        var id = try deviceID(uid: uid)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &id
        )
        guard status == noErr else { throw RecordingDeviceError.property(status) }
    }

    static func restoreDefaultOutput(preferredUID: String?, excluding excludedUID: String?) {
        if let preferredUID, preferredUID != excludedUID, isAlive(uid: preferredUID),
           (try? setDefaultOutputDevice(uid: preferredUID)) != nil {
            return
        }
        let fallback = devices().first {
            $0.uid != excludedUID && $0.outputChannelCount > 0 && !$0.name.hasPrefix("Pro Tools Audio Bridge")
        }
        if let fallback { try? setDefaultOutputDevice(uid: fallback.uid) }
    }

    static func bind(_ audioUnit: AudioUnit, to uid: String) throws {
        var id = try deviceID(uid: uid)
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else { throw RecordingDeviceError.property(status) }
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }
        return ids
    }

    private static func descriptor(_ id: AudioDeviceID) -> AudioDeviceDescriptor? {
        guard let uid: String = stringProperty(id, selector: kAudioDevicePropertyDeviceUID),
              let name: String = stringProperty(id, selector: kAudioObjectPropertyName) else { return nil }
        return AudioDeviceDescriptor(
            uid: uid,
            name: name,
            inputChannelCount: channelCount(id, scope: kAudioObjectPropertyScopeInput),
            outputChannelCount: channelCount(id, scope: kAudioObjectPropertyScopeOutput),
            nominalSampleRate: doubleProperty(id, selector: kAudioDevicePropertyNominalSampleRate) ?? 0
        )
    }

    private static func stringProperty(_ id: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeUnretainedValue() as String?
    }

    private static func doubleProperty(_ id: AudioObjectID, selector: AudioObjectPropertySelector) -> Double? {
        var value: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func channelCount(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return 0 }
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(pointer.assumingMemoryBound(to: AudioBufferList.self))
            .reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
