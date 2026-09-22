/// AccessibilityElement.swift

import Foundation
import Darwin

enum WindowProcessIdentity {
    /// Launch Services may omit launchDate for apps started by an executable.
    /// Kernel start time still distinguishes a reused PID without an AX query.
    static func launchTime(for pid: pid_t) -> TimeInterval? {
        var info = proc_bsdinfo()
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size {
            return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
                .timeIntervalSinceReferenceDate
        }
        return NSRunningApplication(processIdentifier: pid)?.launchDate?.timeIntervalSinceReferenceDate
    }
}

class AccessibilityElement {
    fileprivate let wrappedElement: AXUIElement
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
    var animationObservationElement: AXUIElement { wrappedElement }
    private let knownApplication: Bool
    private var resolvedWindowID: CGWindowID?
    private(set) var messagingTimeout: Float = 0
    
    init(_ element: AXUIElement, application: Bool = false, messagingTimeout: Float = 0, windowID: CGWindowID? = nil) {
        wrappedElement = element
        knownApplication = application
        resolvedWindowID = windowID
        if messagingTimeout > 0 { setMessagingTimeout(messagingTimeout) }
    }
    
    convenience init(_ pid: pid_t) {
        self.init(AXUIElementCreateApplication(pid), application: true)
    }
    
