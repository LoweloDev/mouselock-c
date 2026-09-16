#import <AppKit/AppKit.h>
#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/hidsystem/IOHIDLib.h>
#import <IOKit/hidsystem/IOHIDShared.h>
#import <mach/mach_time.h>
#include <stdatomic.h>
#include <signal.h>
#include <pthread.h>
#include "motion.h"

// IOKit-only movement/output path. Quartz is used ONLY to read the starting
// cursor position and window geometry. No CGEvent tap, post, warp or polling.
// The first supported report format is the seven-byte Attack Shark X3 wired
// mouse report. An exact descriptor check prevents seizing a mismatched device.
static const unsigned char supportedDescriptor[]={
0x05,0x01,0x09,0x02,0xa1,0x01,0x09,0x01,0xa1,0x00,0x05,0x09,0x19,0x01,0x29,0x05,
0x15,0x00,0x25,0x01,0x95,0x05,0x75,0x01,0x81,0x02,0x95,0x01,0x75,0x03,0x81,0x01,
0x05,0x01,0x09,0x30,0x09,0x31,0x16,0x01,0x80,0x26,0xff,0x7f,0x75,0x10,0x95,0x02,
0x81,0x06,0x09,0x38,0x15,0x81,0x25,0x7f,0x75,0x08,0x95,0x01,0x81,0x06,0x05,0x0c,
0x0a,0x38,0x02,0x95,0x01,0x81,0x06,0xc0,0xc0};
static io_connect_t output;
static IOHIDDeviceRef mouse;
static UInt8 reportBuffer[256];
static bool seized, enabled, failed, quitting;
static MLBounds rect;
static MLMotion motion;
static CFRunLoopTimerRef motionTimer;
static double gain=.683, limitSeconds=60, started, lastDown[5];
static int clicks[5];
static uint8_t buttons;
static uint64_t reports, clamped, posts, errors;
static _Atomic uint64_t heartbeat;
static _Atomic bool watchdogDone;
static volatile sig_atomic_t stopRequested;
static mach_timebase_info_data_t timebase;
static NSString *failure;
static bool permitted;
static double lastPermissionCheck=-10, lastGeometryCheck=-10, lastStatusUpdate=-10;
static uint32_t windowID;
static int windowLayer;
static double now(void) {return (double)mach_absolute_time()*timebase.numer/timebase.denom/1e9;}
static void signalStop(int sig) {(void)sig;stopRequested=1;}
static void *watchdog(void *unused) {
    (void)unused;
    while(!atomic_load(&watchdogDone)) {
        usleep(100000);
        uint64_t t=atomic_load(&heartbeat);
        if(t && (double)(mach_absolute_time()-t)*timebase.numer/timebase.denom/1e9>2.0) {
            // Closing the process releases the seized device even if the
            // processing thread is stuck inside an OS call.
            static const char message[]="Watchdog: processing stalled; exiting to release mouse.\n";
            write(STDERR_FILENO,message,sizeof(message)-1);_exit(70);
        }
    }
    return NULL;
}
static IOReturn post(UInt32 type,NXEventData *data) {
    IOGPoint p={(SInt16)lround(motion.position.x),(SInt16)lround(motion.position.y)};
    // Deprecated by Apple, but this experiment deliberately tests the lower
    // IOHIDSystem path rather than recreating the unsuccessful Quartz loop.
    IOReturn r=IOHIDPostEvent(output,type,p,data,kNXEventDataVersion,NX_NONCOALSESCEDMASK,kIOHIDSetCursorPosition);
    posts++;
    if(r!=kIOReturnSuccess){errors++;failed=true;failure=[NSString stringWithFormat:@"IOHIDPostEvent: 0x%x",r];}
    return r;
}
static UInt32 buttonType(int b,bool down) {return b==0?(down?NX_LMOUSEDOWN:NX_LMOUSEUP):b==1?(down?NX_RMOUSEDOWN:NX_RMOUSEUP):(down?NX_OMOUSEDOWN:NX_OMOUSEUP);}
static void sendButton(int b,bool down) {
    NXEventData e={0};e.mouse.buttonNumber=(UInt8)b;e.mouse.eventNum=(SInt16)(b+1);
    if(down){double t=now();clicks[b]=(t-lastDown[b]<NSEvent.doubleClickInterval)?clicks[b]+1:1;lastDown[b]=t;}
    e.mouse.click=clicks[b]?clicks[b]:1;e.mouse.pressure=down?255:0;post(buttonType(b,down),&e);
}
static void flushMotion(void) {
    if(!seized||failed)return;
    MLPoint delta;
    if(!ml_motion_take(&motion,&delta))return;
    NXEventData e={0};e.mouseMove.dx=(int32_t)delta.x;e.mouseMove.dy=(int32_t)delta.y;
    UInt32 type=(buttons&1)?NX_LMOUSEDRAGGED:(buttons&2)?NX_RMOUSEDRAGGED:(buttons&28)?NX_OMOUSEDRAGGED:NX_MOUSEMOVED;
    post(type,&e);
}
static void motionTick(CFRunLoopTimerRef timer,void *context) {
    (void)timer;(void)context;flushMotion();
}
static void releaseMouse(void) {
    if(!seized)return;
    if(motionTimer){CFRunLoopTimerInvalidate(motionTimer);CFRelease(motionTimer);motionTimer=NULL;}
    // Balance any generated down before returning the physical device.
    for(int b=0;b<5;b++)if(buttons&(1u<<b))sendButton(b,false);
    buttons=0;
    IOHIDDeviceUnscheduleFromRunLoop(mouse,CFRunLoopGetMain(),kCFRunLoopCommonModes);
    IOReturn result=IOHIDDeviceClose(mouse,kIOHIDOptionsTypeSeizeDevice);seized=false;
    printf("released result=0x%x reports=%llu clamped=%llu posts=%llu errors=%llu\n",result,(unsigned long long)reports,(unsigned long long)clamped,(unsigned long long)posts,(unsigned long long)errors);
}
static void report(void *context,IOReturn result,void *sender,IOHIDReportType type,uint32_t reportID,uint8_t *bytes,CFIndex length) {
    (void)context;(void)sender;
    if(!seized||failed)return;
    if(result!=kIOReturnSuccess||type!=kIOHIDReportTypeInput||reportID!=0||length!=7) {
        failed=true;failure=@"Unerwartetes HID-Reportformat";return;
    }
    reports++;
    int dx=(int16_t)((uint16_t)bytes[1]|((uint16_t)bytes[2]<<8));
    int dy=(int16_t)((uint16_t)bytes[3]|((uint16_t)bytes[4]<<8));
    uint8_t nextButtons=bytes[0]&31;
    if(ml_motion_input(&motion,rect,dx*gain,dy*gain))clamped++;
    // Position is bounded BEFORE it is submitted to the OS. No unbounded
    // physical report reaches normal cursor processing while seized.
    // Consume every raw report, but submit movement on a 240 Hz timer. Button
    // and wheel reports flush immediately, preserving position/event order.
    int wheel=(int8_t)bytes[5],pan=(int8_t)bytes[6];
    if(nextButtons!=buttons||wheel||pan)flushMotion();
    if(failed)return;
    for(int b=0;b<5;b++)if((nextButtons^buttons)&(1u<<b))sendButton(b,(nextButtons&(1u<<b))!=0);
    buttons=nextButtons;
    if(wheel||pan) {
        NXEventData e={0};e.scrollWheel.deltaAxis1=(SInt16)wheel;e.scrollWheel.deltaAxis2=(SInt16)pan;
        e.scrollWheel.fixedDeltaAxis1=wheel*65536;e.scrollWheel.fixedDeltaAxis2=pan*65536;
        e.scrollWheel.pointDeltaAxis1=wheel*10;e.scrollWheel.pointDeltaAxis2=pan*10;post(NX_SCROLLWHEELMOVED,&e);
    }
}
static bool findMouse(void) {
    IOHIDManagerRef manager=IOHIDManagerCreate(kCFAllocatorDefault,kIOHIDOptionsTypeNone);
    NSDictionary *matching=@{@kIOHIDVendorIDKey:@0x1d57,@kIOHIDProductIDKey:@0xfa61,@kIOHIDDeviceUsagePageKey:@1,@kIOHIDDeviceUsageKey:@2};
    IOHIDManagerSetDeviceMatching(manager,(__bridge CFDictionaryRef)matching);
    NSSet *devices=CFBridgingRelease(IOHIDManagerCopyDevices(manager));
    if(devices.count==1) {
        IOHIDDeviceRef d=(__bridge IOHIDDeviceRef)devices.anyObject;
        CFTypeRef desc=IOHIDDeviceGetProperty(d,CFSTR(kIOHIDReportDescriptorKey));
        if(desc&&CFGetTypeID(desc)==CFDataGetTypeID()&&CFDataGetLength(desc)==sizeof(supportedDescriptor)&&!memcmp(CFDataGetBytePtr(desc),supportedDescriptor,sizeof(supportedDescriptor)))mouse=(IOHIDDeviceRef)CFRetain(d);
    }
    CFRelease(manager);return mouse!=NULL;
}
static bool capture(void) {
    if(!mouse||!ml_valid(rect))return false;
    CGEventRef e=CGEventCreate(NULL);if(!e)return false;
    CGPoint p=CGEventGetLocation(e);CFRelease(e);ml_motion_start(&motion,rect,(MLPoint){p.x,p.y});
    IOHIDDeviceRegisterInputReportCallback(mouse,reportBuffer,sizeof(reportBuffer),report,NULL);
    IOHIDDeviceScheduleWithRunLoop(mouse,CFRunLoopGetMain(),kCFRunLoopCommonModes);
    IOReturn r=IOHIDDeviceOpen(mouse,kIOHIDOptionsTypeSeizeDevice);
    if(r!=kIOReturnSuccess){IOHIDDeviceUnscheduleFromRunLoop(mouse,CFRunLoopGetMain(),kCFRunLoopCommonModes);failure=[NSString stringWithFormat:@"Exklusiver HID-Zugriff: 0x%x",r];failed=true;return false;}
    seized=true;buttons=0;
    NXEventData empty={0};post(NX_NULLEVENT,&empty);
    if(failed){releaseMouse();return false;}
    motionTimer=CFRunLoopTimerCreate(kCFAllocatorDefault,CFAbsoluteTimeGetCurrent()+1.0/240,1.0/240,0,0,motionTick,NULL);
    if(!motionTimer){failed=true;failure=@"Ausgabetimer konnte nicht starten";releaseMouse();return false;}
    CFRunLoopAddTimer(CFRunLoopGetMain(),motionTimer,kCFRunLoopCommonModes);
    printf("captured bounds=%.0f,%.0f,%.0f,%.0f gain=%.6f\n",rect.x,rect.y,rect.w,rect.h,gain);return true;
}

