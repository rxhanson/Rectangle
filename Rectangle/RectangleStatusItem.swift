//
//  RectangleStatusItem.swift
//  Rectangle
//
//  Created by Ryan Hanson on 6/11/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

class RectangleStatusItem {
    static let instance = RectangleStatusItem()
    
    private var nsStatusItem: NSStatusItem?
    private var added: Bool = false
    public var statusMenu: NSMenu? {
        didSet {
            nsStatusItem?.menu = statusMenu
        }
    }
    
    private init() {}
    
    public func refreshVisibility() {
        if Defaults.hideMenuBarIcon.enabled {
            remove()
        } else {
            add()
        }
    }
    
    public func openMenu() {
        if let menu = statusMenu {
            NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength).popUpMenu(menu)
        }
    }
    
    private func add() {
        nsStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        nsStatusItem?.menu = self.statusMenu
        nsStatusItem?.button?.image = NSImage(named: "StatusTemplate")
    }
    
    private func remove() {
        guard let nsStatusItem = nsStatusItem else { return }
        NSStatusBar.system.removeStatusItem(nsStatusItem)
    }
    
}
