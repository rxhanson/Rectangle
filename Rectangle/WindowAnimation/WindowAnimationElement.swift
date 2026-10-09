import Cocoa
import QuartzCore

/// Geometry and write state owned by one window animation.
class WindowAnimationElement: AccessibilityElement {
    private let cachedWindowID: CGWindowID?
    private var messagingTimeout: Float = 0

    init(_ element: AXUIElement, messagingTimeout: Float = 0, windowID: CGWindowID? = nil) {
        cachedWindowID = windowID
        super.init(element)
        if messagingTimeout > 0 { setMessagingTimeout(messagingTimeout) }
    }

    override var windowId: CGWindowID? { cachedWindowID ?? super.windowId }
    override func setMessagingTimeout(_ seconds: Float) {
        messagingTimeout = seconds
        super.setMessagingTimeout(seconds)
    }

    var animationReads: WindowAnimationReadCache?
    var animationPolicy: WindowAnimationWritePolicy?
    var animationSizeInterval: TimeInterval = 0
    var animationLastSizeWrite: TimeInterval = -.infinity
    var animationSizeDeferred = false
    var animationNeedsPositionStep = false
    var animationVerificationTime: TimeInterval?
    var animationIntermediateStep = false
    var animationYieldRequested = false
    var animationNeedsRecovery = false
    var animationObservedFrame: CGRect?
    var animationObservedAt: TimeInterval = -.infinity
    var animationExpectedOrigin: CGPoint?
    var animationNeedsFreshGeometry = false
    var animationResizeNotified = false
    var animationDestination: CGRect?
    var animationEdgeProbeSent = false
    var animationResizeResponse = WindowAnimationResizeResponse()
    var animationMotionApplied = true
    func animationAllowsSizeRead(reservingMotion: Bool) -> Bool { true }
    func animationSizeWriteIsDue(at time: TimeInterval) -> Bool {
        let tolerance = min(animationSizeInterval, animationResizeResponse.frameInterval) * 0.1
        return time - animationLastSizeWrite >= animationSizeInterval - tolerance
    }
    private var animationPosition: CGPoint? {
        if let cached = animationReads?.position { return cached }
        let value: CGPoint? = axElement.getWrappedValue(.position, type: .cgPoint)
        animationReads?.position = value
        return value
    }

    override var size: CGSize? {
        get {
            if let cached = animationReads?.size { return cached }
            let value = super.size
            animationReads?.size = value
            return value
        }
        set { super.size = newValue }
    }

    override var frame: CGRect {
        if let cache = animationReads, cache.position == nil, cache.size == nil { _ = readAnimationGeometry() }
        guard let position = animationPosition, let size = size else { return .null }
        return .init(origin: position, size: size)
    }

