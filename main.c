#include <ApplicationServices/ApplicationServices.h>

bool isOutsideScreen(CGPoint location, CGRect screenBounds) {
    return location.x < screenBounds.origin.x || location.x > CGRectGetMaxX(screenBounds) || location.y < screenBounds.origin.y || location.y > CGRectGetMaxY(screenBounds);
}

CGEventRef myCGEventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    if ((type != kCGEventLeftMouseDragged) && (type != kCGEventRightMouseDragged) && (type != kCGEventMouseMoved)) {
        return event;
    }

    CGPoint location = CGEventGetLocation(event);
    CGRect screenBounds = CGDisplayBounds(CGMainDisplayID());

    if (!isOutsideScreen(location, screenBounds)) {
        return event;
    }

    CGPoint newLocation = CGPointMake(
        fmax(screenBounds.origin.x, fmin(CGRectGetMaxX(screenBounds), location.x)),
        fmax(screenBounds.origin.y, fmin(CGRectGetMaxY(screenBounds), location.y))
    );

    CGEventRef newEvent = CGEventCreateMouseEvent(NULL, type, newLocation, kCGMouseButtonLeft);
    CGEventPost(kCGHIDEventTap, newEvent);
    CFRelease(newEvent);
    return NULL;
}

int main(void) {
    CFMachPortRef eventTap;
    CGEventMask        eventMask;
    CFRunLoopSourceRef runLoopSource;

    eventMask = (1 << kCGEventLeftMouseDragged) | (1 << kCGEventRightMouseDragged) | (1 << kCGEventMouseMoved);
    eventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, 0, eventMask, myCGEventCallback, NULL);
    if (!eventTap) {
        fprintf(stderr, "Fehler beim Erstellen des Event Taps\n");
        exit(1);
    }

    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
    CGEventTapEnable(eventTap, true);

    CFRunLoopRun();

    exit(0);
}