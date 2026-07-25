import FragmentaryDSP
import Testing

@Test("Zero presence is an exact transport bypass")
func zeroPresenceIsExactBypass() {
    let processor = FragmentaryDSPCreate(44_100)
    #expect(processor != nil)
    guard let processor else { return }
    defer { FragmentaryDSPDestroy(processor) }
    FragmentaryDSPSetBlend(processor, 0)

    let input: [Float] = [
        -0.95, 0.73,
        0.12, -0.31,
        0.88, -0.91,
        0, 0
    ]
    var output = Array(repeating: Float.zero, count: input.count)
    input.withUnsafeBufferPointer { inputBuffer in
        output.withUnsafeMutableBufferPointer { outputBuffer in
            FragmentaryDSPProcessInterleavedStereo(
                processor,
                inputBuffer.baseAddress,
                outputBuffer.baseAddress,
                UInt32(input.count / 2)
            )
        }
    }

    #expect(output == input)
}

@Test("All places produce finite, altered stereo audio")
func allPlacesProduceFiniteAudio() {
    let frameCount = 48_000
    let input = (0..<frameCount).flatMap { frame -> [Float] in
        let sample = sin(Float(frame) * 2 * .pi * 440 / 48_000) * 0.2
        return [sample, sample]
    }

    for place in [
        FragmentaryPlaceAfterClosing,
        FragmentaryPlaceOpenShutters,
        FragmentaryPlaceThinWall,
        FragmentaryPlaceHotelCorridor,
        FragmentaryPlaceCinemaAfterCredits,
        FragmentaryPlaceCarParkAtDawn,
        FragmentaryPlaceKitchenRadio1979
    ] {
        let processor = FragmentaryDSPCreate(48_000)
        #expect(processor != nil)
        guard let processor else { continue }
        defer { FragmentaryDSPDestroy(processor) }

        FragmentaryDSPSetPlace(processor, place)
        FragmentaryDSPSetBlend(processor, 1)
        var output = Array(repeating: Float.zero, count: input.count)
        input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                FragmentaryDSPProcessInterleavedStereo(
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

    let processor = FragmentaryDSPCreate(48_000)
    #expect(processor != nil)
    guard let processor else { return }
    defer { FragmentaryDSPDestroy(processor) }
    FragmentaryDSPSetPlace(processor, FragmentaryPlaceAfterClosing)
    FragmentaryDSPSetBlend(processor, 1)

    var output = Array(repeating: Float.zero, count: input.count)
    input.withUnsafeBufferPointer { inputBuffer in
        output.withUnsafeMutableBufferPointer { outputBuffer in
            FragmentaryDSPProcessInterleavedStereo(
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

@Test("Reflections remain quieter than the source transient")
func reflectionsDoNotBecomeDiscreteEchoes() {
    for place in [
        FragmentaryPlaceOpenShutters,
        FragmentaryPlaceHotelCorridor,
        FragmentaryPlaceCinemaAfterCredits,
        FragmentaryPlaceCarParkAtDawn
    ] {
        let processor = FragmentaryDSPCreate(48_000)
        #expect(processor != nil)
        guard let processor else { continue }
        defer { FragmentaryDSPDestroy(processor) }
        FragmentaryDSPSetPlace(processor, place)
        FragmentaryDSPSetBlend(processor, 1)

        let frameCount = 96_000
        var input = Array(repeating: Float.zero, count: frameCount * 2)
        input[0] = 0.7
        input[1] = 0.7
        var output = Array(repeating: Float.zero, count: input.count)
        input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                FragmentaryDSPProcessInterleavedStereo(
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
    let processor = FragmentaryDSPCreate(48_000)
    #expect(processor != nil)
    guard let processor else { return }
    defer { FragmentaryDSPDestroy(processor) }
    FragmentaryDSPSetBlend(processor, 0)

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
            FragmentaryDSPProcess(processor, &inputList, &outputList, 2)
        }
    }

    #expect(output[..<4].elementsEqual(input))
    #expect(output[4...].allSatisfy { $0 == 0 })
}
