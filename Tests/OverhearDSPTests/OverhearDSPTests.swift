import OverhearDSP
import Testing

private let allPlaces: [OverhearPlace] = [
    OverhearPlaceAfterClosing,
    OverhearPlaceCinemaAfterCredits,
    OverhearPlaceOpenShutters,
    OverhearPlaceThinWall,
    OverhearPlaceHotelCorridor,
    OverhearPlaceCarParkAtDawn,
    OverhearPlaceKitchenRadio1979
]

private func representativeMusic(frameCount: Int, sampleRate: Float) -> [Float] {
    let partials: [(frequency: Float, amplitude: Float)] = [
        (63, 0.060),
        (125, 0.052),
        (250, 0.045),
        (500, 0.038),
        (1_000, 0.032),
        (2_000, 0.026),
        (4_000, 0.020),
        (8_000, 0.014),
        (12_000, 0.009)
    ]
    return (0..<frameCount).flatMap { frame -> [Float] in
        let time = Float(frame) / sampleRate
        let left = partials.reduce(Float.zero) {
            $0 + sin(2 * .pi * $1.frequency * time) * $1.amplitude
        }
        let right = partials.reduce(Float.zero) {
            $0 + sin(2 * .pi * $1.frequency * time + 0.37) * $1.amplitude
        }
        return [left, right]
    }
}

private func rms(_ samples: ArraySlice<Float>) -> Float {
    sqrt(samples.reduce(Float.zero) { $0 + $1 * $1 } / Float(samples.count))
}

@Test("Zero presence is an exact transport bypass")
func zeroPresenceIsExactBypass() {
    let processor = OverhearDSPCreate(44_100)
    #expect(processor != nil)
    guard let processor else { return }
    defer { OverhearDSPDestroy(processor) }
    OverhearDSPSetBlend(processor, 0)

    let input: [Float] = [
        -0.95, 0.73,
        0.12, -0.31,
        0.88, -0.91,
        0, 0
    ]
    var output = Array(repeating: Float.zero, count: input.count)
    input.withUnsafeBufferPointer { inputBuffer in
        output.withUnsafeMutableBufferPointer { outputBuffer in
            OverhearDSPProcessInterleavedStereo(
                processor,
                inputBuffer.baseAddress,
                outputBuffer.baseAddress,
                UInt32(input.count / 2)
            )
        }
    }

    #expect(output == input)
}

@Test("Environmental processing avoids a large loudness drop")
func environmentalProcessingMaintainsLevel() {
    let sampleRate: Float = 48_000
    let frameCount = Int(sampleRate * 4)
    let measuredStart = Int(sampleRate * 2) * 2
    let input = representativeMusic(frameCount: frameCount, sampleRate: sampleRate)
    let inputLevel = rms(input[measuredStart...])

    for place in allPlaces {
        let processor = OverhearDSPCreate(Double(sampleRate))
        #expect(processor != nil)
        guard let processor else { continue }
        defer { OverhearDSPDestroy(processor) }
        OverhearDSPSetPlace(processor, place)
        OverhearDSPSetBlend(processor, 1)

        var output = Array(repeating: Float.zero, count: input.count)
        input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                OverhearDSPProcessInterleavedStereo(
                    processor,
                    inputBuffer.baseAddress,
                    outputBuffer.baseAddress,
                    UInt32(frameCount)
                )
            }
        }

        let levelRatio = rms(output[measuredStart...]) / inputLevel
        #expect(levelRatio > 0.60)
        #expect(levelRatio < 0.82)
    }
}

@Test("Partial Presence uses an energy-preserving crossfade")
func partialPresenceMaintainsLevel() {
    let sampleRate: Float = 48_000
    let frameCount = Int(sampleRate * 4)
    let measuredStart = Int(sampleRate * 2) * 2
    let input = representativeMusic(frameCount: frameCount, sampleRate: sampleRate)
    let inputLevel = rms(input[measuredStart...])

    for place in allPlaces {
        let processor = OverhearDSPCreate(Double(sampleRate))
        #expect(processor != nil)
        guard let processor else { continue }
        defer { OverhearDSPDestroy(processor) }
        OverhearDSPSetPlace(processor, place)
        OverhearDSPSetBlend(processor, 0.5)

        var output = Array(repeating: Float.zero, count: input.count)
        input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                OverhearDSPProcessInterleavedStereo(
                    processor,
                    inputBuffer.baseAddress,
                    outputBuffer.baseAddress,
                    UInt32(frameCount)
                )
            }
        }

        let levelRatio = rms(output[measuredStart...]) / inputLevel
        #expect(levelRatio > 0.70)
        #expect(levelRatio < 1.25)
    }
}

