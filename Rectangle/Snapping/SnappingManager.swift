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
    var windowElement: AccessibilityElement?
    var windowId: Int?
    var windowMoving: Bool = false
    var initialWindowRect: CGRect?
    var currentSnapArea: SnapArea?
    
    var box: NSWindow?
    
    let screenDetection = ScreenDetection()
    
    private let gapSize = Defaults.gapSize.value
    private let marginTop = Defaults.snapEdgeMarginTop.value
    private let marginBottom = Defaults.snapEdgeMarginBottom.value
    private let marginLeft = Defaults.snapEdgeMarginLeft.value
    private let marginRight = Defaults.snapEdgeMarginRight.value
    private let ignoredSnapAreas = SnapAreaOption(rawValue: Defaults.ignoredSnapAreas.value)
    
    private let snapOptionToAction: [SnapAreaOption: WindowAction] = [
        .top: .maximize,
        .left: .leftHalf,
        .right: .rightHalf,
        .topLeft: .topLeft,
        .topRight: .topRight,
        .bottomLeft: .bottomLeft,
        .bottomRight: .bottomRight,
        .topLeftShort: .topHalf,
        .topRightShort: .topHalf,
        .bottomLeftShort: .bottomHalf,
        .bottomRightShort: .bottomHalf
    ]
    
    init(windowCalculationFactory: WindowCalculationFactory, windowHistory: WindowHistory) {
        self.windowCalculationFactory = windowCalculationFactory
        self.windowHistory = windowHistory
        
        if Defaults.windowSnapping.enabled != false {
            enableSnapping()
        }
        
        subscribeToWindowSnappingToggle()
    }
    
    private func subscribeToWindowSnappingToggle() {
        NotificationCenter.default.addObserver(self, selector: #selector(windowSnappingToggled), name: SettingsViewController.windowSnappingNotificationName, object: nil)
    }
    
    @objc func windowSnappingToggled(notification: Notification) {
        guard let enabled = notification.object as? Bool else { return }
        if enabled {
            enableSnapping()
        } else {
            disableSnapping()
        }
    }
    
    private func enableSnapping() {
        box = generateBoxWindow()
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .leftMouseUp, .leftMouseDragged], handler: handle)
        eventMonitor?.start()
    }
    
    private func disableSnapping() {
        box = nil
        eventMonitor?.stop()
        eventMonitor = nil
    }
    
    func handle(event: NSEvent?) {
        
        guard let event = event else { return }
        switch event.type {
        case .leftMouseDown:
            if !Defaults.obtainWindowOnClick.userDisabled {
                windowElement = AccessibilityElement.windowUnderCursor()
                windowId = windowElement?.getIdentifier()
                initialWindowRect = windowElement?.rectOfElement()
            }
        case .leftMouseUp:
            windowElement = nil
            windowId = nil
            windowMoving = false
            initialWindowRect = nil
            if let currentSnapArea = self.currentSnapArea {
                box?.close()
                currentSnapArea.action.postSnap(screen: currentSnapArea.screen)
                self.currentSnapArea = nil
            }
        case .leftMouseDragged:
            if windowId == nil {
                windowElement = AccessibilityElement.windowUnderCursor()
                windowId = windowElement?.getIdentifier()
                initialWindowRect = windowElement?.rectOfElement()
            }
            guard let currentRect = windowElement?.rectOfElement(),
                let windowId = windowId
            else { return }
            
            if !windowMoving {
                if currentRect.size == initialWindowRect?.size {
                    if currentRect.origin != initialWindowRect?.origin {
                        windowMoving = true

                        if Defaults.unsnapRestore.enabled != false {
                            // if window was put there by rectangle, restore size
                            if let lastRect = windowHistory.lastRectangleActions[windowId]?.rect,
                                lastRect == initialWindowRect,
                                let restoreRect = windowHistory.restoreRects[windowId] {
                                
                                windowElement?.set(size: restoreRect.size)
                                windowHistory.lastRectangleActions.removeValue(forKey: windowId)
                            } else {
                                windowHistory.restoreRects[windowId] = initialWindowRect
                            }
                        }
                    }
                }
                else {
                    windowHistory.lastRectangleActions.removeValue(forKey: windowId)
                }
            }
            if windowMoving {
                if let snapArea = snapAreaContainingCursor(priorSnapArea: currentSnapArea) {
                    if snapArea == currentSnapArea {
                        return
                    }
                    let currentWindow = Window(id: windowId, rect: currentRect)
                    
                    if let newBoxRect = getBoxRect(hotSpot: snapArea, currentWindow: currentWindow) {
                        box?.setFrame(newBoxRect, display: true)
                        box?.makeKeyAndOrderFront(nil)
                    }
                    
                    currentSnapArea = snapArea
                } else {
                    if currentSnapArea != nil {
                        box?.close()
                        currentSnapArea = nil
                    }
                }
            }
        default:
            return
        }
    }
    
    // Make the box semi-opaque with a border and rounded corners
    private func generateBoxWindow() -> NSWindow {
        
        let initialRect = NSRect(x: 0, y: 0, width: 0, height: 0)
        let box = NSWindow(contentRect: initialRect, styleMask: .titled, backing: .buffered, defer: false)

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
        
        return box
    }
    
    func getBoxRect(hotSpot: SnapArea, currentWindow: Window) -> CGRect? {
        if let calculation = windowCalculationFactory.calculation(for: hotSpot.action) {
            
            let rectResult = calculation.calculateRect(currentWindow, lastAction: nil, visibleFrameOfScreen: hotSpot.screen.visibleFrame, action: hotSpot.action)
            
            if gapSize > 0, hotSpot.action.gapsApplicable {
                let gapSharedEdges = rectResult.subAction?.gapSharedEdge ?? hotSpot.action.gapSharedEdge

                return GapCalculation.applyGaps(rectResult.rect, sharedEdges: gapSharedEdges, gapSize: gapSize)
            }
            
            return rectResult.rect
        }
        return nil
    }
    
    func snapAreaContainingCursor(priorSnapArea: SnapArea?) -> SnapArea? {
        let loc = NSEvent.mouseLocation
        
        for screen in NSScreen.screens {
            let frame = screen.frame
            
            if loc.x >= frame.minX {
                if loc.x < frame.minX + CGFloat(marginLeft) + 20 {
                    if loc.y >= frame.maxY - CGFloat(marginTop) - 20 && loc.y <= frame.maxY {
                        if let area = snapArea(for: .topLeft, on: screen) {
                            return area
                        }
                    }
                    if loc.y >= frame.minY && loc.y <= frame.minY + CGFloat(marginBottom) + 20 {
                        if let area = snapArea(for: .bottomLeft, on: screen) {
                            return area
                        }
                    }
                }
                
                if loc.x < frame.minX + CGFloat(marginLeft) {
                    if loc.y >= frame.minY && loc.y <= frame.minY + CGFloat(marginBottom) + 145 {
                        if let area = snapArea(for: .bottomLeftShort, on: screen) {
                            return area
                        }
                    }
                    if loc.y >= frame.maxY - CGFloat(marginTop) - 145 && loc.y <= frame.maxY {
                        if let area = snapArea(for: .topLeftShort, on: screen) {
                            return area
                        }
                    }
                    if loc.y >= frame.minY && loc.y <= frame.maxY {
                        if let area = snapArea(for: .left, on: screen) {
                            return area
                        }
                    }
                }
            }
            
            if loc.x <= frame.maxX {
                if loc.x > frame.maxX - CGFloat(marginRight) - 20 {
                    if loc.y >= frame.maxY - CGFloat(marginTop) - 20 && loc.y <= frame.maxY {
                        if let area = snapArea(for: .topRight, on: screen) {
                            return area
                        }
                    }
                    if loc.y >= frame.minY && loc.y <= frame.minY + CGFloat(marginBottom) + 20 {
                        if let area = snapArea(for: .bottomRight, on: screen) {
                            return area
                        }
                    }
                }
                
                if loc.x > frame.maxX - CGFloat(marginRight) {
                    if loc.y >= frame.minY && loc.y <= frame.minY + CGFloat(marginBottom) + 145 {
                        if let area = snapArea(for: .bottomRightShort, on: screen) {
                            return area
                        }
                    }
                    if loc.y >= frame.maxY - CGFloat(marginTop) - 145 && loc.y <= frame.maxY {
                        if let area = snapArea(for: .topRightShort, on: screen) {
                            return area
                        }
                    }
                    if loc.y >= frame.minY && loc.y <= frame.maxY {
                        if let area = snapArea(for: .right, on: screen) {
                            return area
                        }
                    }
                }
            }
            
            if loc.y <= frame.maxY && loc.y > frame.maxY - CGFloat(marginTop) {
                if loc.x >= frame.minX && loc.x <= frame.maxX {
                    if let area = snapArea(for: .top, on: screen) {
                        return area
                    }
                }
            }
            
            if loc.y >= frame.minY && loc.y < frame.minY + CGFloat(marginBottom) && !ignoredSnapAreas.contains(.bottom) {
                let thirdWidth = floor(frame.width / 3)
                if loc.x >= frame.minX && loc.x <= frame.minX + thirdWidth {
                    return SnapArea(screen: screen, action: .firstThird)
                }
                if loc.x >= frame.minX + thirdWidth && loc.x <= frame.maxX - thirdWidth{
                    if let priorAction = priorSnapArea?.action {
                        let action: WindowAction
                        switch priorAction {
                        case .firstThird, .firstTwoThirds:
                            action = .firstTwoThirds
                        case .lastThird, .lastTwoThirds:
                            action = .lastTwoThirds
                        default: action = .centerThird
                        }
                        return SnapArea(screen: screen, action: action)
                    }
                    return SnapArea(screen: screen, action: .centerThird)
                }
                if loc.x >= frame.minX + thirdWidth && loc.x <= frame.maxX {
                    return SnapArea(screen: screen, action: .lastThird)
                }
            }
            
        }
        
        return nil
    }
    
    private func snapArea(for snapOption: SnapAreaOption, on screen: NSScreen) -> SnapArea? {
        if ignoredSnapAreas.contains(snapOption) { return nil }
        if let action = snapOptionToAction[snapOption] {
            return SnapArea(screen: screen, action: action)
        }
        return nil
    }
    
}

