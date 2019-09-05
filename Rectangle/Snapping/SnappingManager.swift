//
//  SnappingManager.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/4/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

class SnappingManager {

    let windowCalculationFactory: WindowCalculationFactory
    
    var eventMonitor: EventMonitor?
    var frontmostWindow: AccessibilityElement?
    var windowMoving: Bool = false
    var previousWindowRect: CGRect?
    var currentHotSpot: HotSpot?
    
    var box: NSWindow
    
    let screenDetection = ScreenDetection()
    
    init(windowCalculationFactory: WindowCalculationFactory) {
        self.windowCalculationFactory = windowCalculationFactory
        
        let initialRect = NSRect(x: 0, y: 0, width: 0, height: 0)
        box = NSWindow(contentRect: initialRect, styleMask: .titled, backing: .buffered, defer: false)

        initializeBox()

        eventMonitor = EventMonitor(mask: [.leftMouseUp, .leftMouseDragged]) { event in
            guard let event = event else { return }
            switch event.type {
            case .leftMouseUp:
                self.frontmostWindow = nil
                self.windowMoving = false
                self.previousWindowRect = nil
            case .leftMouseDragged:
                if self.frontmostWindow == nil {
                    self.frontmostWindow = AccessibilityElement.frontmostWindow()
                }
                guard let currentRect = self.frontmostWindow?.rectOfElement() else {
                    return
                }
                if !self.windowMoving {
                    if currentRect.size == self.previousWindowRect?.size && currentRect.origin != self.previousWindowRect?.origin {
                        self.windowMoving = true
                    }
                }
                if self.windowMoving {
                    if let newHotSpot = self.getMouseHotSpot() {
                        if newHotSpot == self.currentHotSpot {
                            return
                        }
                        
                        if let newBoxRect = self.getBoxRect(hotSpot: newHotSpot, currentWindowRect: currentRect) {
                            self.box.setFrame(newBoxRect, display: true)
                            self.box.makeKeyAndOrderFront(nil)
                        }
                        
                        self.currentHotSpot = newHotSpot
                    } else {
                        if self.currentHotSpot != nil {
                            self.box.close()
                            self.currentHotSpot = nil
                        }
                    }
                }
                self.previousWindowRect = currentRect
            default:
                return
            }
        }
        
        eventMonitor?.start()
    }
    
    // Make the box semi-opaque with a border and rouned corners
    private func initializeBox() {
        box.backgroundColor = .clear
        box.isOpaque = false
        box.level = .modalPanel
        box.hasShadow = false
        box.isReleasedWhenClosed = false
  
        box.styleMask.insert(.fullSizeContentView)
        box.titleVisibility = .hidden
        box.titlebarAppearsTransparent = true
        box.collectionBehavior.insert(.transient)
        box.standardWindowButton(.closeButton)?.isHidden = true
        box.standardWindowButton(.miniaturizeButton)?.isHidden = true
        box.standardWindowButton(.zoomButton)?.isHidden = true
        box.standardWindowButton(.toolbarButton)?.isHidden = true
        
        let boxView = NSBox()
        boxView.boxType = .custom
        boxView.borderColor = .lightGray
        boxView.borderType = .lineBorder
        boxView.borderWidth = 0.5
        boxView.cornerRadius = 5
        boxView.wantsLayer = true
        boxView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        
        box.contentView = boxView
    }
    
    func getBoxRect(hotSpot: HotSpot, currentWindowRect: CGRect) -> CGRect? {
        if let calculation = windowCalculationFactory.calculation(for: hotSpot.type.action) {
            
            return calculation.calculateRect(currentWindowRect, visibleFrameOfScreen: hotSpot.screen.visibleFrame, action: hotSpot.type.action)
        }
        return nil
    }
    
    func getMouseHotSpot() -> HotSpot? {
        
        for screen in NSScreen.screens {
            let frame = screen.frame
            let loc = NSEvent.mouseLocation
            
            if loc.x >= frame.minX && loc.x < frame.minX + 5 {
                if loc.y >= frame.minY && loc.y <= frame.maxY {
                    return HotSpot(screen: screen, type: .left)
                }
            }
            
            if loc.x <= frame.maxX && loc.x > frame.maxX - 5 {
                if loc.y >= frame.minY && loc.y <= frame.maxY {
                    return HotSpot(screen: screen, type: .right)
                }
            }
            
            if loc.y >= frame.minY && loc.y < frame.minY + 5 {
                if loc.x >= frame.minX && loc.x <= frame.maxX {
                    return HotSpot(screen: screen, type: .bottom)
                }
            }
            
            if loc.y <= frame.maxY && loc.y > frame.maxY - 5 {
                if loc.x >= frame.minX && loc.x <= frame.maxX {
                    return HotSpot(screen: screen, type: .top)
                }
            }
            
        }
        
        return nil
    }
    
}

struct HotSpot: Equatable {
    let screen: NSScreen
    let type: HotSpotType
}
    
enum HotSpotType {
    case top
    case bottom
    case left
    case right
    
    var action: WindowAction {
        switch self {
        case .top: return .maximize
        case .bottom: return .maximize
        case .left: return .leftHalf
        case .right: return .rightHalf
        }
    }
}
