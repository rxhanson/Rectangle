//
//  AccessibilityAuthorization.swift
//  Rectangle
//
//  Created by Ryan Hanson on 6/11/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation
import Cocoa

class AccessibilityAuthorization {
    
    private var accessibilityWindowController: NSWindowController?
    
    public func checkAccessibility(completion: @escaping () -> Void) -> Bool {
        if !AXIsProcessTrusted() {
            
            accessibilityWindowController = NSStoryboard(name: "Accessibility", bundle: nil).instantiateController(withIdentifier: "AccessibilityWindowController") as? NSWindowController
            
            NSApp.activate(ignoringOtherApps: true)
            accessibilityWindowController?.showWindow(self)
            accessibilityWindowController?.window?.makeKey()
            pollAccessibility(completion: completion)
            return false
        } else {
            return true
        }
    }
    
    private func pollAccessibility(completion: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if AXIsProcessTrusted() {
                self.accessibilityWindowController?.close()
                self.accessibilityWindowController = nil
                completion()
            } else {
                self.pollAccessibility(completion: completion)
            }
        }
    }
    
    func generateUnauthorizedMenu() -> NSMenu {
        let unauthMenu = NSMenu()
        unauthMenu.addItem(withTitle: "Not Authorized to Control Your Computer", action: nil, keyEquivalent: "")
        unauthMenu.addItem(withTitle: "Authorize...", action: #selector(bringWindowToFront), keyEquivalent: "")
        unauthMenu.addItem(NSMenuItem.separator())
        unauthMenu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        unauthMenu.items.forEach { $0.target = self }
        return unauthMenu
    }
    
    @objc func bringWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func quit() {
        exit(0)
    }
    
}
