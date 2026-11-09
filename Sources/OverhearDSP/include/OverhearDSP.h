#ifndef OverhearDSP_h
#define OverhearDSP_h

#ifdef __APPLE__
#include <AudioToolbox/AudioToolbox.h>
#endif
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct OverhearDSP OverhearDSP;

typedef enum OverhearPlace {
    OverhearPlaceEmptyMall = 0,
    OverhearPlaceOpenWindow = 1,
    OverhearPlaceThinWall = 2,
    OverhearPlaceHotelCorridor = 3,
    OverhearPlaceMovieTheater = 4,
    OverhearPlaceParkingGarage = 5,
    OverhearPlaceKitchenRadio = 6
} OverhearPlace;

OverhearDSP *OverhearDSPCreate(double sampleRate);
void OverhearDSPDestroy(OverhearDSP *dsp);
void OverhearDSPSetPlace(OverhearDSP *dsp, OverhearPlace place);
// Stable parameter indices shared by native editor and preset serialization.
// 0..11: LP Hz, HP Hz, width, pan, drive, flutter depth, source/direct/early/
// window/late mixes, output gain. 12..16: damping, feedback, slow/fast Hz,
// diffuse blend. 17..24 early ms; 25..32 early gains; 33..35 window ms;
// 36..38 window gains; 39..41 window pans (0 left, 1 right); 42..49 late ms;
// 50..57 late gains; 58..61 room line ms. Invalid/nonfinite values are ignored,
// finite values are clamped. Setters are lock-free; call from one control queue.
#define OVERHEAR_PARAMETER_COUNT 62
float OverhearDSPPresetParameter(OverhearPlace place, uint32_t index);
void OverhearDSPSetParameter(OverhearDSP *dsp, uint32_t index, float value);
// Scene renderer: six sources, each with tone/gain and twelve geometric paths.
// 6 * (LP Hz, HP Hz, drive, level, 12 * [seconds, gain, pan, cutoff Hz]),
// then four reverb delays, four feedback gains, damping, wet level, send normalization, output makeup gain.
#define OVERHEAR_SCENE_SOURCE_COUNT 6
#define OVERHEAR_SCENE_SOURCE_STRIDE 52
#define OVERHEAR_SCENE_ROOM_OFFSET (OVERHEAR_SCENE_SOURCE_COUNT * OVERHEAR_SCENE_SOURCE_STRIDE)
#define OVERHEAR_SCENE_VALUE_COUNT (OVERHEAR_SCENE_ROOM_OFFSET + 12)
void OverhearDSPSetScene(OverhearDSP *dsp, const float *values, uint32_t count);
void OverhearDSPSetBlend(OverhearDSP *dsp, float blend);

#ifdef __APPLE__
void OverhearDSPProcess(
    OverhearDSP *dsp,
    const AudioBufferList *input,
    AudioBufferList *output,
    uint32_t frameCount
);
#endif

void OverhearDSPProcessInterleavedStereo(
    OverhearDSP *dsp,
    const float *input,
    float *output,
    uint32_t frameCount
);

#ifdef __cplusplus
}
#endif

#endif
