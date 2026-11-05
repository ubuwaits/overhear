#ifndef FragmentaryDSP_h
#define FragmentaryDSP_h

#ifdef __APPLE__
#include <AudioToolbox/AudioToolbox.h>
#endif
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

#ifdef __APPLE__
void FragmentaryDSPProcess(
    FragmentaryDSP *dsp,
    const AudioBufferList *input,
    AudioBufferList *output,
    uint32_t frameCount
);
#endif

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
