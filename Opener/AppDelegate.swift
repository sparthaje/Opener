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

enum Action {
    case open(path: String)
    case switchSpace(displayUUID: String, index: UInt32)
}

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
        var m = Dictionary(uniqueKeysWithValues: letterToKeyCode.map { ($0.value, $0.key) })
        // Numpad digits dispatch the same as top-row digits.
        let numpad: [UInt16: String] = [
            82: "0", 83: "1", 84: "2", 85: "3", 86: "4",
            87: "5", 88: "6", 89: "7", 91: "8", 92: "9",
        ]
        for (k, v) in numpad { m[k] = v }
        return m
    }()

    private static let relevantModifiers: CGEventFlags = [
        .maskCommand, .maskShift, .maskControl, .maskAlternate, .maskSecondaryFn
    ]

    private static let modifierMap: [String: CGEventFlags] = [
        "command": .maskCommand,
        "option": .maskAlternate,
        "control": .maskControl,
        "shift": .maskShift,
        "fn": .maskSecondaryFn,
        "command-shift": [.maskCommand, .maskShift],
        "command-control": [.maskCommand, .maskControl],
        "option-shift": [.maskAlternate, .maskShift],
        "option-command": [.maskAlternate, .maskCommand],
    ]

    let modifierFlags: CGEventFlags
    let hotkeyKeyCode: UInt16
    let globalBindings: [String: Action]
    let monitorBindings: [String: [String: Action]]   // configID → letter → Action

    func matchesHotkey(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        return keyCode == hotkeyKeyCode && flags.intersection(Self.relevantModifiers) == modifierFlags
    }

    func activeBindings(forConfigID configID: String) -> [String: Action] {
        var merged = globalBindings
        if let perMonitor = monitorBindings[configID] {
            for (k, v) in perMonitor { merged[k] = v }
        }
        return merged
    }

    private static func parseAction(value: String) -> Action {
        // "space:<uuid>:<index>"
        let parts = value.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        if parts.count == 3, parts[0] == "space", let idx = UInt32(parts[2]) {
            return .switchSpace(displayUUID: parts[1], index: idx)
        }
        return .open(path: value)
    }

    static func load() -> Settings {
        let path = settingsPath

        if !FileManager.default.fileExists(atPath: path) {
            try? "command-shift:2\nfalse\n9:.opener_settings"
                .write(toFile: path, atomically: true, encoding: .utf8)
        }

        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return Settings(modifierFlags: [.maskCommand, .maskShift], hotkeyKeyCode: 19,
                            globalBindings: [:], monitorBindings: [:])
        }

        let lines = content.components(separatedBy: "\n")

        var modFlags: CGEventFlags = [.maskCommand, .maskShift]
        var keyCode: UInt16 = 19
        var globalBindings: [String: Action] = [:]
        var monitorBindings: [String: [String: Action]] = [:]
        var hotkeyParsed = false
        var currentSection: String? = nil

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.hasPrefix("[monitor:") && line.hasSuffix("]") {
                let inner = String(line.dropFirst("[monitor:".count).dropLast())
                currentSection = inner
                if monitorBindings[inner] == nil {
                    monitorBindings[inner] = [:]
                }
                continue
            }

            // Globals-only structural lines: hotkey only.
            if currentSection == nil {
                guard let colonIdx = line.firstIndex(of: ":") else { continue }
                let key = String(line[line.startIndex..<colonIdx])
                let value = String(line[line.index(after: colonIdx)...])

                if !hotkeyParsed && key.count > 1 && Self.modifierMap[key] != nil {
                    if let flags = modifierMap[key], let kc = letterToKeyCode[value] {
                        modFlags = flags
                        keyCode = kc
                    }
                    hotkeyParsed = true
                    continue
                }

                if key.count == 1 {
                    let resolved = (value == ".opener_settings") ? path : value
                    globalBindings[key] = parseAction(value: resolved)
                }
            } else {
                guard let colonIdx = line.firstIndex(of: ":") else { continue }
                let key = String(line[line.startIndex..<colonIdx])
                let value = String(line[line.index(after: colonIdx)...])
                if key.count == 1 {
                    monitorBindings[currentSection!]?[key] = parseAction(value: value)
                }
            }
        }

        return Settings(modifierFlags: modFlags, hotkeyKeyCode: keyCode,
                        globalBindings: globalBindings,
                        monitorBindings: monitorBindings)
    }

    /// If `.opener_settings` does not yet contain a `[monitor:<configID>]` section
    /// for the current display layout, append a commented template.
    static func ensureSectionExists(forConfigID configID: String, displayUUIDs: [String]) {
        guard !configID.isEmpty else { return }
        let path = settingsPath
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }

        let header = "[monitor:\(configID)]"
        if content.contains(header) { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStamp = formatter.string(from: Date())

        var lines: [String] = []
        if !content.hasSuffix("\n") { lines.append("") }
        lines.append("")
        lines.append(header)
        lines.append("# Auto-generated \(dateStamp). Format: <letter>:space:<displayUUID>:<index0Based>")
        for (i, uuid) in displayUUIDs.enumerated() {
            lines.append("# Display \(i): \(uuid)")
        }
        for uuid in displayUUIDs {
            lines.append("# 1:space:\(uuid):0")
            lines.append("# 2:space:\(uuid):1")
        }
        lines.append("")

        let appended = content + lines.joined(separator: "\n")
        try? appended.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

// MARK: - Event Tap Callback

private func eventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
    return delegate.handleEvent(type: type, event: event)
}

private func displayReconfigCallback(
    display: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags, userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo = userInfo else { return }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
    DispatchQueue.main.async { delegate.handleDisplayReconfiguration() }
}

// MARK: - App Delegate

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var settings = Settings.load()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isListening = false
    private var issInitialized = false

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

        if iss_init() { issInitialized = true }

        ensureCurrentMonitorSection()
        settings = Settings.load()

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(displayReconfigCallback, selfPtr)

        installEventTap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeEventTap()
        if issInitialized { iss_destroy() }
    }

    fileprivate func handleDisplayReconfiguration() {
        ensureCurrentMonitorSection()
        settings = Settings.load()
    }

    private func ensureCurrentMonitorSection() {
        let configID = MonitorConfig.currentConfigID()
        let uuids = MonitorConfig.currentDisplayUUIDs()
        Settings.ensureSectionExists(forConfigID: configID, displayUUIDs: uuids)
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

        if !isListening {
            if settings.matchesHotkey(keyCode: keyCode, flags: event.flags) {
                enterListeningMode()
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        // Backspace: reload settings and dismiss
        if keyCode == 51 {
            settings = Settings.load()
            exitListeningMode()
            return nil
        }

        let active = settings.activeBindings(forConfigID: MonitorConfig.currentConfigID())

        // Mapped key: dispatch and dismiss
        if let letter = Settings.keyCodeToLetter[keyCode],
           let action = active[letter] {
            perform(action: action)
            exitListeningMode()
            return nil
        }

        // Unmapped key: just dismiss
        exitListeningMode()
        return Unmanaged.passUnretained(event)
    }

    private func perform(action: Action) {
        switch action {
        case .open(let path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .switchSpace(let uuid, let index):
            uuid.withCString { _ = iss_switch_to_space_on_display($0, UInt32(index)) }
        }
    }

    private func enterListeningMode() {
        isListening = true
    }

    private func exitListeningMode() {
        isListening = false
    }
}