@interface HIDGuard : NSObject <NSApplicationDelegate>
@property NSStatusItem *item;
@property NSMenuItem *stateItem;
@property NSMenuItem *toggleItem;
@property NSTimer *timer;
@property NSRunningApplication *front;
@end
@implementation HIDGuard
- (void)applicationDidFinishLaunching:(NSNotification*)n {
    (void)n;self.item=[NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];self.item.button.title=@"HID ○";
    NSMenu *menu=[NSMenu new];self.stateItem=[menu addItemWithTitle:@"Vorbereitung" action:nil keyEquivalent:@""];
    self.toggleItem=[menu addItemWithTitle:@"Test aktivieren" action:@selector(toggle:) keyEquivalent:@""];self.toggleItem.target=self;
    [menu addItemWithTitle:@"Command halten: Freigeben" action:nil keyEquivalent:@""];
    [menu addItemWithTitle:[NSString stringWithFormat:@"Automatisches Ende nach %.0f Sekunden",limitSeconds] action:nil keyEquivalent:@""];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit=[menu addItemWithTitle:@"Beenden" action:@selector(quit:) keyEquivalent:@"q"];quit.target=self;self.item.menu=menu;
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(focus:) name:NSWorkspaceDidActivateApplicationNotification object:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(pause:) name:NSWorkspaceWillSleepNotification object:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(pause:) name:NSWorkspaceSessionDidResignActiveNotification object:nil];
    self.front=NSWorkspace.sharedWorkspace.frontmostApplication;
    self.timer=[NSTimer timerWithTimeInterval:.05 target:self selector:@selector(tick:) userInfo:nil repeats:YES];[NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];[self tick:nil];
}
- (void)toggle:(id)sender {(void)sender;if(!enabled){failed=false;failure=nil;started=now();lastPermissionCheck=-10;lastGeometryCheck=-10;}enabled=!enabled;if(!enabled)releaseMouse();lastStatusUpdate=-10;[self tick:nil];}
- (void)pause:(id)sender {(void)sender;enabled=false;releaseMouse();}
- (void)focus:(NSNotification*)n {
    NSRunningApplication *app=n.userInfo[NSWorkspaceApplicationKey];
    self.front=app;lastGeometryCheck=-10;lastStatusUpdate=-10;
    if(![app.bundleIdentifier isEqualToString:@"com.riotgames.LeagueofLegends.GameClient"])releaseMouse();[self tick:nil];
}
- (void)tick:(id)sender {
    (void)sender;atomic_store(&heartbeat,mach_absolute_time());
    if(stopRequested){[self quit:nil];return;}
    if(enabled&&limitSeconds>0&&now()-started>=limitSeconds){enabled=false;releaseMouse();printf("test timer elapsed\n");}
    if(failed){enabled=false;releaseMouse();}
    double t=now();
    if(t-lastPermissionCheck>=2){lastPermissionCheck=t;permitted=IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)==kIOHIDAccessTypeGranted&&IOHIDCheckAccess(kIOHIDRequestTypePostEvent)==kIOHIDAccessTypeGranted;}
    NSRunningApplication *front=self.front;
    bool target=[front.bundleIdentifier isEqualToString:@"com.riotgames.LeagueofLegends.GameClient"];
    bool command=enabled&&(NSEvent.modifierFlags&NSEventModifierFlagCommand)!=0;
    if(enabled&&permitted&&target&&!command&&!failed) {
      if(t-lastGeometryCheck>=.25) {
        lastGeometryCheck=t;
        NSArray *windows=CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly|kCGWindowListExcludeDesktopElements,kCGNullWindowID));
        MLBounds next={0};
        uint32_t nextID=0;int nextLayer=0;
        for(NSDictionary *w in windows) {
            int layer=[w[(__bridge NSString*)kCGWindowLayer] intValue];
            // Borderless windows may use a raised level. Never consider other
            // processes, but do not require the game's window to be layer zero.
            if([w[(__bridge NSString*)kCGWindowOwnerPID] intValue]!=front.processIdentifier||layer<0||[w[(__bridge NSString*)kCGWindowAlpha] doubleValue]<=0)continue;
            CGRect r;if(!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)w[(__bridge NSString*)kCGWindowBounds],&r))continue;
            if(r.size.width>400&&r.size.height>300&&r.size.width*r.size.height>next.w*next.h) {
                next=(MLBounds){r.origin.x,r.origin.y,r.size.width,r.size.height};
                nextID=[w[(__bridge NSString*)kCGWindowNumber] unsignedIntValue];nextLayer=layer;
            }
        }
        NSString *cfg=[NSString stringWithContentsOfFile:@"/Applications/League of Legends.app/Contents/LoL/Config/game.cfg" encoding:NSUTF8StringEncoding error:nil];
        bool decorated=false;for(NSString *line in [cfg componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet])if([line isEqualToString:@"WindowMode=1"])decorated=true;
        next.x+=1;next.y+=decorated?33:1;next.w-=2;next.h-=decorated?34:2;
        if(ml_valid(next)&&next.x>=INT16_MIN&&next.y>=INT16_MIN&&next.x+next.w<INT16_MAX&&next.y+next.h<INT16_MAX) {
            if(nextID!=windowID||nextLayer!=windowLayer||memcmp(&next,&rect,sizeof(next))) {
                printf("window id=%u layer=%d bounds=%.0f,%.0f,%.0f,%.0f configured_decorated=%d\n",nextID,nextLayer,next.x,next.y,next.w,next.h,decorated);
                windowID=nextID;windowLayer=nextLayer;
            }
            rect=next;ml_motion_input(&motion,rect,0,0);if(!seized)capture();else flushMotion();
        }else {
            if(seized)printf("release: no usable game window for pid=%d\n",front.processIdentifier);
            releaseMouse();
        }
      }
    }else releaseMouse();
    NSString *icon=seized?@"HID ●":@"HID ○";
    if(![self.item.button.title isEqualToString:icon])self.item.button.title=icon;
    NSString *toggle=enabled?@"Test pausieren":[NSString stringWithFormat:@"%.0f-Sekunden-Test aktivieren",limitSeconds];
    if(![self.toggleItem.title isEqualToString:toggle])self.toggleItem.title=toggle;
    if(t-lastStatusUpdate>=1) {
        lastStatusUpdate=t;
        NSString *state=failed?failure:!permitted?@"Bedienungshilfen + Eingabeüberwachung nötig":seized?[NSString stringWithFormat:@"HID aktiv · %llu Reports · %llu begrenzt",(unsigned long long)reports,(unsigned long long)clamped]:enabled?@"Warte auf League":@"Pausiert";
        if(![self.stateItem.title isEqualToString:state])self.stateItem.title=state;
    }
}
- (void)quit:(id)sender {
    (void)sender;if(quitting)return;quitting=true;enabled=false;releaseMouse();[self.timer invalidate];atomic_store(&watchdogDone,true);[NSApp terminate:nil];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender {(void)sender;enabled=false;releaseMouse();atomic_store(&watchdogDone,true);return NSTerminateNow;}
@end
int main(int argc,char **argv) {@autoreleasepool {
    bool check=false;
    for(int i=1;i<argc;i++) {
        if(!strcmp(argv[i],"--check"))check=true;
        else if(!strcmp(argv[i],"--arm"))enabled=true;
        else if(!strcmp(argv[i],"--gain")&&i+1<argc)gain=atof(argv[++i]);
        else if(!strcmp(argv[i],"--seconds")&&i+1<argc)limitSeconds=atof(argv[++i]);
        else {fprintf(stderr,"Usage: mouselock [--check] [--arm] [--gain N] [--seconds 1..600]\n");return 2;}
    }
    if(!isfinite(gain)||gain<=0||gain>10||!isfinite(limitSeconds)||limitSeconds<1||limitSeconds>600)return 2;
    setvbuf(stdout,NULL,_IOLBF,0);mach_timebase_info(&timebase);
    signal(SIGINT,signalStop);signal(SIGTERM,signalStop);
    io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching(kIOHIDSystemClass));
    IOReturn opened=service?IOServiceOpen(service,mach_task_self(),kIOHIDParamConnectType,&output):kIOReturnNotFound;if(service)IOObjectRelease(service);
    bool found=findMouse();
    printf("IOHIDSystem=0x%x supported_mouse=%d post_access=%d listen_access=%d\n",opened,found,IOHIDCheckAccess(kIOHIDRequestTypePostEvent),IOHIDCheckAccess(kIOHIDRequestTypeListenEvent));
    if(check){if(mouse)CFRelease(mouse);if(output)IOServiceClose(output);return opened==0&&found?0:1;}
    if(opened!=0||!found){fprintf(stderr,"Supported wired mouse or IOHIDSystem connection unavailable.\n");return 1;}
    atomic_store(&heartbeat,mach_absolute_time());pthread_t thread;int r=pthread_create(&thread,NULL,watchdog,NULL);if(r)return 1;pthread_detach(thread);
    started=now();NSApplication *app=NSApplication.sharedApplication;[app setActivationPolicy:NSApplicationActivationPolicyAccessory];HIDGuard *delegate=[HIDGuard new];app.delegate=delegate;[app run];
    atomic_store(&watchdogDone,true);releaseMouse();if(mouse)CFRelease(mouse);IOServiceClose(output);return 0;
}}
