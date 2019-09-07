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
    let windowHistory: WindowHistory
    
    var eventMonitor: EventMonitor?
    var frontmostWindow: AccessibilityElement?
    var windowMoving: Bool = false
    var initialWindowRect: CGRect?
    var currentHotSpot: HotSpot?
    
    var box: NSWindow
    
    let screenDetection = ScreenDetection()
    
    init(windowCalculationFactory: WindowCalculationFactory, windowHistory: WindowHistory) {
        self.windowCalculationFactory = windowCalculationFactory
        self.windowHistory = windowHistory
        
        let initialRect = NSRect(x: 0, y: 0, width: 0, height: 0)
        box = NSWindow(contentRect: initialRect, styleMask: .titled, backing: .buffered, defer: false)

        initializeBox()

        eventMonitor = EventMonitor(mask: [.leftMouseDown, .leftMouseUp, .leftMouseDragged], handler: handle)
        
        eventMonitor?.start()
    }
    
    func handle(event: NSEvent?) {
        
        guard let event = event else { return }
        switch event.type {
        case .leftMouseDown:
            frontmostWindow = AccessibilityElement.frontmostWindow()
            initialWindowRect = frontmostWindow?.rectOfElement()
        case .leftMouseUp:
            frontmostWindow = nil
            windowMoving = false
            initialWindowRect = nil
            if let currentHotSpot = self.currentHotSpot {
                box.close()
                currentHotSpot.action.postSnap(screen: currentHotSpot.screen)
                self.currentHotSpot = nil
            }
        case .leftMouseDragged:
            guard let currentRect = frontmostWindow?.rectOfElement(),
                let windowId = frontmostWindow?.getIdentifier()
                else {
                    return
            }
            if !windowMoving {
                if currentRect.size == initialWindowRect?.size
                    && currentRect.origin != initialWindowRect?.origin {
                    windowMoving = true
                    
                    // if window was put there by rectangle, restore size and put center window under cursor while keeping window on screen
                    if let restoreRect = obtainRestoreRect(windowId: windowId, currentRect: currentRect) {
                        frontmostWindow?.setRectOf(restoreRect)
                        windowHistory.lastRectangleActions.removeValue(forKey: windowId)
                    } else {
                        // else record history
                        windowHistory.restoreRects[windowId] = initialWindowRect
                    }
                }
            }
            if windowMoving {
                if let newHotSpot = getMouseHotSpot() {
                    if newHotSpot == currentHotSpot {
                        return
                    }
                    
                    if let newBoxRect = getBoxRect(hotSpot: newHotSpot, currentWindowRect: currentRect) {
                        box.setFrame(newBoxRect, display: true)
                        box.makeKeyAndOrderFront(nil)
                    }
                    
                    currentHotSpot = newHotSpot
                } else {
                    if currentHotSpot != nil {
                        box.close()
                        currentHotSpot = nil
                    }
                }
            }
        default:
            return
        }
    }
    
    private func obtainRestoreRect(windowId: WindowId, currentRect: CGRect) -> CGRect? {
        guard let lastRect = windowHistory.lastRectangleActions[windowId]?.rect,
            lastRect == initialWindowRect,
            let restoreRect = windowHistory.restoreRects[windowId]
        else { return nil }
        
        // Set x and y WRT the current rect to reduce jenkiness
        let adjustedRestoreRect = CGRect(
            x: currentRect.minX,
            y: currentRect.minY + currentRect.height - restoreRect.height,
            width: restoreRect.width,
            height: restoreRect.height)
        return adjustedRestoreRect
    }
    
    // Make the box semi-opaque with a border and rouned corners
    private func initializeBox() {
        box.title = "Rectangle"
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
        if let calculation = windowCalculationFactory.calculation(for: hotSpot.action) {
            
            return calculation.calculateRect(currentWindowRect, visibleFrameOfScreen: hotSpot.screen.visibleFrame, action: hotSpot.action)
        }
        return nil
    }
    
    func getMouseHotSpot() -> HotSpot? {
        
        for screen in NSScreen.screens {
            let frame = screen.frame
            let loc = NSEvent.mouseLocation
            
            if loc.x >= frame.minX {
                if loc.x < frame.minX + 25 {
                    if loc.y >= frame.maxY - 25 && loc.y <= frame.maxY {
                        return HotSpot(screen: screen, action: .upperLeft)
                    }
                    if loc.y >= frame.minY && loc.y <= frame.minY + 25 {
                        return HotSpot(screen: screen, action: .lowerLeft)
                    }
                }
                
                if loc.x < frame.minX + 5 {
                    if loc.y >= frame.minY && loc.y <= frame.minY + 150 {
                        return HotSpot(screen: screen, action: .bottomHalf)
                    }
                    if loc.y >= frame.maxY - 150 && loc.y <= frame.maxY {
                        return HotSpot(screen: screen, action: .topHalf)
                    }
                    if loc.y >= frame.minY && loc.y <= frame.maxY {
                        return HotSpot(screen: screen, action: .leftHalf)
                    }
                }
            }
            
            
            if loc.x <= frame.maxX {
                if loc.x > frame.maxX - 25 {
                    if loc.y >= frame.maxY - 25 && loc.y <= frame.maxY {
                        return HotSpot(screen: screen, action: .upperRight)
                    }
                    if loc.y >= frame.minY && loc.y <= frame.minY + 25 {
                        return HotSpot(screen: screen, action: .lowerRight)
                    }
                }

                
                if loc.x > frame.maxX - 5 {
                    if loc.y >= frame.minY && loc.y <= frame.minY + 150 {
                        return HotSpot(screen: screen, action: .bottomHalf)
                    }
                    if loc.y >= frame.maxY - 150 && loc.y <= frame.maxY {
                        return HotSpot(screen: screen, action: .topHalf)
                    }
                    if loc.y >= frame.minY && loc.y <= frame.maxY {
                        return HotSpot(screen: screen, action: .rightHalf)
                    }
                }
            }
            
            if loc.y >= frame.minY && loc.y < frame.minY + 5 {
                let thirdWidth = floor(frame.width / 3)
                if loc.x >= frame.minX && loc.x <= frame.minX + thirdWidth {
                    return HotSpot(screen: screen, action: .firstThird)
                }
                if loc.x >= frame.minX + thirdWidth && loc.x <= frame.maxX - thirdWidth{
                    return HotSpot(screen: screen, action: .centerThird)
                }
                if loc.x >= frame.minX + thirdWidth && loc.x <= frame.maxX {
                    return HotSpot(screen: screen, action: .lastThird)
                }
            }
            
            if loc.y <= frame.maxY && loc.y > frame.maxY - 5 {
                if loc.x >= frame.minX && loc.x <= frame.maxX {
                    return HotSpot(screen: screen, action: .maximize)
                }
            }
            
        }
        
        return nil
    }
    
}

struct HotSpot: Equatable {
    let screen: NSScreen
    let action: WindowAction
}
