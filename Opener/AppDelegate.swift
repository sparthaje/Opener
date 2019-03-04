//
//  AppDelegate.swift
//  Opener
//
//  Created by Shreepa Parthaje on 3/2/19.
//  Copyright © 2019 https://github.com/sparthaje. All rights reserved.
//

import Cocoa
import Carbon

let letterToKey = [
    "a": 0,
    "b": 11,
    "c": 8,
    "d": 2,
    "e": 14,
    "f": 3,
    "g": 5,
    "h": 4,
    "i": 34,
    "j": 38,
    "k": 40,
    "l": 37,
    "m": 46,
    "n": 45,
    "o": 31,
    "p": 35,
    "q": 12,
    "r": 15,
    "s": 1,
    "t": 17,
    "u": 32,
    "v": 9,
    "w": 13,
    "x": 7,
    "y": 16,
    "z": 6,
    "1": 18,
    "2": 19,
    "3": 20,
    "4": 21,
    "5": 23,
    "6": 22,
    "7": 26,
    "8": 28,
    "9": 25,
    "0": 29,
    ";": 41,
    ".": 47
]

let keyToLetter: [UInt16:String] = [
    0: "a",
    11: "b",
    8: "c",
    2: "d",
    14: "e",
    3: "f",
    5: "g",
    4: "h",
    34: "i",
    38: "j",
    40: "k",
    37: "l",
    46: "m",
    45: "n",
    31: "o",
    35: "p",
    12: "q",
    15: "r",
    1: "s",
    17: "t",
    32: "u",
    9: "v",
    13: "w",
    7: "x",
    16: "y",
    6: "z",
    18: "1",
    19: "2",
    20: "3",
    21: "4",
    23: "5",
    22: "6",
    26: "7",
    28: "8",
    25: "9",
    29: "0",
    41: ";",
    47: "."
]

let modifiersToFlag = [
    "command": 1048840,
    "option": 524576,
    "control": 262401,
    "shift": 131330,
    "fn": 8388864,
    "command-shift":1179914,
    "command-control":1310985,
    "option-shift":655650,
    "option-command":1573160
]

var waitForNextLetter = false

var windows: [NSWindow] = []

// SETTINGS

var flagname = "command-shift"
var hotkey = "2"
var letterToPath: [String:String] = [:]
var clear = false

func loadSettings() {
    let file = "/Users/" + NSUserName() + "/.opener_settings"
    let fileURL = URL(fileURLWithPath: file)
    let fileManager = FileManager.default
    
    if !fileManager.fileExists(atPath: file) {
        let contents = "command-shift:2\nfalse\n9:.opener_settings"
        try! contents.write(to: fileURL, atomically: true, encoding: String.Encoding.utf8)
    }
    
    do {
        let content = try String(contentsOf: fileURL, encoding: .utf8).components(separatedBy: "\n")
        for line in content {
            if line.first! != "#" {
                let arguments = line.components(separatedBy: ":")
                if arguments[0] == "true" {
                    clear = true
                    continue
                }
                if arguments[0] == "false" {
                    clear = false
                    continue
                }
                if arguments[0].count > 1 {
                    flagname = arguments[0]
                    hotkey = arguments[1]
                    continue
                }
                if arguments[1] == ".opener_settings" {
                    letterToPath[arguments[0]] = file
                    continue
                }
                letterToPath[arguments[0]] = arguments[1]
            }
        }
    }
    catch {
        print(error)
    }
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    func hideTitleBar(window: NSWindow!) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true;
        window.isMovableByWindowBackground  = true
        window.standardWindowButton(.closeButton)!.isHidden = true
        window.standardWindowButton(.miniaturizeButton)!.isHidden = true
        window.standardWindowButton(.zoomButton)!.isHidden = true
    }
    
    func makeClear(window: NSWindow!) {
        window.isOpaque = false
        window.backgroundColor = .clear
    }
    
    func handler(event: NSEvent!) {
        
        let key = event.keyCode
        let flag = event.modifierFlags.rawValue
        
        if key == letterToKey[hotkey]! && flag == modifiersToFlag[flagname]! {
            waitForNextLetter = true
            // CGEventTap
            NSApplication.shared.activate(ignoringOtherApps: true)
            
            let window = NSWindow(contentViewController: ClearPanelController())
            window.level = .floating
            window.display()
            window.makeKey()
            window.orderFrontRegardless()
            
            hideTitleBar(window: window)
            
            if clear {
                makeClear(window: window)
            }
            
            windows.append(window)
        }
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let options = NSDictionary(object: kCFBooleanTrue, forKey: kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString) as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if (trusted) {
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: self.handler)
        }
        
        loadSettings()
    }
    
}

