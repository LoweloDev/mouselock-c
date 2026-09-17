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

## Follow-up trial, 2026-09-17

- User confirms the desktop is smooth again with the helper stopped.
- Rebuilt app's stale TCC code requirements were confirmed in system logs.
  Resetting only its Accessibility and ListenEvent entries, re-adding the app
  in System Settings, and relaunching restored both access states to `0`.
  Merely toggling or re-adding without resetting did not update the old hash.
- Paused helper measured 0.1% CPU in a process snapshot. Active snapshots ranged
  from 2.4% to 6.4%; these are observations, not a controlled performance benchmark.
- Live borderless transition is now recorded: the same game window changed
  from layer **0** to layer **1000**. The old layer-zero filter would reject it.
  The revised helper retained capture and changed bounds from
  `1921,63,3838,2001` to `1921,1,3838,2158`, with decoration changing from on to off.
- The user confirmed the revised trial worked and felt completely smooth.
  Speed remains undecided and needs longer gameplay. This confirms the brief
  windowed/borderless trial, not every click combination or routine use.
- At normal game exit, device release succeeded: 69,331 reports, 12,417 clamped
  candidate positions, 18,330 output posts, zero reported API errors. The helper
  was then terminated; no test or diagnosis process was left running.
- Additional user feedback: the macOS Dock remains hoverable in windowed mode.
  This is a known remaining limitation; borderless is the user's preferred mode.

## Normal play mode, 0.3.0

- User requested that the working helper stay enabled for actual gameplay.
  Normal launch now enables League-only capture without a trial timeout.
- `--paused` keeps manual paused startup available; `--seconds 1..600` preserves
  bounded trials and `--seconds 0` explicitly chooses no timeout.
- The input/output backend, gain, motion batching and geometry are unchanged
  from the successful 0.2.0 trial. Command/focus release, watchdog, sleep pause,
  menu pause/quit and permission checks remain in place. No login item is added.
- Numeric options now reject malformed/non-finite strings rather than allowing
  an invalid duration to parse as unlimited. Invalid durations were checked.
- Build, boundary/motion tests and static analysis passed. Long-session behavior
  remains to be assessed during normal play.

## Additional observations, 2026-09-17

- Launching the unchanged packaged app through Launch Services restored
  `post_access=0`, `listen_access=0` and capture after a direct binary launch
  from the development host returned `post_access=1`. The app's Accessibility
  toggle was already on; no permission setting was changed for this comparison.
- A later passive session/game-delivery comparison counted 169 mouse-button
  downs targeted at League and 169 delivered to its process, with no recorded
  other/unknown targets. Observed motion positions stayed within the game
  window. This supports confinement for the observed intervals, not every
  focus transition or button combination.
- Intermittent champion position jumps and missed ability activations remain
  unresolved. They also occurred while confinement stayed active; tabbing out
  was not a necessary trigger. The last symptom change happened without a
  helper/configuration change. These symptoms must not be claimed as fixed.
- Separate passive keyboard checks observed all ten test R presses/releases
  reaching the game process despite only six reported activations. Process
  delivery does not establish game acceptance. No keyboard interception or
  remapping was added; the diagnostic probes are not part of this repository.

## Not established by those checks

A successful IOKit return code does not prove correct on-screen cursor
confinement, camera scrolling, or click delivery. The user's short revised
windowed/borderless trial succeeded, but routine use, all button combinations,
and mouse-speed equivalence have not been established.

The initial passive comparison showed more HID callbacks than Quartz callbacks,
but queried foreground state in its hot path and used an unvalidated Quartz
timestamp conversion. Its exact latency figures are invalid and must not be
used. The diagnostic now avoids the hot-path foreground query and omits the
unvalidated timestamp subtraction. No fixed Quartz frequency limit is claimed.

## Pending

- Broader regression coverage of fast edge movements and outside-click prevention.
- Left/right/middle/side buttons, dragging, wheel and keyboard modifiers.
- Camera edge scrolling and focus return with Command-Tab.
- Desktop versus in-game perceived speed; default gain remains provisional.
- Geometry during resize/display changes and sleep/resume.
- Longer-session behavior, beyond the successful brief windowed/borderless trial.
- Controlled performance comparison: the revised helper felt smooth, but the
  contribution of individual batching/menu/geometry changes was not isolated.
- Intermittent position jumps and missed ability activations, as noted above.
