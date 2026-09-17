#ifndef MOUSELOCK_MOTION_H
#define MOUSELOCK_MOTION_H
#include "bounds.h"
typedef struct { MLPoint position, emitted; } MLMotion;
static inline void ml_motion_start(MLMotion *m, MLBounds bounds, MLPoint p) {
    m->position=ml_clamp(bounds,p);
    m->emitted=(MLPoint){round(m->position.x),round(m->position.y)};
}
// Clamp EACH hardware report. Summing raw deltas before clamping would lose
// reversals at the edge and change the user's motion.
static inline bool ml_motion_input(MLMotion *m,MLBounds bounds,double dx,double dy) {
    MLPoint candidate={m->position.x+dx,m->position.y+dy};
    m->position=ml_clamp(bounds,candidate);
    return ml_outside(bounds,candidate);
}
static inline bool ml_motion_take(MLMotion *m,MLPoint *delta) {
    MLPoint p={round(m->position.x),round(m->position.y)};
    *delta=(MLPoint){p.x-m->emitted.x,p.y-m->emitted.y};
    m->emitted=p;
    return delta->x!=0||delta->y!=0;
}
#endif