    convenience init?(_ bundleIdentifier: String) {
        guard let app = (NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleIdentifier }) else { return nil }
        self.init(app.processIdentifier)
    }
    
    convenience init?(_ position: CGPoint) {
        guard let element = AXUIElement.systemWide.getElementAtPosition(position) else { return nil }
        self.init(element)
    }
    
    private func getElementValue(_ attribute: NSAccessibility.Attribute) -> AccessibilityElement? {
        guard let value = wrappedElement.getValue(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return AccessibilityElement(value as! AXUIElement, messagingTimeout: messagingTimeout)
    }
    
    private func getElementsValue(_ attribute: NSAccessibility.Attribute) -> [AccessibilityElement]? {
        guard let value = wrappedElement.getValue(attribute), let array = value as? [AXUIElement] else { return nil }
        return array.map { AccessibilityElement($0, messagingTimeout: messagingTimeout) }
    }
    
    private var role: NSAccessibility.Role? {
        if knownApplication { return .application }
        guard let value = wrappedElement.getValue(.role) as? String else { return nil }
        return NSAccessibility.Role(rawValue: value)
    }
    
    private var isApplication: Bool? {
        guard let role = role else { return nil }
        return role == .application
    }
    
    var isWindow: Bool? {
        guard let role = role else { return nil }
        return role == .window
    }
    
    var isSheet: Bool? {
        guard let role = role else { return nil }
        return role == .sheet
    }
    
    var isToolbar: Bool? {
        guard let role = role else { return nil }
        return role == .toolbar
    }
    
    var isGroup: Bool? {
        guard let role = role else { return nil }
        return role == .group
    }
    
    var isTabGroup: Bool? {
        guard let role = role else { return nil }
        return role == .tabGroup
    }
    
    var isStaticText: Bool? {
        guard let role = role else { return nil }
        return role == .staticText
    }

    func isTitleBarSpacer(in titleBar: CGRect) -> Bool {
        guard role == .splitter else { return false }
        var settable: DarwinBoolean = false
        let status = AXUIElementIsAttributeSettable(wrappedElement, kAXValueAttribute as CFString, &settable)
        let value = wrappedElement.getValue(.value)
        return Self.isTitleBarSpacer(role: role, parentRole: getElementValue(.parent)?.role,
            frame: frame, titleBar: titleBar, childCount: childElements?.count,
            hasValue: value != nil && (value as? String) != "",
            hasOrientation: wrappedElement.getValue(.orientation) != nil,
            valueSettable: status == .success ? settable.boolValue : nil)
    }

    /// Some toolkits expose empty titlebar spacing as a splitter. A real
    /// adjustable divider, or spacing below the titlebar, keeps its own clicks.
    static func isTitleBarSpacer(role: NSAccessibility.Role?, parentRole: NSAccessibility.Role?,
                                 frame: CGRect, titleBar: CGRect, childCount: Int?,
                                 hasValue: Bool, hasOrientation: Bool, valueSettable: Bool?) -> Bool {
        role == .splitter && parentRole == .toolbar && childCount == 0
            && !hasValue && !hasOrientation && valueSettable == false
            && !frame.isEmpty && !frame.isInfinite && titleBar.contains(frame)
    }
    
    private var subrole: NSAccessibility.Subrole? {
        guard let value = wrappedElement.getValue(.subrole) as? String else { return nil }
        return NSAccessibility.Subrole(rawValue: value)
    }
    
    var isSystemDialog: Bool? {
        guard let subrole = subrole else { return nil }
        return subrole == .systemDialog
    }

    var isFullScreenButton: Bool? {
        guard let subrole = subrole else { return nil }
        return subrole == .fullScreenButton
    }
    
    private var position: CGPoint? {
        get {
            if let cached = animationReads?.position { return cached }
            let value: CGPoint? = wrappedElement.getWrappedValue(.position)
            animationReads?.position = value
            return value
        }
        set {
            guard let newValue = newValue else { return }
            wrappedElement.setValue(.position, newValue)
            Logger.log("AX position proposed: \(newValue.debugDescription), result: \(position?.debugDescription ?? "N/A")")
        }
    }
    
    func isResizable() -> Bool {
        if let isResizable = wrappedElement.isValueSettable(.size) {
            return isResizable
        }
        Logger.log("Unable to determine if window is resizeable. Assuming it is.")
        return true
    }
    
    var size: CGSize? {
        get {
            if let cached = animationReads?.size { return cached }
            let value: CGSize? = wrappedElement.getWrappedValue(.size)
            animationReads?.size = value
            return value
        }
        set {
            guard let newValue = newValue else { return }
            wrappedElement.setValue(.size, newValue)
            Logger.log("AX sizing proposed: \(newValue.debugDescription), result: \(size?.debugDescription ?? "N/A")")
        }
    }

    var minimumSize: CGSize? {
        WindowSizeConstraints.shared.minimum(for: self, reported: reportedMinimumSize)
    }

    var rememberedMinimumSize: CGSize? {
        WindowSizeConstraints.shared.rememberedMinimum(for: self)
    }

    var reportedMinimumSize: CGSize? {
        wrappedElement.getWrappedValue(.minSize)
            ?? wrappedElement.getWrappedValue(.minimumSize)
    }

    /// Structural metadata only: never read text values or document content.
    /// An incomplete hierarchy cannot justify restoring a different live window.
    var sizeConstraintIdentity: (identifier: String?, role: String, subrole: String, structure: [String]) {
        let identifier = wrappedElement.getValue(.identifier) as? String
        let subrole = wrappedElement.getValue(.subrole) as? String ?? ""
        let children = childElements
        let structure: [String]
        if let children, !children.isEmpty, children.count <= 32 {
            structure = children.map {
                [$0.role?.rawValue ?? "", $0.wrappedElement.getValue(.subrole) as? String ?? "",
                 $0.wrappedElement.getValue(.identifier) as? String ?? ""].joined(separator: "|")
            }.sorted()
        } else { structure = [] }
        return (identifier, role?.rawValue ?? "", subrole, structure)
    }
    
    func readAnimationGeometry() -> Bool {
        guard let cache = animationReads else { return false }
        var values: CFArray?
        let keys = [kAXPositionAttribute, kAXSizeAttribute] as CFArray
        guard AXUIElementCopyMultipleAttributeValues(wrappedElement, keys, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
              let values = values as? [AnyObject], values.count == 2,
              CFGetTypeID(values[0]) == AXValueGetTypeID(), CFGetTypeID(values[1]) == AXValueGetTypeID() else { return false }
        var position = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(values[0] as! AXValue, .cgPoint, &position),
              AXValueGetValue(values[1] as! AXValue, .cgSize, &size) else { return false }
        cache.position = position; cache.size = size
        return true
    }

    var frame: CGRect {
        if let cache = animationReads, cache.position == nil, cache.size == nil { _ = readAnimationGeometry() }
        guard let position = position, let size = size else { return .null }
        return .init(origin: position, size: size)
    }
    
    /// The Accessebility API only allows size & position adjustments individually.
    /// To handle moving to different displays, we have to adjust the size then the position, then the size again since macOS will enforce sizes that fit on the current display.
    /// When windows take a long time to adjust size & position, there is some visual stutter with doing each of these actions. The stutter can be slightly reduced by removing the initial size adjustment, which can make unsnap restore appear smoother.
    func setFrame(_ frame: CGRect, adjustSizeFirst: Bool = true, adjustPosition: Bool = true) {
        let before = self.frame
        let appElement = applicationElement
        let builtInAssistiveTechnologyEnabled = NSWorkspace.shared.isVoiceOverEnabled
            || NSWorkspace.shared.isSwitchControlEnabled
        Defaults.enhancedUI.value.performWindowAdjustment(
            bundleIdentifier: appElement?.bundleIdentifier,
            builtInAssistiveTechnologyEnabled: builtInAssistiveTechnologyEnabled,
            readEnhancedUI: { appElement?.enhancedUserInterface },
            writeEnhancedUI: { enabled in
                if !enabled {
                    Logger.log("AXEnhancedUserInterface was enabled, will disable before resizing")
                }
                appElement?.enhancedUserInterface = enabled
            },
            adjustment: {
                if adjustSizeFirst {
                    size = frame.size
                }
                if adjustPosition { position = frame.origin }
                size = frame.size
            }
        )
        if isWindow == true, isSystemDialog != true, isResizable() {
            WindowSizeConstraints.shared.observeResize(self, before: before, requested: frame)
        }
    }

    /// Keep the existing Enhanced UI policy active for the whole transition,
    /// instead of toggling application accessibility on every timer tick.
    func beginAnimatedAdjustment() -> () -> Void {
        let appElement = applicationElement
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

    /// A divider acknowledgment step must not resend an already accepted size.
    func setDividerPosition(_ point: CGPoint) -> Bool {
        guard WindowAnimator.shared.destination(for: self) == nil else { return false }
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(wrappedElement, kAXPositionAttribute as CFString, value) == .success
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
            return setObservedAnimationFrame(frame, observed: observed, placement: placement, origin: origin)
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
            && (now - animationLastSizeWrite < animationSizeInterval
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
                                          placement: WindowAnimationPlacement, origin: CGRect) -> CGRect? {
        let now = animationVerificationTime ?? ProcessInfo.processInfo.systemUptime
        animationMotionApplied = false
        animationSizeDeferred = true
        var size = requested.size
        if placement.positionBeforeGrowing(from: observed, to: requested) != nil {
            size.width = min(size.width, max(observed.width, placement.screenFrame.maxX - observed.minX))
            size.height = min(size.height, max(observed.height, placement.screenFrame.maxY - observed.minY))
        }
        let intermediate = WindowAnimationPlacement(screenFrame: placement.screenFrame, sharedEdges: nil,
            constrainToScreen: placement.constrainToScreen, gap: placement.gap)
        var safeSize = observed.size
        if let pending = animationResizeResponse.pendingSize {
            safeSize.width = max(safeSize.width, pending.width)
            safeSize.height = max(safeSize.height, pending.height)
        }
        safeSize.width = max(safeSize.width, size.width)
        safeSize.height = max(safeSize.height, size.height)
        var position = intermediate.frame(for: requested, actualSize: safeSize, origin: origin, progress: 0).origin
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
        // Submit safe motion before a potentially slow resize. Size delivery
        // cannot consume the position step or turn its response into a minimum.
        if position != observed.origin {
            guard writeAnimationPosition(position) == .success else {
                animationNeedsRecovery = true
                return nil
            }
            animationExpectedOrigin = position
        }
        animationMotionApplied = true
        if probe {
            animationNeedsFreshGeometry = true
        }
        let achieved = CGRect(origin: position, size: observed.size)
        guard !animationYieldRequested else { return achieved }
        let grows = size.width > observed.width + 0.5 || size.height > observed.height + 0.5
        if grows, now - animationObservedAt > 1.0 / 60 {
            animationNeedsFreshGeometry = true
            return achieved
        }
        let needsSize = abs(size.width - observed.width) > 0.5 || abs(size.height - observed.height) > 0.5
        if needsSize, (probe || animationResizeResponse.mayRequest(at: now)),
           now - animationLastSizeWrite >= animationSizeInterval {
            let result = writeAnimationSize(size)
            if probe { animationEdgeProbeSent = true }
            animationResizeResponse.requested(size, previous: observed.size, at: now)
            animationLastSizeWrite = now
            if result != .success { animationNeedsRecovery = true }
        }
        return achieved
    }

    func writeAnimationPosition(_ position: CGPoint) -> AXError {
        animationReads?.position = nil
        animationReads?.server = nil
        var position = position
        guard let value = AXValueCreate(.cgPoint, &position) else { return .failure }
        return AXUIElementSetAttributeValue(wrappedElement, kAXPositionAttribute as CFString, value)
    }

    func writeAnimationSize(_ size: CGSize) -> AXError {
        // A resize can also move the origin when AppKit enforces screen bounds.
        animationReads?.size = nil
        animationReads?.position = nil
        animationReads?.server = nil
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return .failure }
        return AXUIElementSetAttributeValue(wrappedElement, kAXSizeAttribute as CFString, value)
    }
    
    private var childElements: [AccessibilityElement]? {
        getElementsValue(.children)
    }
    
    func getChildElement(_ role: NSAccessibility.Role) -> AccessibilityElement? {
        return childElements?.first { $0.role == role }
    }
    
    func getChildElements(_ role: NSAccessibility.Role) -> [AccessibilityElement]? {
        guard let elements = (childElements?.filter { $0.role == role }), elements.count > 0 else {
            return nil
        }
        return elements
    }
    
    func getChildElement(_ subrole: NSAccessibility.Subrole) -> AccessibilityElement? {
        return childElements?.first { $0.subrole == subrole }
    }
    
    func getChildElements(_ subrole: NSAccessibility.Subrole) -> [AccessibilityElement]? {
        guard let elements = (childElements?.filter { $0.subrole == subrole }), elements.count > 0 else {
            return nil
        }
        return elements
    }
    
    func getSelfOrChildElementRecursively(_ position: CGPoint) -> AccessibilityElement? {
        func getChildElement() -> AccessibilityElement? {
            return element.childElements?
                .map { (element: $0, frame: $0.frame) }
                .filter { $0.frame.contains(position) }
                .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?
                .element
        }
        var element = self
        var elements = Set<AccessibilityElement>()
        while let childElement = getChildElement(), elements.insert(childElement).inserted {
            element = childElement
        }
        return element
    }
    
    var windowId: CGWindowID? {
        if let resolvedWindowID { return resolvedWindowID }
        guard let id = wrappedElement.getWindowId(), id != 0 else { return nil }
        resolvedWindowID = id
        return id
    }

    func getWindowId() -> CGWindowID? {
        if let windowId = windowId {
            return windowId
        }
        let frame = frame
        // Take the first match because there's no real way to guarantee which window we're actually getting
        if let pid = pid, let info = (WindowUtil.getWindowList().first { $0.pid == pid && $0.frame == frame }) {
            return info.id
        }
        if !frame.isNull {
            // Last resort (#640): derive a stand-in id from the accessibility
            // element's identity so window-id-keyed bookkeeping keeps working
            // when macOS isn't vending real window ids. CFHash is constant for
            // the same window across fetches and unaffected by moves/resizes.
            Logger.log("Using a derived window id for bookkeeping")
            return AccessibilityElement.deriveWindowId(fromElementHash: CFHash(wrappedElement))
        }
        Logger.log("Unable to obtain window id")
        return nil
    }

    /// The high bit keeps derived ids out of the real window id space;
    /// real ids are assigned incrementally by the window server.
    static func deriveWindowId(fromElementHash hash: CFHashCode) -> CGWindowID {
        CGWindowID(0x8000_0000) | (CGWindowID(truncatingIfNeeded: hash) & 0x7FFF_FFFF)
    }
    
    var pid: pid_t? {
        wrappedElement.getPid()
    }

    var bundleIdentifier: String? {
        guard let pid else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }
    
    var windowElement: AccessibilityElement? {
        if isWindow == true { return self }
        return getElementValue(.window)
    }
    
    var isMainWindow: Bool? {
        get {
            windowElement?.wrappedElement.getValue(.main) as? Bool
        }
        set {
            guard let newValue = newValue else { return }
            windowElement?.wrappedElement.setValue(.main, newValue)
        }
    }
    
    var isMinimized: Bool? {
        windowElement?.wrappedElement.getValue(.minimized) as? Bool
    }

    var title: String? {
        wrappedElement.getValue(.title) as? String
    }

    /// Caps how long AX calls through this element can block on an
    /// unresponsive app (the systemwide default is several seconds).
    func setMessagingTimeout(_ seconds: Float) {
        messagingTimeout = seconds
        AXUIElementSetMessagingTimeout(wrappedElement, seconds)
    }
    
    var isFullScreen: Bool? {
        guard let subrole = windowElement?.getElementValue(.fullScreenButton)?.subrole else { return nil }
        return subrole == .zoomButton
    }
    
    var titleBarFrame: CGRect? {
        guard
            let windowElement,
            case let windowFrame = windowElement.frame,
            windowFrame != .null,
            let closeButtonFrame = windowElement.getChildElement(.closeButton)?.frame,
            closeButtonFrame != .null
        else {
            return nil
        }
        let gap = closeButtonFrame.minY - windowFrame.minY
        let height = 2 * gap + closeButtonFrame.height
        return CGRect(origin: windowFrame.origin, size: CGSize(width: windowFrame.width, height: height))
    }
    
    private var applicationElement: AccessibilityElement? {
        // PID construction already establishes the type. A failed role request
        // must not create an unbounded replacement application handle.
        if knownApplication { return self }
        guard let pid = pid else { return nil }
        return AccessibilityElement(AXUIElementCreateApplication(pid), application: true,
                                    messagingTimeout: messagingTimeout)
    }
    
    private var focusedWindowElement: AccessibilityElement? {
        applicationElement?.getElementValue(.focusedWindow)
    }
    
    var windowElements: [AccessibilityElement]? {
        applicationElement?.getElementsValue(.windows)
    }
    
    var isHidden: Bool? {
        applicationElement?.wrappedElement.getValue(.hidden) as? Bool
    }
    
    var enhancedUserInterface: Bool? {
        get {
            applicationElement?.wrappedElement.getValue(.enhancedUserInterface) as? Bool
        }
        set {
            guard let newValue = newValue else { return }
            applicationElement?.wrappedElement.setValue(.enhancedUserInterface, newValue)
        }
    }
    
    // Only for Stage Manager
    var windowIds: [CGWindowID]? {
        wrappedElement.getValue(.windowIds) as? [CGWindowID]
    }
    
    func bringToFront(force: Bool = false) {
        if isMainWindow != true {
            isMainWindow = true
        }
        if let pid = pid, let app = NSRunningApplication(processIdentifier: pid), !app.isActive || force {
            app.activate()
        }
    }

    /// Select one window before activating its application. Front-window-only
    /// activation preserves the stacking order of the application's siblings.
    func activateAndRaiseWindow(isCurrent: @escaping () -> Bool,
                                completion: @escaping (AXError, AXError, AXError) -> Void) {
        guard let pid else { completion(.invalidUIElement, .invalidUIElement, .invalidUIElement); return }
        let workspace = NSWorkspace.shared
        func raiseSelected(activation: AXError) {
            guard isCurrent() else { return }
            guard workspace.frontmostApplication?.processIdentifier == pid else {
                completion(activation, .cannotComplete, .cannotComplete)
                return
            }
            let main = AXUIElementSetAttributeValue(wrappedElement, kAXMainAttribute as CFString, kCFBooleanTrue)
            let raise = AXUIElementPerformAction(wrappedElement, kAXRaiseAction as CFString)
            completion(activation, main, raise)
        }
        if workspace.frontmostApplication?.processIdentifier == pid {
            raiseSelected(activation: .success)
            return
        }
        var observer: NSObjectProtocol?
        var timeout: DispatchWorkItem?
        var finished = false
        var activation = AXError.success
        let finish = {
            guard !finished else { return }
            finished = true
            if let registered = observer { workspace.notificationCenter.removeObserver(registered) }
            observer = nil
            timeout?.cancel(); timeout = nil
            raiseSelected(activation: activation)
        }
        observer = workspace.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { note in
                guard (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier == pid else { return }
                DispatchQueue.main.async(execute: finish)
            }
        let deadline = DispatchWorkItem(block: finish)
        timeout = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: deadline)
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, messagingTimeout > 0 ? min(messagingTimeout, 0.05) : 0.05)
        let selectedMain = AXUIElementSetAttributeValue(wrappedElement, kAXMainAttribute as CFString, kCFBooleanTrue)
        let selectedRaise = AXUIElementPerformAction(wrappedElement, kAXRaiseAction as CFString)
        guard isCurrent() else { finish(); return }
        if selectedMain == .success, selectedRaise == .success,
           let app = NSRunningApplication(processIdentifier: pid), app.activate(options: []) {
            activation = .success
        } else {
            // Some applications refuse background main-window changes. Retain
            // application activation as the fallback for an otherwise unusable selection.
            activation = AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
        if activation != .success || workspace.frontmostApplication?.processIdentifier == pid { finish() }
    }

}

extension AccessibilityElement {
    static func getFrontApplicationElement() -> AccessibilityElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return AccessibilityElement(app.processIdentifier)
    }

    static func getFocusedWindowElement() -> AccessibilityElement? {
        getFrontApplicationElement()?.focusedWindowElement
    }
    
    static func getFrontWindowElement() -> AccessibilityElement? {
        guard let appElement = getFrontApplicationElement() else {
            Logger.log("Failed to find the application that currently has focus.")
            return nil
        }
        if let focusedWindowElement = appElement.focusedWindowElement {
            return focusedWindowElement
        }
        if let firstWindowElement = appElement.windowElements?.first {
            return firstWindowElement
        }
        Logger.log("Failed to find frontmost window.")
        return nil
    }
    
    private static func getWindowInfo(_ location: CGPoint, eventWindowID: CGWindowID? = nil) -> WindowInfo? {
        // Ignore Rectangle preview surfaces when selecting an application window.
        let ignoredWindows = Set(NSApp.windows.compactMap { window in
            window.ignoresMouseEvents ? CGWindowID(exactly: window.windowNumber) : nil
        })
        // A new click can follow a focus change or reveal within the list's
        // 100 ms cache lifetime. Select from the current stacking order.
        return windowInfoUnderCursor(at: location, windows: WindowUtil.getWindowList(ids: eventWindowID.map { [$0] }, forceRefresh: true),
                                     eventWindowID: eventWindowID, ignoring: ignoredWindows)
    }

    static func windowInfoUnderCursor(at location: CGPoint, windows: [WindowInfo],
                                     eventWindowID: CGWindowID? = nil,
                                     ignoring ignoredWindows: Set<CGWindowID> = []) -> WindowInfo? {
        windows.first(where: { windowInfo in
            windowInfo.level < 21 // 21 is the level of the Notification Center
            && windowInfo.alpha > 0
            && !ignoredWindows.contains(windowInfo.id)
            && !["Dock", "WindowManager"].contains(windowInfo.processName)
            && (eventWindowID.map { windowInfo.id == $0 } ?? windowInfo.frame.contains(location))
        })
    }

    static func getWindowElementUnderCursor(at mouseDown: CGPoint? = nil, eventWindowID: CGWindowID? = nil) -> AccessibilityElement? {
        let position = mouseDown ?? NSEvent.mouseLocation.screenFlipped
        
        var systemWideFirst = Defaults.systemWideMouseDown.userEnabled
        if Defaults.systemWideMouseDown.notSet, let frontAppId = ApplicationToggle.frontAppId {
            systemWideFirst = Defaults.systemWideMouseDownApps.typedValue?.contains(frontAppId) == true
        }
        
        if systemWideFirst,
            let element = AccessibilityElement(position),
            let windowElement = element.windowElement,
            eventWindowID == nil || windowElement.windowId == eventWindowID {
                return windowElement
        }

        if let info = getWindowInfo(position, eventWindowID: eventWindowID) {
            if !Defaults.dragFromStage.userDisabled {
                if StageUtil.stageCapable && StageUtil.stageEnabled,
                   let group = StageUtil.getStageStripWindowGroup(info.id),
                   let windowId = group.first,
                   windowId != info.id,
                   let element = StageWindowAccessibilityElement(windowId) {
                    return element
                }
            }
            if let windowElements = AccessibilityElement(info.pid).windowElements {
                if let windowElement = (windowElements.first { $0.windowId == info.id }) {
                    return windowElement
                }
                if eventWindowID == nil, let windowElement = (windowElements.first { $0.frame == info.frame }) {
                    return windowElement
                }
            }
        }
        
        if !systemWideFirst,
           let element = AccessibilityElement(position),
           let windowElement = element.windowElement,
           eventWindowID == nil || windowElement.windowId == eventWindowID {
            
            if Logger.logging, let pid = windowElement.pid {
                let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? ""
                Logger.log("Window under cursor fallback matched: \(appName)")
            }
            return windowElement
        }

        // Last resort for when the window server isn't vending window info (#640):
        // the frontmost app's own accessibility windows don't depend on it.
        if let frontAppElement = getFrontApplicationElement(),
           let windowElements = frontAppElement.windowElements {
            if let eventWindowID {
                return windowElements.first { $0.windowId == eventWindowID }
            }
            let windowElement = windowElements
                .map { (element: $0, frame: $0.frame) }
                .filter { !$0.frame.isNull && $0.frame.contains(position) }
                .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?
                .element
            if let windowElement {
                if Logger.logging, let pid = windowElement.pid {
                    let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? ""
                    Logger.log("Window under cursor frontmost app fallback matched: \(appName)")
                }
                return windowElement
            }
        }

        Logger.log("Unable to obtain the accessibility element with the specified attribute at mouse location")
        return nil
    }
    
    static func getWindowElement(_ windowId: CGWindowID) -> AccessibilityElement? {
        guard let pid = WindowUtil.getWindowList(ids: [windowId]).first?.pid else { return nil }
        return AccessibilityElement(pid).windowElements?.first { $0.windowId == windowId }
    }
    
    private static let excludedProcessNames: Set<String> = ["Dock", "WindowManager", "Notification Center"]

    static func getAllWindowElements(from onScreen: [WindowInfo]? = nil) -> [AccessibilityElement] {
        return (onScreen ?? WindowUtil.getWindowList())
            .filter { !excludedProcessNames.contains($0.processName ?? "") }
            .uniqueMap { $0.pid }
            .compactMap { AccessibilityElement($0).windowElements }
            .flatMap { $0 }
    }
}

extension AccessibilityElement: Equatable {
    static func == (lhs: AccessibilityElement, rhs: AccessibilityElement) -> Bool {
        return lhs.wrappedElement == rhs.wrappedElement
    }
}

extension AccessibilityElement: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedElement)
    }
}

