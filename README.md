# MouseLock C — experimental direct HID backend

This branch preserves the original 2023 `main.c` experiments and adds a new,
opt-in backend in `src/hid_guard.m` for the League of Legends Mac cursor escape
problem. It is **not yet a verified fix**. The first physical test worked in
windowed mode, failed after switching to borderless, and was accompanied by
reported desktop/game stutter. The revised code below has passed offline tests
but has not yet had its next physical gameplay test.

## Why this backend

The original attempts received too few high-level movement events to reliably
pull the cursor back before a click escaped. Increasing a polling loop rate does
not remove that race. The new backend:

1. Opens only the supported gaming mouse with `kIOHIDOptionsTypeSeizeDevice`,
   and only while the actual League game process is foreground.
2. Decodes each hardware input report, accumulates a linear cursor position,
   and clamps it to the game window **before** submitting any input.
3. Sends movement, five buttons and two wheel axes through
   `IOHIDPostEvent` / `IOHIDSystem`, with absolute bounded coordinates.
4. Returns the physical mouse on Command, application switch, pause, timeout,
   sleep, logout notification, or termination.

There is **no Quartz event tap, CGEventPost, or CGWarpMouseCursorPosition** in
this backend. Quartz is only used to read the initial cursor position and window
geometry. Cocoa provides the menu and foreground-app notifications.

Every incoming movement is integrated and clamped, including reversals at an
edge. Pure motion is submitted by a 240 Hz timer rather than once per report;
actual timer delivery depends on scheduling. Button and wheel changes flush
pending motion immediately before their event. This reduces output traffic
without returning the original hardware stream to normal cursor processing.
There is no motion-output timer while the device is released. Unchanged status
titles are not rewritten; permissions and geometry are no longer queried on
every control-loop tick.

## Current scope and limits

- Initially supports the **wired Attack Shark X3**, USB `1d57:fa61`, and only its
  exact verified seven-byte, no-report-ID descriptor. Other devices are refused
  before capture. Keyboard and trackpad are not seized.
- `IOHIDPostEvent` has been deprecated since macOS 11. Opening its connection
  succeeds on the development Mac; successful event delivery and gameplay still
  require live verification. It is deliberately isolated as an experiment.
- The stronger `IOHIDSetCursorBounds` interface requires Apple's privileged HID
  server connection. Opening that connection failed locally; the ordinary
  parameter connection must **not** be passed to that function (selector 6 has
  a different meaning on it).
- Default linear gain `0.683` is a provisional value estimated from this mouse's
  desktop input, not a universal conversion from League's sensitivity slider.
  DPI and macOS settings are not modified. Use `--gain` for controlled tests.
- In decorated League windows a 32-point title bar is excluded. Other window
  decorations/scaling require validation. The current actual window dimensions
  determine the rectangle, not the saved game resolution. The selection accepts
  raised window levels belonging to the actual game process. Decoration still
  uses `WindowMode` from `game.cfg`, which can lag a live mode change; title-bar
  exclusion and camera edge scrolling therefore remain unverified. Window ID,
  layer and bounds are logged on changes for the next borderless trial.
- Genuine gameplay, camera edge scrolling, modifier-clicks, additional buttons,
  scroll direction and rapid focus changes must be checked before routine use.
- The menu app starts paused. Each activation defaults to a 60-second limit,
  configurable with `--seconds`. The timer starts at activation, including time
  spent waiting for League. Command
  releases the mouse; Command-Tab remains available. A separate watchdog thread
  exits the process if its input/UI loop stalls for over two seconds, so the OS
  closes the exclusive device handle. A force quit also closes it.
- Accessibility (event posting) and Input Monitoring (physical mouse input) are
  required. The program checks these permissions and never changes them itself.
- No kernel extension, driver installation, firmware writes, login item,
  keyboard capture, or network connection.

## Build and test

```sh
make all test
./build/mouselock --check
./build/mouselock                     # paused menu-bar app
./build/mouselock --arm --seconds 60   # controlled trial
./build/mouselock --arm --gain 0.683 --seconds 60
```

`--check` only inspects supported hardware and whether the IOHIDSystem parameter
connection opens. It does not seize the mouse or post events. Its output also
includes the permission states (`0` granted, `1` denied, `2` unknown).

`build/mouse-diagnose 120` is a separate passive diagnostic: mouse-only HID input
and a **listen-only** Quartz tap are counted for comparison. It cannot lock the
cursor. It logs aggregated rates/deltas, never key contents. Intervals below
100 ms exclude idle gaps; callback counts are not a certified device polling
rate. Context changes and observer overhead must be considered. Quartz timestamp
ages are not reported because the clock domains were not validated.

## Primary references

- [IOHIDDeviceOpen](https://developer.apple.com/documentation/iokit/1588670-iohiddeviceopen)
- [Exclusive device access](https://developer.apple.com/documentation/iokit/1556660-anonymous/kiohidoptionstypeseizedevice)
- [Apple IOHIDSystem source](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDSystem/IOHIDSystem.cpp)
- [Apple user-client dispatch and entitlement checks](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDSystem/IOHIDUserClient.cpp)
- [Apple IOHIDLib implementation](https://github.com/apple-oss-distributions/IOKitUser/blob/main/hidsystem.subproj/IOHIDLib.c)
