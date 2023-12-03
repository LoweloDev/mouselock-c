#include <ApplicationServices/ApplicationServices.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>

#define BUFFER 10 // Definiert einen Pufferbereich von 1 Pixel

bool isOutsideScreen(CGPoint location, CGRect screenBounds) {
    bool outside = location.x < screenBounds.origin.x || location.x > CGRectGetMaxX(screenBounds) - BUFFER || location.y < screenBounds.origin.y || location.y > CGRectGetMaxY(screenBounds) - BUFFER;
    if (outside) {
        printf("Maus ist außerhalb des Bildschirms: (%f, %f)\n", location.x, location.y);
    }
    return outside;
}

CGEventRef myCGEventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    if (type == kCGEventMouseMoved || type == kCGEventLeftMouseDragged || type == kCGEventRightMouseDragged) {
        CGPoint location = CGEventGetLocation(event);
        printf("Maus bewegt zu: (%f, %f)\n", location.x, location.y);
        CGRect screenBounds = CGDisplayBounds(CGMainDisplayID());

        if (isOutsideScreen(location, screenBounds)) {
            // Setzen Sie die Mausposition zurück auf den Rand des Hauptbildschirms
            CGPoint newLocation = CGPointMake(MIN(MAX(location.x, screenBounds.origin.x), CGRectGetMaxX(screenBounds) - BUFFER), MIN(MAX(location.y, screenBounds.origin.y), CGRectGetMaxY(screenBounds) - BUFFER));
            CGWarpMouseCursorPosition(newLocation);
            printf("Mausposition korrigiert zu: (%f, %f)\n", newLocation.x, newLocation.y);
            return NULL; // Verwerfen Sie das ursprüngliche Ereignis
        }
    }

    return event;
}

int main(void) {
    CFMachPortRef eventTap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap, 0, kCGEventMaskForAllEvents, myCGEventCallback, NULL);

    if (!eventTap) {
        printf("Fehler beim Erstellen des Event Taps\n");
        exit(1);
    }

    CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
    CGEventTapEnable(eventTap, true);

    printf("Event Tap erstellt und aktiviert\n");

    CFRunLoopRun();

    return 0;
}