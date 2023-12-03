#include <ApplicationServices/ApplicationServices.h>
#include <pthread.h>
#include <stdbool.h>

#define BUFFER 1 // Definiert einen Pufferbereich von 1 Pixel

bool isNearRightEdge(CGPoint location, CGRect screenBounds) {
    return location.x > CGRectGetMaxX(screenBounds) - BUFFER;
}

void* checkMousePosition(void* arg) {
    while (true) {
        CGPoint location = CGEventGetLocation(CGEventCreate(NULL));
        CGRect screenBounds = CGDisplayBounds(CGMainDisplayID());

        if (isNearRightEdge(location, screenBounds)) {
            CGPoint newLocation = CGPointMake(CGRectGetMaxX(screenBounds) - BUFFER, location.y);
            CGWarpMouseCursorPosition(newLocation);
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