class StageWindowAccessibilityElement: AccessibilityElement {
    private let _windowId: CGWindowID
    
    init?(_ windowId: CGWindowID) {
        guard let element = AccessibilityElement.getWindowElement(windowId) else { return nil }
        _windowId = windowId
        super.init(element.wrappedElement)
    }
    
    override var frame: CGRect {
        let frame = super.frame
        guard !frame.isNull, let windowId = windowId, let info = WindowUtil.getWindowList(ids: [windowId]).first else { return frame }
        return .init(origin: info.frame.origin, size: frame.size)
    }
    
    override var windowId: CGWindowID? {
        _windowId
    }
}

enum EnhancedUI: Int {
    case disableEnable = 1 /// Always restore Enhanced UI after moving/resizing when it was previously enabled
    case disableOnly = 2 /// Don't re-enable Enhanced UI after it gets disabled
    case frontmostDisable = 3 /// Disable Enhanced UI every time the frontmost app changes
    case automatic = 4 /// Avoid re-enabling Chromium accessibility while preserving Enhanced UI for other apps

    private static let chromiumBrowserBundleIdentifierFamilies = [
        "com.google.Chrome",
        "org.chromium.Chromium",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaNext",
        "com.operasoftware.OperaDeveloper",
        "com.operasoftware.OperaNightly",
        "com.operasoftware.OperaGX",
        "com.operasoftware.OperaGXNext",
        "com.operasoftware.OperaGXDeveloper",
        "com.operasoftware.OperaGXNightly",
        "company.thebrowser.Browser",
        "company.thebrowser.dia",
        "ai.perplexity.comet",
        "com.openai.atlas"
    ]

