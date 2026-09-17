#include <assert.h>
#include <stdio.h>
#include "../src/motion.h"
int main(void) {
    MLBounds b={100,100,400,300};MLMotion m;MLPoint delta;
    ml_motion_start(&m,b,(MLPoint){450,250});
    assert(ml_motion_input(&m,b,1000,0));
    assert(!ml_motion_input(&m,b,-10,0));
    assert(ml_motion_take(&m,&delta));
    assert(m.emitted.x==489&&delta.x==39); // reversal must survive batching
    assert(!ml_motion_take(&m,&delta)); // idle means no OS posts
    ml_motion_start(&m,b,(MLPoint){250,250});
    for(int i=0;i<1000;i++) {
        ml_motion_input(&m,b,0.1,0);
        if(i%5==4)ml_motion_take(&m,&delta);
    }
    assert(m.emitted.x==350); // retain sub-pixel motion across output ticks
    for(int i=0;i<10000;i++) {
        ml_motion_input(&m,b,(i%7-3)*1000,(i%11-5)*1000);
        if(i%4==0) {
            ml_motion_take(&m,&delta);
            assert(!ml_outside(b,m.emitted));
        }
    }
    b=(MLBounds){-200,-300,100,100};
    ml_motion_input(&m,b,0,0); // geometry change forces a bounded next output
    assert(ml_motion_take(&m,&delta));assert(!ml_outside(b,m.emitted));
    puts("motion tests passed");return 0;
}
