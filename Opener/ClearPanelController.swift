//
//  ClearPanelController.swift
//  Opener
//
//  Created by Shreepa Parthaje on 3/2/19.
//  Copyright © 2019 https://github.com/sparthaje. All rights reserved.
//

import Cocoa

class ClearPanelController: NSViewController {

    @IBOutlet var leftPane: NSTextField!
    @IBOutlet var rightPane: NSTextField!
    
    func handler(event: NSEvent!) -> NSEvent? {
        
        let key = event.keyCode
        
        if key == 51 {
            loadSettings()
            for window in windows {
                window.close()
            }
            return nil
        }
        
        if waitForNextLetter {
            waitForNextLetter = false
            if keyToLetter.keys.contains(key) {
                let letter = keyToLetter[key]!
                if letterToPath.keys.contains(letter) {
                    let filePath = letterToPath[letter]!
                    
                    if filePath.contains(",") {
                        let arguments = filePath.components(separatedBy: ",")
                        CGDisplayMoveCursorToPoint(CGMainDisplayID(), CGPoint(x: Double(arguments[0])!, y: Double(arguments[1])!))
                    }
                    
                    NSWorkspace.shared.open(URL(fileURLWithPath: filePath))
                    for window in windows {
                        window.close()
                    }
                    return nil
                }
            }
        }
        
        for window in windows {
            window.close()
        }
        
        return event
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: self.handler)
        
        var leftDirs: [String] = []
        var rightDirs: [String] = []
        var onLeft = true
        
        for letter in letterToPath.keys {
            let name = letterToPath[letter]!.components(separatedBy: "/").last!
            if (onLeft) {
                leftDirs.append(letter + "    " + name)
                onLeft = false
                continue
            }
            rightDirs.append(letter + "    " + name)
            onLeft = true
        }
        
        var left = ""
        var right = ""
        
        for dir in leftDirs {
            left += dir + "\n"
        }
        
        for dir in rightDirs {
            right += dir + "\n"
        }
        
        if !clear {
            leftPane.placeholderString = left
            rightPane.placeholderString = right
        }
        
    }
    
}
