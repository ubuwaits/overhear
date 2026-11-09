#ifndef SceneDSP_h
#define SceneDSP_h
#include <stdint.h>
typedef struct SceneDSP SceneDSP;
SceneDSP *SceneDSPCreate(double sampleRate);
void SceneDSPDestroy(SceneDSP *dsp);
void SceneDSPConfigure(SceneDSP *dsp, const float *values);
void SceneDSPProcess(SceneDSP *dsp, float left, float right, float *outLeft, float *outRight);
#endif
