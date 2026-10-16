# Opener

[![Github](http://img.shields.io/badge/github-sparthaje-green.svg?style=flat)](https://github.com/sparthaje)
[![Swift 4.2](https://img.shields.io/badge/swift-4.0.3-orange.svg?style=flat)](https://github.com/apple/swift)
[![Platform](http://img.shields.io/badge/platform-macOS-blue.svg?style=flat)](https://developer.apple.com/macos/)

Opener is a customizable application/file opener utility for macOS. With it, you can map any application or file to two key strokes. The first hotkey makes Opener listen for an input, and the following letter opens the mapped application or file, as seen below.

-

![Video Demonstration](https://raw.githubusercontent.com/sparthaje/Opener/master/Examples/example.gif)
Note: the pop-up window shown in the GIF has been removed — Opener now listens silently.

-
All the commands can be mapped in a file called `.opener_settings` in the home directory. The first line in this file defines the hot key for the app. The following lines define what application/file to open following the hot key.

# Installation
1. Download the [app](https://github.com/sparthaje/Opener/releases/download/v1.0.0/Opener.zip) from the releases page
2. Move the app into the `/Applications/` directory
3. Open the app
4. Go to Security > Privacy > Accessibility and enable Opener.app
5. Opener automatically quits after showing the first Accessibility prompt
6. Re-open the application after granting permission
7. Edit the configuration file (`⌘⇧2` followed by `9`)

# Configuring .opener_settings

Any line starting with a `#` will be ignored, so it can be used to separate/block off segments

---

The first line is `command-shift:2` by default. This defines the hot key that activates Opener. The `command-shift` is the modifier and the `2` is the key. All the modifiers and keys are listed at the bottom of the README.md.

---

`9:.opener_settings` is the default binding for opening the settings file itself. Only change the key value before the colon. All the modifiers and keys are listed at the bottom of the README.md.

---

The following lines define what key will map to which application. The general format for this is `key:absolute_file_path`. Some examples are listed below:

	n:/Applications/Notes.app
	p:/Applications/PyCharm CE.app
	t:/Applications/iTerm.app
	3:/System/Library/CoreServices/Finder.app

---

## Application routing by monitor

Application bindings prefer a window on the monitor that was focused when the Opener hotkey was pressed. Opener snapshots that monitor from the frontmost application's focused window (or from the pointer if no focused window is available), then routes in this order:

1. The application's frontmost eligible window on the focused monitor.
2. Its frontmost window on the only monitor where it has an eligible window.
3. Its most-recently-used eligible window across all monitors, using the current macOS front-to-back window order.
4. If no eligible window exists, launch/open the application normally.

An eligible window is a standard, non-minimized window visible in the current Mission Control Space on its monitor. Dialogs, panels, minimized windows, and windows in other Spaces are ignored. A window spanning monitors belongs to the monitor containing the largest part of it; deterministic center and display-UUID tie-breakers handle exact splits.

File bindings still open normally, and Opener does not move a newly launched application's window.

## Selecting an application's monitor

Bind the exact value `monitor-select` to any key, then follow it with an application binding and a monitor number:

	command-shift:2

	m:monitor-select
	a:/Applications/App A.app
	b:/Applications/App B.app
	c:/Applications/App C.app

For example, `⌘⇧2`, then `m`, then `b` displays centered number badges on all and only the monitors containing an eligible App B window. Pressing a displayed number raises App B's frontmost window on that monitor. Badges are keyboard-only and never take focus.

Numbering is fixed for the current monitor arrangement: the macOS main display (the display configured as primary in System Settings) is always `1`, regardless of which monitor is focused. The remaining attached monitors are ordered left-to-right, then top-to-bottom, with display UUID as the final tie-breaker. All monitors are numbered before unavailable ones are hidden, so gaps remain. If App B exists on monitors 1 and 3 but not 2, the visible badges are `1` and `3`.

Monitor selection supports the single number keys `1` through `9`, including their numpad equivalents. Escape, Backspace, an undisplayed number, or any other invalid key cancels selection. If the application has no eligible window, Opener dismisses selection and launches it normally. Disconnecting a display while badges are visible safely cancels the selection.

Because `monitor-select` is an ordinary binding value, it can be rebound globally or inside a per-monitor section. Reload preferences with the Opener hotkey followed by Backspace; the new picker binding takes effect immediately.

---

## Quitting Opener

Bind the exact value `quit` to any key to terminate Opener without using Activity Monitor or relaunching its app bundle:

	q:quit

For example, with that binding, press the Opener hotkey followed by `q`.

---

## Switching Mission Control spaces

A binding can also jump to a specific Mission Control space on a specific monitor. Format:

	letter:space:<displayUUID>:<index0Based>

Example:

	1:space:51CD4EB6-A648-4F66-87AD-F48E592DD496:0
	2:space:51CD4EB6-A648-4F66-87AD-F48E592DD496:1

The space-switching engine is vendored from [knollet/InstantSpaceSwitcher](https://github.com/knollet/InstantSpaceSwitcher) (sources under `Opener/ISS/`). It posts synthetic Dock-swipe `CGEvent`s to jump directly to the target space with no slide animation. The standalone tool always operates on the display under the cursor; Opener wraps it so a binding can name a specific display by UUID, briefly warping the cursor to that display while the gesture is posted.

## Per-monitor sections

Because the same hotkey often means different things on different setups (laptop alone vs. laptop + external display vs. dock), bindings can be scoped to a **monitor configuration** — the sorted, `+`-joined list of all attached displays' UUIDs. Sections look like:

	[monitor:<configID>]
	1:space:<displayUUID>:0
	2:space:<displayUUID>:1

Bindings inside a section apply only when the current configuration matches; they shadow globals for the same letter. The first time Opener boots into a configuration it has not seen, it appends a commented template section to `.opener_settings` — uncomment lines to enable. Plugging or unplugging a display does the same thing live (no restart required).

To find a display's UUID, attach the monitor and look at the auto-generated `[monitor:...]` header.

---

The app must be reloaded to see changes (the hot key (`⌘⇧2` by default) followed by a `delete`).

---

Available Modifiers (case-sensitive):

	command
	option
	control
	shift
	fn
	command-shift
	command-control
	option-shift
	option-command
	
Available Keys (case-sensitive):

	a b c d e f g h i j k l m n o p q r s t u v w x y z
	1 2 3 4 5 6 7 8 9 0 ; .

Numeric keys also dispatch from the numpad — pressing numpad `5` resolves to letter `5`.
