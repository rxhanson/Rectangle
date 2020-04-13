//
//  WelcomeViewController.swift
//  Rectangle
//
//  Created by Ryan Hanson on 4/9/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Cocoa

class WelcomeViewController: NSViewController {
    
    @IBAction func selectRecommended(_ sender: Any) {
        NSApp.stopModal(withCode: .alertFirstButtonReturn)
    }
    
    @IBAction func selectSpectacle(_ sender: Any) {
        NSApp.stopModal(withCode: .alertSecondButtonReturn)
    }
}

class WelcomeWindowController: NSWindowController {
    
    override func windowDidLoad() {
        super.windowDidLoad()
        let closeButton = self.window?.standardWindowButton(.closeButton)
        closeButton?.target = self
        closeButton?.action = #selector(windowClosed)
    }
    
    @objc func windowClosed() {
        NSApp.stopModal(withCode: .alertFirstButtonReturn)
    }

}

