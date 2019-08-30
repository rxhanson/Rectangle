//
//  AccessibilityWindow.swift
//  Rectangle
//
//  Created by Ryan Hanson on 6/13/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

class AccessibilityWindowController: NSWindowController {
    
    override func windowDidLoad() {
        super.windowDidLoad()
        self.window?.titlebarAppearsTransparent = true
        let closeButton = self.window?.standardWindowButton(.closeButton)
        closeButton?.target = self
        closeButton?.action = #selector(quit)
    }
    
    @objc func quit() {
        exit(1)
    }
    
}

class AccessibilityViewController: NSViewController {
    
    @IBAction func openSystemPrefs(_ sender: Any) {
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
