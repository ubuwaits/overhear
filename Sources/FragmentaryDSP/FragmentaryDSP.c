#include "FragmentaryDSP.h"

#include <math.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    float lowpassHz;
    float highpassHz;
    float width;
    float pan;
    float drive;
    float flutterDepth;
    float sourceMix;
    float directMix;
    float earlyMix;
    float windowMix;
    float lateMix;
    float outputGain;
} PlaceParameters;

#define REFLECTION_TAP_COUNT 8
#define WINDOW_TAP_COUNT 3
#define LATE_TAP_COUNT 8
#define AFTER_CLOSING_ROOM_LINE_COUNT 4

struct FragmentaryDSP {
    double sampleRate;
    _Atomic int place;
    _Atomic float targetBlend;
    int cachedPlace;
    PlaceParameters targetParameters;

    float blend;
    float lowpassHz;
    float highpassHz;
    float width;
    float pan;
    float drive;
    float flutterDepth;
    float sourceMix;
    float directMix;
    float earlyMix;
    float windowMix;
    float lateMix;
    float outputGain;

    float lowState[2];
    float lowStateSecond[2];
    float highState[2];
    float highInput[2];
    float coefficientLowpassHz;
    float coefficientHighpassHz;
    float lowpassCoefficient;
    float highpassCoefficient;
    uint64_t processedFrameCount;

    float *reflectionLeft;
    float *reflectionRight;
    uint32_t reflectionCapacity;
    uint32_t reflectionIndex;
    uint32_t reflectionTapFrames[REFLECTION_TAP_COUNT];
    uint32_t windowTapFrames[WINDOW_TAP_COUNT];
    uint32_t lateTapFrames[LATE_TAP_COUNT];

    float *afterClosingRoomLine[AFTER_CLOSING_ROOM_LINE_COUNT];
    uint32_t afterClosingRoomLineLength[AFTER_CLOSING_ROOM_LINE_COUNT];
    uint32_t afterClosingRoomLineIndex[AFTER_CLOSING_ROOM_LINE_COUNT];
    float afterClosingRoomDampingState[AFTER_CLOSING_ROOM_LINE_COUNT];
};

static float clampf(float value, float lower, float upper) {
    return fminf(fmaxf(value, lower), upper);
}

static PlaceParameters parametersForPlace(int place) {
    switch (place) {
        case FragmentaryPlaceHotelCorridor:
            return (PlaceParameters) {
                .lowpassHz = 1550.0f,
                .highpassHz = 165.0f,
                .width = 0.02f,
                .pan = 0.52f,
                .drive = 1.25f,
                .flutterDepth = 0.0f,
                .sourceMix = 0.16f,
                .directMix = 0.72f,
                .earlyMix = 0.24f,
                .windowMix = 0.0f,
                .lateMix = 0.08f,
                .outputGain = 1.59f
            };
        case FragmentaryPlaceCinemaAfterCredits:
            return (PlaceParameters) {
                .lowpassHz = 2700.0f,
                .highpassHz = 60.0f,
                .width = 0.48f,
                .pan = 0.0f,
                .drive = 1.05f,
                .flutterDepth = 0.0f,
                .sourceMix = 0.14f,
                .directMix = 0.28f,
                .earlyMix = 0.03f,
                .windowMix = 0.0f,
                .lateMix = 0.85f,
                .outputGain = 1.86f
            };
        case FragmentaryPlaceCarParkAtDawn:
            return (PlaceParameters) {
                .lowpassHz = 12500.0f,
                .highpassHz = 470.0f,
                .width = 0.05f,
                .pan = -0.28f,
                .drive = 1.28f,
                .flutterDepth = 0.0f,
                .sourceMix = 0.12f,
                .directMix = 0.30f,
                .earlyMix = 0.68f,
                .windowMix = 0.0f,
                .lateMix = 0.52f,
                .outputGain = 1.02f
            };
        case FragmentaryPlaceKitchenRadio1979:
            return (PlaceParameters) {
                .lowpassHz = 1950.0f,
                .highpassHz = 650.0f,
                .width = 0.0f,
                .pan = 0.46f,
                .drive = 3.40f,
                .flutterDepth = 0.08f,
                .sourceMix = 0.12f,
                .directMix = 0.98f,
                .earlyMix = 0.0f,
                .windowMix = 0.0f,
                .lateMix = 0.0f,
                .outputGain = 0.84f
            };
        case FragmentaryPlaceOpenShutters:
            return (PlaceParameters) {
                .lowpassHz = 4000.0f,
                .highpassHz = 410.0f,
                .width = 0.0f,
                .pan = -0.56f,
                .drive = 1.32f,
                .flutterDepth = 0.0f,
                .sourceMix = 0.14f,
                .directMix = 0.44f,
                .earlyMix = 0.03f,
                .windowMix = 0.88f,
                .lateMix = 0.14f,
                .outputGain = 1.76f
            };
        case FragmentaryPlaceThinWall:
            return (PlaceParameters) {
                .lowpassHz = 520.0f,
                .highpassHz = 92.0f,
                .width = 0.0f,
                .pan = 0.0f,
                .drive = 1.12f,
                .flutterDepth = 0.0f,
                .sourceMix = 0.08f,
                .directMix = 0.88f,
                .earlyMix = 0.16f,
                .windowMix = 0.0f,
                .lateMix = 0.04f,
                .outputGain = 1.23f
            };
        case FragmentaryPlaceAfterClosing:
        default:
            return (PlaceParameters) {
                .lowpassHz = 4800.0f,
                .highpassHz = 110.0f,
                .width = 0.12f,
                .pan = 0.0f,
                .drive = 1.04f,
                .flutterDepth = 0.0f,
                .sourceMix = 0.10f,
                .directMix = 0.22f,
                .earlyMix = 0.68f,
                .windowMix = 0.0f,
                .lateMix = 1.08f,
                .outputGain = 1.14f
            };
    }
}

