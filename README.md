# Opener

[![Github](http://img.shields.io/badge/github-sparthaje-green.svg?style=flat)](https://github.com/sparthaje)
[![Swift 4.2](https://img.shields.io/badge/swift-4.0.3-orange.svg?style=flat)](https://github.com/apple/swift)
[![Platform](http://img.shields.io/badge/platform-macOS-blue.svg?style=flat)](https://developer.apple.com/macos/)

Opener is a customizable application/file opener utility for macOS. With it, you can map any application or file to two key strokes. The first hotkey makes Opener listen for an input, and the following letter opens the mapped application or file, as seen below.
-

![Video Demonstration](https://raw.githubusercontent.com/sparthaje/Opener/master/Examples/example.gif)
Note: The pop-up window can be disabled in the settings file

-
All the commands can be mapped in a file called `.opener_settings` in the home directory. The first line in this file defines the hot key for the app. The following lines define what application/file to open following the hot key.


# Installation
1. Download the [app](https://github.com/sparthaje/Opener/releases/download/v1.0.0/Opener.zip) from the releases page
2. Move the app into the `/Applications/` directory
3. Open the app
4. Go to Security > Privacy > Accessibility and enable Opener.app
5. Quit the application (double click the Opener.app file and then `⌘Q`) 
6. Re-open the application
7. Edit the configuration file (`⌘⇧2` followed by `9`)

# Configuring .opener_settings

Any line starting with a `#` will be ignored, so it can be used to separate/block off segments.

---

**Line 1 — Listening hotkey (required):** `command-shift:2` by default. This defines the hotkey that activates Opener to listen for an input. The modifier(s) come before the colon and the key comes after.

---

**Line 2 — Window chooser hotkey (optional):** A second hotkey line that goes directly into window-selecting mode, skipping the listening step. For example, `control-command-shift:2` lets you press `⌃⌘⇧2` to immediately pick an app and then a window number.

---

**Key bindings:** Each subsequent line maps a single character to an application path: `key:absolute_file_path`. Some examples:

	n:/Applications/Notes.app
	p:/Applications/PyCharm CE.app
	t:/Applications/iTerm.app
	3:/System/Library/CoreServices/Finder.app
	9:.opener_settings

The special value `.opener_settings` opens the settings file itself for editing.

---

**Special keywords:** Instead of a file path, a key can be bound to a keyword:

- `ui` — enters window-selecting mode from the listening state. Example: `u:ui`
- `reload` — reloads the settings file without restarting the app. Example: `r:reload`

---

**Modifiers** can be any combination of the following, joined by `-` (case-sensitive):

	command
	option
	control
	shift
	fn

Examples: `command-shift`, `control-command-shift`, `option-command`, `fn`

**Available keys** (case-sensitive):

	a b c d e f g h i j k l m n o p q r s t u v w x y z
	1 2 3 4 5 6 7 8 9 0 ; .
