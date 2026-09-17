# MouseLock C — experimental direct HID backend

This branch preserves the original 2023 `main.c` experiments and adds a new,
opt-in backend in `src/hid_guard.m` for the League of Legends Mac cursor escape
problem. It is an **experimental backend with a successful short physical
gameplay test**, not a broadly validated release. The first build worked in
windowed mode but failed in borderless and was accompanied by reported stutter.
On 2026-09-17, the user confirmed the revised build worked through the borderless
test and felt smooth. Longer gameplay, speed calibration and other hardware
remain unverified. See `VALIDATION.md` for the observations and limits.

## Why this backend

The original Quartz event-tap/polling attempts corrected cursor movement after
observing it; they did not confine button events together with movement. A click
could therefore reach the desktop before the correction. The polling version on
`main` also checks only the main display's horizontal limits, not all four edges
of the actual game window. Faster polling does not make that sequence atomic;
the high-level approach also has a documented practical polling-rate limit in
the tested setup: [LoweloDev's upstream report](https://github.com/mxrlkn/mouselock/issues/17)
identifies 250 Hz as the highest stable mouse polling rate, with jitter/jumps
above it. [The implementation experiments](https://github.com/mxrlkn/mouselock/issues/17#issuecomment-1837467796)
describe jitter from continuous repositioning and escape/sticking with edge-only
correction; [another user](https://github.com/mxrlkn/mouselock/issues/17#issuecomment-1951406468)
later confirmed the above-250-Hz failure on a Superlight 2. This is evidence for
that approach and tested hardware, rather than a universal API callback ceiling.
The new backend:

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
- Opening the menu app enables it for League **without a time limit**. Use the
  `HID` menu to pause or quit, or launch with `--paused`. An optional trial limit
  is available with `--seconds 1..600`; `--seconds 0` means unlimited. A trial
  timer starts at activation, including time spent waiting for League. Command
  releases the mouse; Command-Tab remains available. A separate watchdog thread
  exits the process if its input/UI loop stalls for over two seconds, so the OS
  closes the exclusive device handle. A force quit also closes it.
- After sleep or session deactivation it pauses; re-enable it in the `HID` menu.
  It does not start at login. Reopening the app after quitting enables it again.
  A second running app instance is refused to avoid competing device capture.
- Accessibility (event posting) and Input Monitoring (physical mouse input) are
  required. The program checks these permissions and never changes them itself.
- No kernel extension, driver installation, firmware writes, login item,
  keyboard capture, or network connection.

## Build and test

```sh
make all test
./build/mouselock --check
./build/mouselock                     # enabled for League, no time limit
./build/mouselock --paused            # paused menu-bar app
./build/mouselock --arm --seconds 60   # controlled trial
./build/mouselock --arm --gain 0.683 --seconds 60
```

For a separately attributed macOS permission entry, build a menu-bar app:

```sh
python3 build_app.py /absolute/output/path/MouseLock\ HID.app
```

Launch the packaged app through Finder or Launch Services so macOS evaluates
the app's own permission entry:

```sh
open -a /absolute/output/path/MouseLock\ HID.app
# Optional: capture startup/access/capture diagnostics (absolute log paths).
open -a /absolute/output/path/MouseLock\ HID.app \
  --stdout /absolute/path/mouselock.log --stderr /absolute/path/mouselock-error.log \
  --args --arm --seconds 0
```

Quit an existing instance before changing its launch route; opening an already
running app does not restart it. In a live test, directly executing the bundle's
`Contents/MacOS/mouselock` from the development host returned `post_access=1`
despite the app's enabled Accessibility entry. Launching the unchanged bundle
through Launch Services returned both access states as `0` and immediately
captured the foreground game. Check the launch route before resetting TCC.
A running process or the startup `mode=enabled` message alone does not prove
active capture: confirm granted access and a `captured bounds=...` log entry
while League is in front. Switching away from League normally releases capture.

Local ad-hoc rebuilds change the code hash. In testing, toggling an old enabled
permission entry or adding the updated app again did **not** replace its old
code requirement. If the app still reports denied access after a rebuild, quit
it, reset only its two entries, and re-add that exact app in System Settings →
Privacy & Security → Accessibility and Input Monitoring:

```sh
tccutil reset Accessibility dev.lowelodev.mouselock-hid
tccutil reset ListenEvent dev.lowelodev.mouselock-hid
```

These commands revoke the old entries; they do not grant access. Do not reset
all applications. Relaunch the app afterward and verify both reported access
states are `0` before activating a trial.

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