static uint32_t framesForSeconds(double sampleRate, double seconds) {
    return (uint32_t)fmax(1.0, floor(sampleRate * seconds));
}

static inline uint32_t delayedIndex(uint32_t index, uint32_t capacity, uint32_t delay) {
    return index >= delay ? index - delay : capacity - (delay - index);
}

FragmentaryDSP *FragmentaryDSPCreate(double sampleRate) {
    if (sampleRate < 8000.0 || sampleRate > 384000.0) {
        return NULL;
    }

    FragmentaryDSP *dsp = calloc(1, sizeof(FragmentaryDSP));
    if (dsp == NULL) {
        return NULL;
    }

    dsp->sampleRate = sampleRate;
    atomic_init(&dsp->place, FragmentaryPlaceAfterClosing);
    atomic_init(&dsp->targetBlend, 1.0f);
    dsp->cachedPlace = FragmentaryPlaceAfterClosing;
    dsp->targetParameters = parametersForPlace(dsp->cachedPlace);

    static const double reflectionSeconds[REFLECTION_TAP_COUNT] = {
        0.071, 0.109, 0.151, 0.223, 0.317, 0.443, 0.619, 0.811
    };
    dsp->reflectionCapacity = framesForSeconds(sampleRate, 1.9);
    dsp->reflectionLeft = calloc(dsp->reflectionCapacity, sizeof(float));
    dsp->reflectionRight = calloc(dsp->reflectionCapacity, sizeof(float));
    if (dsp->reflectionLeft == NULL || dsp->reflectionRight == NULL) {
        FragmentaryDSPDestroy(dsp);
        return NULL;
    }
    for (int tap = 0; tap < REFLECTION_TAP_COUNT; tap++) {
        dsp->reflectionTapFrames[tap] = framesForSeconds(sampleRate, reflectionSeconds[tap]);
    }
    static const double windowSeconds[WINDOW_TAP_COUNT] = {
        0.023, 0.187, 0.347
    };
    for (int tap = 0; tap < WINDOW_TAP_COUNT; tap++) {
        dsp->windowTapFrames[tap] = framesForSeconds(sampleRate, windowSeconds[tap]);
    }
    static const double lateSeconds[LATE_TAP_COUNT] = {
        0.491, 0.637, 0.811, 0.997, 1.181, 1.377, 1.593, 1.817
    };
    for (int tap = 0; tap < LATE_TAP_COUNT; tap++) {
        dsp->lateTapFrames[tap] = framesForSeconds(sampleRate, lateSeconds[tap]);
    }
    static const double afterClosingRoomLineSeconds[AFTER_CLOSING_ROOM_LINE_COUNT] = {
        0.073, 0.089, 0.113, 0.131
    };
    for (int line = 0; line < AFTER_CLOSING_ROOM_LINE_COUNT; line++) {
        dsp->afterClosingRoomLineLength[line] =
            framesForSeconds(sampleRate, afterClosingRoomLineSeconds[line]);
        dsp->afterClosingRoomLine[line] =
            calloc(dsp->afterClosingRoomLineLength[line], sizeof(float));
        if (dsp->afterClosingRoomLine[line] == NULL) {
            FragmentaryDSPDestroy(dsp);
            return NULL;
        }
    }

    PlaceParameters initial = dsp->targetParameters;
    dsp->blend = 1.0f;
    dsp->lowpassHz = initial.lowpassHz;
    dsp->highpassHz = initial.highpassHz;
    dsp->width = initial.width;
    dsp->pan = initial.pan;
    dsp->drive = initial.drive;
    dsp->flutterDepth = initial.flutterDepth;
    dsp->sourceMix = initial.sourceMix;
    dsp->directMix = initial.directMix;
    dsp->earlyMix = initial.earlyMix;
    dsp->windowMix = initial.windowMix;
    dsp->lateMix = initial.lateMix;
    dsp->outputGain = initial.outputGain;
    return dsp;
}