struct SnapArea: Equatable {
    let screen: NSScreen
    let action: WindowAction
}

struct SnapAreaOption: OptionSet, Hashable {
    let rawValue: Int
    
    static let top = SnapAreaOption(rawValue: 1 << 0)
    static let bottom = SnapAreaOption(rawValue: 1 << 1)
    static let left = SnapAreaOption(rawValue: 1 << 2)
    static let right = SnapAreaOption(rawValue: 1 << 3)
    static let topLeft = SnapAreaOption(rawValue: 1 << 4)
    static let topRight = SnapAreaOption(rawValue: 1 << 5)
    static let bottomLeft = SnapAreaOption(rawValue: 1 << 6)
    static let bottomRight = SnapAreaOption(rawValue: 1 << 7)
    static let topLeftShort = SnapAreaOption(rawValue: 1 << 8)
    static let topRightShort = SnapAreaOption(rawValue: 1 << 9)
    static let bottomLeftShort = SnapAreaOption(rawValue: 1 << 10)
    static let bottomRightShort = SnapAreaOption(rawValue: 1 << 11)
    
    static let all: SnapAreaOption = [.top, .bottom, .left, .right, .topLeft, .topRight, .bottomLeft, .bottomRight, .topLeftShort, .topRightShort, .bottomLeftShort, .bottomRightShort]
    static let none: SnapAreaOption = []
}