    static func isKnownChromiumBrowser(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return chromiumBrowserBundleIdentifierFamilies.contains {
            bundleIdentifier == $0 || bundleIdentifier.hasPrefix("\($0).")
        }
    }

    private func restoresEnhancedUI(
        bundleIdentifier: String?,
        builtInAssistiveTechnologyEnabled: Bool
    ) -> Bool {
        switch self {
        case .disableEnable:
            return true
        case .disableOnly, .frontmostDisable:
            return false
        case .automatic:
            return builtInAssistiveTechnologyEnabled
                || !Self.isKnownChromiumBrowser(bundleIdentifier: bundleIdentifier)
        }
    }

    func disablesEnhancedUIOnApplicationActivation(
        bundleIdentifier: String?,
        builtInAssistiveTechnologyEnabled: Bool
    ) -> Bool {
        switch self {
        case .frontmostDisable:
            return true
        case .automatic:
            return !builtInAssistiveTechnologyEnabled
                && Self.isKnownChromiumBrowser(bundleIdentifier: bundleIdentifier)
        case .disableEnable, .disableOnly:
            return false
        }
    }

    func performWindowAdjustment(
        bundleIdentifier: String?,
        builtInAssistiveTechnologyEnabled: Bool,
        readEnhancedUI: () -> Bool?,
        writeEnhancedUI: @escaping (Bool) -> Void,
        adjustment: () -> Void
    ) {
        let restore = beginWindowAdjustment(bundleIdentifier: bundleIdentifier,
                                            builtInAssistiveTechnologyEnabled: builtInAssistiveTechnologyEnabled,
                                            readEnhancedUI: readEnhancedUI,
                                            writeEnhancedUI: writeEnhancedUI)
        adjustment()
        restore()
    }

