//
//  AppDelegate.swift
//  Opener
//
//  Created by Shreepa Parthaje on 3/2/19.
//  Copyright © 2019 https://github.com/sparthaje. All rights reserved.
//

import Cocoa
import Carbon

// MARK: - Settings

struct Settings {
    static let settingsPath = (NSHomeDirectory() as NSString).appendingPathComponent(".opener_settings")

    static let letterToKeyCode: [String: UInt16] = [
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4,
        "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35,
        "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7,
        "y": 16, "z": 6, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22,
        "7": 26, "8": 28, "9": 25, "0": 29, ";": 41, ".": 47
    ]

    static let keyCodeToLetter: [UInt16: String] = {
        Dictionary(uniqueKeysWithValues: letterToKeyCode.map { ($0.value, $0.key) })
    }()

    private static let relevantModifiers: CGEventFlags = [
        .maskCommand, .maskShift, .maskControl, .maskAlternate, .maskSecondaryFn
    ]

    private static let singleModifierMap: [String: CGEventFlags] = [
        "command": .maskCommand,
        "option": .maskAlternate,
        "control": .maskControl,
        "shift": .maskShift,
        "fn": .maskSecondaryFn,
    ]

    private static func parseModifiers(_ key: String) -> CGEventFlags? {
        let parts = key.split(separator: "-").map(String.init)
        var flags: CGEventFlags = []
        for part in parts {
            guard let flag = singleModifierMap[part] else { return nil }
            flags.insert(flag)
        }
        return flags.isEmpty ? nil : flags
    }

    let modifierFlags: CGEventFlags
    let hotkeyKeyCode: UInt16
    let windowChooserModifierFlags: CGEventFlags?
    let windowChooserKeyCode: UInt16?
    let keybinds: [String: String]

    func matchesHotkey(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        return keyCode == hotkeyKeyCode && flags.intersection(Self.relevantModifiers) == modifierFlags
    }

    func matchesWindowChooserHotkey(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard let wcFlags = windowChooserModifierFlags, let wcKeyCode = windowChooserKeyCode else {
            return false
        }
        return keyCode == wcKeyCode && flags.intersection(Self.relevantModifiers) == wcFlags
    }

    static func load() -> Settings {
        let path = settingsPath

        if !FileManager.default.fileExists(atPath: path) {
            try? "command-shift:2\n9:.opener_settings"
                .write(toFile: path, atomically: true, encoding: .utf8)
        }

        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return Settings(modifierFlags: [.maskCommand, .maskShift], hotkeyKeyCode: 19,
                            windowChooserModifierFlags: nil, windowChooserKeyCode: nil,
                            keybinds: [:])
        }

        let lines = content.components(separatedBy: "\n")
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        var modFlags: CGEventFlags = [.maskCommand, .maskShift]
        var keyCode: UInt16 = 19
        var wcModFlags: CGEventFlags? = nil
        var wcKeyCode: UInt16? = nil
        var keybinds: [String: String] = [:]
        var hotkeysParsed = 0

        for line in lines {
            guard let colonIdx = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colonIdx])
            let value = String(line[line.index(after: colonIdx)...])

            if hotkeysParsed < 2 && key.count > 1 {
                if let flags = parseModifiers(key), let kc = letterToKeyCode[value] {
                    if hotkeysParsed == 0 {
                        modFlags = flags
                        keyCode = kc
                    } else {
                        wcModFlags = flags
                        wcKeyCode = kc
                    }
                }
                hotkeysParsed += 1
                continue
            }

            if key.count == 1 {
                keybinds[key] = (value == ".opener_settings") ? path : value
            }
        }

        return Settings(modifierFlags: modFlags, hotkeyKeyCode: keyCode,
                        windowChooserModifierFlags: wcModFlags, windowChooserKeyCode: wcKeyCode,
                        keybinds: keybinds)
    }
}

// MARK: - Input State

enum InputState {
    case idle
    case listening            // single hotkey; waiting for letter
    case windowSelecting      // window-chooser hotkey or 'ui' key; waiting for letter to pick app
    case appChosen(String)    // app picked; waiting for digit to pick window
}

// MARK: - Private API for matching AXUIElement to CGWindowID

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

// MARK: - Event Tap Callback

private func eventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
    return delegate.handleEvent(type: type, event: event)
}