void FragmentaryDSPDestroy(FragmentaryDSP *dsp) {
    if (dsp == NULL) {
        return;
    }
    free(dsp->reflectionLeft);
    free(dsp->reflectionRight);
    for (int line = 0; line < AFTER_CLOSING_ROOM_LINE_COUNT; line++) {
        free(dsp->afterClosingRoomLine[line]);
    }
    free(dsp);
}

void FragmentaryDSPSetPlace(FragmentaryDSP *dsp, FragmentaryPlace place) {
    if (dsp != NULL) {
        atomic_store_explicit(&dsp->place, (int)place, memory_order_relaxed);
    }
}

void FragmentaryDSPSetBlend(FragmentaryDSP *dsp, float blend) {
    if (dsp != NULL) {
        atomic_store_explicit(&dsp->targetBlend, clampf(blend, 0.0f, 1.0f), memory_order_relaxed);
    }
}

static inline float onePoleLowpass(float input, float coefficient, float *state) {
    float output = (1.0f - coefficient) * input + coefficient * *state;
    *state = output;
    return output;
}

static inline float onePoleHighpass(
    float input,
    float coefficient,
    float *state,
    float *previousInput
) {
    float output = coefficient * (*state + input - *previousInput);
    *state = output;
    *previousInput = input;
    return output;
}

static float softLimit(float input) {
    const float threshold = 0.90f;
    const float knee = 0.10f;
    float magnitude = fabsf(input);
    if (magnitude <= threshold) {
        return input;
    }
    float limited = threshold + knee * (1.0f - expf(-(magnitude - threshold) / knee));
    return copysignf(limited, input);
}