    func beginWindowAdjustment(
        bundleIdentifier: String?,
        builtInAssistiveTechnologyEnabled: Bool,
        readEnhancedUI: () -> Bool?,
        writeEnhancedUI: @escaping (Bool) -> Void
    ) -> () -> Void {
        let enhancedUIWasEnabled = readEnhancedUI()
        if enhancedUIWasEnabled == true {
            writeEnhancedUI(false)
        }

        let shouldRestore = enhancedUIWasEnabled == true && restoresEnhancedUI(
               bundleIdentifier: bundleIdentifier,
               builtInAssistiveTechnologyEnabled: builtInAssistiveTechnologyEnabled
           )
        return {
            if shouldRestore { writeEnhancedUI(true) }
        }
    }
}

enum WindowAccessibilityLookup {
    static func resolve(pid: pid_t, id: CGWindowID, launch: TimeInterval,
                        preferred: AXUIElement?, isCurrent: () -> Bool) -> AXUIElement? {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.25
        func valid() -> Bool { isCurrent() && WindowProcessIdentity.launchTime(for: pid) == launch }
        while valid(), ProcessInfo.processInfo.systemUptime < deadline {
            let reader = AccessibilityReadBatch(budget: deadline - ProcessInfo.processInfo.systemUptime)
            // Activation can stall AXWindows even while the selected window responds.
            if let preferred {
                var owner: pid_t = 0
                if AXUIElementGetPid(preferred, &owner) == .success, owner == pid,
                   reader.windowID(preferred) == id, valid() { return preferred }
            }
            if reader.available,
               let windows = reader.value(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement],
               let window = windows.first(where: { reader.windowID($0) == id }),
               reader.available, valid() { return window }
            guard reader.timedOut, valid() else { return nil }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining > 0 { Thread.sleep(forTimeInterval: min(0.02, remaining)) }
        }
        return nil
    }
}

