#include "../src/bounds.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    MLBounds game={1921,63,3838,2001};
    assert(ml_valid(game));
    MLPoint p=ml_clamp(game,(MLPoint){7000,100});
    assert(p.x==5758&&p.y==100); // Inside monitor, outside League.
    p=ml_clamp(game,(MLPoint){1900,30});assert(p.x==1921&&p.y==63);
    p=ml_clamp(game,(MLPoint){3000,2500});assert(p.x==3000&&p.y==2063);
    assert(!ml_outside(game,(MLPoint){5758,2063}));
    assert(ml_outside(game,(MLPoint){5759,2063}));
    MLBounds left={-1920,-1080,1920,1080};
    p=ml_clamp(left,(MLPoint){300,400});assert(p.x==-1&&p.y==-1);
    assert(!ml_valid((MLBounds){0,0,0,100}));assert(!ml_valid((MLBounds){NAN,0,100,100}));
    for(int x=-10000;x<=10000;x+=17)for(int y=-3000;y<=3000;y+=29) {
        p=ml_clamp(game,(MLPoint){x,y});assert(!ml_outside(game,p));
        MLPoint twice=ml_clamp(game,p);assert(p.x==twice.x&&p.y==twice.y);
    }
    puts("bounds tests passed: offset window, title bar, negative monitor, all edges, large jumps");
}