    func readAnimationGeometry() -> Bool {
        guard let cache = animationReads else { return false }
        var values: CFArray?
        let keys = [kAXPositionAttribute, kAXSizeAttribute] as CFArray
        guard AXUIElementCopyMultipleAttributeValues(axElement, keys, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
              let values = values as? [AnyObject], values.count == 2,
              CFGetTypeID(values[0]) == AXValueGetTypeID(), CFGetTypeID(values[1]) == AXValueGetTypeID() else { return false }
        var position = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(values[0] as! AXValue, .cgPoint, &position),
              AXValueGetValue(values[1] as! AXValue, .cgSize, &size) else { return false }
        cache.position = position; cache.size = size
        return true
    }

    /// Keep the existing Enhanced UI policy active for the whole transition,
    /// instead of toggling application accessibility on every timer tick.
    func beginAnimatedAdjustment() -> () -> Void {
        let appElement = pid.map { AnimationApplication(pid: $0, timeout: 0.05) }
        let restore = Defaults.enhancedUI.value.beginWindowAdjustment(
            bundleIdentifier: appElement?.bundleIdentifier,
            builtInAssistiveTechnologyEnabled: NSWorkspace.shared.isVoiceOverEnabled
                || NSWorkspace.shared.isSwitchControlEnabled,
            readEnhancedUI: { appElement?.enhancedUserInterface },
            writeEnhancedUI: { appElement?.enhancedUserInterface = $0 }
        )
        // Avoid a long stream of blocking requests to an unresponsive app.
        let previousTimeout = messagingTimeout
        setMessagingTimeout(previousTimeout > 0 ? min(previousTimeout, 0.05) : 0.05)
        return { [self] in
            setMessagingTimeout(previousTimeout)
            restore()
        }
    }

    /// Writes one frame without readback; completion handles the final placement.
    func setAnimationFrame(_ frame: CGRect, resizeOnly: Bool = false) -> Bool {
        setAnimationFrame(frame, resizeOnly: resizeOnly, positionFirst: false)
    }

    func setAnimationFrame(_ frame: CGRect, resizeOnly: Bool = false, positionFirst: Bool) -> Bool {
        if positionFirst, !resizeOnly, writeAnimationPosition(frame.origin) != .success { return false }
        guard writeAnimationSize(frame.size) == .success else { return false }
        if !resizeOnly, !positionFirst, writeAnimationPosition(frame.origin) != .success { return false }
        return true
    }

    func setConstrainedAnimationFrame(_ frame: CGRect, placement: WindowAnimationPlacement,
                                      origin: CGRect, progress: CGFloat, previousFrame: CGRect? = nil,
                                      maximumCorrection: CGFloat = 0) -> CGRect? {
        if progress < 1, let observed = animationObservedFrame {
            return setObservedAnimationFrame(frame, observed: observed, placement: placement, origin: origin,
                                             previous: previousFrame ?? observed)
        }
        animationSizeDeferred = false
        var frame = frame
        // Grow only into space already available at the current origin. Moving
        // creates room for the next step without exposing a second position write.
        if progress < 0.9, let previousFrame,
           placement.positionBeforeGrowing(from: previousFrame, to: frame) != nil {
            let bounds = placement.screenFrame
            if frame.width > previousFrame.width {
                frame.size.width = min(frame.width, max(previousFrame.width, bounds.maxX - previousFrame.minX))
            }
            if frame.height > previousFrame.height {
                frame.size.height = min(frame.height, max(previousFrame.height, bounds.maxY - previousFrame.minY))
            }
            animationSizeDeferred = true
        }
        let predicted = animationPolicy?.mayPredict(frame, previous: previousFrame, placement: placement,
            progress: progress) == true
        var preparedPosition: CGPoint?
        if progress >= 0.9, let previousFrame,
           let position = placement.positionBeforeGrowing(from: previousFrame, to: frame),
           writeAnimationPosition(position) == .success {
            preparedPosition = position
        }
        if progress < 1, animationYieldRequested {
            animationNeedsRecovery = true
            return nil
        }
        // Resize before moving on shrinking axes: a refused shrink must not carry the wider window
        // to the narrower frame's origin and leave it behind the Dock until completion.
        let sizeUnchanged = progress < 1 && previousFrame?.size == frame.size
        let now = ProcessInfo.processInfo.systemUptime
        let deferred = progress < 0.85 && previousFrame != nil && preparedPosition == nil
            && animationSizeInterval > 0
            && (!animationSizeWriteIsDue(at: now)
                || (animationNeedsPositionStep && frame.origin != previousFrame?.origin))
        animationSizeDeferred = animationSizeDeferred || (deferred && !sizeUnchanged)
        animationNeedsPositionStep = !sizeUnchanged && !deferred
        let resized = sizeUnchanged || deferred || writeAnimationSize(frame.size) == .success
        if !sizeUnchanged && !deferred { animationLastSizeWrite = now; animationReads?.invalidate() }
        if progress < 1, !resized || animationYieldRequested {
            animationNeedsRecovery = true
            animationPolicy?.reset()
            return nil
        }
        let actualSize = ((deferred || sizeUnchanged) ? previousFrame?.size : (predicted ? frame.size : size)).flatMap { size -> CGSize? in
            guard size.width.isFinite, size.height.isFinite,
                  size.width > 0, size.height > 0 else { return nil }
            return size
        }
        if progress < 1, animationYieldRequested {
            animationNeedsRecovery = true
            return nil
        }
        // Finish positioning with the size the app reports. Shrinking axes must
        // not move to the requested origin and then move back after a delayed
        // Chromium readback. Continue moving even if resizing failed;
        // native display settlement must not stall every intermediate position.
        var resolved = placement.frame(for: frame, actualSize: actualSize ?? frame.size,
                                       origin: origin, progress: progress)
        if progress < 1, let previousFrame {
            let previous = CGRect(origin: preparedPosition ?? previousFrame.origin, size: previousFrame.size)
            resolved = placement.intermediateFrame(resolved, requested: frame, previous: previous, maximumCorrection: maximumCorrection)
        }
        if (preparedPosition ?? previousFrame?.origin) != resolved.origin {
            guard writeAnimationPosition(resolved.origin) == .success else {
                animationNeedsRecovery = progress < 1
                animationPolicy?.reset(); return nil
            }
            animationReads?.position = nil
            animationReads?.server = nil
        }
        if progress < 1, animationYieldRequested {
            animationNeedsRecovery = true
            return nil
        }
        guard resized, actualSize != nil else { animationPolicy?.reset(); return nil }
        if deferred || WindowAnimationGeometry.near(resolved, frame, tolerance: 1) {
            animationPolicy?.requested(resolved)
        } else { animationPolicy?.reset() }
        return resolved
    }

    private func setObservedAnimationFrame(_ requested: CGRect, observed: CGRect,
                                          placement: WindowAnimationPlacement, origin: CGRect, previous: CGRect) -> CGRect? {
        let now = animationVerificationTime ?? ProcessInfo.processInfo.systemUptime
        animationMotionApplied = false
        animationSizeDeferred = true
        let currentSize = animationResizeResponse.planningSize(observed: observed.size, at: now)
        let current = CGRect(origin: observed.origin, size: currentSize)
        let room = placement.positionBeforeGrowing(from: current, to: requested)
        var size = requested.size
        if room != nil {
            size.width = min(size.width, max(currentSize.width, placement.screenFrame.maxX - observed.minX))
            size.height = min(size.height, max(currentSize.height, placement.screenFrame.maxY - observed.minY))
        }
        let grows = size.width > currentSize.width + 0.5 || size.height > currentSize.height + 0.5
        let freshSize = now - animationObservedAt <= animationResizeResponse.freshnessInterval
            || animationResizeResponse.hasRecentAcceptance(at: now)
        let resizeDue = !animationYieldRequested && (!grows || freshSize)
            && animationResizeResponse.mayRequest(at: now)
            && animationSizeWriteIsDue(at: now)
        let intermediate = WindowAnimationPlacement(screenFrame: placement.screenFrame, sharedEdges: nil,
            constrainToScreen: placement.constrainToScreen, gap: placement.gap)
        var safeSize = CGSize(width: max(currentSize.width, size.width),
                              height: max(currentSize.height, size.height))
        if let pending = animationResizeResponse.pendingSize {
            safeSize.width = max(safeSize.width, pending.width)
            safeSize.height = max(safeSize.height, pending.height)
        }
        var position = intermediate.frame(for: requested, actualSize: safeSize, origin: origin, progress: 0).origin
        if let destination = animationDestination {
            // A responsive resize can accompany this position write. Only hold
            // motion for a size update that actually has to wait.
            let coupledSize = resizeDue && animationSizeInterval <= animationResizeResponse.frameInterval ? size : currentSize
            let coordinated = placement.coordinatedPosition(position, size: coupledSize, previous: previous,
                                                            origin: origin, destination: destination)
            // At a screen edge, movement may be necessary before growth can fit.
            if room?.x == nil || room?.x == observed.minX || size.width > current.width { position.x = coordinated.x }
            if room?.y == nil || room?.y == observed.minY || size.height > current.height { position.y = coordinated.y }
            position = intermediate.frame(for: CGRect(origin: position, size: safeSize), actualSize: safeSize,
                                          origin: origin, progress: 0).origin
        }
        var probe = false
        if let destination = animationDestination, placement.constrainToScreen,
           abs(requested.minX - destination.minX) <= 2, abs(requested.minY - destination.minY) <= 2,
           requested.size == destination.size {
            let bounds = placement.screenFrame.insetBy(dx: placement.gap, dy: placement.gap)
            if observed.width > destination.width + 1, observed.maxX > bounds.maxX + 1 {
                position.x = destination.minX - 1
                probe = !animationEdgeProbeSent
            } else if observed.height > destination.height + 1, observed.maxY > bounds.maxY + 1 {
                position.y = destination.minY - 1
                probe = !animationEdgeProbeSent
            }
        }
        // Submit safe motion before a potentially slow resize. Coupled axes
        // advance only as far as the accepted size allows the opposite edge.
        if position != observed.origin {
            guard writeAnimationPosition(position) == .success else {
                animationNeedsRecovery = true
                return nil
            }
            animationExpectedOrigin = position
        }
        animationMotionApplied = true
        if probe { animationNeedsFreshGeometry = true }
        let achieved = CGRect(origin: position, size: currentSize)
        guard !animationYieldRequested else { recordAnimationWait("yield"); return achieved }
        if grows, !freshSize {
            animationNeedsFreshGeometry = true
            recordAnimationWait("freshness")
            return achieved
        }
        let needsSize = abs(size.width - currentSize.width) > 0.5 || abs(size.height - currentSize.height) > 0.5
        if needsSize {
            if !probe && !animationResizeResponse.mayRequest(at: now) {
                recordAnimationWait("response")
            } else if !animationSizeWriteIsDue(at: now) {
                recordAnimationWait("cadence")
            } else {
                let result = writeAnimationSize(size)
                if probe { animationEdgeProbeSent = true }
                animationResizeResponse.requested(size, previous: currentSize, at: now)
                animationLastSizeWrite = now
                if result != .success { animationNeedsRecovery = true }
            }
        }
        return achieved
    }

    private func recordAnimationWait(_ reason: String) {
        guard WindowAnimationDiagnostics.enabled else { return }
        WindowAnimationDiagnostics.event("animation-feedback-wait", fields: ["windowID": windowId ?? 0,
            "reason": reason, "frameInterval": animationResizeResponse.frameInterval,
            "responseInterval": animationResizeResponse.responseInterval])
    }

    func writeAnimationPosition(_ position: CGPoint) -> AXError {
        animationReads?.position = nil
        animationReads?.server = nil
        var position = position
        guard let value = AXValueCreate(.cgPoint, &position) else { return .failure }
        return AXUIElementSetAttributeValue(axElement, kAXPositionAttribute as CFString, value)
    }

    func writeAnimationSize(_ size: CGSize) -> AXError {
        // A resize can also move the origin when AppKit enforces screen bounds.
        animationReads?.size = nil
        animationReads?.position = nil
        animationReads?.server = nil
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return .failure }
        return AXUIElementSetAttributeValue(axElement, kAXSizeAttribute as CFString, value)
    }
    
}