static void processFrame(FragmentaryDSP *dsp, float left, float right, float *outLeft, float *outRight) {
    float targetBlend = atomic_load_explicit(&dsp->targetBlend, memory_order_relaxed);
    if (targetBlend <= 0.0001f) {
        // Presence at zero is a bit-transparent diagnostic path through the
        // same capture and clock-synchronous speaker callback.
        dsp->blend = 0.0f;
        *outLeft = left;
        *outRight = right;
        return;
    }

    int activePlace = atomic_load_explicit(&dsp->place, memory_order_relaxed);
    if (activePlace != dsp->cachedPlace) {
        dsp->cachedPlace = activePlace;
        dsp->targetParameters = parametersForPlace(activePlace);
    }
    PlaceParameters target = dsp->targetParameters;
    const float smoothing = 0.00085f;
    dsp->blend += (targetBlend - dsp->blend) * 0.0015f;
    dsp->lowpassHz += (target.lowpassHz - dsp->lowpassHz) * smoothing;
    dsp->highpassHz += (target.highpassHz - dsp->highpassHz) * smoothing;
    dsp->width += (target.width - dsp->width) * smoothing;
    dsp->pan += (target.pan - dsp->pan) * smoothing;
    dsp->drive += (target.drive - dsp->drive) * smoothing;
    dsp->flutterDepth += (target.flutterDepth - dsp->flutterDepth) * smoothing;
    dsp->sourceMix += (target.sourceMix - dsp->sourceMix) * smoothing;
    dsp->directMix += (target.directMix - dsp->directMix) * smoothing;
    dsp->earlyMix += (target.earlyMix - dsp->earlyMix) * smoothing;
    dsp->windowMix += (target.windowMix - dsp->windowMix) * smoothing;
    dsp->lateMix += (target.lateMix - dsp->lateMix) * smoothing;
    dsp->outputGain += (target.outputGain - dsp->outputGain) * smoothing;

    const float mid = (left + right) * 0.5f;
    float source[2] = {
        mid + (left - mid) * dsp->width,
        mid + (right - mid) * dsp->width
    };
    if (fabsf(dsp->pan) > 0.0001f) {
        if (dsp->pan > 0.0f) {
            source[0] *= 1.0f - dsp->pan * 0.72f;
        } else {
            source[1] *= 1.0f + dsp->pan * 0.72f;
        }
    }
    float dry[2] = { left, right };
    float filtered[2];
    // Recalculate only while cutoff smoothing changes the actual float value.
    // This preserves the exact filter math without steady-state expf/divisions.
    if (dsp->coefficientLowpassHz != dsp->lowpassHz) {
        dsp->coefficientLowpassHz = dsp->lowpassHz;
        dsp->lowpassCoefficient = expf(
            -2.0f * (float)M_PI * dsp->lowpassHz / (float)dsp->sampleRate
        );
    }
    if (dsp->coefficientHighpassHz != dsp->highpassHz) {
        dsp->coefficientHighpassHz = dsp->highpassHz;
        float rc = 1.0f / (2.0f * (float)M_PI * dsp->highpassHz);
        float dt = 1.0f / (float)dsp->sampleRate;
        dsp->highpassCoefficient = rc / (rc + dt);
    }
    float lowpassCoefficient = dsp->lowpassCoefficient;
    float highpassCoefficient = dsp->highpassCoefficient;

    for (int channel = 0; channel < 2; channel++) {
        float shaped = onePoleLowpass(
            source[channel],
            lowpassCoefficient,
            &dsp->lowState[channel]
        );
        shaped = onePoleLowpass(
            shaped,
            lowpassCoefficient,
            &dsp->lowStateSecond[channel]
        );
        shaped = onePoleHighpass(
            shaped,
            highpassCoefficient,
            &dsp->highState[channel],
            &dsp->highInput[channel]
        );
        filtered[channel] = tanhf(shaped * dsp->drive);
    }
    if (dsp->flutterDepth > 0.0001f) {
        float time = (float)((double)dsp->processedFrameCount / dsp->sampleRate);
        float flutter = 1.0f
            - dsp->flutterDepth * 0.50f
            + sinf(2.0f * (float)M_PI * 0.73f * time) * dsp->flutterDepth * 0.34f
            + sinf(2.0f * (float)M_PI * 6.10f * time) * dsp->flutterDepth * 0.16f;
        filtered[0] *= flutter;
        filtered[1] *= flutter;
    }
    dsp->processedFrameCount++;

    uint32_t reflectionWriteIndex = dsp->reflectionIndex;
    dsp->reflectionLeft[reflectionWriteIndex] = filtered[0];
    dsp->reflectionRight[reflectionWriteIndex] = filtered[1];

    static const float reflectionGain[REFLECTION_TAP_COUNT] = {
        0.27f, 0.22f, 0.18f, 0.145f, 0.115f, 0.09f, 0.07f, 0.05f
    };
    float reflected[2] = { 0.0f, 0.0f };
    for (int tap = 0; tap < REFLECTION_TAP_COUNT; tap++) {
        uint32_t index = delayedIndex(
            reflectionWriteIndex,
            dsp->reflectionCapacity,
            dsp->reflectionTapFrames[tap]
        );
        // Alternate walls between the same and opposite stereo channels.
        if ((tap & 1) == 0) {
            reflected[0] += dsp->reflectionLeft[index] * reflectionGain[tap];
            reflected[1] += dsp->reflectionRight[index] * reflectionGain[tap];
        } else {
            reflected[0] += dsp->reflectionRight[index] * reflectionGain[tap];
            reflected[1] += dsp->reflectionLeft[index] * reflectionGain[tap];
        }
    }

    static const float windowGain[WINDOW_TAP_COUNT] = {
        0.24f, 0.20f, 0.13f
    };
    float windowReturn[2] = { 0.0f, 0.0f };
    for (int tap = 0; tap < WINDOW_TAP_COUNT; tap++) {
        uint32_t index = delayedIndex(
            reflectionWriteIndex,
            dsp->reflectionCapacity,
            dsp->windowTapFrames[tap]
        );
        // The nearby window reveal is centered; the later returns spread
        // asymmetrically from opposing stone façades.
        float delayedMid = (dsp->reflectionLeft[index] + dsp->reflectionRight[index]) * 0.5f;
        float pan = tap == 1 ? 0.72f : (tap == 2 ? 0.28f : 0.5f);
        windowReturn[0] += delayedMid * windowGain[tap] * (1.0f - pan) * 2.0f;
        windowReturn[1] += delayedMid * windowGain[tap] * pan * 2.0f;
    }

    static const float lateGain[LATE_TAP_COUNT] = {
        0.15f, 0.13f, 0.11f, 0.095f, 0.08f, 0.067f, 0.055f, 0.045f
    };
    float late[2] = { 0.0f, 0.0f };
    for (int tap = 0; tap < LATE_TAP_COUNT; tap++) {
        uint32_t index = delayedIndex(
            reflectionWriteIndex,
            dsp->reflectionCapacity,
            dsp->lateTapFrames[tap]
        );
        if ((tap & 1) == 0) {
            late[0] += dsp->reflectionLeft[index] * lateGain[tap];
            late[1] += dsp->reflectionRight[index] * lateGain[tap];
        } else {
            late[0] += dsp->reflectionRight[index] * lateGain[tap];
            late[1] += dsp->reflectionLeft[index] * lateGain[tap];
        }
    }
    dsp->reflectionIndex++;
    if (dsp->reflectionIndex == dsp->reflectionCapacity) {
        dsp->reflectionIndex = 0;
    }

    float roomOutput[AFTER_CLOSING_ROOM_LINE_COUNT];
    for (int line = 0; line < AFTER_CLOSING_ROOM_LINE_COUNT; line++) {
        roomOutput[line] =
            dsp->afterClosingRoomLine[line][dsp->afterClosingRoomLineIndex[line]];
    }
    const float afterClosingDamping = 0.68f;
    float roomDamped[AFTER_CLOSING_ROOM_LINE_COUNT];
    for (int line = 0; line < AFTER_CLOSING_ROOM_LINE_COUNT; line++) {
        roomDamped[line] =
            roomOutput[line] * (1.0f - afterClosingDamping)
            + dsp->afterClosingRoomDampingState[line] * afterClosingDamping;
        dsp->afterClosingRoomDampingState[line] = roomDamped[line];
    }
    float roomMixed[AFTER_CLOSING_ROOM_LINE_COUNT] = {
        (roomDamped[0] + roomDamped[1] + roomDamped[2] + roomDamped[3]) * 0.5f,
        (roomDamped[0] - roomDamped[1] + roomDamped[2] - roomDamped[3]) * 0.5f,
        (roomDamped[0] + roomDamped[1] - roomDamped[2] - roomDamped[3]) * 0.5f,
        (roomDamped[0] - roomDamped[1] - roomDamped[2] + roomDamped[3]) * 0.5f
    };
    float roomInput[AFTER_CLOSING_ROOM_LINE_COUNT] = {
        filtered[0], filtered[1], filtered[0], -filtered[1]
    };
    const float afterClosingFeedback = 0.82f;
    for (int line = 0; line < AFTER_CLOSING_ROOM_LINE_COUNT; line++) {
        dsp->afterClosingRoomLine[line][dsp->afterClosingRoomLineIndex[line]] =
            roomInput[line] * 0.32f + roomMixed[line] * afterClosingFeedback;
        dsp->afterClosingRoomLineIndex[line]++;
        if (
            dsp->afterClosingRoomLineIndex[line]
                == dsp->afterClosingRoomLineLength[line]
        ) {
            dsp->afterClosingRoomLineIndex[line] = 0;
        }
    }
    float afterClosingLate[2] = {
        (roomOutput[0] + roomOutput[2]) * 0.5f,
        (roomOutput[1] + roomOutput[3]) * 0.5f
    };
    float *selectedLate = (
        activePlace == FragmentaryPlaceAfterClosing
        || activePlace == FragmentaryPlaceCinemaAfterCredits
    )
        ? afterClosingLate
        : late;

    // Preserve a quiet, unfiltered stereo core while the environmental bus
    // carries all distance filtering, saturation, reflections, and reverb.
    // sourceMix replaces part of the former filtered direct component, so the
    // room balance and total direct weight remain stable.
    float filteredDirectMix = fmaxf(dsp->directMix - dsp->sourceMix, 0.0f);
    float wet[2] = {
        dry[0] * dsp->sourceMix
            + filtered[0] * filteredDirectMix
            + reflected[0] * dsp->earlyMix
            + windowReturn[0] * dsp->windowMix
            + selectedLate[0] * dsp->lateMix,
        dry[1] * dsp->sourceMix
            + filtered[1] * filteredDirectMix
            + reflected[1] * dsp->earlyMix
            + windowReturn[1] * dsp->windowMix
            + selectedLate[1] * dsp->lateMix
    };

    // Equal-power Presence avoids the loss of energy caused by a linear
    // crossfade. Makeup gain belongs only to the environmental path.
    float blendAngle = dsp->blend * (float)M_PI_2;
    float dryGain = cosf(blendAngle);
    float wetGain = sinf(blendAngle) * dsp->outputGain;
    *outLeft = softLimit(dry[0] * dryGain + wet[0] * wetGain);
    *outRight = softLimit(dry[1] * dryGain + wet[1] * wetGain);
}

