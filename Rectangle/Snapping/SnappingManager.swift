/// SnappingManager.swift

import Cocoa

struct SnapArea: Equatable {
    let screen: NSScreen
    let directional: Directional
    let action: WindowAction
}

class SnappingManager {
    
    private let fullIgnoreIds: [String] = Defaults.fullIgnoreBundleIds.typedValue ?? ["com.install4j", 
                                                                                      "com.mathworks.matlab",
                                                                                      "com.live2d.cubism.CECubismEditorApp",
                                                                                      "com.aquafold.datastudio.DataStudio",
                                                                                      "com.adobe.illustrator",
                                                                                      "com.adobe.AfterEffects"]
    
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
    
    private let marginTop = Defaults.snapEdgeMarginTop.cgFloat
    private let marginBottom = Defaults.snapEdgeMarginBottom.cgFloat
    private let marginLeft = Defaults.snapEdgeMarginLeft.cgFloat
    private let marginRight = Defaults.snapEdgeMarginRight.cgFloat
    
    init() {
        if Defaults.windowSnapping.enabled != false {
            enableSnapping()
        }
        
        registerWorkspaceChangeNote()
        registerSessionChangeNote()
        
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
        if ApplicationToggle.shortcutsDisabled {
            DispatchQueue.main.async {
                if !Defaults.ignoreDragSnapToo.userDisabled {
                    self.allowListening = false
                    self.toggleListening()
                } else {
                    for id in self.fullIgnoreIds {
                        if ApplicationToggle.frontAppId?.starts(with: id) == true {
                            self.allowListening = false
                            self.toggleListening()
                            break
                        }
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
        isFullScreen = AccessibilityElement.getFrontWindowElement()?.isFullScreen == true
        toggleListening()
    }
    
    @objc func receiveWorkspaceNote(_ notification: Notification) {
        checkFullScreen()
    }
    
    private func registerSessionChangeNote() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(receiveSessionNote(_:)), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    }
    
    @objc func receiveSessionNote(_ notification: Notification) {
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
            if let cgEvent = event.cgEvent, let screen = NSScreen.main {
                let minY = screen.frame.screenFlipped.minY
                if cgEvent.location.y == minY && dragPrevY == minY {
                    if event.deltaY < -Defaults.missionControlDraggingAllowedOffscreenDistance.cgFloat {
                        cgEvent.location.y = minY + 1
                        dragRestrictionExpirationTimestamp = DispatchTime.now().uptimeMilliseconds + UInt64(Defaults.missionControlDraggingDisallowedDuration.value)
                    } else if !dragRestrictionExpired {
                        cgEvent.location.y = minY + 1
                    }
                }
                dragPrevY = cgEvent.location.y
            }
        default:
            break
        }
        return false
    }
    
    func canSnap(_ event: NSEvent) -> Bool {
        if Defaults.snapModifiers.value > 0 {
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue != Defaults.snapModifiers.value {
                return false
            }
        }
        if let windowId = windowId {
            if StageUtil.stageCapable && StageUtil.stageEnabled && StageUtil.getStageStripWindowGroup(windowId) != nil {
                return false
            }
        }
        return true
    }
    
    func handle(event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            // A manual grab owns the window from this point onward.
            WindowAnimator.shared.finish()
            if !Defaults.obtainWindowOnClick.userDisabled {
                windowElement = AccessibilityElement.getWindowElementUnderCursor()
                windowId = windowElement?.getWindowId()
                initialWindowRect = windowElement?.frame
            }
        case .leftMouseUp:
            // Only a drag release should settle drag restoration. A title-bar
            // double-click can start maximize/restore on this same mouse-up;
            // another event monitor must not immediately finish that animation.
            if windowMoving { WindowAnimator.shared.finish() }
            if let currentSnapArea = self.currentSnapArea {
                box?.orderOut(nil)
                currentSnapArea.action.postSnap(windowElement: windowElement, windowId: windowId, screen: currentSnapArea.screen)
                self.currentSnapArea = nil
            } else {
                // it's possible that the window has moved, but the mouse dragged events are not getting the updated window position
                // this typically only happens if the user is dragging and dropping windows really quickly
                // in this scenario, the footprint doesn't display but the snap will still occur, as long as the window position is updated as of mouse up.
                if let currentRect = windowElement?.frame,
                   currentRect.size == initialWindowRect?.size,
                   currentRect.origin != initialWindowRect?.origin {
  
                    if let windowId {
                        unsnapRestore(windowId: windowId, currentRect: currentRect, cursorLoc: event.cgEvent?.location)
                    }
                    
                    if let snapArea = snapAreaContainingCursor(priorSnapArea: currentSnapArea)  {
                        box?.orderOut(nil)
                        if canSnap(event) {
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
                    windowElement = AccessibilityElement.getWindowElementUnderCursor()
                }
                windowId = windowElement?.getWindowId()
                initialWindowRect = windowElement?.frame
                windowIdAttempt += 1
                lastWindowIdAttempt = event.timestamp
            }
            guard let currentRect = windowElement?.frame
            else { return }
            
            if !windowMoving {
                if let initialWindowRect, (currentRect.size == initialWindowRect.size || currentRect.numSharedEdges(withRect: initialWindowRect) < 2) {
                    if currentRect.origin != initialWindowRect.origin {
                        windowMoving = true
                        if let windowId {
                            unsnapRestore(windowId: windowId, currentRect: currentRect, cursorLoc: event.cgEvent?.location)
                        }
                    }
                }
                else if let windowId {
                    AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowId)
                }
            }
            if windowMoving {
                if !canSnap(event) {
                    if currentSnapArea != nil {
                        box?.orderOut(nil)
                        currentSnapArea = nil
                    }
                    return
                }
                
                if let snapArea = snapAreaContainingCursor(priorSnapArea: currentSnapArea) {
                    if snapArea == currentSnapArea {
                        return
                    }
                    
                    if Defaults.hapticFeedbackOnSnap.userEnabled {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                    
                    let currentWindow = Window(id: windowId, rect: currentRect)
                    
                    if let newBoxRect = getBoxRect(hotSpot: snapArea, currentWindow: currentWindow) {
                        if box == nil {
                            box = FootprintWindow()
                        }
                        box?.showPreview(in: newBoxRect,
                                         from: getFootprintAnimationOrigin(snapArea, newBoxRect),
                                         duration: getFootprintAnimationDuration())
                    }
                    
                    currentSnapArea = snapArea
                } else {
                    if currentSnapArea != nil {
                        box?.orderOut(nil)
                        currentSnapArea = nil
                    }
                }
            }
        default:
            return
        }
    }
    
    func unsnapRestore(windowId: CGWindowID, currentRect: CGRect, cursorLoc: CGPoint?) {
        guard !Defaults.unsnapRestore.userDisabled else { return }
        
        // if window was put there by rectangle, restore size
        if let restoreRect = getRestoreRect(windowId: windowId) {
            
            if let windowElement = windowElement {
                if #available(macOS 12, *) { // earlier versions of macOS would stutter the reposition when dragging the window
                    var newRect = currentRect
                    newRect.size = restoreRect.size
                    if let cursorLoc = cursorLoc {
                        if !newRect.contains(cursorLoc) { // keep the same maxX if possible
                            newRect.origin = CGPoint(x: currentRect.maxX - newRect.width, y: newRect.minY)
                            
                            if !newRect.contains(cursorLoc) { // still doesn't contain cursor
                                newRect.origin = CGPoint(x: cursorLoc.x - (newRect.width / 2), y: newRect.minY)
                            }
                        }
                    }
                    // Let native dragging own position whenever restoring the
                    // width does not require moving the window under the cursor.
                    let resizeOnly = WindowAnimator.enabled && newRect.origin == currentRect.origin
                    var cursorOffset = CGPoint.zero
                    let initialCursor = NSEvent.mouseLocation.screenFlipped
                    WindowAnimator.shared.animate(windowElement, to: newRect, duration: 0.18, resizeOnly: resizeOnly, offset: {
                        // Follow the drag during restoration, but do not follow
                        // unrelated cursor movement after the button is released.
                        if NSEvent.pressedMouseButtons & 1 != 0 {
                            let cursor = NSEvent.mouseLocation.screenFlipped
                            cursorOffset = CGPoint(x: cursor.x - initialCursor.x, y: cursor.y - initialCursor.y)
                        }
                        return cursorOffset
                    }, curve: WindowAnimationCurve.unsnapValue) { frame in
                        windowElement.setFrame(frame, adjustSizeFirst: false, adjustPosition: !resizeOnly)
                    }
                } else {
                    windowElement.size = restoreRect.size
                }
            }
            
            AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowId)
        } else {
            AppDelegate.windowHistory.restoreRects[windowId] = initialWindowRect
        }
    }
    
    private func getRestoreRect(windowId: CGWindowID) -> CGRect? {
        guard let lastAction = AppDelegate.windowHistory.lastRectangleActions[windowId],
              lastAction.rect == initialWindowRect
        else { return nil }
        
        if lastAction.action.category == .size && Defaults.unsnapRestoreFromSizeChange.userDisabled {
            return nil
        }
        
        return AppDelegate.windowHistory.restoreRects[windowId]
    }
    
    func getFootprintAnimationDuration() -> Double {
        // The checkbox's standard multiplier uses the same duration as window
        // snapping; retain the hidden preference as a proportional adjustment.
        return WindowAnimationCurve.duration * Double(Defaults.footprintAnimationDurationMultiplier.value) / 0.75
    }
    
    func getFootprintAnimationOrigin(_ snapArea: SnapArea, _ boxRect: CGRect) -> CGPoint? {
        switch snapArea.directional {
        case .tl:
            return CGPoint(x: boxRect.minX, y: boxRect.maxY)
        case .t:
            return CGPoint(x: boxRect.midX, y: boxRect.maxY)
        case .tr:
            return CGPoint(x: boxRect.maxX, y: boxRect.maxY)
        case .l:
            return CGPoint(x: boxRect.minX, y: boxRect.midY)
        case .r:
            return CGPoint(x: boxRect.maxX, y: boxRect.midY)
        case .bl:
            return CGPoint(x: boxRect.minX, y: boxRect.minY)
        case .b:
            return CGPoint(x: boxRect.midX, y: boxRect.minY)
        case .br:
            return CGPoint(x: boxRect.maxX, y: boxRect.minY)
        default:
            return nil
        }
    }
    
    func getBoxRect(hotSpot: SnapArea, currentWindow: Window) -> CGRect? {
        if let calculation = WindowCalculationFactory.calculationsByAction[hotSpot.action] {
            
            let ignoreTodo = currentWindow.id.map { TodoManager.isTodoWindow($0) } ?? false
            let rectCalcParams = RectCalculationParameters(window: currentWindow, visibleFrameOfScreen: hotSpot.screen.adjustedVisibleFrame(ignoreTodo), action: hotSpot.action, lastAction: nil)
            let rectResult = calculation.calculateRect(rectCalcParams)
            
            let gapsApplicable = hotSpot.action.gapsApplicable
            
            if Defaults.gapSize.value > 0, gapsApplicable != .none {
                let gapSharedEdges = rectResult.subAction?.gapSharedEdge ?? hotSpot.action.gapSharedEdge

                return GapCalculation.applyGaps(rectResult.rect, dimension: gapsApplicable, sharedEdges: gapSharedEdges, gapSize: Defaults.gapSize.value, skipTopGap: Defaults.skipGapTopEdge.enabled)
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
            
            if let windowId = windowId, Defaults.todo.userEnabled && Defaults.todoMode.enabled && TodoManager.isTodoWindow(windowId) {
                if Defaults.todoSidebarSide.value == .left && directional == .l {
                    return SnapArea(screen: screen, directional: directional, action: .leftTodo)
                }
                if Defaults.todoSidebarSide.value == .right && directional == .r {
                    return SnapArea(screen: screen, directional: directional, action: .rightTodo)
                }
            }
            
            let config = screen.frame.isLandscape
            ? SnapAreaModel.instance.landscape[directional]
            : SnapAreaModel.instance.portrait[directional]
            
            if let action = config?.action {
                return SnapArea(screen: screen, directional: directional, action: action)
            }
            if let compound = config?.compound {
                return compound.calculation.snapArea(cursorLocation: loc, screen: screen, directional: directional, priorSnapArea: priorSnapArea)
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
