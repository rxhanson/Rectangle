//
//  SnappingManager.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/4/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

struct SnapArea: Equatable {
    let screen: NSScreen
    let action: WindowAction
}

class SnappingManager {
    
    private let fullIgnoreIds: [String] = Defaults.fullIgnoreBundleIds.typedValue ?? ["com.install4j", "com.mathworks.matlab", "com.live2d.cubism.CECubismEditorApp", "com.aquafold.datastudio.DataStudio"]
    
    var eventMonitor: EventMonitor?
    var windowElement: AccessibilityElement?
    var windowId: CGWindowID?
    var windowIdAttempt: Int = 0
    var lastWindowIdAttempt: TimeInterval?
    var windowMoving: Bool = false
    var isFullScreen: Bool = false
    var allowListening: Bool = true
    var initialWindowRect: CGRect?
    var currentSnapArea: SnapArea?
    var dragPrevY: Double?
    var dragRestrictionExpirationTimestamp: UInt64 = 0
    var dragRestrictionExpired: Bool { DispatchTime.now().uptimeMilliseconds > dragRestrictionExpirationTimestamp }
    
    var box: FootprintWindow?

    let screenDetection = ScreenDetection()
    let applicationToggle: ApplicationToggle
    
    private let marginTop = Defaults.snapEdgeMarginTop.cgFloat
    private let marginBottom = Defaults.snapEdgeMarginBottom.cgFloat
    private let marginLeft = Defaults.snapEdgeMarginLeft.cgFloat
    private let marginRight = Defaults.snapEdgeMarginRight.cgFloat
    
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
        Notification.Name.missionControlDragging.onPost { notification in
            self.stopEventMonitor()
            self.startEventMonitor()
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
            if eventMonitor?.running == true {
                if Defaults.missionControlDragging.userDisabled != (eventMonitor is ActiveEventMonitor) {
                    stopEventMonitor()
                    startEventMonitor()
                }
            } else {
                enableSnapping()
            }
        }
    }
    
    private func enableSnapping() {
        if box == nil {
            box = FootprintWindow()
        }
        if eventMonitor == nil {
            startEventMonitor()
        }
    }
    
    private func disableSnapping() {
        box = nil
        stopEventMonitor()
    }
    
    private func startEventMonitor() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
        eventMonitor = Defaults.missionControlDragging.userDisabled ? ActiveEventMonitor(mask: mask, filterer: filter, handler: handle) : PassiveEventMonitor(mask: mask, handler: handle)
        eventMonitor?.start()
    }
    
    private func stopEventMonitor() {
        eventMonitor?.stop()
        eventMonitor = nil
    }
    
    func filter(event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseUp:
            dragPrevY = nil
        case .leftMouseDragged:
            if let cgEvent = event.cgEvent {
                if cgEvent.location.y == 0 && dragPrevY == 0 {
                    if event.deltaY < -25 {
                        cgEvent.location.y = 1
                        dragRestrictionExpirationTimestamp = DispatchTime.now().uptimeMilliseconds + 250
                    } else if !dragRestrictionExpired {
                        cgEvent.location.y = 1
                    }
                }
                dragPrevY = cgEvent.location.y
            }
        default:
            break
        }
        return false
    }
    
    func handle(event: NSEvent) {
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
                        box?.setFrame(.zero, display: false)
                        box?.makeKeyAndOrderFront(nil)
                        box?.setFrame(newBoxRect, display: true)
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
    
    func unsnapRestore(windowId: CGWindowID) {
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
            guard let directional = directionalLocationOfCursor(loc: loc, screen: screen)
            else { continue }
            
            let config = screen.frame.isLandscape
            ? SnapAreaModel.instance.landscape[directional]
            : SnapAreaModel.instance.portrait[directional]
            
            if let action = config?.action {
                return SnapArea(screen: screen, action: action)
            }
            if let compound = config?.compound {
                return compound.calculation.snapArea(cursorLocation: loc, screen: screen, priorSnapArea: priorSnapArea)
            }
        }
        
        return nil
    }
    
    func directionalLocationOfCursor(loc: NSPoint, screen: NSScreen) -> Directional? {
        let frame = screen.frame
        let cornerSize = Defaults.cornerSnapAreaSize.cgFloat
        
        /// cgrect contains doesn't include max edges, so manually compare
        guard loc.x >= frame.minX,
              loc.x <= frame.maxX,
              loc.y >= frame.minY,
              loc.y <= frame.maxY
        else { return nil }
        
        if loc.x < frame.minX + marginLeft + cornerSize {
            if loc.y >= frame.maxY - marginTop - cornerSize {
                return .tl
            }
            if loc.y <= frame.minY + marginBottom + cornerSize {
                return .bl
            }
            if loc.x < frame.minX + marginLeft {
                return .l
            }
        }
        
        if loc.x > frame.maxX - marginRight - cornerSize {
            if loc.y >= frame.maxY - marginTop - cornerSize {
                return .tr
            }
            if loc.y <= frame.minY + marginBottom + cornerSize {
                return .br
            }
            if loc.x > frame.maxX - marginRight {
                return .r
            }
        }
        
        if loc.y > frame.maxY - marginTop {
            return .t
        }
        if loc.y < frame.minY + marginBottom {
            return .b
        }
        
        return nil
    }
}
