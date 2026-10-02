import AVFoundation
import CoreAudio

/// Everything the Mac plays, such as the other people on a Zoom, Meet, or FaceTime call, as
/// 16 kHz mono chunks. Uses a Core Audio process tap (macOS 14.2+), which asks for the "System
/// Audio Recording Only" permission instead of Screen Recording. Parrot's own sounds are left out.
///
/// If that permission is denied, the tap still runs but hears silence.
@MainActor
final class SystemAudio {
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?

    init(deliver: @escaping @Sendable ([Float]) -> Void) throws {
        do {
            try start(deliver: deliver)
        } catch {
            stop()
            throw error
        }
    }

    private func start(deliver: @escaping @Sendable ([Float]) -> Void) throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: Self.ownProcess().map { [$0] } ?? [])
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tap))

        var stream = try Self.format(of: tap)
        guard let format = AVAudioFormat(streamDescription: &stream) else { throw SystemAudioError.failed("format") }
        let converter = try Converter(from: format, deliver: deliver)

        // A tap is read through a private aggregate device, clocked by the current output.
        let output = try Self.defaultOutputUID()
        let settings: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Parrot Call",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: output,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        try check(AudioHardwareCreateAggregateDevice(settings as CFDictionary, &device))
        try check(AudioDeviceCreateIOProcIDWithBlock(&proc, device, Self.queue, Self.block(format: format, converter: converter)))
        try check(AudioDeviceStart(device, proc))
    }

    func stop() {
        if device != kAudioObjectUnknown {
            if let proc {
                AudioDeviceStop(device, proc)
                AudioDeviceDestroyIOProcID(device, proc)
            }
            AudioHardwareDestroyAggregateDevice(device)
        }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        proc = nil
        device = AudioObjectID(kAudioObjectUnknown)
        tap = AudioObjectID(kAudioObjectUnknown)
    }

    private static let queue = DispatchQueue(label: "dev.parrot.system-audio", qos: .userInitiated)

    /// Built outside the main actor so Core Audio can call it on its own queue.
    private nonisolated static func block(format: AVAudioFormat, converter: Converter) -> AudioDeviceIOBlock {
        { _, input, _, _, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil) else { return }
            converter.convert(buffer)
        }
    }

    private static func ownProcess() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var pid = getpid()
        var process = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &process)
        return status == noErr && process != kAudioObjectUnknown ? process : nil
    }

    private static func format(of tap: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format))
        return format
    }

    private static func defaultOutputUID() throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device))
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid))
        guard let uid = uid?.takeRetainedValue() else { throw SystemAudioError.failed("output") }
        return uid as String
    }
}

private func check(_ status: OSStatus) throws {
    guard status == noErr else { throw SystemAudioError.status(status) }
}

enum SystemAudioError: LocalizedError {
    case status(OSStatus)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .status(let status): "Parrot couldn't capture the Mac's audio (error \(status))."
        case .failed(let step): "Parrot couldn't capture the Mac's audio (\(step))."
        }
    }
}
