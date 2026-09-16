#ifndef MOUSELOCK_BOUNDS_H
#define MOUSELOCK_BOUNDS_H
#include <stdbool.h>
#include <math.h>
typedef struct { double x,y,w,h; } MLBounds;
typedef struct { double x,y; } MLPoint;
static inline bool ml_valid(MLBounds b) { return isfinite(b.x)&&isfinite(b.y)&&isfinite(b.w)&&isfinite(b.h)&&b.w>2&&b.h>2; }
static inline MLPoint ml_clamp(MLBounds b,MLPoint p) {
    return (MLPoint){fmax(b.x,fmin(b.x+b.w-1,p.x)),fmax(b.y,fmin(b.y+b.h-1,p.y))};
}
static inline bool ml_outside(MLBounds b,MLPoint p) {
    return p.x<b.x || p.x>b.x+b.w-1 || p.y<b.y || p.y>b.y+b.h-1;
}
#endif