void FragmentaryDSPProcessInterleavedStereo(
    FragmentaryDSP *dsp,
    const float *input,
    float *output,
    uint32_t frameCount
) {
    if (dsp == NULL || input == NULL || output == NULL) {
        return;
    }
    for (uint32_t frame = 0; frame < frameCount; frame++) {
        processFrame(
            dsp,
            input[frame * 2],
            input[frame * 2 + 1],
            &output[frame * 2],
            &output[frame * 2 + 1]
        );
    }
}

#ifdef __APPLE__
static bool readStereoFrame(const AudioBufferList *list, uint32_t frame, float *left, float *right) {
    if (list == NULL || list->mNumberBuffers == 0) {
        return false;
    }

    const AudioBuffer *first = &list->mBuffers[0];
    if (first->mData == NULL) {
        return false;
    }

    if (first->mNumberChannels >= 2) {
        const float *samples = first->mData;
        *left = samples[frame * first->mNumberChannels];
        *right = samples[frame * first->mNumberChannels + 1];
        return true;
    }

    if (list->mNumberBuffers >= 2 && list->mBuffers[1].mData != NULL) {
        const float *leftSamples = first->mData;
        const float *rightSamples = list->mBuffers[1].mData;
        *left = leftSamples[frame];
        *right = rightSamples[frame];
        return true;
    }

    const float *samples = first->mData;
    *left = samples[frame];
    *right = samples[frame];
    return true;
}

