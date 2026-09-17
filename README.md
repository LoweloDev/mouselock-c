# MouseLock C

Keep your mouse inside **League of Legends on macOS**, including clicks, while
the game is in front. MouseLock runs in the menu bar and releases the mouse when
you hold Command or switch to another app.

**Experimental — currently only for the tested wired Attack Shark X3**
(USB `1d57:fa61`, exact supported report format). Wireless receivers and other
mice are not supported. A short windowed/borderless test worked smoothly;
longer play and other setups are not fully validated.

**[EZ setup](#ez-setup)** · **[Advanced guide](docs/ADVANCED.md)** ·
**[Test results and limitations](VALIDATION.md)**

## EZ setup

There is no ready-made app download yet. These steps build the app on your Mac;
you can copy and paste the commands without editing code. You only need to do
this setup once, then open the app normally before playing.

### 1. Prepare your Mac

Connect the supported mouse **by USB cable**. Open **Terminal** using Spotlight
(Command-Space, type `Terminal`, press Return).

Install Apple's Command Line Tools:

```sh
xcode-select --install
```

Complete the installation dialog before continuing. If Terminal says the tools
are already installed, continue. Full Xcode is not required.

Check that Python 3 is available:

```sh
python3 --version
```

If this prints `Python 3.x.x`, continue. If it is missing, install Python 3 using
the [official macOS installer](https://www.python.org/downloads/macos/), reopen
Terminal and check again.

### 2. Build the app

Copy this whole block into Terminal and press Return. Wait for it to finish:

```sh
git clone https://github.com/LoweloDev/mouselock-c.git "$HOME/Downloads/mouselock-c" &&
cd "$HOME/Downloads/mouselock-c" &&
mkdir -p "$HOME/Applications" &&
python3 build_app.py "$HOME/Applications/MouseLock HID.app"
```

The build runs its checks and creates **MouseLock HID.app** in your user
Applications folder. If a command fails, stop and check its error before
continuing. If `mouselock-c` already exists in Downloads, use the
[update instructions](docs/ADVANCED.md#updating-an-existing-installation).

Open the app:

```sh
open -a "$HOME/Applications/MouseLock HID.app"
```

**No window opens.** Look for **HID ○** in the macOS menu bar at the top of the
screen. Always open the app itself, not the executable inside its bundle.

### 3. Allow the two macOS permissions

1. Open **System Settings → Privacy & Security → Accessibility**
   (German: **Datenschutz & Sicherheit → Bedienungshilfen**).
2. Add **MouseLock HID.app** with the **+** button and enable its switch.
   In the file picker, press **Command-Shift-G**, paste `~/Applications`,
   press Return and select the app. Unlock with Touch ID or your Mac password
   if macOS asks.
3. Repeat in **Privacy & Security → Input Monitoring**
   (German: **Eingabeüberwachung**), enabling the **same app**.
4. Quit MouseLock via **HID → Beenden**, then open it again with the command above.

Accessibility lets MouseLock send the confined mouse input. Input Monitoring
lets it read the physical mouse. MouseLock does not capture keyboard input.
If macOS asks you to quit and reopen the app, do so.

### 4. Play

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
and `~/Applications` takes you to it.

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
