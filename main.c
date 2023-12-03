#include <ApplicationServices/ApplicationServices.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>

#define BUFFER 10 // Definiert einen Pufferbereich von 1 Pixel

bool isOutsideScreen(CGPoint location, CGRect screenBounds) {
    return location.x < screenBounds.origin.x || location.x > CGRectGetMaxX(screenBounds) - BUFFER;
}

void* checkMousePosition(void* arg) {
    while (true) {
        CGPoint location = CGEventGetLocation(CGEventCreate(NULL));
        CGRect screenBounds = CGDisplayBounds(CGMainDisplayID());

        printf("Mausposition: (%f, %f)\n", location.x, location.y);
        printf("Bildschirmgrenzen: (%f, %f, %f, %f)\n", screenBounds.origin.x, screenBounds.origin.y, CGRectGetMaxX(screenBounds), CGRectGetMaxY(screenBounds));

        if (isOutsideScreen(location, screenBounds)) {
            CGPoint newLocation = CGPointMake(
                fmax(screenBounds.origin.x, fmin(CGRectGetMaxX(screenBounds) - BUFFER, location.x)),
                location.y
            );
            printf("Neue Mausposition: (%f, %f)\n", newLocation.x, newLocation.y);
            CGEventRef moveEvent = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, newLocation, kCGMouseButtonLeft);
            CGEventPost(kCGHIDEventTap, moveEvent);
            CFRelease(moveEvent);
        }

        usleep(1000); // Warte 1ms vor dem nächsten Check
    }

    return NULL;
}

int main(void) {
    pthread_t thread;
    if (pthread_create(&thread, NULL, checkMousePosition, NULL)) {
        fprintf(stderr, "Fehler beim Erstellen des Threads\n");
        return 1;
    }

    pthread_join(thread, NULL);

    return 0;
}