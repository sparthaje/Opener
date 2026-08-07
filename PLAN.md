# Generic Per-Monitor Application Routing

## Summary

Extend Opener so ordinary application bindings prefer an existing window on the display containing the focused window. Add an explicit, rebindable monitor-selection action that displays deterministic numbered badges only on monitors where the chosen application has an eligible window.

Example configuration:

```text
command-shift:2

m:monitor-select
a:/Applications/App A.app
b:/Applications/App B.app
c:/Applications/App C.app
```

## Implementation Changes

### Window discovery and routing

- Replace direct `NSWorkspace.open` dispatch for application bundles with window-aware routing.
- Snapshot the focused display when the Opener leader key is pressed:
  - Use the frontmost application's AX focused window.
  - Assign it to the display containing the largest portion of its frame.
  - Fall back to the display under the pointer if no focused window is available.
- Enumerate the selected application's standard, non-minimized windows using Accessibility APIs.
- Match AX windows to the on-screen Core Graphics window list to obtain display placement and front-to-back order.
- Consider only windows in the currently visible Space on each display.
- Assign spanning windows to the display containing the greatest portion of their area, using the window center and display UUID as deterministic tie-breakers.
- Activate an exact selected window by unhiding its application, making it main/focused where supported, performing the AX raise action, and activating the owning process.

For a normal `opener → app-key` binding:

1. If an eligible window exists on the focused display, raise the frontmost window for that app on that display.
2. Otherwise, if the app exists on exactly one eligible display, raise its frontmost window there.
3. Otherwise, use the app's most-recently-used eligible window, represented by the first matching window in the current Core Graphics z-order.
4. If no eligible window exists, preserve existing behavior and launch/open the application with `NSWorkspace`; do not relocate the newly created window.

Non-application file bindings and Space actions retain their existing behavior.

### Monitor-selection state and preferences

- Add `Action.monitorSelect`, parsed when a binding value is exactly `monitor-select`.
- Replace the Boolean listening flag with explicit states:
  - idle
  - waiting for a normal binding
  - waiting for an application after `monitor-select`
  - waiting for a numbered monitor
- `opener → m → app-key` must:
  1. Resolve the app binding.
  2. Enumerate its eligible windows.
  3. Build the monitor-number mapping.
  4. Display badges and wait for a number key.
- If the app has no eligible window, dismiss selection and launch it normally.
- Escape, Backspace, or an invalid selection dismisses the overlays and returns to idle.
- Only number-key selection is supported; badges are not clickable.
- Reloading preferences must recognize a newly rebound `monitor-select` key without restarting.

### Deterministic monitor numbering and overlay

- Number all attached displays before filtering for application availability:
  - The snapshotted focused display is always `1`.
  - Sort remaining displays left-to-right, then top-to-bottom.
  - Use display UUID as the final tie-breaker.
- Render a badge only when the selected app has an eligible window on that display.
- Preserve gaps. If displays 1 and 3 contain the app, show `1` and `3`; do not renumber display 3 to `2`.
- If the focused display has no eligible app window, badge `1` remains hidden while other displays retain their assigned numbers.
- Add a lightweight overlay manager that creates one centered, borderless, non-activating panel per eligible display.
- Panels must not steal focus and should use `.canJoinAllSpaces` and `.fullScreenAuxiliary`.
- Update the direct `swiftc` build script to compile the new overlay source.
- Document `monitor-select`, direct-routing precedence, visible-Space scope, numbering gaps, and cancellation behavior in the README.

## Test Plan

- Build successfully with `./build.sh` without using `xcodebuild`.
- Verify the core example:
  - Monitor 1 focused: A foreground, B background.
  - Monitor 2: B foreground, C background.
  - `opener → a` focuses A on monitor 1.
  - `opener → c` focuses C on monitor 2.
  - `opener → b` focuses B on monitor 1.
- Verify direct-routing precedence:
  - App only on one non-focused monitor.
  - App on the focused monitor and other monitors.
  - App on multiple non-focused monitors, selecting its z-order MRU window.
  - App not running or without eligible windows, launching normally.
  - Multiple windows for the same app on one display, selecting its frontmost window.
- Verify explicit selection:
  - `opener → m → b` shows badges on all and only displays containing B.
  - Pressing a displayed number focuses B on that display.
  - Pressing a hidden/invalid number dismisses without activating a window.
  - Rebinding `monitor-select` in preferences works after reload.
- Verify deterministic numbering:
  - Ten repeated invocations with unchanged focus and monitor configuration produce identical labels.
  - Changing the focused monitor moves label `1` to that monitor.
  - Three-monitor layouts retain numbering gaps when an app is absent from a display.
  - Horizontal, vertical, and mixed monitor arrangements sort consistently.
- Verify exclusions and resilience:
  - Minimized, dialog, panel, and other-Space windows do not make a display eligible.
  - A spanning window is assigned consistently.
  - Overlays do not change the frontmost application or focused display.
  - Disconnecting a display during selection safely cancels or recomputes without crashing.
  - Existing app, file, Space, per-monitor, numpad, reload, and unmapped-key bindings continue working.

## Assumptions and Defaults

- “Focused monitor” means the display containing the focused window, snapshotted when the leader key is pressed.
- The monitor picker chooses a monitor, not an individual window; the frontmost eligible app window on that monitor is selected.
- Window MRU is derived from current Core Graphics z-order and is not persisted.
- Only visible-Space, standard, non-minimized windows are eligible.
- Number selection supports displays numbered `1` through `9`, matching Opener's single-key input model.
- The existing Accessibility permission is sufficient for discovery and activation.
- The reverted window-management commits may be used as reference for AX enumeration and exact-window activation, but their draggable window-order overlay and persistence format should not be restored.

## Follow-up Changes

- Resolve the focused display from the system-wide AX focused application first, with the frontmost application's Core Graphics window as an additional fallback before pointer location.
- Activate only the selected application's front window so sibling windows on other monitors remain behind.
- Render monitor numbers on a fully transparent panel with no badge background.
- Parse the exact binding value `quit` as an action that terminates Opener.
- Automatically terminate after macOS presents the first-run Accessibility permission prompt; the user reopens Opener after granting access.
