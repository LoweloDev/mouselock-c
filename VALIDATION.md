# Validation status

## Verified

- Builds with Apple Clang, `-Wall -Wextra -Werror` (deprecated IOKit backend
  intentionally exempted from deprecation warnings).
- Clang static analysis reports no findings for the backend.
- Boundary tests cover a centered half-width game window, all four edges,
  excluded title bar, a monitor with negative coordinates, invalid bounds,
  large jumps, and idempotent clamping.
- Exact HID report descriptor matches the connected wired `1d57:fa61` mouse.
- IOHIDSystem parameter connection opens successfully.
- Input Monitoring and event-posting access are granted to the built app.
- First live League trial: exclusive capture succeeded, 28,324 reports were
  processed, 2,068 candidate positions were clamped, 28,494 IOKit posts returned
  success, no posting error was reported, and device close returned success.
- The trial timer stopped capture.
- User confirmed that the first direct HID build worked in windowed mode,
  but failed on switching to borderless. User also reported apparent ~30 Hz
  motion despite 120 Hz display configuration, including on the desktop.
- The helper was terminated after that report; no helper or passive diagnostic
  was left running. No login item or background schedule was installed.
- The game log records successful borderless/windowed transitions and a normal
  user-confirmed game exit, not a crash. Its whole-session average was 192.62
  FPS, with a maximum frame time of 83.98 ms. This does **not** measure desktop
  presentation cadence or exclude stuttering during the short borderless test.

## Revision after the first user trial (offline checks only)

- Integrates/clamps every raw report; a 240 Hz timer submits pure motion.
  Pending motion flushes before buttons/wheel. There is no output timer while
  released and no movement post when the integer position is unchanged.
- Removes the layer-zero-only restriction for game window selection. Actual
  window IDs, layers and bounds were not recorded by the first build, so this
  is a plausible correction, **not a proven diagnosis** of the borderless issue.
- Stops rewriting identical menu/status titles on every 50 ms tick. Permission
  checks are limited to every two seconds; active geometry checks to four per
  second. Foreground state comes from activation notifications.
- Added tests for clamping before batching, immediate reversal after overshoot,
  fractional movement, no duplicate idle output, and geometry changes.
- Static analysis and the warning-clean build pass for the revised backend.
- Revised app is packaged but left stopped. Its new ad-hoc signature may require
  macOS to renew the app's previously approved permissions before another trial.

## Not established by those checks

A successful IOKit return code does not prove correct on-screen cursor
confinement, camera scrolling, or click delivery. Only the user's limited
windowed-mode success has been established in gameplay; neither borderless nor
the revised backend should be called fixed from offline tests alone.

The initial passive comparison showed more HID callbacks than Quartz callbacks,
but queried foreground state in its hot path and used an unvalidated Quartz
timestamp conversion. Its exact latency figures are invalid and must not be
used. The diagnostic now avoids the hot-path foreground query and omits the
unvalidated timestamp subtraction. No fixed Quartz frequency limit is claimed.

## Pending

- User verification of fast edge movements and outside-click prevention.
- Left/right/middle/side buttons, dragging, wheel and keyboard modifiers.
- Camera edge scrolling and focus return with Command-Tab.
- Desktop versus in-game perceived speed; default gain remains provisional.
- Borderless and decorated window geometry, resize, display changes, sleep.
- Routine-use behavior beyond a timed prototype.
- Whether desktop stutter disappears with the helper stopped; process snapshots
  showed load from WindowServer, League client and other apps and cannot assign
  causality. Compare with the revised helper only after a clean baseline.
- User reports dropped or delayed keyboard input on macOS, absent on Windows.
  First establish whether it occurs with the helper off; no keyboard interception
  or setting change has been implemented. User requested this investigation
  after mouse confinement and smoothness are resolved.
