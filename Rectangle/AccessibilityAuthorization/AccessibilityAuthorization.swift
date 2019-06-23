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
    
    private var accessibilityWindow: AccessibilityWindow?
    
    public func checkAccessibility(completion: @escaping () -> Void) -> Bool {
        if !AXIsProcessTrusted() {
            accessibilityWindow = AccessibilityWindow(windowNibName: "AccessibilityWindow")
            accessibilityWindow?.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            pollAccessibility(completion: completion)
            return false
        } else {
            return true
        }
    }
    
    private func pollAccessibility(completion: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if AXIsProcessTrusted() {
                self.accessibilityWindow?.close()
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
