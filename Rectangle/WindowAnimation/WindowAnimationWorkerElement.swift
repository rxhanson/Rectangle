import Cocoa
import QuartzCore

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
        let application = AccessibilityElement(AXUIElementCreateApplication(process), application: true,
                                                messagingTimeout: 0.05)
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
