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
    OverhearPlaceAfterClosing = 0,
    OverhearPlaceOpenShutters = 1,
    OverhearPlaceThinWall = 2,
    OverhearPlaceHotelCorridor = 3,
    OverhearPlaceCinemaAfterCredits = 4,
    OverhearPlaceCarParkAtDawn = 5,
    OverhearPlaceKitchenRadio1979 = 6
} OverhearPlace;

OverhearDSP *OverhearDSPCreate(double sampleRate);
void OverhearDSPDestroy(OverhearDSP *dsp);
void OverhearDSPSetPlace(OverhearDSP *dsp, OverhearPlace place);
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
