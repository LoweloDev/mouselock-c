# MouseLock C

Keep your mouse inside **League of Legends on macOS**, including clicks, while
the game is in front. MouseLock runs in the menu bar and releases the mouse when
you hold Command or switch to another app.

**Experimental — currently only for the tested wired Attack Shark X3**
(USB `1d57:fa61`, exact supported report format). Wireless receivers and other
mice are not supported. A short windowed/borderless test worked smoothly;
longer play and other setups are not fully validated.

**Known unresolved issue:** the test mouse twice stopped responding and disappeared
from the Mac's USB device list after use. Whether MouseLock caused this is unknown;
quitting did not restore it, and reconnecting only helped the first time. This
release is for troubleshooting/experimentation, not validated for routine play.

**[EZ setup](#ez-setup)** · **[Advanced guide](docs/ADVANCED.md)** ·
**[Test results and limitations](VALIDATION.md)**

## EZ setup

### 1. Download and open

1. Download **[MouseLock-HID-v0.3.0-macos-arm64.zip](https://github.com/LoweloDev/mouselock-c/releases/download/v0.3.0/MouseLock-HID-v0.3.0-macos-arm64.zip)**
   from the [GitHub release](https://github.com/LoweloDev/mouselock-c/releases/tag/v0.3.0).
   Choose the app ZIP under **Assets**, not GitHub's source-code archives.
2. Double-click the ZIP and drag **MouseLock HID.app** into **Applications**.
   Quit any older MouseLock copy first; keep only one installed copy.
3. Open **MouseLock HID.app** from Applications.

This download is for **Apple Silicon (M-series), macOS 12 or newer**. It was
built and tested on macOS 26.6.2; older versions have not been tested. Intel Macs
are not included in this download.

The app is locally signed, **not Apple-notarized**. If macOS blocks it as an
unknown developer, try opening it once, then go to **System Settings → Privacy
& Security → Open Anyway** and confirm only if you trust this download.
See [Apple's instructions](https://support.apple.com/en-gb/102445).

**No window opens.** Look for **HID ○** in the macOS menu bar at the top of the
screen. Always open the app itself, not the executable inside its bundle.
No Terminal, Python or developer tools are needed for this download.
For a local build, use the [Advanced source setup](docs/ADVANCED.md#build-from-source).

### 2. Allow the two macOS permissions

1. Open **System Settings → Privacy & Security → Accessibility**
   (German: **Datenschutz & Sicherheit → Bedienungshilfen**).
2. Add **MouseLock HID.app** with the **+** button and enable its switch.
   In the file picker, press **Command-Shift-G**, paste `/Applications`,
   press Return and select the app. Unlock with Touch ID or your Mac password
   if macOS asks.
3. Repeat in **Privacy & Security → Input Monitoring**
   (German: **Eingabeüberwachung**), enabling the **same app**.
4. Quit MouseLock via **HID → Beenden**, then open it again from Applications.

Accessibility lets MouseLock send the confined mouse input. Input Monitoring
lets it read the physical mouse. MouseLock does not capture keyboard input.
If macOS asks you to quit and reopen the app, do so.

### 3. Play

Start a **Practice Tool** game first and try quick movements and clicks along
all four edges. **Borderless is recommended** for this version; the Dock can
still react to hovering in windowed mode.

MouseLock starts enabled, without a time limit. It captures only while the
actual League match is in front, not the launcher or desktop:

| Menu indicator / action | Meaning |
| --- | --- |
| **HID ●** | The mouse is captured. |
| **HID ○** | The mouse is released: waiting for League, paused, or unable to capture. Open the menu for status. |
| Hold **Command** | Temporarily release the mouse. |
| **Command-Tab** | Switch out of the game and release the mouse. |
| **MouseLock pausieren** | Pause capture. |
| **MouseLock aktivieren** | Enable capture again. |
| **Beenden** | Quit MouseLock. |

The app's menu labels are currently German. After sleep or a session switch,
use **MouseLock aktivieren** to resume. There is no automatic start at login:
open **MouseLock HID.app** before your next session. In Finder, Command-Shift-G
and `/Applications` takes you to it.

## If something does not work

- **HID stays ○ in a match:** Check the menu status, supported wired mouse,
  both permissions, and that capture is enabled. Quit and reopen the app normally.
  A launcher window alone does not activate capture.
- **Permissions are enabled but it still fails after rebuilding:** Follow the
  [Advanced permission troubleshooting](docs/ADVANCED.md#permissions-after-rebuilding).
- **Mouse stops responding:** Hold Command to release it. Use the trackpad to
  choose **HID → Beenden** if needed. Alternatively, open **Activity Monitor**,
  search for `mouselock` and quit/force-quit that process. If the mouse still does
  not respond after the app has stopped, unplug and reconnect its USB cable or
  receiver. This symptom alone does not establish its cause.
- **Movement feels different:** Sensitivity is not calibrated for every setup.
  MouseLock uses a provisional fixed movement scale; it does not change your
  mouse DPI or macOS settings. See `--gain` in the Advanced guide.
- **Missed abilities or champion “teleporting”:** These remain unresolved;
  MouseLock is not a confirmed fix for them.

## Why this approach works differently

The old approach corrected the cursor **after** macOS moved it. At high mouse
polling rates, it could escape or send a click to the desktop before correction;
[the original reports document a practical 250 Hz limit in the tested setup](https://github.com/mxrlkn/mouselock/issues/17).

The new backend takes exclusive control of the supported mouse while League is
in front and bounds movement **before** sending movement and clicks to macOS.
Batched movement output avoids flooding the system, and raised borderless game
windows are recognized. See the [Advanced guide](docs/ADVANCED.md) for the
implementation, commands and evidence behind these changes.
