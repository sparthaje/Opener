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
    let showPanel: Bool
    let keybinds: [String: String]

    func matchesHotkey(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        return keyCode == hotkeyKeyCode && flags.intersection(Self.relevantModifiers) == modifierFlags
    }

    static func load() -> Settings {
        let path = settingsPath

        if !FileManager.default.fileExists(atPath: path) {
            try? "command-shift:2\nfalse\n9:.opener_settings"
                .write(toFile: path, atomically: true, encoding: .utf8)
        }

        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return Settings(modifierFlags: [.maskCommand, .maskShift], hotkeyKeyCode: 19,
                            showPanel: true, keybinds: [:])
        }

        let lines = content.components(separatedBy: "\n")
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        var modFlags: CGEventFlags = [.maskCommand, .maskShift]
        var keyCode: UInt16 = 19
        var showPanel = true
        var keybinds: [String: String] = [:]
        var hotkeyParsed = false
        var clearParsed = false

        for line in lines {
            if !clearParsed && (line == "true" || line == "false") {
                showPanel = (line == "false")
                clearParsed = true
                continue
            }

            guard let colonIdx = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colonIdx])
            let value = String(line[line.index(after: colonIdx)...])

            if !hotkeyParsed && key.count > 1 {
                if let flags = modifierMap[key], let kc = letterToKeyCode[value] {
                    modFlags = flags
                    keyCode = kc
                }
                hotkeyParsed = true
                continue
            }

            if key.count == 1 {
                keybinds[key] = (value == ".opener_settings") ? path : value
            }
        }

        return Settings(modifierFlags: modFlags, hotkeyKeyCode: keyCode,
                        showPanel: showPanel, keybinds: keybinds)
    }
}

// MARK: - Overlay Panel

final class OverlayPanel: NSPanel {
    init(keybinds: [String: String]) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered, defer: false
        )

        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 360))
        let font = NSFont(name: "Avenir-Book", size: 19) ?? .systemFont(ofSize: 19)

        let leftLabel = NSTextField(frame: NSRect(x: 20, y: 0, width: 220, height: 360))
        let rightLabel = NSTextField(frame: NSRect(x: 240, y: 0, width: 220, height: 360))

        for label in [leftLabel, rightLabel] {
            label.isEditable = false
            label.isBordered = false
            label.drawsBackground = false
            label.font = font
        }

        var leftLines: [String] = []
        var rightLines: [String] = []
        for (i, entry) in keybinds.sorted(by: { $0.key < $1.key }).enumerated() {
            let name = (entry.value as NSString).lastPathComponent
            let line = "\(entry.key)    \(name)"
            if i % 2 == 0 { leftLines.append(line) } else { rightLines.append(line) }
        }

        leftLabel.stringValue = leftLines.joined(separator: "\n")
        rightLabel.stringValue = rightLines.joined(separator: "\n")

        container.addSubview(leftLabel)
        container.addSubview(rightLabel)
        contentView = container
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

// MARK: - App Delegate

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var settings = Settings.load()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var overlayPanel: OverlayPanel?
    private var isListening = false

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

        // Mapped key: open and dismiss
        if let letter = Settings.keyCodeToLetter[keyCode],
           let path = settings.keybinds[letter] {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            exitListeningMode()
            return nil
        }

        // Unmapped key: just dismiss
        exitListeningMode()
        return Unmanaged.passUnretained(event)
    }

    private func enterListeningMode() {
        isListening = true
        guard settings.showPanel else { return }

        NSApplication.shared.activate(ignoringOtherApps: true)
        let panel = OverlayPanel(keybinds: settings.keybinds)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        overlayPanel = panel
    }

    private func exitListeningMode() {
        isListening = false
        overlayPanel?.close()
        overlayPanel = nil
    }
}
