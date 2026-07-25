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
    float drive;
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

    float blend;
    float lowpassHz;
    float highpassHz;
    float width;
    float drive;
    float directMix;
    float earlyMix;
    float windowMix;
    float lateMix;
    float outputGain;

    float lowState[2];
    float lowStateSecond[2];
    float highState[2];
    float highInput[2];

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

    float *ringLeft;
    float *ringRight;
    uint64_t ringCapacity;
    _Atomic uint64_t ringWriteFrame;
    _Atomic uint64_t ringReadFrame;
    _Atomic uint64_t underrunCount;
    _Atomic uint64_t overflowCount;

    bool outputPrimed;
    uint32_t startupMuteRemaining;
    uint32_t startupFadeRemaining;
    uint32_t startupFadeLength;
};

static float clampf(float value, float lower, float upper) {
    return fminf(fmaxf(value, lower), upper);
}

static PlaceParameters parametersForPlace(int place) {
    switch (place) {
        case FragmentaryPlaceHotelCorridor:
            return (PlaceParameters) {
                .lowpassHz = 1550.0f,
                .highpassHz = 105.0f,
                .width = 0.01f,
                .drive = 1.10f,
                .directMix = 0.70f,
                .earlyMix = 0.18f,
                .windowMix = 0.0f,
                .lateMix = 0.12f,
                .outputGain = 0.54f
            };
        case FragmentaryPlaceCinemaAfterCredits:
            return (PlaceParameters) {
                .lowpassHz = 3900.0f,
                .highpassHz = 78.0f,
                .width = 0.30f,
                .drive = 1.02f,
                .directMix = 0.42f,
                .earlyMix = 0.05f,
                .windowMix = 0.0f,
                .lateMix = 0.42f,
                .outputGain = 0.57f
            };
        case FragmentaryPlaceCarParkAtDawn:
            return (PlaceParameters) {
                .lowpassHz = 8200.0f,
                .highpassHz = 175.0f,
                .width = 0.18f,
                .drive = 1.03f,
                .directMix = 0.52f,
                .earlyMix = 0.28f,
                .windowMix = 0.0f,
                .lateMix = 0.32f,
                .outputGain = 0.58f
            };
        case FragmentaryPlaceKitchenRadio1979:
            return (PlaceParameters) {
                .lowpassHz = 3300.0f,
                .highpassHz = 320.0f,
                .width = 0.0f,
                .drive = 1.62f,
                .directMix = 0.98f,
                .earlyMix = 0.07f,
                .windowMix = 0.0f,
                .lateMix = 0.02f,
                .outputGain = 0.61f
            };
        case FragmentaryPlaceOpenShutters:
            return (PlaceParameters) {
                .lowpassHz = 6500.0f,
                .highpassHz = 135.0f,
                .width = 0.06f,
                .drive = 1.01f,
                .directMix = 0.72f,
                .earlyMix = 0.06f,
                .windowMix = 0.32f,
                .lateMix = 0.16f,
                .outputGain = 0.62f
            };
        case FragmentaryPlaceThinWall:
            return (PlaceParameters) {
                .lowpassHz = 520.0f,
                .highpassHz = 92.0f,
                .width = 0.0f,
                .drive = 1.12f,
                .directMix = 0.88f,
                .earlyMix = 0.16f,
                .windowMix = 0.0f,
                .lateMix = 0.04f,
                .outputGain = 0.44f
            };
        case FragmentaryPlaceAfterClosing:
        default:
            return (PlaceParameters) {
                .lowpassHz = 4800.0f,
                .highpassHz = 110.0f,
                .width = 0.12f,
                .drive = 1.04f,
                .directMix = 0.22f,
                .earlyMix = 0.68f,
                .windowMix = 0.0f,
                .lateMix = 1.08f,
                .outputGain = 0.55f
            };
    }
}

