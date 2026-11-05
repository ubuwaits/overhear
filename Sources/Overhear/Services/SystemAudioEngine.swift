import CoreAudio
import Foundation
import OverhearDSP
import os

final class SystemAudioEngine: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.chadwin.overhear", category: "audio")
    private let controlQueue = DispatchQueue(label: "com.chadwin.overhear.audio-control")

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var processor: OpaquePointer?
    private var running = false

    deinit {
        stopSynchronously()
    }

    func start(place: Place, blend: Double) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            controlQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CoreAudioFailure.unavailable("The audio engine was released."))
                    return
                }
                do {
                    if self.running {
                        self.setPlaceSynchronously(place)
                        self.setBlendSynchronously(blend)
                    } else {
                        try self.startSynchronously(place: place, blend: blend)
                    }
                    continuation.resume()
                } catch {
                    self.stopSynchronously()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            controlQueue.async { [weak self] in
                self?.stopSynchronously()
                continuation.resume()
            }
        }
    }

    func setPlace(_ place: Place) {
        controlQueue.async { [weak self] in
            self?.setPlaceSynchronously(place)
        }
    }

    func setBlend(_ blend: Double) {
        controlQueue.async { [weak self] in
            self?.setBlendSynchronously(blend)
        }
    }

    private func startSynchronously(place: Place, blend: Double) throws {
        guard #available(macOS 14.2, *) else {
            throw CoreAudioFailure.unavailable("Overhear requires macOS 14.2 or later.")
        }

        let outputDeviceID = try readDefaultOutputDevice()
        let outputUID = try readCFString(outputDeviceID, selector: kAudioDevicePropertyDeviceUID)

        let ownProcessID = processObjectID(for: getpid())
        let excludedProcesses = ownProcessID == kAudioObjectUnknown ? [] : [ownProcessID]
        logger.notice(
            "Tap setup pid=\(getpid(), privacy: .public) processObject=\(ownProcessID, privacy: .public) exclusionCount=\(excludedProcesses.count, privacy: .public)"
        )
        // Configure the description explicitly, matching Apple's sample. Keeping
        // deviceUID nil makes this a true global mix; pairing a device UID with no
        // stream index can produce a successful status with an unknown tap ID.
        let description = CATapDescription()
        description.name = "Overhear System Mix"
        description.uuid = UUID()
        description.processes = excludedProcesses
        description.isExclusive = true
        description.isMixdown = true
        description.isMono = false
        description.isPrivate = true
        // Overhear supplies the only audible copy through its own output
        // engine. Conditional muting can briefly expose the original hardware
        // route between tap reads, producing comb-filtering against the
        // processed copy that is especially obvious on sustained music.
        description.muteBehavior = .muted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        try requireNoError(
            AudioHardwareCreateProcessTap(description, &newTapID),
            "Creating the system audio tap"
        )
        guard newTapID != kAudioObjectUnknown else {
            throw CoreAudioFailure.unavailable(
                "macOS did not create the audio tap. Check Screen & System Audio Recording permission, then retry."
            )
        }
        tapID = newTapID

        let tapUID = try readCFString(tapID, selector: kAudioTapPropertyUID)
        let aggregateUID = "com.chadwin.overhear.aggregate.\(UUID().uuidString)"
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Overhear Private Output",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            // Do not start the aggregate clock against an empty/not-yet-ready
            // tap after a quick toggle. Core Audio will hold AudioDeviceStart
            // until the first valid frame arrives from a tapped application.
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]

        var newAggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        try requireNoError(
            AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateDeviceID),
            "Creating the private aggregate output"
        )
        aggregateDeviceID = newAggregateDeviceID

        let tapFormat = try readASBD(tapID, selector: kAudioTapPropertyFormat)
        guard tapFormat.mFormatID == kAudioFormatLinearPCM,
              (tapFormat.mFormatFlags & kAudioFormatFlagIsFloat) != 0,
              tapFormat.mBitsPerChannel == 32 else {
            throw CoreAudioFailure.unavailable("The current output format is not supported yet.")
        }

        guard let newProcessor = OverhearDSPCreate(tapFormat.mSampleRate) else {
            throw CoreAudioFailure.unavailable("The environmental audio processor could not be created.")
        }
        processor = newProcessor
        OverhearDSPSetPlace(newProcessor, place.dspValue)
        OverhearDSPSetBlend(newProcessor, Float(blend))

        var newIOProcID: AudioDeviceIOProcID?
        let processorForCallback = newProcessor
        try requireNoError(
            AudioDeviceCreateIOProcIDWithBlock(
                &newIOProcID,
                aggregateDeviceID,
                nil
            ) { _, inputData, _, outputData, _ in
                let inputFrameCount = Self.frameCount(from: inputData)
                let outputFrameCount = Self.frameCount(from: outputData)
                let frameCount = min(inputFrameCount, outputFrameCount)
                OverhearDSPProcess(
                    processorForCallback,
                    inputData,
                    outputData,
                    frameCount
                )
            },
            "Installing the real-time audio processor"
        )
        ioProcID = newIOProcID

        guard let ioProcID else {
            throw CoreAudioFailure.unavailable("Core Audio did not return an I/O processor.")
        }
        try requireNoError(
            AudioDeviceStart(aggregateDeviceID, ioProcID),
            "Starting system-audio capture"
        )
        running = true
        logger.notice(
            "Environmental audio started with clock-synchronous aggregate output at \(tapFormat.mSampleRate, privacy: .public) Hz"
        )
    }

    private func setPlaceSynchronously(_ place: Place) {
        guard let processor else { return }
        OverhearDSPSetPlace(processor, place.dspValue)
    }

    private func setBlendSynchronously(_ blend: Double) {
        guard let processor else { return }
        OverhearDSPSetBlend(processor, Float(blend))
    }

    private func stopSynchronously() {
        let destroyedAudioObjects =
            aggregateDeviceID != kAudioObjectUnknown || tapID != kAudioObjectUnknown

        if aggregateDeviceID != kAudioObjectUnknown, let ioProcID {
            _ = AudioDeviceStop(aggregateDeviceID, ioProcID)
            _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        ioProcID = nil
        running = false

        if aggregateDeviceID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            if #available(macOS 14.2, *) {
                _ = AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        if destroyedAudioObjects {
            // Aggregate and tap teardown completes asynchronously inside
            // coreaudiod. Prevent an immediate restart from racing it.
            Thread.sleep(forTimeInterval: 0.12)
        }
        if let processor {
            OverhearDSPDestroy(processor)
            self.processor = nil
        }
        logger.notice("Environmental audio stopped")
    }

    private static func frameCount(from list: UnsafePointer<AudioBufferList>) -> UInt32 {
        guard list.pointee.mNumberBuffers > 0 else { return 0 }
        let first = list.pointee.mBuffers
        guard first.mData != nil, first.mNumberChannels > 0 else { return 0 }
        let bytesPerFrame = UInt32(MemoryLayout<Float>.size) * first.mNumberChannels
        return bytesPerFrame > 0 ? first.mDataByteSize / bytesPerFrame : 0
    }
}
