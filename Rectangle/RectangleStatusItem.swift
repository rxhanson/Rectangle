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
    private var isVisibleObserver: NSKeyValueObservation?
    
    private init() {}
    
    public func refreshVisibility() {
        if Defaults.hideMenuBarIcon.enabled {
            remove()
        } else {
            add()
        }
    }
    
    public func openMenu() {
        if !added {
            add()
        }
        nsStatusItem?.button?.performClick(self)
        refreshVisibility()
    }
    
    private func add() {
        added = true
        nsStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        nsStatusItem?.menu = self.statusMenu
        nsStatusItem?.button?.image = NSImage(named: "StatusTemplate")
        nsStatusItem?.behavior = .removalAllowed
        isVisibleObserver = nsStatusItem?.observe(\.isVisible, options: [.old, .new]) { nsStatusItem, change in
            if change.oldValue == true && change.newValue == false {
                Notification.Name.menuBarIconHidden.post()
                Defaults.hideMenuBarIcon.enabled = true
            }
        }
        nsStatusItem?.isVisible = true
    }
    
    private func remove() {
        added = false
        guard let nsStatusItem = nsStatusItem else { return }
        NSStatusBar.system.removeStatusItem(nsStatusItem)
    }
    
}