// MARK: - App Delegate

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var settings = Settings.load()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var overlayPanel: WindowOverlayPanel?

    private var inputState: InputState = .idle {
        didSet {
            switch inputState {
            case .appChosen:
                break // overlay shown explicitly at call site
            default:
                overlayPanel?.hideOverlay()
            }
        }
    }

    // Stable window numbering: app path -> (CGWindowID -> assigned number)
    private var windowNumberMap: [String: [CGWindowID: Int]] = [:]
    private var currentWindowList: [(number: Int, title: String, windowID: CGWindowID, pid: pid_t)] = []

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }
        installEventTap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeEventTap()
    }

    private func installEventTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: selfPtr
        ) else {
            print("Failed to create event tap — check Accessibility permissions.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeEventTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        switch inputState {
        case .idle:
            if settings.matchesHotkey(keyCode: keyCode, flags: event.flags) {
                enterListeningMode()
                return nil
            }
            if settings.matchesWindowChooserHotkey(keyCode: keyCode, flags: event.flags) {
                inputState = .windowSelecting
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .listening:
            // Mapped key: check for special values or open app
            if let letter = Settings.keyCodeToLetter[keyCode],
               let value = settings.keybinds[letter] {
                if value == "ui" {
                    inputState = .windowSelecting
                } else if value == "reload" {
                    settings = Settings.load()
                    resetToIdle()
                } else {
                    NSWorkspace.shared.open(URL(fileURLWithPath: value))
                    resetToIdle()
                }
                return nil
            }
            // Unmapped key: just dismiss
            resetToIdle()
            return Unmanaged.passUnretained(event)

        case .windowSelecting:
            // Backspace: go back to listening
            if keyCode == 51 {
                enterListeningMode()
                return nil
            }
            // Mapped key: enumerate windows for that app
            if let letter = Settings.keyCodeToLetter[keyCode],
               let path = settings.keybinds[letter] {
                // Skip special keywords in window-selecting mode
                if path == "ui" || path == "reload" {
                    return nil
                }
                let windows = enumerateWindows(forAppPath: path)
                if windows.isEmpty {
                    // App not running or no windows: open the app
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    resetToIdle()
                } else if windows.count == 1 {
                    // Single window: activate directly
                    currentWindowList = windows
                    activateWindow(number: windows[0].number)
                    resetToIdle()
                } else {
                    // Multiple windows: show overlay, wait for digit
                    inputState = .appChosen(path)
                    currentWindowList = windows
                    showOverlay(forApp: path)
                }
                return nil
            }
            // Unmapped key: dismiss
            resetToIdle()
            return Unmanaged.passUnretained(event)

        case .appChosen(_):
            // Backspace: go back to window selecting
            if keyCode == 51 {
                inputState = .windowSelecting
                return nil
            }
            // Digit 1-9: activate that window
            if let digit = Settings.keyCodeToLetter[keyCode],
               let number = Int(digit),
               number >= 1, number <= 9 {
                activateWindow(number: number)
                resetToIdle()
                return nil
            }
            // Unmapped key: dismiss
            resetToIdle()
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - State Helpers

    private func enterListeningMode() {
        inputState = .listening
    }

    private func resetToIdle() {
        inputState = .idle
    }

    // MARK: - Window Management

    private func findRunningApp(forPath appPath: String) -> NSRunningApplication? {
        let appURL = URL(fileURLWithPath: appPath)
        if let match = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL == appURL }) {
            return match
        }
        if let bundle = Bundle(url: appURL),
           let bundleID = bundle.bundleIdentifier {
            return NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID })
        }
        return nil
    }

    private func enumerateWindows(forAppPath appPath: String) -> [(number: Int, title: String, windowID: CGWindowID, pid: pid_t)] {
        guard let runningApp = findRunningApp(forPath: appPath) else { return [] }
        let pid = runningApp.processIdentifier

        // Enumerate from AX windows — works reliably across all monitors
        let appElement = AXUIElementCreateApplication(pid)
        var axWindowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &axWindowsRef) == .success,
              let axWindows = axWindowsRef as? [AXUIElement] else { return [] }

        // Phase 1: Collect eligible windows (standard, non-minimized)
        struct WindowInfo {
            let windowID: CGWindowID
            let title: String
        }
        var windows: [WindowInfo] = []

        for axWindow in axWindows {
            // Only include standard windows (skip popups, dialogs, panels, devtools)
            var subroleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow, kAXSubroleAttribute as CFString, &subroleRef) == .success,
               let subrole = subroleRef as? String, subrole != "AXStandardWindow" {
                continue
            }

            // Skip minimized windows
            var minimizedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
               let isMinimized = minimizedRef as? Bool, isMinimized {
                continue
            }

            var windowID: CGWindowID = 0
            guard _AXUIElementGetWindow(axWindow, &windowID) == .success else { continue }

            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            let title = (titleRef as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled"

            windows.append(WindowInfo(windowID: windowID, title: title))
        }

        // Phase 2: Assign numbers (1-based), ensuring no duplicates
        let previousMapping = windowNumberMap[appPath] ?? [:]
        let persistedOrder = WindowOrderPersistence.preferredOrder(forApp: appPath)
        var usedNumbers = Set<Int>()
        var newMapping: [CGWindowID: Int] = [:]
        var result: [(number: Int, title: String, windowID: CGWindowID, pid: pid_t)] = []

        // Pass A: assign from previous session mapping (stable within session)
        for win in windows {
            if let num = previousMapping[win.windowID], num >= 1, !usedNumbers.contains(num) {
                usedNumbers.insert(num)
                newMapping[win.windowID] = num
            }
        }

        // Pass B: assign from persisted title order (stable across sessions)
        var usedPersistedTitles = Set<String>()
        for win in windows where newMapping[win.windowID] == nil {
            if let num = persistedOrder[win.title], num >= 1,
               !usedNumbers.contains(num), !usedPersistedTitles.contains(win.title) {
                usedPersistedTitles.insert(win.title)
                usedNumbers.insert(num)
                newMapping[win.windowID] = num
            }
        }

        // Pass C: assign fresh numbers to any remaining
        for win in windows where newMapping[win.windowID] == nil {
            var next = 1
            while usedNumbers.contains(next) { next += 1 }
            usedNumbers.insert(next)
            newMapping[win.windowID] = next
        }

        // Build result
        for win in windows {
            let num = newMapping[win.windowID]!
            result.append((number: num, title: win.title, windowID: win.windowID, pid: pid))
        }

        windowNumberMap[appPath] = newMapping
        result.sort { $0.number < $1.number }
        return result
    }

    private func activateWindow(number: Int) {
        guard let entry = currentWindowList.first(where: { $0.number == number }) else { return }

        let appElement = AXUIElementCreateApplication(entry.pid)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return }

        // Match by CGWindowID via private API
        for axWindow in axWindows {
            var windowID: CGWindowID = 0
            if _AXUIElementGetWindow(axWindow, &windowID) == .success,
               windowID == entry.windowID {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                NSRunningApplication(processIdentifier: entry.pid)?.activate(options: [])
                return
            }
        }

        // Fallback: match by title
        for axWindow in axWindows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            if let axTitle = titleRef as? String, axTitle == entry.title {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                NSRunningApplication(processIdentifier: entry.pid)?.activate(options: [])
                return
            }
        }
    }

    // MARK: - Overlay

    private func showOverlay(forApp appPath: String) {
        if overlayPanel == nil {
            overlayPanel = WindowOverlayPanel()
        }
        overlayPanel?.showOverlay(windows: currentWindowList) { [weak self] newTitleOrder in
            self?.applyReorder(newTitleOrder, forApp: appPath)
        }
    }

    private func applyReorder(_ newTitleOrder: [String], forApp appPath: String) {
        var titleToNumber: [String: Int] = [:]
        for (idx, title) in newTitleOrder.enumerated() {
            titleToNumber[title] = idx + 1
        }

        // Update currentWindowList numbers
        for i in 0..<currentWindowList.count {
            if let newNum = titleToNumber[currentWindowList[i].title] {
                currentWindowList[i].number = newNum
            }
        }
        currentWindowList.sort { $0.number < $1.number }

        // Update in-memory windowNumberMap
        var mapping: [CGWindowID: Int] = [:]
        for entry in currentWindowList {
            mapping[entry.windowID] = entry.number
        }
        windowNumberMap[appPath] = mapping

        // Persist
        WindowOrderPersistence.updateOrder(forApp: appPath, titleToNumber: titleToNumber)
    }
}
