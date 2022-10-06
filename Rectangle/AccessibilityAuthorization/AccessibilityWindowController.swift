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
        let closeButton = self.window?.standardWindowButton(.closeButton)
        closeButton?.target = self
        closeButton?.action = #selector(quit)
    }
    
    @objc func quit() {
        exit(1)
    }
    
}

class AccessibilityViewController: NSViewController {
    
    @IBOutlet weak var sysPrefsPathField: NSTextField!
    @IBOutlet weak var openSysPrefsButton: NSButton!
    @IBOutlet weak var padlockField: NSTextField!
    
    override func viewDidLoad() {
        if #available(OSX 13, *) {
            sysPrefsPathField.stringValue =  NSLocalizedString(
                "Go to System Settings → Privacy & Security → Accessibility", tableName: "Main", value: "", comment: "")
            openSysPrefsButton.title = NSLocalizedString(
                "Open System Settings", tableName: "Main", value: "", comment: "")
            padlockField.isHidden = true
        }
    }
    
    @IBAction func openSystemPrefs(_ sender: Any) {
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
