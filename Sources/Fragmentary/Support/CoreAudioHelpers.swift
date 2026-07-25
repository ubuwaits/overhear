import CoreAudio
import Foundation

enum CoreAudioFailure: LocalizedError {
    case operation(String, OSStatus)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .operation(operation, status):
            let code = UInt32(bitPattern: status)
            let characters = [
                Character(UnicodeScalar((code >> 24) & 0xff)!),
                Character(UnicodeScalar((code >> 16) & 0xff)!),
                Character(UnicodeScalar((code >> 8) & 0xff)!),
                Character(UnicodeScalar(code & 0xff)!)
            ]
            let fourCC = String(characters)
            return "\(operation) failed (\(fourCC), \(status))."
        case let .unavailable(message):
            return message
        }
    }
}

@inline(__always)
func requireNoError(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else {
        throw CoreAudioFailure.operation(operation, status)
    }
}

func propertyAddress(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: element
    )
}

func readDefaultOutputDevice() throws -> AudioObjectID {
    var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
    var device = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    try requireNoError(
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        ),
        "Reading the default output device"
    )
    guard device != kAudioObjectUnknown else {
        throw CoreAudioFailure.unavailable("No audio output device is available.")
    }
    return device
}

func readCFString(_ objectID: AudioObjectID, selector: AudioObjectPropertySelector) throws -> String {
    var address = propertyAddress(selector)
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    try requireNoError(
        withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, $0)
        },
        "Reading a Core Audio identifier"
    )
    return value as String
}

func readASBD(
    _ objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) throws -> AudioStreamBasicDescription {
    var address = propertyAddress(selector, scope: scope)
    var format = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    try requireNoError(
        AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &format),
        "Reading the audio stream format"
    )
    return format
}

func processObjectID(for pid: pid_t) -> AudioObjectID {
    var address = propertyAddress(kAudioHardwarePropertyTranslatePIDToProcessObject)
    var qualifier = pid
    var processID = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = withUnsafePointer(to: &qualifier) { qualifierPointer in
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            qualifierPointer,
            &size,
            &processID
        )
    }
    return status == noErr ? processID : AudioObjectID(kAudioObjectUnknown)
}