static uint32_t framesForSeconds(double sampleRate, double seconds) {
    return (uint32_t)fmax(1.0, floor(sampleRate * seconds));
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
    atomic_init(&dsp->targetBlend, 0.72f);
    atomic_init(&dsp->ringWriteFrame, 0);
    atomic_init(&dsp->ringReadFrame, 0);
    atomic_init(&dsp->underrunCount, 0);
    atomic_init(&dsp->overflowCount, 0);

    dsp->ringCapacity = framesForSeconds(sampleRate, 2.0);
    dsp->ringLeft = calloc(dsp->ringCapacity, sizeof(float));
    dsp->ringRight = calloc(dsp->ringCapacity, sizeof(float));
    if (dsp->ringLeft == NULL || dsp->ringRight == NULL) {
        FragmentaryDSPDestroy(dsp);
        return NULL;
    }

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

    dsp->startupMuteRemaining = framesForSeconds(sampleRate, 0.15);
    dsp->startupFadeLength = framesForSeconds(sampleRate, 0.03);
    dsp->startupFadeRemaining = dsp->startupFadeLength;

    PlaceParameters initial = parametersForPlace(FragmentaryPlaceAfterClosing);
    dsp->blend = 0.72f;
    dsp->lowpassHz = initial.lowpassHz;
    dsp->highpassHz = initial.highpassHz;
    dsp->width = initial.width;
    dsp->drive = initial.drive;
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
    free(dsp->ringLeft);
    free(dsp->ringRight);
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

void FragmentaryDSPReset(FragmentaryDSP *dsp) {
    if (dsp == NULL) {
        return;
    }
    memset(dsp->lowState, 0, sizeof(dsp->lowState));
    memset(dsp->lowStateSecond, 0, sizeof(dsp->lowStateSecond));
    memset(dsp->highState, 0, sizeof(dsp->highState));
    memset(dsp->highInput, 0, sizeof(dsp->highInput));
    if (dsp->reflectionLeft != NULL && dsp->reflectionRight != NULL) {
        memset(dsp->reflectionLeft, 0, dsp->reflectionCapacity * sizeof(float));
        memset(dsp->reflectionRight, 0, dsp->reflectionCapacity * sizeof(float));
    }
    dsp->reflectionIndex = 0;
    for (int line = 0; line < AFTER_CLOSING_ROOM_LINE_COUNT; line++) {
        if (dsp->afterClosingRoomLine[line] != NULL) {
            memset(
                dsp->afterClosingRoomLine[line],
                0,
                dsp->afterClosingRoomLineLength[line] * sizeof(float)
            );
        }
        dsp->afterClosingRoomLineIndex[line] = 0;
        dsp->afterClosingRoomDampingState[line] = 0.0f;
    }
    if (dsp->ringLeft != NULL && dsp->ringRight != NULL) {
        memset(dsp->ringLeft, 0, dsp->ringCapacity * sizeof(float));
        memset(dsp->ringRight, 0, dsp->ringCapacity * sizeof(float));
    }
    atomic_store_explicit(&dsp->ringWriteFrame, 0, memory_order_relaxed);
    atomic_store_explicit(&dsp->ringReadFrame, 0, memory_order_relaxed);
    atomic_store_explicit(&dsp->underrunCount, 0, memory_order_relaxed);
    atomic_store_explicit(&dsp->overflowCount, 0, memory_order_relaxed);
    dsp->outputPrimed = false;
    dsp->startupMuteRemaining = framesForSeconds(dsp->sampleRate, 0.15);
    dsp->startupFadeRemaining = dsp->startupFadeLength;
}

static float lowpass(FragmentaryDSP *dsp, int channel, float input, float cutoff) {
    float coefficient = expf(-2.0f * (float)M_PI * cutoff / (float)dsp->sampleRate);
    float output = (1.0f - coefficient) * input + coefficient * dsp->lowState[channel];
    dsp->lowState[channel] = output;
    return output;
}

static float lowpassSecond(FragmentaryDSP *dsp, int channel, float input, float cutoff) {
    float coefficient = expf(-2.0f * (float)M_PI * cutoff / (float)dsp->sampleRate);
    float output = (1.0f - coefficient) * input + coefficient * dsp->lowStateSecond[channel];
    dsp->lowStateSecond[channel] = output;
    return output;
}

static float highpass(FragmentaryDSP *dsp, int channel, float input, float cutoff) {
    float dt = 1.0f / (float)dsp->sampleRate;
    float rc = 1.0f / (2.0f * (float)M_PI * cutoff);
    float coefficient = rc / (rc + dt);
    float output = coefficient * (dsp->highState[channel] + input - dsp->highInput[channel]);
    dsp->highState[channel] = output;
    dsp->highInput[channel] = input;
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
        // same capture, ring buffer, and speaker engine.
        dsp->blend = 0.0f;
        *outLeft = left;
        *outRight = right;
        return;
    }

    int activePlace = atomic_load_explicit(&dsp->place, memory_order_relaxed);
    PlaceParameters target = parametersForPlace(activePlace);
    const float smoothing = 0.00085f;
    dsp->blend += (targetBlend - dsp->blend) * 0.0015f;
    dsp->lowpassHz += (target.lowpassHz - dsp->lowpassHz) * smoothing;
    dsp->highpassHz += (target.highpassHz - dsp->highpassHz) * smoothing;
    dsp->width += (target.width - dsp->width) * smoothing;
    dsp->drive += (target.drive - dsp->drive) * smoothing;
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
    float dry[2] = { left, right };
    float filtered[2];

    for (int channel = 0; channel < 2; channel++) {
        float shaped = lowpass(dsp, channel, source[channel], dsp->lowpassHz);
        shaped = lowpassSecond(dsp, channel, shaped, dsp->lowpassHz);
        shaped = highpass(dsp, channel, shaped, dsp->highpassHz);
        filtered[channel] = tanhf(shaped * dsp->drive);
    }

    dsp->reflectionLeft[dsp->reflectionIndex] = filtered[0];
    dsp->reflectionRight[dsp->reflectionIndex] = filtered[1];

    static const float reflectionGain[REFLECTION_TAP_COUNT] = {
        0.27f, 0.22f, 0.18f, 0.145f, 0.115f, 0.09f, 0.07f, 0.05f
    };
    float reflected[2] = { 0.0f, 0.0f };
    for (int tap = 0; tap < REFLECTION_TAP_COUNT; tap++) {
        uint32_t delay = dsp->reflectionTapFrames[tap];
        uint32_t index = (dsp->reflectionIndex + dsp->reflectionCapacity - delay)
            % dsp->reflectionCapacity;
        // Alternate walls between the same and opposite stereo channels.
        if ((tap & 1) == 0) {
            reflected[0] += dsp->reflectionLeft[index] * reflectionGain[tap];
            reflected[1] += dsp->reflectionRight[index] * reflectionGain[tap];
        } else {
            reflected[0] += dsp->reflectionRight[index] * reflectionGain[tap];
            reflected[1] += dsp->reflectionLeft[index] * reflectionGain[tap];
        }
    }
    dsp->reflectionIndex = (dsp->reflectionIndex + 1) % dsp->reflectionCapacity;

    static const float windowGain[WINDOW_TAP_COUNT] = {
        0.24f, 0.20f, 0.13f
    };
    float windowReturn[2] = { 0.0f, 0.0f };
    for (int tap = 0; tap < WINDOW_TAP_COUNT; tap++) {
        uint32_t delay = dsp->windowTapFrames[tap];
        uint32_t index = (dsp->reflectionIndex + dsp->reflectionCapacity - 1 - delay)
            % dsp->reflectionCapacity;
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
        uint32_t delay = dsp->lateTapFrames[tap];
        uint32_t index = (dsp->reflectionIndex + dsp->reflectionCapacity - 1 - delay)
            % dsp->reflectionCapacity;
        if ((tap & 1) == 0) {
            late[0] += dsp->reflectionLeft[index] * lateGain[tap];
            late[1] += dsp->reflectionRight[index] * lateGain[tap];
        } else {
            late[0] += dsp->reflectionRight[index] * lateGain[tap];
            late[1] += dsp->reflectionLeft[index] * lateGain[tap];
        }
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
        dsp->afterClosingRoomLineIndex[line] =
            (dsp->afterClosingRoomLineIndex[line] + 1)
            % dsp->afterClosingRoomLineLength[line];
    }
    float afterClosingLate[2] = {
        (roomOutput[0] + roomOutput[2]) * 0.5f,
        (roomOutput[1] + roomOutput[3]) * 0.5f
    };
    float *selectedLate = activePlace == FragmentaryPlaceAfterClosing
        ? afterClosingLate
        : late;

    float wet[2] = {
        filtered[0] * dsp->directMix
            + reflected[0] * dsp->earlyMix
            + windowReturn[0] * dsp->windowMix
            + selectedLate[0] * dsp->lateMix,
        filtered[1] * dsp->directMix
            + reflected[1] * dsp->earlyMix
            + windowReturn[1] * dsp->windowMix
            + selectedLate[1] * dsp->lateMix
    };

    // Fade both coloration and distance attenuation with Presence.
    float gain = 1.0f + (dsp->outputGain - 1.0f) * dsp->blend;
    *outLeft = softLimit((dry[0] * (1.0f - dsp->blend) + wet[0] * dsp->blend) * gain);
    *outRight = softLimit((dry[1] * (1.0f - dsp->blend) + wet[1] * dsp->blend) * gain);
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

void FragmentaryDSPProcess(
    FragmentaryDSP *dsp,
    const AudioBufferList *input,
    AudioBufferList *output,
    uint32_t frameCount
) {
    if (dsp == NULL || input == NULL || output == NULL) {
        return;
    }

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

void FragmentaryDSPPush(
    FragmentaryDSP *dsp,
    const AudioBufferList *input,
    uint32_t frameCount
) {
    if (dsp == NULL || input == NULL || frameCount == 0) {
        return;
    }

    uint64_t writeFrame = atomic_load_explicit(&dsp->ringWriteFrame, memory_order_relaxed);
    uint64_t readFrame = atomic_load_explicit(&dsp->ringReadFrame, memory_order_acquire);
    uint64_t occupied = writeFrame - readFrame;
    uint64_t writable = occupied < dsp->ringCapacity ? dsp->ringCapacity - occupied : 0;
    uint32_t framesToWrite = (uint32_t)fmin((double)frameCount, (double)writable);

    for (uint32_t frame = 0; frame < framesToWrite; frame++) {
        float left = 0.0f;
        float right = 0.0f;
        if (!readStereoFrame(input, frame, &left, &right)) {
            framesToWrite = frame;
            break;
        }
        float processedLeft = 0.0f;
        float processedRight = 0.0f;
        processFrame(dsp, left, right, &processedLeft, &processedRight);
        uint64_t index = (writeFrame + frame) % dsp->ringCapacity;
        dsp->ringLeft[index] = processedLeft;
        dsp->ringRight[index] = processedRight;
    }

    if (framesToWrite < frameCount) {
        atomic_fetch_add_explicit(&dsp->overflowCount, 1, memory_order_relaxed);
    }
    atomic_store_explicit(
        &dsp->ringWriteFrame,
        writeFrame + framesToWrite,
        memory_order_release
    );
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

void FragmentaryDSPRender(
    FragmentaryDSP *dsp,
    AudioBufferList *output,
    uint32_t frameCount
) {
    if (dsp == NULL || output == NULL || frameCount == 0) {
        clearOutput(output);
        return;
    }

    uint64_t readFrame = atomic_load_explicit(&dsp->ringReadFrame, memory_order_relaxed);
    uint64_t writeFrame = atomic_load_explicit(&dsp->ringWriteFrame, memory_order_acquire);
    uint64_t available = writeFrame - readFrame;

    // Wait for roughly four common 512-frame buffers before speaking. This
    // decouples capture cadence from the speaker render deadline.
    const uint64_t prefillFrames = 2048;
    if (!dsp->outputPrimed) {
        if (available < prefillFrames) {
            clearOutput(output);
            return;
        }
        dsp->outputPrimed = true;
    }

    uint32_t framesToRead = (uint32_t)fmin((double)frameCount, (double)available);
    for (uint32_t frame = 0; frame < framesToRead; frame++) {
        uint64_t index = (readFrame + frame) % dsp->ringCapacity;
        float left = dsp->ringLeft[index];
        float right = dsp->ringRight[index];

        float outputGain = 1.0f;
        if (dsp->startupMuteRemaining > 0) {
            dsp->startupMuteRemaining--;
            outputGain = 0.0f;
        } else if (dsp->startupFadeRemaining > 0) {
            outputGain = 1.0f
                - ((float)dsp->startupFadeRemaining / (float)dsp->startupFadeLength);
            dsp->startupFadeRemaining--;
        }

        if (!writeStereoFrame(output, frame, left * outputGain, right * outputGain)) {
            framesToRead = frame;
            break;
        }
    }

    if (framesToRead < frameCount) {
        // Core Audio zeroes output buffers on entry, so the unwritten tail is
        // already silence. Count the event for setup-time diagnostics.
        atomic_fetch_add_explicit(&dsp->underrunCount, 1, memory_order_relaxed);
    }
    atomic_store_explicit(
        &dsp->ringReadFrame,
        readFrame + framesToRead,
        memory_order_release
    );
}

uint64_t FragmentaryDSPUnderrunCount(FragmentaryDSP *dsp) {
    if (dsp == NULL) {
        return 0;
    }
    return atomic_load_explicit(&dsp->underrunCount, memory_order_relaxed);
}

uint64_t FragmentaryDSPOverflowCount(FragmentaryDSP *dsp) {
    if (dsp == NULL) {
        return 0;
    }
    return atomic_load_explicit(&dsp->overflowCount, memory_order_relaxed);
}
