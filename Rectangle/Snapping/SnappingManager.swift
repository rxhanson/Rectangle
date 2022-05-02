//
//  SnappingManager.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/4/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

class SnappingManager {
    
    private let fullIgnoreIds: [String] = Defaults.fullIgnoreBundleIds.typedValue ?? ["com.install4j", "com.mathworks.matlab", "com.live2d.cubism.CECubismEditorApp"]
    
    var eventMonitor: EventMonitor?
    var windowElement: AccessibilityElement?
    var windowId: Int?
    var windowIdAttempt: Int = 0
    var lastWindowIdAttempt: TimeInterval?
    var windowMoving: Bool = false
    var isFullScreen: Bool = false
    var allowListening: Bool = true
    var initialWindowRect: CGRect?
    var currentSnapArea: SnapArea?
    
    var box: FootprintWindow?

    let screenDetection = ScreenDetection()
    let applicationToggle: ApplicationToggle
    
    private let marginTop = CGFloat(Defaults.snapEdgeMarginTop.value)
    private let marginBottom = CGFloat(Defaults.snapEdgeMarginBottom.value)
    private let marginLeft = CGFloat(Defaults.snapEdgeMarginLeft.value)
    private let marginRight = CGFloat(Defaults.snapEdgeMarginRight.value)
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
    
    init(applicationToggle: ApplicationToggle) {
        self.applicationToggle = applicationToggle
        
        if Defaults.windowSnapping.enabled != false {
            enableSnapping()
        }
        
        registerWorkspaceChangeNote()
        
        Notification.Name.windowSnapping.onPost { notification in
            if let enabled = notification.object as? Bool {
                self.allowListening = enabled
            }
            self.toggleListening()
        }
        Notification.Name.frontAppChanged.onPost(using: frontAppChanged)
    }
    
    func frontAppChanged(notification: Notification) {
        if applicationToggle.shortcutsDisabled {
            DispatchQueue.main.async {
                for id in self.fullIgnoreIds {
                    if self.applicationToggle.frontAppId?.starts(with: id) == true {
                        self.allowListening = false
                        self.toggleListening()
                        break
                    }
                }
            }
        } else {
            allowListening = true
            checkFullScreen()
        }
    }
    
    func toggleListening() {
        if allowListening, !isFullScreen, !Defaults.windowSnapping.userDisabled {
            enableSnapping()
        } else {
            disableSnapping()
        }
    }
    
