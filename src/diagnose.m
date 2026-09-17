#import <AppKit/AppKit.h>
#import <IOKit/hid/IOHIDManager.h>
#import <mach/mach_time.h>
#include <signal.h>

// Passive observation only. No event injection, device seizure, or key logging.
typedef struct { uint64_t n, last; double gaps[8192], ages[8192]; size_t ng, na; double dx, dy; } Stats;
static Stats raw, quartz;
static uint64_t rawStamp;
static mach_timebase_info_data_t tb;
static volatile sig_atomic_t done;
static double seconds(uint64_t ticks) { return (double)ticks * tb.numer / tb.denom / 1e9; }
static int cmp(const void *a,const void *b) { double x=*(const double*)a,y=*(const double*)b; return (x>y)-(x<y); }
static void record(Stats *s, uint64_t now, double age) {
    if(s->last) { double gap=seconds(now-s->last)*1000; if(gap<100 && s->ng<8192) s->gaps[s->ng++]=gap; }
    s->last=now; s->n++; if(s->na<8192 && age>=0) s->ages[s->na++]=age;
}
static void input(void *ctx, IOReturn result, void *sender, IOHIDValueRef value) {
    (void)ctx;(void)sender; if(result!=kIOReturnSuccess)return;
    IOHIDElementRef e=IOHIDValueGetElement(value);
    uint32_t page=IOHIDElementGetUsagePage(e),usage=IOHIDElementGetUsage(e);
    if(page!=kHIDPage_GenericDesktop || (usage!=kHIDUsage_GD_X && usage!=kHIDUsage_GD_Y) || !IOHIDElementIsRelative(e))return;
    uint64_t stamp=IOHIDValueGetTimeStamp(value), now=mach_absolute_time();
    if(stamp!=rawStamp) { rawStamp=stamp; record(&raw,now,seconds(now-stamp)*1000); }
    double delta=fabs((double)IOHIDValueGetIntegerValue(value));
    if(usage==kHIDUsage_GD_X)raw.dx+=delta;else raw.dy+=delta;
}
static CGEventRef event(CGEventTapProxy proxy,CGEventType type,CGEventRef e,void *ctx) {
    (void)proxy;(void)ctx;
    if(type==kCGEventMouseMoved || type==kCGEventLeftMouseDragged || type==kCGEventRightMouseDragged || type==kCGEventOtherMouseDragged) {
        uint64_t now=mach_absolute_time();
        // Do not subtract timestamps from different clock domains. Callback
        // intervals are sufficient for the comparison made by this monitor.
        record(&quartz,now,-1);
        quartz.dx+=fabs(CGEventGetDoubleValueField(e,kCGMouseEventDeltaX));
        quartz.dy+=fabs(CGEventGetDoubleValueField(e,kCGMouseEventDeltaY));
    }
    return e;
}
static void printStats(const char *name, Stats *s) {
    qsort(s->gaps,s->ng,sizeof(double),cmp);qsort(s->ages,s->na,sizeof(double),cmp);
    printf("%s n=%llu gap_p50_ms=%.3f gap_p95_ms=%.3f age_p95_ms=%.3f abs_dx=%.0f abs_dy=%.0f ",name,(unsigned long long)s->n,s->ng?s->gaps[s->ng/2]:0,s->ng?s->gaps[(s->ng-1)*95/100]:0,s->na?s->ages[(s->na-1)*95/100]:0,s->dx,s->dy);
    *s=(Stats){0};
}
static void stop(int sig) { (void)sig;done=1; }
int main(int argc,char **argv) { @autoreleasepool {
    double duration=argc>1?atof(argv[1]):120; if(duration<=0 || duration>3600)return 2;
    mach_timebase_info(&tb);signal(SIGINT,stop);signal(SIGTERM,stop);setvbuf(stdout,NULL,_IOLBF,0);
    IOHIDManagerRef manager=IOHIDManagerCreate(kCFAllocatorDefault,kIOHIDOptionsTypeNone);
    NSDictionary *match=@{@kIOHIDDeviceUsagePageKey:@(kHIDPage_GenericDesktop),@kIOHIDDeviceUsageKey:@(kHIDUsage_GD_Mouse)};
    IOHIDManagerSetDeviceMatching(manager,(__bridge CFDictionaryRef)match);
    IOHIDManagerRegisterInputValueCallback(manager,input,NULL);
    IOHIDManagerScheduleWithRunLoop(manager,CFRunLoopGetCurrent(),kCFRunLoopCommonModes);
    IOReturn opened=IOHIDManagerOpen(manager,kIOHIDOptionsTypeNone);
    CGEventMask mask=CGEventMaskBit(kCGEventMouseMoved)|CGEventMaskBit(kCGEventLeftMouseDragged)|CGEventMaskBit(kCGEventRightMouseDragged)|CGEventMaskBit(kCGEventOtherMouseDragged);
    CFMachPortRef tap=CGEventTapCreate(kCGHIDEventTap,kCGHeadInsertEventTap,kCGEventTapOptionListenOnly,mask,event,NULL);
    printf("passive monitor: IOHID open=0x%x QuartzHIDtap=%s accessibility=%d\n",opened,tap?"yes":"NO",AXIsProcessTrusted());
    if(!tap || opened!=kIOReturnSuccess) { if(tap)CFRelease(tap);IOHIDManagerClose(manager,0);CFRelease(manager);return 1; }
    CFRunLoopSourceRef source=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(),source,kCFRunLoopCommonModes);
    double start=seconds(mach_absolute_time()),last=start;
    pid_t previous=-1;
    double nextContextCheck=start;
    while(!done && seconds(mach_absolute_time())-start<duration) { @autoreleasepool {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode,.05,true);
        double now=seconds(mach_absolute_time());
        // Querying NSWorkspace once per HID element can itself delay delivery.
        if(now<nextContextCheck)continue;
        nextContextCheck=now+.1;
        NSRunningApplication *front=NSWorkspace.sharedWorkspace.frontmostApplication;
        if(now-last>=2 || previous!=front.processIdentifier) {
            printf("t=%.2f elapsed=%.2f context=%s ",now-start,now-last,[front.bundleIdentifier isEqualToString:@"com.riotgames.LeagueofLegends.GameClient"]?"league":"desktop/other");
            printStats("hid",&raw);printStats("quartz",&quartz);puts("");last=now;previous=front.processIdentifier;
        }
    }}
    CFMachPortInvalidate(tap);CFRelease(source);CFRelease(tap);IOHIDManagerClose(manager,0);CFRelease(manager);
    return 0;
}}
