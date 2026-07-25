#ifndef FragmentaryDSP_h
#define FragmentaryDSP_h

#include <AudioToolbox/AudioToolbox.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct FragmentaryDSP FragmentaryDSP;

typedef enum FragmentaryPlace {
    FragmentaryPlaceAfterClosing = 0,
    FragmentaryPlaceOpenShutters = 1,
    FragmentaryPlaceThinWall = 2,
    FragmentaryPlaceHotelCorridor = 3,
    FragmentaryPlaceCinemaAfterCredits = 4,
    FragmentaryPlaceCarParkAtDawn = 5,
    FragmentaryPlaceKitchenRadio1979 = 6
} FragmentaryPlace;

FragmentaryDSP *FragmentaryDSPCreate(double sampleRate);
void FragmentaryDSPDestroy(FragmentaryDSP *dsp);
void FragmentaryDSPSetPlace(FragmentaryDSP *dsp, FragmentaryPlace place);
void FragmentaryDSPSetBlend(FragmentaryDSP *dsp, float blend);
void FragmentaryDSPReset(FragmentaryDSP *dsp);

void FragmentaryDSPProcess(
    FragmentaryDSP *dsp,
    const AudioBufferList *input,
    AudioBufferList *output,
    uint32_t frameCount
);

void FragmentaryDSPPush(
    FragmentaryDSP *dsp,
    const AudioBufferList *input,
    uint32_t frameCount
);

void FragmentaryDSPRender(
    FragmentaryDSP *dsp,
    AudioBufferList *output,
    uint32_t frameCount
);

uint64_t FragmentaryDSPUnderrunCount(FragmentaryDSP *dsp);
uint64_t FragmentaryDSPOverflowCount(FragmentaryDSP *dsp);

void FragmentaryDSPProcessInterleavedStereo(
    FragmentaryDSP *dsp,
    const float *input,
    float *output,
    uint32_t frameCount
);

#ifdef __cplusplus
}
#endif

#endif