    private func registerWorkspaceChangeNote() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(receiveWorkspaceNote(_:)), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        checkFullScreen()
    }
    
    func checkFullScreen() {
        isFullScreen = AccessibilityElement.frontmostWindow()?.isFullScreen() == true
        toggleListening()
    }
    
    @objc func receiveWorkspaceNote(_ notification: Notification) {
        checkFullScreen()
    }
        
    public func reloadFromDefaults() {
        if Defaults.windowSnapping.userDisabled {
            if eventMonitor?.running == true {
                disableSnapping()
            }
        } else {
            if eventMonitor?.running != true {
                enableSnapping()
            }
        }
    }
    
    private func enableSnapping() {
        if box == nil {
            box = FootprintWindow()
        }
        if eventMonitor == nil {
            eventMonitor = EventMonitor(mask: [.leftMouseDown, .leftMouseUp, .leftMouseDragged], handler: handle)
            eventMonitor?.start()
        }
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
            if let currentSnapArea = self.currentSnapArea {
                box?.close()
                currentSnapArea.action.postSnap(windowElement: windowElement, windowId: windowId, screen: currentSnapArea.screen)
                self.currentSnapArea = nil
            } else {
                // it's possible that the window has moved, but the mouse dragged events are not getting the updated window position
                // this typically only happens if the user is dragging and dropping windows really quickly
                // in this scenario, the footprint doesn't display but the snap will still occur, as long as the window position is updated as of mouse up.
                if let currentRect = windowElement?.rectOfElement(),
                   let windowId = windowId,
                   currentRect.size == initialWindowRect?.size,
                   currentRect.origin != initialWindowRect?.origin {
  
                    unsnapRestore(windowId: windowId)
                    
                    if let snapArea = snapAreaContainingCursor(priorSnapArea: currentSnapArea)  {
                        box?.close()
                        if !(Defaults.snapModifiers.value > 0) ||
                            event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue == Defaults.snapModifiers.value {
                            snapArea.action.postSnap(windowElement: windowElement, windowId: windowId, screen: snapArea.screen)
                        }
                        self.currentSnapArea = nil
                    }
                }
            }
            windowElement = nil
            windowId = nil
            windowMoving = false
            initialWindowRect = nil
            windowIdAttempt = 0
            lastWindowIdAttempt = nil
        case .leftMouseDragged:
            if windowId == nil, windowIdAttempt < 20 {
                if let lastWindowIdAttempt = lastWindowIdAttempt {
                    if event.timestamp - lastWindowIdAttempt < 0.1 {
                        return
                    }
                }
                if windowElement == nil {
                    windowElement = AccessibilityElement.windowUnderCursor()
                }
                windowId = windowElement?.getIdentifier()
                initialWindowRect = windowElement?.rectOfElement()
                windowIdAttempt += 1
                lastWindowIdAttempt = event.timestamp
            }
            guard let currentRect = windowElement?.rectOfElement(),
                let windowId = windowId
            else { return }
            
            if !windowMoving {
                if currentRect.size == initialWindowRect?.size {
                    if currentRect.origin != initialWindowRect?.origin {
                        windowMoving = true
                        unsnapRestore(windowId: windowId)
                    }
                }
                else {
                    AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowId)
                }
            }
            if windowMoving {
                if Defaults.snapModifiers.value > 0 {
                    if event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue != Defaults.snapModifiers.value {
                        if currentSnapArea != nil {
                            box?.close()
                            currentSnapArea = nil
                        }
                        return
                    }
                }
                
                if let snapArea = snapAreaContainingCursor(priorSnapArea: currentSnapArea) {
                    if snapArea == currentSnapArea {
                        return
                    }
                    let currentWindow = Window(id: windowId, rect: currentRect)
                    
                    if let newBoxRect = getBoxRect(hotSpot: snapArea, currentWindow: currentWindow) {
                        if box == nil {
                            box = FootprintWindow()
                        }
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
    
    func unsnapRestore(windowId: Int) {
        if Defaults.unsnapRestore.enabled != false {
            // if window was put there by rectangle, restore size
            if let lastRect = AppDelegate.windowHistory.lastRectangleActions[windowId]?.rect,
                lastRect == initialWindowRect,
                let restoreRect = AppDelegate.windowHistory.restoreRects[windowId] {
                
                windowElement?.set(size: restoreRect.size)
                AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowId)
            } else {
                AppDelegate.windowHistory.restoreRects[windowId] = initialWindowRect
            }
        }
    }
    
    func getBoxRect(hotSpot: SnapArea, currentWindow: Window) -> CGRect? {
        if let calculation = WindowCalculationFactory.calculationsByAction[hotSpot.action] {
            
            let rectCalcParams = RectCalculationParameters(window: currentWindow, visibleFrameOfScreen: hotSpot.screen.adjustedVisibleFrame, action: hotSpot.action, lastAction: nil)
            let rectResult = calculation.calculateRect(rectCalcParams)
            
            let gapsApplicable = hotSpot.action.gapsApplicable
            
            if Defaults.gapSize.value > 0, gapsApplicable != .none {
                let gapSharedEdges = rectResult.subAction?.gapSharedEdge ?? hotSpot.action.gapSharedEdge

                return GapCalculation.applyGaps(rectResult.rect, dimension: gapsApplicable, sharedEdges: gapSharedEdges, gapSize: Defaults.gapSize.value)
            }
            
            return rectResult.rect
        }
        return nil
    }
    
    func snapAreaContainingCursor(priorSnapArea: SnapArea?) -> SnapArea? {
        let loc = NSEvent.mouseLocation
        
        for screen in NSScreen.screens {
            
            if screen.frame.isLandscape {
                if let snapArea = landscapeSnapArea(loc: loc, screen: screen, priorSnapArea: priorSnapArea) {
                    return snapArea
                }
            } else {
                if let snapArea = portraitSnapArea(loc: loc, screen: screen, priorSnapArea: priorSnapArea) {
                    return snapArea
                }
            }
        }
        
        return nil
    }
    
    private func landscapeSnapArea(loc: NSPoint, screen: NSScreen, priorSnapArea: SnapArea?) -> SnapArea? {
        let cornerSize = CGFloat(Defaults.cornerSnapAreaSize.value)
        let shortEdgeSize = CGFloat(Defaults.shortEdgeSnapAreaSize.value)
        let frame = screen.frame
        
        if Defaults.sixthsSnapArea.userEnabled {
            if loc.y >= frame.maxY - marginTop - cornerSize && loc.y <= frame.maxY && !ignoredSnapAreas.contains(.top) {
                let thirdWidth = floor(frame.width / 3)
                if loc.x >= frame.minX + cornerSize && loc.x <= frame.minX + thirdWidth {
                    if let priorAction = priorSnapArea?.action {
                        if priorAction == .topLeft || priorAction == .topLeftSixth || priorAction == .topCenterSixth {
                            return SnapArea(screen: screen, action: .topLeftSixth)
                        }
                    }
                }
                if loc.x >= frame.maxX - thirdWidth && loc.x <= frame.maxX - cornerSize {
                    if let priorAction = priorSnapArea?.action {
                        if priorAction == .topRight || priorAction == .topRightSixth || priorAction == .topCenterSixth {
                            return SnapArea(screen: screen, action: .topRightSixth)
                        }
                    }
                }
            }
        }
        
        if loc.x >= frame.minX {
            if loc.x < frame.minX + marginLeft + cornerSize {
                if loc.y >= frame.maxY - marginTop - cornerSize && loc.y <= frame.maxY {
                    if let area = snapArea(for: .topLeft, on: screen) {
                        return area
                    }
                }
                if loc.y >= frame.minY && loc.y <= frame.minY + marginBottom + cornerSize {
                    if let area = snapArea(for: .bottomLeft, on: screen) {
                        return area
                    }
                }
            }
            
            if loc.x < frame.minX + marginLeft {
                if loc.y >= frame.minY && loc.y <= frame.minY + marginBottom + shortEdgeSize {
                    if let area = snapArea(for: .bottomLeftShort, on: screen) {
                        return area
                    }
                }
                if loc.y >= frame.maxY - marginTop - shortEdgeSize && loc.y <= frame.maxY {
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
            if loc.x > frame.maxX - marginRight - cornerSize {
                if loc.y >= frame.maxY - marginTop - cornerSize && loc.y <= frame.maxY {
                    if let area = snapArea(for: .topRight, on: screen) {
                        return area
                    }
                }
                if loc.y >= frame.minY && loc.y <= frame.minY + marginBottom + cornerSize {
                    if let area = snapArea(for: .bottomRight, on: screen) {
                        return area
                    }
                }
            }
            
            if loc.x > frame.maxX - marginRight {
                if loc.y >= frame.minY && loc.y <= frame.minY + marginBottom + shortEdgeSize {
                    if let area = snapArea(for: .bottomRightShort, on: screen) {
                        return area
                    }
                }
                if loc.y >= frame.maxY - marginTop - shortEdgeSize && loc.y <= frame.maxY {
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
        
        if loc.y <= frame.maxY && loc.y > frame.maxY - marginTop {
            let thirdWidth = floor(frame.width / 3)
            if loc.x >= frame.minX && loc.x <= frame.maxX {
                if Defaults.sixthsSnapArea.userEnabled && loc.x >= frame.minX + thirdWidth && loc.x <= frame.maxX - thirdWidth {
                    if let priorAction = priorSnapArea?.action {
                        if priorAction == .topLeftSixth || priorAction == .topRightSixth || priorAction == .topCenterSixth {
                            return SnapArea(screen: screen, action: .topCenterSixth)
                        }
                    }
                }
                if let area = snapArea(for: .top, on: screen) {
                    return area
                }
            }
        }
        
        if loc.y >= frame.minY && loc.y < frame.minY + marginBottom && !ignoredSnapAreas.contains(.bottom) {
            let thirdWidth = floor(frame.width / 3)
            if loc.x >= frame.minX && loc.x <= frame.minX + thirdWidth {
                if Defaults.sixthsSnapArea.userEnabled {
                    if let priorAction = priorSnapArea?.action {
                        let action: WindowAction
                        switch priorAction {
                        case .bottomLeft, .bottomLeftSixth, .bottomCenterSixth:
                            action = .bottomLeftSixth
                        default: action = .firstThird
                        }
                        return SnapArea(screen: screen, action: action)
                    }
                }
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
                    case .bottomLeftSixth, .bottomRightSixth, .bottomCenterSixth:
                        if Defaults.sixthsSnapArea.userEnabled {
                            action = .bottomCenterSixth
                        } else {
                            action = .centerThird
                        }
                    default: action = .centerThird
                    }
                    return SnapArea(screen: screen, action: action)
                }
                return SnapArea(screen: screen, action: .centerThird)
            }
            if loc.x >= frame.minX + thirdWidth && loc.x <= frame.maxX {
                if Defaults.sixthsSnapArea.userEnabled {
                    if let priorAction = priorSnapArea?.action {
                        let action: WindowAction
                        switch priorAction {
                        case .bottomRight, .bottomRightSixth, .bottomCenterSixth:
                            action = .bottomRightSixth
                        default: action = .lastThird
                        }
                        return SnapArea(screen: screen, action: action)
                    }
                }
                return SnapArea(screen: screen, action: .lastThird)
            }
        }
        return nil
    }
    
    private func portraitSnapArea(loc: NSPoint, screen: NSScreen, priorSnapArea: SnapArea?) -> SnapArea? {
        let cornerSize = CGFloat(Defaults.cornerSnapAreaSize.value)
        let shortEdgeSize = CGFloat(Defaults.shortEdgeSnapAreaSize.value)

        let frame = screen.frame
        if loc.x >= frame.minX {
            if loc.x < frame.minX + marginLeft + cornerSize {
                if loc.y >= frame.maxY - marginTop - cornerSize && loc.y <= frame.maxY {
                    if let area = snapArea(for: .topLeft, on: screen) {
                        return area
                    }
                }
                if loc.y >= frame.minY && loc.y <= frame.minY + marginBottom + cornerSize {
                    if let area = snapArea(for: .bottomLeft, on: screen) {
                        return area
                    }
                }
            }
            
            if loc.x < frame.minX + marginLeft {
                if loc.y >= frame.minY && loc.y <= frame.minY + marginBottom + shortEdgeSize {
                    if let area = snapArea(for: .bottomLeftShort, on: screen) {
                        return area
                    }
                }
                if loc.y >= frame.maxY - marginTop - shortEdgeSize && loc.y <= frame.maxY {
                    if let area = snapArea(for: .topLeftShort, on: screen) {
                        return area
                    }
                }
                if loc.y >= frame.minY && loc.y <= frame.maxY && !ignoredSnapAreas.contains(.left) {
                    // left
                    if let area = portraitThirdsSnapArea(loc: loc, screen: screen, priorSnapArea: priorSnapArea) {
                        return area
                    }
                }
            }
        }
        
        if loc.x <= frame.maxX {
            if loc.x > frame.maxX - marginRight - cornerSize {
                if loc.y >= frame.maxY - marginTop - cornerSize && loc.y <= frame.maxY {
                    if let area = snapArea(for: .topRight, on: screen) {
                        return area
                    }
                }
                if loc.y >= frame.minY && loc.y <= frame.minY + marginBottom + cornerSize {
                    if let area = snapArea(for: .bottomRight, on: screen) {
                        return area
                    }
                }
            }
            
            if loc.x > frame.maxX - marginRight {
                if loc.y >= frame.minY && loc.y <= frame.minY + marginBottom + shortEdgeSize {
                    if let area = snapArea(for: .bottomRightShort, on: screen) {
                        return area
                    }
                }
                if loc.y >= frame.maxY - marginTop - shortEdgeSize && loc.y <= frame.maxY {
                    if let area = snapArea(for: .topRightShort, on: screen) {
                        return area
                    }
                }
                if loc.y >= frame.minY && loc.y <= frame.maxY && !ignoredSnapAreas.contains(.right) {
                    // right
                    if let area = portraitThirdsSnapArea(loc: loc, screen: screen, priorSnapArea: priorSnapArea) {
                        return area
                    }
                }
            }
        }
        
        if loc.y <= frame.maxY && loc.y > frame.maxY - marginTop {
            if loc.x >= frame.minX && loc.x <= frame.maxX {
                if let area = snapArea(for: .top, on: screen) {
                    return area
                }
            }
        }
        
        if loc.y >= frame.minY && loc.y < frame.minY + marginBottom && !ignoredSnapAreas.contains(.bottom) {
            
            return loc.x < frame.maxX - (frame.width / 2)
                ? SnapArea(screen: screen, action: .leftHalf)
                : SnapArea(screen: screen, action: .rightHalf)
            
        }
        return nil
    }
    
    private func portraitThirdsSnapArea(loc: NSPoint, screen: NSScreen, priorSnapArea: SnapArea?) -> SnapArea? {
        let frame = screen.frame
        let thirdHeight = floor(frame.height / 3)
        if loc.y >= frame.minY && loc.y <= frame.minY + thirdHeight {
            return SnapArea(screen: screen, action: .lastThird)
        }
        if loc.y >= frame.minY + thirdHeight && loc.y <= frame.maxY - thirdHeight {
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
        if loc.y >= frame.minY + thirdHeight && loc.y <= frame.maxY {
            return SnapArea(screen: screen, action: .firstThird)
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