/// An application handle with a bounded timeout; no role lookup or replacement handle.
private final class AnimationApplication {
    private let element: AXUIElement
    let bundleIdentifier: String?

    init(pid: pid_t, timeout: Float) {
        element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, timeout)
        bundleIdentifier = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    var enhancedUserInterface: Bool? {
        get { element.getValue(.enhancedUserInterface) as? Bool }
        set {
            if let newValue { element.setValue(.enhancedUserInterface, newValue) }
        }
    }
}

/// Owns AX handles independently of main-thread caches. Cancellation is checked
/// between properties, without holding a lock across an unresponsive AX call.
final class WindowAnimationWorkerElement: WindowAnimationElement {
    let process: pid_t
    let launch: TimeInterval
    let bundle: String?
    let enhancedUI: EnhancedUI
    let assistiveTechnology: Bool
    var request: WindowAnimationRequest
    var hint: CGSize?
    var readCount = 0
    var writeCount = 0
    var resizeCost: TimeInterval = 0
    var resizeWork: TimeInterval = 0
    var frameBudget = WindowAnimationFrameBudget()
    var resizeCadence = WindowAnimationResizeCadence(frameInterval: 1.0 / 60)
    private func measured<T>(_ operation: String, _ body: () -> T) -> T {
        let start = ProcessInfo.processInfo.systemUptime
        let value = body()
        let cost = ProcessInfo.processInfo.systemUptime - start
        if operation == "size-write" || operation == "size-read" { resizeWork += cost }
        if operation == "size-read" {
            frameBudget.observeSizeRead(cost, at: start + cost, frameInterval: resizeCadence.frameInterval)
        }
        if operation == "position-write" { frameBudget.observePositionWrite(cost) }
        if animationIntermediateStep && cost > 0.02 {
            animationYieldRequested = true
        }
        if operation == "size-write" {
            resizeCost = resizeCost == 0 ? cost : resizeCost * 0.75 + cost * 0.25
            resizeCadence.observe(cost: resizeCost)
            animationSizeInterval = resizeCadence.interval
        }
        WindowAnimationDiagnostics.event("animation-operation", fields: ["windowID": windowId ?? 0,
            "operation": operation, "milliseconds": cost * 1000])
        return value
    }
    override func animationAllowsSizeRead(reservingMotion: Bool) -> Bool {
        guard request.isCurrent else { return false }
        if animationReads?.size != nil { return true }
        let now = ProcessInfo.processInfo.systemUptime
        let allowed = frameBudget.allowsSizeRead(at: now,
            frameInterval: resizeCadence.frameInterval, resizeCost: resizeCost, reservingMotion: reservingMotion)
        if !allowed {
            WindowAnimationDiagnostics.event("animation-read-deferred", fields: ["windowID": windowId ?? 0,
                "reservingMotion": reservingMotion,
                "estimatedMilliseconds": frameBudget.estimatedSizeReadCost(at: now, frameInterval: resizeCadence.frameInterval) * 1000])
        }
        return allowed
    }
    override func readAnimationGeometry() -> Bool {
        readCount += 1
        return measured("geometry-read") { super.readAnimationGeometry() }
    }

