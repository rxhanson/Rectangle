/// SnappingManager.swift

import Cocoa

struct SnapArea: Equatable {
    let screen: NSScreen
    let directional: Directional
    let action: WindowAction
}

struct WindowDragGeometry {
    let initialFrame: CGRect?
    let currentFrame: CGRect

    init?(initialFrame: CGRect?, initialServerFrame: CGRect?, serverFrame: CGRect?, accessibilityFrame: () -> CGRect?) {
        // Compare frames from the same source; AX and WindowServer can disagree during a drag.
        if let initialServerFrame, !initialServerFrame.isNull, !initialServerFrame.isEmpty,
           let serverFrame, !serverFrame.isNull, !serverFrame.isEmpty {
            self.initialFrame = initialServerFrame
            currentFrame = serverFrame
        } else {
            guard let frame = accessibilityFrame(), !frame.isNull else { return nil }
            self.initialFrame = initialFrame
            currentFrame = frame
        }
    }

    var isResizing: Bool {
        guard let initialFrame else { return true }
        return currentFrame.size != initialFrame.size && currentFrame.numSharedEdges(withRect: initialFrame) >= 2
    }

    var isMoving: Bool {
        guard let initialFrame else { return false }
        return !isResizing && currentFrame.origin != initialFrame.origin
    }

    var movedWithoutResizing: Bool {
        initialFrame?.size == currentFrame.size && initialFrame?.origin != currentFrame.origin
    }
}

enum DragRestorePlacement {
    static func referenceCursor(current: CGRect, initial: CGRect?, mouseDown: CGPoint?, fallback: CGPoint) -> CGPoint {
        guard let initial, let mouseDown else { return fallback }
        return CGPoint(x: current.minX + mouseDown.x - initial.minX,
                       y: current.minY + mouseDown.y - initial.minY)
    }

    static func frame(from current: CGRect, size: CGSize, cursor: CGPoint?) -> CGRect {
        var restored = CGRect(origin: current.origin, size: size)
        if let cursor {
            // Move only as far as the grab point needs. Keeping the old right edge would
            // abruptly shift by the entire width difference when the cursor crosses the cutoff.
            let inset = min(32, size.width / 2)
            let neededShift = cursor.x - current.minX - (size.width - inset)
            restored.origin.x += min(max(0, neededShift), max(0, current.width - size.width))
        }
        return restored
    }
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
    private var initialWindowServerRect: CGRect?
    private var initialCursorLocation: CGPoint?
    private var releaseDragRestore: ((CGPoint?) -> Void)?
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
            WindowAnimator.shared.finish()
            releaseDragRestore = nil
            initialCursorLocation = event.cgEvent?.location
            if !Defaults.obtainWindowOnClick.userDisabled {
                windowElement = AccessibilityElement.getWindowElementUnderCursor()
                windowId = windowElement?.getWindowId()
                initialWindowRect = windowElement?.frame
                initialWindowServerRect = windowId.flatMap { WindowUtil.getWindowFrame(id: $0) }
            }
        case .leftMouseUp:
            releaseDragRestore?(event.cgEvent?.location)
            releaseDragRestore = nil
            // A quick release must not jump to the end of drag restoration.
            // Its cursor offset freezes on release, so the remaining frames can settle normally.
            if windowMoving, currentSnapArea != nil { WindowAnimator.shared.finish() }
            if let currentSnapArea = self.currentSnapArea {
                box?.orderOut(nil)
                currentSnapArea.action.postSnap(windowElement: windowElement, windowId: windowId, screen: currentSnapArea.screen)
                self.currentSnapArea = nil
            } else {
                // it's possible that the window has moved, but the mouse dragged events are not getting the updated window position
                // this typically only happens if the user is dragging and dropping windows really quickly
                // in this scenario, the footprint doesn't display but the snap will still occur, as long as the window position is updated as of mouse up.
                if let geometry = dragGeometry(), geometry.movedWithoutResizing {
  
                    // Displayed bounds may still have the old size just after finish().
                    if !windowMoving, let windowId {
                        unsnapRestore(windowId: windowId, currentRect: geometry.currentFrame, cursorLoc: event.cgEvent?.location)
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
            initialWindowServerRect = nil
            initialCursorLocation = nil
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
                initialWindowServerRect = windowId.flatMap { WindowUtil.getWindowFrame(id: $0) }
                windowIdAttempt += 1
                lastWindowIdAttempt = event.timestamp
            }
            var currentRect: CGRect?
            if !windowMoving {
                guard let geometry = dragGeometry() else { return }
                currentRect = geometry.currentFrame
                if geometry.isMoving {
                    windowMoving = true
                    if let windowId {
                        unsnapRestore(windowId: windowId, currentRect: geometry.currentFrame, cursorLoc: event.cgEvent?.location)
                    }
                }
                else if geometry.isResizing, let windowId {
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

                    guard let currentRect = currentRect ?? dragGeometry()?.currentFrame else { return }
                    
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
    
    private func dragGeometry() -> WindowDragGeometry? {
        WindowDragGeometry(initialFrame: initialWindowRect, initialServerFrame: initialWindowServerRect,
                           serverFrame: windowId.flatMap { WindowUtil.getWindowFrame(id: $0) },
                           accessibilityFrame: { windowElement?.frame })
    }

    func unsnapRestore(windowId: CGWindowID, currentRect: CGRect, cursorLoc: CGPoint?) {
        guard !Defaults.unsnapRestore.userDisabled else { return }
        
        // if window was put there by rectangle, restore size
        if let restoreRect = getRestoreRect(windowId: windowId) {
            
            if let windowElement = windowElement {
                if #available(macOS 12, *) { // earlier versions of macOS would stutter the reposition when dragging the window
                    // Pair the displayed frame with its native grab point, not a newer mouse sample.
                    let initialCursor = DragRestorePlacement.referenceCursor(current: currentRect, initial: initialWindowRect,
                                                                              mouseDown: initialCursorLocation,
                                                                              fallback: cursorLoc ?? NSEvent.mouseLocation.screenFlipped)
                    let newRect = DragRestorePlacement.frame(from: currentRect, size: restoreRect.size, cursor: initialCursor)
                    // Preserve native drag positioning unless restoration requires a new origin.
                    let resizeOnly = WindowAnimator.enabled && newRect.origin == currentRect.origin
                    var cursorOffset = CGPoint.zero
                    var released = false
                    releaseDragRestore = { cursor in
                        if let cursor {
                            cursorOffset = CGPoint(x: cursor.x - initialCursor.x, y: cursor.y - initialCursor.y)
                        }
                        released = true
                    }
                    WindowAnimator.shared.animate(windowElement, from: currentRect, to: newRect, duration: 0.18, resizeOnly: resizeOnly, offset: {
                        // Freeze the drag offset when the mouse button is released.
                        if !released, NSEvent.pressedMouseButtons & 1 != 0 {
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
        // The checkbox uses 0.75; normalize it to the window animation duration.
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