/// The deadline covers the entire batch. A timeout ends it immediately; optional
/// unsupported attributes are absence, not an excuse to reset the AX timeout.
final class AccessibilityReadBatch {
    private let deadline: TimeInterval
    private var failed = false
    var timedOut: Bool { failed }
    init(budget: TimeInterval) { deadline = ProcessInfo.processInfo.systemUptime + budget }
    var available: Bool { !failed && ProcessInfo.processInfo.systemUptime < deadline }
    private func prepare(_ element: AXUIElement) -> Bool {
        guard available else { return false }
        AXUIElementSetMessagingTimeout(element, Float(min(0.05, max(0.001, deadline - ProcessInfo.processInfo.systemUptime))))
        return true
    }
    func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        guard prepare(element) else { return nil }
        var result: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        if status == .cannotComplete { failed = true }
        return status == .success ? result : nil
    }
    func windowID(_ element: AXUIElement) -> CGWindowID? {
        guard prepare(element) else { return nil }
        var id: CGWindowID = 0
        let status = _AXUIElementGetWindow(element, &id)
        if status == .cannotComplete { failed = true }
        return status == .success && id != 0 ? id : nil
    }
    func wrapped<T>(_ element: AXUIElement, _ attribute: String, type: AXValueType) -> T? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        return AXValueGetValue(value as! AXValue, type, pointer) ? pointer.pointee : nil
    }
    func settable(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard prepare(element) else { return nil }
        var result = DarwinBoolean(false)
        let status = AXUIElementIsAttributeSettable(element, attribute as CFString, &result)
        if status == .cannotComplete { failed = true }
        return status == .success ? result.boolValue : nil
    }
    func observe(_ observer: AXObserver, _ element: AXUIElement, _ notification: String,
                 context: UnsafeMutableRawPointer) {
        guard prepare(element) else { return }
        if AXObserverAddNotification(observer, element, notification as CFString, context) == .cannotComplete {
            failed = true
        }
    }
}
