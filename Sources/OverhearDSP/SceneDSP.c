#include "SceneDSP.h"
#include "OverhearDSP.h"
#include <stdlib.h>
#include <stdatomic.h>
#include <math.h>
#include <string.h>
#define COUNT OVERHEAR_SCENE_VALUE_COUNT
#define ROOM OVERHEAR_SCENE_ROOM_OFFSET
#define SOURCES OVERHEAR_SCENE_SOURCE_COUNT
#define PATHS 12
struct SceneDSP {
    double rate;
    float smoothing;
    _Atomic unsigned revision;
    _Atomic float mailbox[COUNT];
    unsigned seen, frame;
    float target[COUNT], live[COUNT];
    float sourceLP[SOURCES], sourceLP2[SOURCES], sourceHP[SOURCES];
    float pathLP[SOURCES][PATHS];
    float *sourceRing[SOURCES], *roomRing[4];
    float roomDamped[4];
    unsigned capacity, position;
    int initialized;
};
SceneDSP *SceneDSPCreate(double rate) {
    SceneDSP *d = calloc(1,sizeof(*d));
    if (!d) return NULL;
    d->smoothing = 1-expf(-1.0f/(0.025f*rate));
    d->rate = rate; d->capacity = (unsigned)(rate*0.6)+4;
    atomic_init(&d->revision,0);
    for (int i=0;i<COUNT;i++) atomic_init(&d->mailbox[i],0);
    for (int i=0;i<SOURCES;i++) {
        d->sourceRing[i] = calloc(d->capacity,sizeof(float));
        if (!d->sourceRing[i]) { SceneDSPDestroy(d); return NULL; }
    }
    for (int i=0;i<4;i++) {
        d->roomRing[i] = calloc(d->capacity,sizeof(float));
        if (!d->roomRing[i]) { SceneDSPDestroy(d); return NULL; }
    }
    return d;
}
void SceneDSPDestroy(SceneDSP *d) {
    if (!d) return;
    for(int i=0;i<SOURCES;i++) free(d->sourceRing[i]);
    for(int i=0;i<4;i++) free(d->roomRing[i]);
    free(d);
}
static float clamp(float x,float lo,float hi) { return fminf(hi,fmaxf(lo,x)); }
void SceneDSPConfigure(SceneDSP *d,const float *v) {
    if (!d || !v) return;
    // Single writer publishes an atomic snapshot. The audio thread never waits.
    atomic_fetch_add_explicit(&d->revision,1,memory_order_acq_rel);
    for(int i=0;i<COUNT;i++) atomic_store_explicit(&d->mailbox[i],isfinite(v[i])?v[i]:0,memory_order_relaxed);
    atomic_fetch_add_explicit(&d->revision,1,memory_order_release);
}
static float readDelay(SceneDSP *d,float *ring,float frames) {
    float at = (float)d->position-clamp(frames,1,(float)d->capacity-2);
    if (at<0) at += d->capacity;
    unsigned first = (unsigned)at, second = (first+1)%d->capacity;
    float fraction = at-first;
    return ring[first]*(1-fraction)+ring[second]*fraction;
}
static void update(SceneDSP *d) {
    unsigned rev = atomic_load_explicit(&d->revision,memory_order_acquire);
    if (rev == d->seen || (rev&1)) return;
    float copy[COUNT];
    for(int i=0;i<COUNT;i++) copy[i] = atomic_load_explicit(&d->mailbox[i],memory_order_relaxed);
    atomic_thread_fence(memory_order_acquire);
    if (rev != atomic_load_explicit(&d->revision,memory_order_acquire)) return;
    for(int s=0;s<SOURCES;s++) {
        int base=s*OVERHEAR_SCENE_SOURCE_STRIDE;
        copy[base] = expf(-2*M_PI*clamp(copy[base],20,20000)/d->rate);
        copy[base+1] = expf(-2*M_PI*clamp(copy[base+1],20,20000)/d->rate);
        copy[base+2] = clamp(copy[base+2],0.1,6);
        copy[base+3] = clamp(copy[base+3],0,1.5);
        for(int p=0;p<12;p++) {
            int i=base+4+p*4;
            copy[i] = clamp(copy[i]*d->rate,1,d->capacity-2);
            float gain=clamp(copy[i+1],0,2), pan=clamp(copy[i+2],-1,1);
            copy[i+1] = gain*sqrtf((1-pan)*0.5f);
            copy[i+2] = gain*sqrtf((1+pan)*0.5f);
            copy[i+3] = expf(-2*M_PI*clamp(copy[i+3],100,20000)/d->rate);
        }
    }
    for(int i=0;i<4;i++) {
        copy[ROOM+i] = clamp(copy[ROOM+i]*d->rate,1,d->capacity-2);
        copy[ROOM+4+i] = clamp(copy[ROOM+4+i],0,.985);
    }
    copy[ROOM+8] = clamp(copy[ROOM+8],0,.95); copy[ROOM+9] = clamp(copy[ROOM+9],0,2); copy[ROOM+10] = clamp(copy[ROOM+10],0,1);
    copy[ROOM+11] = clamp(copy[ROOM+11],0.25f,128.0f);
    memcpy(d->target,copy,sizeof(copy));
    if(!d->initialized) { memcpy(d->live,copy,sizeof(copy)); d->initialized=1; }
    d->seen=rev;
}
void SceneDSPProcess(SceneDSP *d,float left,float right,float *outLeft,float *outRight) {
    if ((d->frame++ & 127) == 0) update(d);
    float smoothing=d->smoothing;
    for(int i=0;i<COUNT;i++) d->live[i] += (d->target[i]-d->live[i])*smoothing;
    float l=0,r=0,send=0,mono=(left+right)*.5f;
    for(int s=0;s<SOURCES;s++) {
        int base=s*OVERHEAR_SCENE_SOURCE_STRIDE;
        float lp=d->live[base],hp=d->live[base+1];
        d->sourceLP[s] = mono*(1-lp)+d->sourceLP[s]*lp;
        d->sourceLP2[s] = d->sourceLP[s]*(1-lp)+d->sourceLP2[s]*lp;
        d->sourceHP[s] = d->sourceLP2[s]*(1-hp)+d->sourceHP[s]*hp;
        float signal=tanhf((d->sourceLP2[s]-d->sourceHP[s])*d->live[base+2])*d->live[base+3];
        d->sourceRing[s][d->position]=signal;

        for(int p=0;p<12;p++) {
            int i=base+4+p*4;
            float tap=readDelay(d,d->sourceRing[s],d->live[i]);
            float a=d->live[i+3];
            d->pathLP[s][p]=tap*(1-a)+d->pathLP[s][p]*a;
            l += d->pathLP[s][p]*d->live[i+1];
            r += d->pathLP[s][p]*d->live[i+2];
            // Feed the diffuse field only after direct arrival, including any
            // transmission loss/filtering through the partition.
            if (p==0) send += d->pathLP[s][p]*(d->live[i+1]+d->live[i+2])*.25f*d->live[ROOM+10];
        }
    }
    float room[4], damp[4];
    for(int i=0;i<4;i++) {
        room[i]=readDelay(d,d->roomRing[i],d->live[ROOM+i]);
        damp[i]=room[i]*(1-d->live[ROOM+8])+d->roomDamped[i]*d->live[ROOM+8];
        d->roomDamped[i]=damp[i];
    }
    float mix[4] = { (damp[0]+damp[1]+damp[2]+damp[3])*.5f,
        (damp[0]-damp[1]+damp[2]-damp[3])*.5f,
        (damp[0]+damp[1]-damp[2]-damp[3])*.5f,
        (damp[0]-damp[1]-damp[2]+damp[3])*.5f };
    for(int i=0;i<4;i++) d->roomRing[i][d->position]=send*(i==3?-1:1)+mix[i]*d->live[ROOM+4+i];
    *outLeft=(l+(room[0]+room[2])*.5f*d->live[ROOM+9])*d->live[ROOM+11];
    *outRight=(r+(room[1]+room[3])*.5f*d->live[ROOM+9])*d->live[ROOM+11];
    d->position=(d->position+1)%d->capacity;
}