    init(_ element: AXUIElement, pid: pid_t, id: CGWindowID, launch: TimeInterval,
         bundle: String?, enhancedUI: EnhancedUI, assistiveTechnology: Bool, request: WindowAnimationRequest) {
        process = pid; self.launch = launch; self.bundle = bundle; self.enhancedUI = enhancedUI
        self.assistiveTechnology = assistiveTechnology; self.request = request
        super.init(element, messagingTimeout: 0.05, windowID: id)
    }
    override var bundleIdentifier: String? { bundle }
    override var pid: pid_t? { process }
    func readMinimumSizeHint() -> CGSize? {
        // This optional metadata must not delay main or stack two timeouts while
        // the target is busy. Retargeting can cancel between the two attributes.
        let reader = AccessibilityReadBatch(budget: 0.01)
        defer { setMessagingTimeout(0.05) }
        guard request.isCurrent else { return nil }
        if let size: CGSize = reader.wrapped(axElement, NSAccessibility.Attribute.minSize.rawValue, type: .cgSize) {
            return size
        }
        guard request.isCurrent else { return nil }
        return reader.wrapped(axElement, NSAccessibility.Attribute.minimumSize.rawValue, type: .cgSize)
    }
    override var frame: CGRect {
        return measured("frame-read") { super.frame }
    }
    override var size: CGSize? {
        get {
            if let size = animationReads?.size { return size }
            readCount += 1
            return measured("size-read") { super.size }
        }
        set { if let newValue { _ = writeAnimationSize(newValue) } }
    }
    private var mayWrite: Bool {
        request.isCurrent && WindowProcessIdentity.launchTime(for: process) == launch
    }
    override func writeAnimationPosition(_ position: CGPoint) -> AXError {
        guard mayWrite else { return .cannotComplete }
        writeCount += 1
        return measured("position-write") { super.writeAnimationPosition(position) }
    }
    override func writeAnimationSize(_ size: CGSize) -> AXError {
        guard mayWrite else { return .cannotComplete }
        writeCount += 1
        return measured("size-write") { super.writeAnimationSize(size) }
    }
    override func beginAnimatedAdjustment() -> () -> Void {
        let application = AnimationApplication(pid: process, timeout: 0.05)
        return measured("enhanced-ui-begin") {
            enhancedUI.beginWindowAdjustment(bundleIdentifier: bundle,
                builtInAssistiveTechnologyEnabled: assistiveTechnology,
                readEnhancedUI: { application.enhancedUserInterface },
                writeEnhancedUI: { application.enhancedUserInterface = $0 })
        }
    }
    override func setFrame(_ frame: CGRect, adjustSizeFirst: Bool = true, adjustPosition: Bool = true) {
        if adjustSizeFirst, writeAnimationSize(frame.size) != .success { return }
        if adjustPosition, writeAnimationPosition(frame.origin) != .success { return }
        _ = writeAnimationSize(frame.size)
    }
}

/// Readbacks are reusable only until a write invalidates the affected geometry.
final class WindowAnimationReadCache {
    var position: CGPoint?
    var size: CGSize?
    var server: CGRect?
    func invalidate() { position = nil; size = nil; server = nil }
}