static bool writeStereoFrame(AudioBufferList *list, uint32_t frame, float left, float right) {
    if (list == NULL || list->mNumberBuffers == 0) {
        return false;
    }

    AudioBuffer *first = &list->mBuffers[0];
    if (first->mData == NULL) {
        return false;
    }

    if (first->mNumberChannels >= 2) {
        float *samples = first->mData;
        samples[frame * first->mNumberChannels] = left;
        samples[frame * first->mNumberChannels + 1] = right;
        return true;
    }

    if (list->mNumberBuffers >= 2 && list->mBuffers[1].mData != NULL) {
        float *leftSamples = first->mData;
        float *rightSamples = list->mBuffers[1].mData;
        leftSamples[frame] = left;
        rightSamples[frame] = right;
        return true;
    }

    float *samples = first->mData;
    samples[frame] = (left + right) * 0.5f;
    return true;
}

static void clearOutput(AudioBufferList *output) {
    if (output == NULL) {
        return;
    }
    for (uint32_t buffer = 0; buffer < output->mNumberBuffers; buffer++) {
        AudioBuffer *audioBuffer = &output->mBuffers[buffer];
        if (audioBuffer->mData != NULL) {
            memset(audioBuffer->mData, 0, audioBuffer->mDataByteSize);
        }
    }
}

void FragmentaryDSPProcess(
    FragmentaryDSP *dsp,
    const AudioBufferList *input,
    AudioBufferList *output,
    uint32_t frameCount
) {
    if (dsp == NULL || input == NULL || output == NULL) {
        return;
    }

    // The aggregate input and hardware output normally have equal frame
    // counts. Clear first so a short input buffer can never leave stale data
    // in the unwritten output tail.
    clearOutput(output);
    for (uint32_t frame = 0; frame < frameCount; frame++) {
        float left = 0.0f;
        float right = 0.0f;
        if (!readStereoFrame(input, frame, &left, &right)) {
            break;
        }
        float outLeft = 0.0f;
        float outRight = 0.0f;
        processFrame(dsp, left, right, &outLeft, &outRight);
        if (!writeStereoFrame(output, frame, outLeft, outRight)) {
            break;
        }
    }
}
#endif