@Test("Full Presence retains a clean high-frequency core")
func fullPresenceRetainsSourceDetail() {
    let sampleRate: Float = 48_000
    let frameCount = Int(sampleRate * 3)
    let measuredStart = Int(sampleRate * 2) * 2
    let input = (0..<frameCount).flatMap { frame -> [Float] in
        let time = Float(frame) / sampleRate
        return [
            sin(2 * .pi * 10_000 * time) * 0.1,
            sin(2 * .pi * 10_000 * time + 0.41) * 0.1
        ]
    }
    let inputLevel = rms(input[measuredStart...])

    for place in allPlaces {
        let processor = OverhearDSPCreate(Double(sampleRate))
        #expect(processor != nil)
        guard let processor else { continue }
        defer { OverhearDSPDestroy(processor) }
        OverhearDSPSetPlace(processor, place)
        OverhearDSPSetBlend(processor, 1)

        var output = Array(repeating: Float.zero, count: input.count)
        input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                OverhearDSPProcessInterleavedStereo(
                    processor,
                    inputBuffer.baseAddress,
                    outputBuffer.baseAddress,
                    UInt32(frameCount)
                )
            }
        }

        #expect(rms(output[measuredStart...]) / inputLevel > 0.06)
    }
}

@Test("Through a kitchen radio does not introduce digital sample-hold artifacts")
func kitchenRadioAvoidsSampleHoldArtifacts() {
    let sampleRate: Float = 48_000
    let frameCount = Int(sampleRate * 2)
    let input = (0..<frameCount).flatMap { frame -> [Float] in
        let sample = sin(Float(frame) * 2 * .pi * 440 / sampleRate) * 0.2
        return [sample, sample]
    }

    let processor = OverhearDSPCreate(Double(sampleRate))
    #expect(processor != nil)
    guard let processor else { return }
    defer { OverhearDSPDestroy(processor) }
    OverhearDSPSetPlace(processor, OverhearPlaceKitchenRadio1979)
    OverhearDSPSetBlend(processor, 1)

    var output = Array(repeating: Float.zero, count: input.count)
    input.withUnsafeBufferPointer { inputBuffer in
        output.withUnsafeMutableBufferPointer { outputBuffer in
            OverhearDSPProcessInterleavedStereo(
                processor,
                inputBuffer.baseAddress,
                outputBuffer.baseAddress,
                UInt32(frameCount)
            )
        }
    }

    let settledLeft = stride(from: frameCount, to: output.count, by: 2).map { output[$0] }
    let repeatedFrames = zip(settledLeft, settledLeft.dropFirst()).count {
        abs($0 - $1) < 0.000_000_1
    }
    #expect(repeatedFrames < settledLeft.count / 100)
}

@Test("All places produce finite, altered stereo audio")
func allPlacesProduceFiniteAudio() {
    let frameCount = 48_000
    let input = (0..<frameCount).flatMap { frame -> [Float] in
        let sample = sin(Float(frame) * 2 * .pi * 440 / 48_000) * 0.2
        return [sample, sample]
    }

    for place in allPlaces {
        let processor = OverhearDSPCreate(48_000)
        #expect(processor != nil)
        guard let processor else { continue }
        defer { OverhearDSPDestroy(processor) }

        OverhearDSPSetPlace(processor, place)
        OverhearDSPSetBlend(processor, 1)
        var output = Array(repeating: Float.zero, count: input.count)
        input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                OverhearDSPProcessInterleavedStereo(
                    processor,
                    inputBuffer.baseAddress,
                    outputBuffer.baseAddress,
                    UInt32(frameCount)
                )
            }
        }

        #expect(output.allSatisfy { $0.isFinite })
        #expect(zip(input, output).contains { abs($0 - $1) > 0.001 })
    }
}

