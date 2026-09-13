/// SnappingManager.swift

import Cocoa

struct SnapArea: Equatable {
    let screen: NSScreen
    let directional: Directional
    let action: WindowAction
}

struct NativeSnapGesture {
    private(set) var generation = UUID()
    private(set) var held = false
    private(set) var cancelled = false
    private(set) var observedDrag = false

    mutating func begin() { generation = UUID(); held = true; cancelled = false; observedDrag = false }
    mutating func drag() { if held { observedDrag = true } }
    mutating func cancel() { if held { cancelled = true } }
    mutating func end() { held = false }
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

    static func releasedMovement(initialAX: CGRect, initialServer: CGRect, ax: CGRect, server: CGRect?) -> Bool {
        let serverGeometry = WindowDragGeometry(initialFrame: initialAX, initialServerFrame: initialServer,
            serverFrame: server, accessibilityFrame: { nil })
        if serverGeometry?.movedWithoutResizing == true { return true }
        // The two mouse-down reads may straddle the first native movement.
        // AX catching up still proves movement against its own baseline, but
        // a persistent difference between coordinate sources does not.
        guard let server, WindowRecoveryGeometry.near(ax, server, tolerance: 1),
              !WindowRecoveryGeometry.near(initialAX, ax, tolerance: 1) else { return false }
        return WindowDragGeometry(initialFrame: initialAX, initialServerFrame: nil, serverFrame: nil,
            accessibilityFrame: { ax })?.movedWithoutResizing == true
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
    private var initialEventWindowID: CGWindowID?
    private var latestNativeDragEvent: CGEvent?
    private var nativeGesture = NativeSnapGesture()
    private var pendingReleasedRestore: UUID?
    private struct NativeSizeRestore {
        let windowID: CGWindowID
        let size: CGSize
        var lastAttemptOrigin: CGPoint
    }
    private var nativeSizeRestore: NativeSizeRestore?
    private lazy var restoreDragController = FrostedRestoreDragController(owner: self)
    private final class PreviewDrag {
        let token: UUID
        let candidate: FrostedRestoreDragCandidate
        let down: CGPoint
        var started = false
        var released = false
        var releaseWatch = FrostedRestoreDragReleaseWatch()
        init(token: UUID, candidate: FrostedRestoreDragCandidate, frame: CGRect, down: CGPoint) {
            self.token = token
            self.down = down
            self.candidate = FrostedRestoreDragCandidate(element: candidate.element, rawWindow: candidate.rawWindow,
                pid: candidate.pid, windowID: candidate.windowID, original: frame, restoreSize: candidate.restoreSize,
                safeRegions: candidate.safeRegions, cachedAt: candidate.cachedAt)
        }
    }
    private var previewDrag: PreviewDrag?
    private var previewReleaseTimer: Timer?
    private var ownedRestoreID: UUID?
    private var ownedRestoreSnap: SnapArea?
    private var ownedRestoreFallbackSnap: SnapArea?
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
        WindowAnimator.shared.previewDragHandler = { [weak self] token, candidate, frame, event in
            self?.handlePreviewDrag(token: token, candidate: candidate, frame: frame, event: event)
        }
        WindowAnimator.shared.previewDragEnded = { [weak self] token in self?.clearPreviewDrag(token) }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .keyDown]
        eventMonitor = Defaults.missionControlDragging.userDisabled ? ActiveEventMonitor(mask: mask, filterer: filter, handler: handle) : PassiveEventMonitor(mask: mask, handler: handle)
        eventMonitor?.start()
        // Insert after the ordinary monitor so this tap sees the original down
        // first and can own an eligible gesture before native dragging begins.
        restoreDragController.start()
    }
    
    private func stopEventMonitor() {
        pendingReleasedRestore = nil
        if let previewDrag { WindowAnimator.shared.cancelOwnedDrag(previewDrag.token) }
        if let previewDrag { clearPreviewDrag(previewDrag.token) }
        WindowAnimator.shared.previewDragHandler = nil
        WindowAnimator.shared.previewDragEnded = nil
        restoreDragController.stop()
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
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == FrostedRestoreDragRules.handoffMarker { return }
        if restoreDragController.ownsGesture { return }
        switch event.type {
        case .keyDown:
            guard event.keyCode == 53, nativeGesture.held else { return }
            nativeGesture.cancel()
            WindowAnimator.shared.cancelDeferredNativeRestore()
            currentSnapArea = nil
            box?.orderOut(nil)
            // A drag waiting for another window can be held still. Escape
            // must finish its native cancellation without another pointer move.
            if let windowId, let event = latestNativeDragEvent,
               let geometry = dragGeometry(), geometry.movedWithoutResizing {
                _ = beginNativeFrostRestore(windowID: windowId, current: geometry.currentFrame, event: event)
            }
        case .leftMouseDown:
            beginNativeDrag()
            WindowAnimator.shared.finishForNewDrag()
            initialCursorLocation = event.cgEvent?.location
            // The main queue can handle this after the pointer and window have
            // already moved. Keep the event's original target for all retries.
            initialEventWindowID = event.cgEvent.flatMap {
                let id = $0.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
                return id > 0 ? CGWindowID(exactly: id) : nil
            }
            if !Defaults.obtainWindowOnClick.userDisabled {
                windowElement = AccessibilityElement.getWindowElementUnderCursor(at: initialCursorLocation, eventWindowID: initialEventWindowID)
                windowId = windowElement?.getWindowId()
                initialWindowRect = windowElement?.frame
                initialWindowServerRect = windowId.flatMap { WindowUtil.getWindowFrame(id: $0) }
            }
            traceNativeInput(event, phase: "down")
        case .leftMouseUp:
            WindowAnimator.shared.cancelDeferredNativeRestore()
            if restoreDragController.nativeDragCancelled { nativeGesture.cancel() }
            nativeGesture.end()
            traceNativeInput(event, phase: "up")
            if !windowMoving, let windowId, let geometry = dragGeometry(), geometry.movedWithoutResizing,
               beginNativeFrostRestore(windowID: windowId, current: geometry.currentFrame, event: event.cgEvent) { return }
            reconcileLateNativeRelease(event)
            // Owned restoration releases through its tap; this is the native path.
            if windowMoving, currentSnapArea != nil { WindowAnimator.shared.finish() }
            if currentSnapArea != nil {
                // A coalesced final drag can leave the preview on the previous screen.
                // Commit the release event's position, including withdrawal from an edge.
                currentSnapArea = snapAreaForNativeRelease(event)
                if currentSnapArea == nil { box?.orderOut(nil) }
            }
            if let currentSnapArea = self.currentSnapArea {
                nativeSizeRestore = nil
                dismissSnapPreviewForCommit()
                currentSnapArea.action.postSnap(windowElement: windowElement, windowId: windowId, screen: currentSnapArea.screen)
                self.currentSnapArea = nil
            } else {
                // it's possible that the window has moved, but the mouse dragged events are not getting the updated window position
                // this typically only happens if the user is dragging and dropping windows really quickly
                // in this scenario, the footprint doesn't display but the snap will still occur, as long as the window position is updated as of mouse up.
                if !nativeGesture.cancelled, let geometry = dragGeometry(), geometry.movedWithoutResizing {
  
                    // Displayed bounds may still have the old size just after finish().
                    if !windowMoving, let windowId {
                        unsnapRestore(windowId: windowId, currentRect: geometry.currentFrame, cursorLoc: event.cgEvent?.location)
                    }
                    
                    if let snapArea = snapAreaContainingCursor(priorSnapArea: currentSnapArea, event: event)  {
                        dismissSnapPreviewForCommit()
                        if canSnap(event) {
                            snapArea.action.postSnap(windowElement: windowElement, windowId: windowId, screen: snapArea.screen)
                        }
                        self.currentSnapArea = nil
                    }
                }
            }
            finishNativeSizeRestore()
            windowElement = nil
            windowId = nil
            windowMoving = false
            initialWindowRect = nil
            initialWindowServerRect = nil
            initialCursorLocation = nil
            initialEventWindowID = nil
            latestNativeDragEvent = nil
            windowIdAttempt = 0
            lastWindowIdAttempt = nil
        case .leftMouseDragged:
            latestNativeDragEvent = event.cgEvent?.copy()
            nativeGesture.drag()
            if restoreDragController.nativeDragCancelled { nativeGesture.cancel() }
            if nativeGesture.cancelled {
                if let windowId, let geometry = dragGeometry(), geometry.movedWithoutResizing {
                    _ = beginNativeFrostRestore(windowID: windowId, current: geometry.currentFrame, event: event.cgEvent)
                }
                return
            }
            if windowId == nil, windowIdAttempt < 20 {
                if let lastWindowIdAttempt = lastWindowIdAttempt {
                    if event.timestamp - lastWindowIdAttempt < 0.1 {
                        return
                    }
                }
                if windowElement == nil {
                    windowElement = AccessibilityElement.getWindowElementUnderCursor(at: initialCursorLocation, eventWindowID: initialEventWindowID)
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
                        if beginNativeFrostRestore(windowID: windowId, current: geometry.currentFrame, event: event.cgEvent) { return }
                        if restoreDragController.nativeDragCancelled { nativeGesture.cancel(); return }
                        unsnapRestore(windowId: windowId, currentRect: geometry.currentFrame, cursorLoc: event.cgEvent?.location)
                    }
                }
                else if geometry.isResizing, let windowId {
                    AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowId)
                }
            }
            if windowMoving {
                retryNativeSizeRestore(cursor: event.cgEvent?.location)
                if !canSnap(event) {
                    if currentSnapArea != nil {
                        box?.orderOut(nil)
                        currentSnapArea = nil
                    }
                    return
                }
                
                if let snapArea = snapAreaContainingCursor(priorSnapArea: currentSnapArea, event: event) {
                    if snapArea == currentSnapArea {
                        return
                    }

                    guard let currentRect = currentRect ?? dragGeometry()?.currentFrame else { return }
                    
                    if Defaults.hapticFeedbackOnSnap.userEnabled {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                    
                    let currentWindow = Window(id: windowId, rect: currentRect)
                    
                    if let newBoxRect = getBoxRect(hotSpot: snapArea, currentWindow: currentWindow) {
                        showSnapPreview(in: newBoxRect, snapArea: snapArea)
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

    private func traceNativeInput(_ event: NSEvent, phase: String) {
        guard WindowFrostDiagnostics.enabled else { return }
        func fields(_ frame: CGRect?) -> [CGFloat] {
            guard let frame else { return [] }
            return [frame.minX, frame.minY, frame.width, frame.height]
        }
        WindowFrostDiagnostics.event("native-input-" + phase, fields: ["windowID": windowId ?? 0,
            "initialAX": fields(initialWindowRect), "initialServer": fields(initialWindowServerRect),
            "history": fields(windowId.flatMap { AppDelegate.windowHistory.lastRectangleActions[$0]?.rect }),
            "moving": windowMoving, "dragged": nativeGesture.observedDrag, "cancelled": nativeGesture.cancelled,
            "targetPID": event.cgEvent?.getIntegerValueField(.eventTargetUnixProcessID) ?? 0,
            "pointerWindow": event.cgEvent?.getIntegerValueField(.mouseEventWindowUnderMousePointer) ?? 0,
            "handlingWindow": event.cgEvent?.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent) ?? 0,
            "eventTimestamp": event.cgEvent?.timestamp ?? 0,
            "eventCursor": event.cgEvent.map { [$0.location.x, $0.location.y] } ?? [],
            "globalCursor": [NSEvent.mouseLocation.screenFlipped.x, NSEvent.mouseLocation.screenFlipped.y]])
    }

    func finishNativeRestore(element: AccessibilityElement, windowID: CGWindowID, frame: CGRect, release: CGEvent) {
        element.setFrame(frame)
        AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowID)
        if let event = NSEvent(cgEvent: release), canSnap(event),
           let area = snapAreaContainingCursor(priorSnapArea: nil, at: release.location.screenFlipped) {
            area.action.postSnap(windowElement: element, windowId: windowID, screen: area.screen)
        }
    }

    /// A very short native drag can deliver mouse-up before either geometry
    /// source reports movement. Retain this release, but never reuse it after
    /// another mouse-down or an unrelated change to the window's snap history.
    private func reconcileLateNativeRelease(_ event: NSEvent) {
        guard WindowAnimator.frostedEnabled, !Defaults.unsnapRestore.userDisabled,
              nativeGesture.observedDrag, (!windowMoving || nativeGesture.cancelled),
              let element = windowElement, let id = windowId,
              let initial = initialWindowRect, let restore = getRestoreRect(windowId: id),
              restore.size != initial.size, let release = event.cgEvent?.copy(),
              nativeGesture.cancelled || dragGeometry()?.movedWithoutResizing != true else { return }
        let operation = UUID()
        pendingReleasedRestore = operation
        let cancelled = nativeGesture.cancelled
        let down = initialCursorLocation
        let initialServer = initialWindowServerRect ?? initial
        var settlement = FrostedNativeDragSettlement(startedAt: ProcessInfo.processInfo.systemUptime)
        func finish(_ reason: String) {
            guard self.pendingReleasedRestore == operation, !self.nativeGesture.held,
                  !self.restoreDragController.hasMouseDown(after: release.timestamp) else { return }
            self.pendingReleasedRestore = nil
            if cancelled {
                element.setFrame(initial)
            } else {
                let destination = FrostedRestoreDragRules.destination(original: initial, restoreSize: restore.size,
                    mouseDown: down ?? release.location, cursor: release.location,
                    screenFrame: NSScreen.screens.map { $0.frame.screenFlipped }.first { $0.contains(initial) })
                self.finishNativeRestore(element: element, windowID: id, frame: destination, release: release)
            }
            WindowFrostDiagnostics.event(reason, fields: ["windowID": id, "cancelled": cancelled])
        }
        func poll() {
            guard self.pendingReleasedRestore == operation, !self.nativeGesture.held,
                  !self.restoreDragController.hasMouseDown(after: release.timestamp),
                  self.allowListening, WindowAnimator.frostedEnabled,
                  !Defaults.unsnapRestore.userDisabled,
                  element.pid == NSWorkspace.shared.frontmostApplication?.processIdentifier,
                  element.getWindowId() == id,
                  AppDelegate.windowHistory.lastRectangleActions[id]?.rect == initial else { return }
            let ax = element.frame
            let server = WindowUtil.getWindowFrame(id: id)
            let moved = WindowDragGeometry.releasedMovement(initialAX: initial, initialServer: initialServer,
                                                             ax: ax, server: server)
            if WindowFrostDiagnostics.enabled {
                WindowFrostDiagnostics.event("native-late-release-sample", fields: ["windowID": id, "moved": moved,
                    "ax": [ax.minX, ax.minY, ax.width, ax.height],
                    "server": server.map { [$0.minX, $0.minY, $0.width, $0.height] } ?? []])
            }
            switch settlement.observe(ax: moved ? ax : nil, server: server,
                                      at: ProcessInfo.processInfo.systemUptime) {
            case .ready:
                finish("native-late-release-settled")
            case .timedOut:
                // Stale AX readback still forbids parking/Frost. After release,
                // proven WindowServer movement can use the ordinary placement.
                if moved {
                    finish("native-late-release-fallback")
                } else {
                    self.pendingReleasedRestore = nil
                    WindowFrostDiagnostics.event("native-late-release-timeout", fields: ["windowID": id])
                }
            case .waiting:
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 120, execute: poll)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 120, execute: poll)
    }

    private func beginNativeFrostRestore(windowID: CGWindowID, current: CGRect, event: CGEvent?) -> Bool {
        guard WindowAnimator.frostedEnabled, !Defaults.unsnapRestore.userDisabled,
              let event, event.type == .leftMouseDragged || event.type == .leftMouseUp,
              let windowElement, let initialWindowRect,
              let restore = getRestoreRect(windowId: windowID), restore.size != current.size else { return false }
        let generation = nativeGesture.generation
        if event.type == .leftMouseDragged, !nativeGesture.cancelled,
           WindowAnimator.shared.deferNativeRestoreIfBusy(with: windowElement, action: { [weak self] in
               guard let self, self.nativeGesture.generation == generation, self.nativeGesture.held,
                     !self.nativeGesture.cancelled, !self.windowMoving, self.windowId == windowID,
                     self.restoreDragController.hasHeldNativeDrag(at: event.timestamp),
                     let event = NSEvent(cgEvent: event) else { return }
               self.handle(event: event)
           }) {
            // Native dragging remains in charge until the previous window's
            // recovery finishes. Keep the latest event, including a held pause.
            windowMoving = false
            return true
        }
        let cursor = DragRestorePlacement.referenceCursor(current: current, initial: initialWindowRect,
            mouseDown: initialCursorLocation, fallback: event.location)
        return restoreDragController.beginNativeRestore(element: windowElement, windowID: windowID,
            source: current, historyFrame: initialWindowRect, restoreSize: restore.size,
            referenceCursor: cursor, event: event)
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
                    // Native drag restoration applies the saved size immediately.
                    // Frosted drags use their separate owned handoff before this fallback.
                    windowElement.setFrame(newRect, adjustSizeFirst: false,
                                           adjustPosition: newRect.origin != currentRect.origin)
                    // AX can report success while the Dock limits only the width.
                    // Keep the unachieved size after consuming snap history so the
                    // native drag can make room for it on a later event.
                    let achieved = windowElement.frame
                    if needsNativeSizeRestore(achieved.size, to: restoreRect.size) {
                        nativeSizeRestore = NativeSizeRestore(windowID: windowId, size: restoreRect.size,
                                                              lastAttemptOrigin: currentRect.origin)
                    }
                    WindowFrostDiagnostics.event("native-size-restore", fields: ["windowID": windowId,
                        "requested": [restoreRect.width, restoreRect.height],
                        "achieved": [achieved.width, achieved.height], "pending": nativeSizeRestore != nil])
                } else {
                    windowElement.size = restoreRect.size
                }
            }
            
            AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowId)
        } else {
            AppDelegate.windowHistory.restoreRects[windowId] = initialWindowRect
        }
    }

    private func needsNativeSizeRestore(_ actual: CGSize, to requested: CGSize) -> Bool {
        actual.width < requested.width - 1 || actual.height < requested.height - 1
    }

    private func retryNativeSizeRestore(cursor: CGPoint?) {
        guard var pending = nativeSizeRestore, pending.windowID == windowId,
              let windowElement, !Defaults.unsnapRestore.userDisabled else { return }
        let current = windowElement.frame
        guard WindowRecoveryGeometry.valid(current) else { return }
        guard needsNativeSizeRestore(current.size, to: pending.size) else {
            nativeSizeRestore = nil
            return
        }
        guard current.origin != pending.lastAttemptOrigin else { return }
        let point = cursor ?? current.centerPoint
        if let screen = NSScreen.screens.first(where: { $0.frame.screenFlipped.contains(point) }) {
            let bounds = screen.visibleFrame.screenFlipped
            // Do not repeatedly ask for growth that still cannot fit at the
            // native drag's current origin. Position remains owned by the app.
            if current.width < pending.size.width - 1 && current.minX + pending.size.width > bounds.maxX { return }
            if current.height < pending.size.height - 1 && current.minY + pending.size.height > bounds.maxY { return }
        }
        pending.lastAttemptOrigin = current.origin
        nativeSizeRestore = pending
        windowElement.setFrame(CGRect(origin: current.origin, size: pending.size),
                               adjustSizeFirst: false, adjustPosition: false)
        let achieved = windowElement.frame
        if !needsNativeSizeRestore(achieved.size, to: pending.size) { nativeSizeRestore = nil }
        WindowFrostDiagnostics.event("native-size-restore-retry", fields: ["windowID": pending.windowID,
            "requested": [pending.size.width, pending.size.height],
            "achieved": [achieved.width, achieved.height], "pending": nativeSizeRestore != nil])
    }

    private func finishNativeSizeRestore() {
        guard let pending = nativeSizeRestore, let element = windowElement,
              AppDelegate.windowHistory.lastRectangleActions[pending.windowID] == nil else {
            nativeSizeRestore = nil
            return
        }
        nativeSizeRestore = nil
        let operation = UUID()
        pendingReleasedRestore = operation
        // Wait until mouse-up has left native tracking before moving a short
        // release far enough inside its display to accept the full saved size.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pendingReleasedRestore == operation, !self.nativeGesture.held,
                  !Defaults.unsnapRestore.userDisabled,
                  AppDelegate.windowHistory.lastRectangleActions[pending.windowID] == nil else { return }
            self.pendingReleasedRestore = nil
            let current = element.frame
            guard WindowRecoveryGeometry.valid(current), self.needsNativeSizeRestore(current.size, to: pending.size) else { return }
            var target = CGRect(origin: current.origin, size: pending.size)
            if let screen = NSScreen.screens.first(where: { $0.frame.screenFlipped.contains(current.origin) }) {
                target = WindowFrameBounds.constrained(target, to: screen.visibleFrame.screenFlipped, gap: 0)
            }
            element.setFrame(target, adjustSizeFirst: false)
            let achieved = element.frame
            WindowFrostDiagnostics.event("native-size-restore-released", fields: ["windowID": pending.windowID,
                "requested": [pending.size.width, pending.size.height],
                "achieved": [achieved.width, achieved.height]])
        }
    }

    private func clearPreviewDrag(_ token: UUID) {
        guard previewDrag?.token == token else { return }
        previewDrag = nil
        previewReleaseTimer?.invalidate()
        previewReleaseTimer = nil
    }

    private func handlePreviewDrag(token: UUID, candidate: FrostedRestoreDragCandidate, frame: CGRect, event: CGEvent) {
        if event.type == .leftMouseDown {
            guard allowListening, !isFullScreen else { WindowAnimator.shared.cancelOwnedDrag(token); return }
            let gesture = PreviewDrag(token: token, candidate: candidate, frame: frame, down: event.location)
            previewDrag = gesture
            _ = gesture.releaseWatch.shouldRecover(hidDown: CGEventSource.buttonState(.hidSystemState, button: .left),
                sessionDown: CGEventSource.buttonState(.combinedSessionState, button: .left), now: ProcessInfo.processInfo.systemUptime)
            previewReleaseTimer?.invalidate()
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self, weak gesture] _ in
                guard let self, let gesture, self.previewDrag === gesture, !gesture.released else { return }
                if gesture.releaseWatch.shouldRecover(hidDown: CGEventSource.buttonState(.hidSystemState, button: .left),
                    sessionDown: CGEventSource.buttonState(.combinedSessionState, button: .left), now: ProcessInfo.processInfo.systemUptime) {
                    WindowAnimator.shared.cancelOwnedDrag(token)
                }
            }
            previewReleaseTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            return
        }
        guard let gesture = previewDrag, gesture.token == token, !gesture.released else { return }
        if event.type == .leftMouseDragged {
            if !gesture.started {
                guard FrostedRestoreDragRules.crossedThreshold(from: gesture.down, to: event.location) else { return }
                guard beginOwnedRestore(candidate: gesture.candidate, mouseDown: gesture.down, cursor: event.location,
                    existingToken: token, finished: { [weak self] in self?.clearPreviewDrag(token) }) != nil else {
                    WindowAnimator.shared.cancelOwnedDrag(token)
                    return
                }
                guard previewDrag === gesture else { return }
                gesture.started = true
            }
            updateOwnedRestore(token: token, candidate: gesture.candidate, mouseDown: gesture.down, cursor: event.location, event: event)
        } else if event.type == .leftMouseUp {
            gesture.released = true
            previewReleaseTimer?.invalidate()
            if gesture.started {
                endOwnedRestore(token: token, candidate: gesture.candidate, mouseDown: gesture.down, cursor: event.location, event: event)
            } else {
                clearPreviewDrag(token)
                WindowAnimator.shared.resumePreviewClick(token)
            }
        }
    }

    func beginOwnedRestore(candidate: FrostedRestoreDragCandidate, mouseDown: CGPoint, cursor: CGPoint,
                           existingToken: UUID? = nil, finished: @escaping () -> Void) -> UUID? {
        guard WindowAnimator.frostedEnabled, allowListening, !isFullScreen,
              existingToken != nil || AppDelegate.windowHistory.lastRectangleActions[candidate.windowID]?.rect == (candidate.historyFrame ?? candidate.original) else { return nil }
        let operation = UUID()
        let nativeGeneration = nativeGesture.generation
        ownedRestoreID = operation
        ownedRestoreSnap = nil
        ownedRestoreFallbackSnap = nil
        let destination = FrostedRestoreDragRules.destination(original: candidate.original, restoreSize: candidate.restoreSize,
                                                              mouseDown: mouseDown, cursor: cursor,
                                                              screenFrame: NSScreen.screens.map { $0.frame.screenFlipped }.first { $0.contains(candidate.original) })
        let completion: (CGRect?) -> Void = { [weak self] frame in
            guard let self, self.ownedRestoreID == operation else { return }
            let fallback = self.ownedRestoreFallbackSnap
            if let frame {
                if let snap = self.ownedRestoreSnap {
                    AppDelegate.windowHistory.lastRectangleActions[candidate.windowID] = RectangleAction(
                        action: snap.action, subAction: nil, rect: frame, count: 1)
                } else {
                    AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: candidate.windowID)
                }
            }
            self.cancelOwnedRestore(nativeGeneration: nativeGeneration)
            finished()
            if frame != nil { Notification.Name.windowActionCompleted.post() }
            if frame != nil, let fallback {
                fallback.action.postSnap(windowElement: candidate.element, windowId: candidate.windowID, screen: fallback.screen)
            }
        }
        let offset = CGPoint(x: cursor.x - mouseDown.x, y: cursor.y - mouseDown.y)
        let token: UUID?
        if let existingToken {
            token = WindowAnimator.shared.adoptPreviewDrag(existingToken, element: candidate.element,
                destination: destination, initialCursorOffset: offset, completion: completion)
        } else {
            token = WindowAnimator.shared.beginOwnedDrag(candidate.element, from: candidate.original,
                to: destination, initialCursorOffset: offset, cancellationFrame: candidate.historyFrame,
                completion: completion)
        }
        guard let token else {
            if ownedRestoreID == operation { cancelOwnedRestore() }
            return nil
        }
        guard ownedRestoreID == operation else {
            WindowAnimator.shared.cancelOwnedDrag(token)
            return nil
        }
        windowElement = candidate.element
        windowId = candidate.windowID
        initialWindowRect = candidate.original
        initialWindowServerRect = candidate.original
        initialCursorLocation = mouseDown
        windowMoving = true
        return token
    }

    func updateOwnedRestore(token: UUID, candidate: FrostedRestoreDragCandidate, mouseDown: CGPoint, cursor: CGPoint, event: CGEvent) {
        guard ownedRestoreID != nil else { return }
        let destination = FrostedRestoreDragRules.destination(original: candidate.original, restoreSize: candidate.restoreSize,
                                                              mouseDown: mouseDown, cursor: cursor,
                                                              screenFrame: NSScreen.screens.map { $0.frame.screenFlipped }.first { $0.contains(candidate.original) })
        WindowAnimator.shared.updateOwnedDrag(token, destination: destination)
        guard let nsEvent = NSEvent(cgEvent: event), canSnap(nsEvent),
              let snap = snapAreaContainingCursor(priorSnapArea: currentSnapArea, at: cursor.screenFlipped) else {
            if box?.realIsVisible == true { box?.orderOut(nil) }
            currentSnapArea = nil
            return
        }
        guard snap != currentSnapArea else { return }
        if let rect = getBoxRect(hotSpot: snap, currentWindow: Window(id: candidate.windowID, rect: destination.screenFlipped)) {
            if Defaults.hapticFeedbackOnSnap.userEnabled {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            showSnapPreview(in: rect, snapArea: snap)
        }
        currentSnapArea = snap
    }

    func endOwnedRestore(token: UUID, candidate: FrostedRestoreDragCandidate, mouseDown: CGPoint, cursor: CGPoint, event: CGEvent) {
        guard ownedRestoreID != nil else { return }
        var destination = FrostedRestoreDragRules.destination(original: candidate.original, restoreSize: candidate.restoreSize,
                                                              mouseDown: mouseDown, cursor: cursor,
                                                              screenFrame: NSScreen.screens.map { $0.frame.screenFlipped }.first { $0.contains(candidate.original) })
        if let nsEvent = NSEvent(cgEvent: event), canSnap(nsEvent),
           let snap = snapAreaContainingCursor(priorSnapArea: currentSnapArea, at: cursor.screenFlipped) {
            // These actions are fully described by the snap-zone calculation.
            // Actions with additional window-manager effects retain that route.
            let basic: Set<WindowAction> = [.leftHalf, .rightHalf, .topLeft, .topRight, .bottomLeft, .bottomRight, .maximize]
            if basic.contains(snap.action), !Defaults.cooperativeCornerResize.enabled,
               !Defaults.cyclingOverlapOffset.userEnabled, !Defaults.todo.userEnabled,
               let rect = getBoxRect(hotSpot: snap, currentWindow: Window(id: candidate.windowID, rect: destination.screenFlipped)) {
                destination = rect.screenFlipped
                ownedRestoreSnap = snap
            } else {
                ownedRestoreFallbackSnap = snap
            }
        }
        if ownedRestoreSnap != nil {
            dismissSnapPreviewForCommit()
        } else if box?.realIsVisible == true {
            box?.orderOut(nil)
        }
        currentSnapArea = nil
        WindowAnimator.shared.endOwnedDrag(token, destination: destination)
    }

    @discardableResult
    func beginNativeDrag() -> UUID {
        pendingReleasedRestore = nil
        nativeGesture.begin()
        resetNativeDragState()
        return nativeGesture.generation
    }

    func cancelOwnedRestore(nativeGeneration: UUID? = nil) {
        // Native handoff owns the gesture before an animation token exists.
        // Its cancellation/timeout must reset the same drag state too.
        ownedRestoreID = nil
        ownedRestoreSnap = nil
        ownedRestoreFallbackSnap = nil
        // An earlier animation can complete after the next mouse-down, before
        // that new native drag has acquired an animation token of its own.
        if let nativeGeneration, nativeGeneration != nativeGesture.generation { return }
        resetNativeDragState()
    }

    private func resetNativeDragState() {
        nativeSizeRestore = nil
        WindowAnimator.shared.cancelDeferredNativeRestore()
        if box?.realIsVisible == true { box?.orderOut(nil) }
        currentSnapArea = nil
        windowElement = nil
        windowId = nil
        windowMoving = false
        initialWindowRect = nil
        initialWindowServerRect = nil
        initialCursorLocation = nil
        initialEventWindowID = nil
        latestNativeDragEvent = nil
        windowIdAttempt = 0
        lastWindowIdAttempt = nil
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
    
    private func dismissSnapPreviewForCommit() {
        if WindowAnimator.frostedEnabled { box?.commitSnapPreview(windowID: windowId) }
        else { box?.orderOut(nil) }
    }

    private func showSnapPreview(in rect: CGRect, snapArea: SnapArea) {
        // A transient window can retain its old display's Space. Construct it
        // with a real frame on the destination display before first ordering.
        if box == nil || box?.frame.isEmpty == true || box?.screen != snapArea.screen {
            box?.close()
            box = FootprintWindow(initialFrame: rect)
        }
        box?.showPreview(in: rect, from: getFootprintAnimationOrigin(snapArea, rect),
                         duration: getFootprintAnimationDuration())
    }

    func getFootprintAnimationDuration() -> Double {
        // The checkbox uses 0.75; normalize it to the shared preview duration.
        return WindowPreviewDeceleration.duration * Double(Defaults.footprintAnimationDurationMultiplier.value) / 0.75
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
    
    func snapAreaForNativeRelease(_ event: NSEvent) -> SnapArea? {
        guard !nativeGesture.cancelled, canSnap(event) else { return nil }
        return snapAreaContainingCursor(priorSnapArea: currentSnapArea, event: event)
    }

    func snapAreaContainingCursor(priorSnapArea: SnapArea?, event: NSEvent) -> SnapArea? {
        guard let location = event.cgEvent?.location else {
            return snapAreaContainingCursor(priorSnapArea: priorSnapArea)
        }
        return snapAreaContainingCursor(priorSnapArea: priorSnapArea, at: location.screenFlipped)
    }

    func snapAreaContainingCursor(priorSnapArea: SnapArea?) -> SnapArea? {
        snapAreaContainingCursor(priorSnapArea: priorSnapArea, at: NSEvent.mouseLocation)
    }

    func snapAreaContainingCursor(priorSnapArea: SnapArea?, at loc: CGPoint) -> SnapArea? {
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
