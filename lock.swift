import Cocoa

let BUFFER: CGFloat = 1

func isOutsideScreen(location: NSPoint, screenBounds: NSRect) -> Bool {
    return location.x < screenBounds.origin.x || location.x > screenBounds.maxX - BUFFER || location.y < screenBounds.origin.y || location.y > screenBounds.maxY - BUFFER
}

DispatchQueue.global(qos: .background).async {
    while true {
        let location = NSEvent.mouseLocation
        guard let screen = NSScreen.main else { continue }
        let screenBounds = screen.frame

        print("Mausposition: \(location)")
        print("Bildschirmgrenzen: \(screenBounds)")

        if isOutsideScreen(location: location, screenBounds: screenBounds) {
            let newLocation = NSPoint(
                x: max(screenBounds.minX, min(screenBounds.maxX - BUFFER, location.x)),
                y: max(screenBounds.minY, min(screenBounds.maxY - BUFFER, location.y))
            )
            print("Neue Mausposition: \(newLocation)")
            let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: newLocation, mouseButton: .left)
            moveEvent?.post(tap: .cghidEventTap)
        }

        // Thread.sleep(forTimeInterval: 0.001)
    }
}

RunLoop.main.run() // Startet die Haupt-Event-Schleife