@Test("Loud material stays smooth instead of hard clipping")
func loudMaterialDoesNotHardClip() {
    let frameCount = 96_000
    let input = (0..<frameCount).flatMap { frame -> [Float] in
        let fundamental = sin(Float(frame) * 2 * .pi * 110 / 48_000) * 0.88
        let overtone = sin(Float(frame) * 2 * .pi * 880 / 48_000) * 0.24
        return [fundamental + overtone, fundamental - overtone]
    }

    for place in allPlaces {
        let processor = OverhearDSPCreate(48_000)
        #expect(processor != nil)
        guard let processor else { continue }
        defer { OverhearDSPDestroy(processor) }
        OverhearDSPSetPlace(processor, place)
        OverhearDSPSetBlend(processor, 1)

        var output = Array(repeating: Float.zero, count: input.count)
        input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                OverhearDSPProcessInterleavedStereo(
                    processor,
                    inputBuffer.baseAddress,
                    outputBuffer.baseAddress,
                    UInt32(frameCount)
                )
            }
        }

        let peak = output.map(abs).max() ?? 0
        let largestStep = zip(output.dropFirst(2), output).map { abs($0 - $1) }.max() ?? 0
        #expect(peak < 0.999)
        #expect(largestStep < 0.30)
    }
}

@Test("Reflections remain quieter than the source transient")
func reflectionsDoNotBecomeDiscreteEchoes() {
    for place in [
        OverhearPlaceOpenShutters,
        OverhearPlaceHotelCorridor,
        OverhearPlaceCinemaAfterCredits,
        OverhearPlaceCarParkAtDawn
    ] {
        let processor = OverhearDSPCreate(48_000)
        #expect(processor != nil)
        guard let processor else { continue }
        defer { OverhearDSPDestroy(processor) }
        OverhearDSPSetPlace(processor, place)
        OverhearDSPSetBlend(processor, 1)

        // Let the normal place-change smoothing settle so the source transient
        // and its later reflections are measured at the same output gain.
        let settlingFrameCount = 96_000
        let settlingInput = Array(repeating: Float.zero, count: settlingFrameCount * 2)
        var settlingOutput = settlingInput
        settlingInput.withUnsafeBufferPointer { inputBuffer in
            settlingOutput.withUnsafeMutableBufferPointer { outputBuffer in
                OverhearDSPProcessInterleavedStereo(
                    processor,
                    inputBuffer.baseAddress,
                    outputBuffer.baseAddress,
                    UInt32(settlingFrameCount)
                )
            }
        }

        let frameCount = 96_000
        var input = Array(repeating: Float.zero, count: frameCount * 2)
        input[0] = 0.7
        input[1] = 0.7
        var output = Array(repeating: Float.zero, count: input.count)
        input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                OverhearDSPProcessInterleavedStereo(
                    processor,
                    inputBuffer.baseAddress,
                    outputBuffer.baseAddress,
                    UInt32(frameCount)
                )
            }
        }

        let sourcePeak = output[..<(4_800 * 2)].map(abs).max() ?? 0
        let reflectionPeak = output[(4_800 * 2)...].map(abs).max() ?? 0
        #expect(reflectionPeak < sourcePeak)
    }
}

@Test("AudioBufferList processing clears an unwritten output tail")
func audioBufferListProcessingClearsOutputTail() {
    let processor = OverhearDSPCreate(48_000)
    #expect(processor != nil)
    guard let processor else { return }
    defer { OverhearDSPDestroy(processor) }
    OverhearDSPSetBlend(processor, 0)

    var input: [Float] = [0.2, -0.2, 0.4, -0.4]
    var output = Array(repeating: Float(1), count: 8)
    input.withUnsafeMutableBytes { inputBytes in
        var inputList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 2,
                mDataByteSize: UInt32(inputBytes.count),
                mData: inputBytes.baseAddress
            )
        )
        output.withUnsafeMutableBytes { outputBytes in
            var outputList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 2,
                    mDataByteSize: UInt32(outputBytes.count),
                    mData: outputBytes.baseAddress
                )
            )
            OverhearDSPProcess(processor, &inputList, &outputList, 2)
        }
    }

    #expect(output[..<4].elementsEqual(input))
    #expect(output[4...].allSatisfy { $0 == 0 })
}
