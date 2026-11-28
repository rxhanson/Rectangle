/// AccessibilityElement.swift

import Foundation

enum WindowLookupResult: Equatable {
    case found(AccessibilityElement)
    case ownWindow
    case notFound
    case timedOut

    var element: AccessibilityElement? {
        if case .found(let element) = self { return element }
        return nil
    }
}

class AccessibilityElement {
    fileprivate let wrappedElement: AXUIElement
    private let knownApplication: Bool
    var axElement: AXUIElement { wrappedElement }
    
    init(_ element: AXUIElement, isApplication: Bool = false) {
        wrappedElement = element
        knownApplication = isApplication
    }
    
    convenience init(_ pid: pid_t) {
        self.init(AXUIElementCreateApplication(pid), isApplication: true)
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
        return AccessibilityElement(value as! AXUIElement)
    }
    
    private func getElementsValue(_ attribute: NSAccessibility.Attribute) -> [AccessibilityElement]? {
        guard let value = wrappedElement.getValue(attribute), let array = value as? [AXUIElement] else { return nil }
        return array.map { AccessibilityElement($0) }
    }
    
    private var role: NSAccessibility.Role? {
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

    var isStandardWindow: Bool? {
        guard let subrole = subrole else { return nil }
        return subrole == .standardWindow
    }

    var isFullScreenButton: Bool? {
        guard let subrole = subrole else { return nil }
        return subrole == .fullScreenButton
    }
    
    private var position: CGPoint? {
        get {
            wrappedElement.getWrappedValue(.position, type: .cgPoint)
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
            wrappedElement.getWrappedValue(.size, type: .cgSize)
        }
        set {
            guard let newValue = newValue else { return }
            wrappedElement.setValue(.size, newValue)
            Logger.log("AX sizing proposed: \(newValue.debugDescription), result: \(size?.debugDescription ?? "N/A")")
        }
    }

    var minimumSize: CGSize? {
        wrappedElement.getWrappedValue(.minSize, type: .cgSize)
        ?? wrappedElement.getWrappedValue(.minimumSize, type: .cgSize)
    }
    
    var frame: CGRect {
        guard let position = position, let size = size else { return .null }
        return .init(origin: position, size: size)
    }
    
    /// The Accessebility API only allows size & position adjustments individually.
    /// To handle moving to different displays, we have to adjust the size then the position, then the size again since macOS will enforce sizes that fit on the current display.
    /// When windows take a long time to adjust size & position, there is some visual stutter with doing each of these actions. The stutter can be slightly reduced by removing the initial size adjustment, which can make unsnap restore appear smoother.
    func setFrame(_ frame: CGRect, adjustSizeFirst: Bool = true, adjustPosition: Bool = true) {
        performFrameAdjustment {
            if adjustSizeFirst { size = frame.size }
            if adjustPosition { position = frame.origin }
            size = frame.size
        }
    }

    /// A move can release a size restriction imposed by the old screen or Dock edge.
    /// An unconfirmed size refusal may be transient until the window moves on-screen.
    func setImmediateFrame(_ target: CGRect, from before: CGRect, sizeFirst: Bool,
                           placement: ImmediateWindowPlacement? = nil) {
        guard !before.isNull, before != target else { return }
        performFrameAdjustment {
            if sizeFirst, before.size != target.size {
                size = target.size
                let resized = self.frame
                guard !resized.isNull else {
                    position = target.origin
                    size = target.size
                    return
                }
                // Keep the accepted size on-screen while moving to the requested edge.
                let placedSize = CGSize(width: max(resized.width, target.width),
                                        height: max(resized.height, target.height))
                var destination = target.origin
                if let placement, placedSize.width <= placement.screenFrame.width,
                   placedSize.height <= placement.screenFrame.height {
                    destination = placement.frame(for: target, actualSize: placedSize).origin
                }
                if resized.origin != destination {
                    position = destination
                    if abs(resized.width - target.width) > 1 || abs(resized.height - target.height) > 1 {
                        let minimum = minimumSize ?? .zero
                        let feasibleSize = CGSize(width: max(target.width, minimum.width),
                                                  height: max(target.height, minimum.height))
                        if let currentSize = size,
                           abs(currentSize.width - feasibleSize.width) > 1 || abs(currentSize.height - feasibleSize.height) > 1 {
                            size = feasibleSize
                            let settled = self.frame
                            if !settled.isNull, let placement, settled.width <= placement.screenFrame.width,
                               settled.height <= placement.screenFrame.height {
                                let origin = placement.frame(for: target, actualSize: settled.size).origin
                                if settled.origin != origin { position = origin }
                            }
                        }
                    }
                }
            } else {
                if before.origin != target.origin { position = target.origin }
                if before.size != target.size { size = target.size }
            }
        }
    }

    private func performFrameAdjustment(_ adjustment: () -> Void) {
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
            adjustment: adjustment
        )
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
        wrappedElement.getWindowId()
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
        Self.resolveWindowElement(self, isWindow: isWindow,
                                  containingWindow: { getElementValue(.window) },
                                  subrole: { subrole })
    }

    static func resolveWindowElement(_ element: AccessibilityElement, isWindow: Bool?,
                                     containingWindow: () -> AccessibilityElement?,
                                     subrole: () -> NSAccessibility.Subrole?) -> AccessibilityElement? {
        if isWindow == true { return element }
        if let window = containingWindow() { return window }
        // Emacs 28 exposes its window as AXTextField without an AXWindow attribute.
        // Its AXStandardWindow subrole still identifies the element as the window itself.
        return subrole() == .standardWindow ? element : nil
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
            // Window capture replaces the visible traffic-light children with a
            // sharing indicator, but AXCloseButton still provides their geometry.
            let closeButtonFrame = (windowElement.getChildElement(.closeButton)
                ?? windowElement.getElementValue(.closeButton))?.frame,
            closeButtonFrame != .null
        else {
            return nil
        }
        let gap = closeButtonFrame.minY - windowFrame.minY
        let height = 2 * gap + closeButtonFrame.height
        return CGRect(origin: windowFrame.origin, size: CGSize(width: windowFrame.width, height: height))
    }
    
    private var applicationElement: AccessibilityElement? {
        if knownApplication || isApplication == true { return self }
        guard let pid = pid else { return nil }
        return AccessibilityElement(pid)
    }
    
    private var focusedWindowElement: AccessibilityElement? {
        applicationElement?.getElementValue(.focusedWindow)
    }
    
    var windowElements: [AccessibilityElement]? {
        getWindowElements().elements
    }

    func getWindowElements(timeout: Float? = nil) -> (elements: [AccessibilityElement]?, timedOut: Bool) {
        guard let appElement = applicationElement else { return (nil, false) }
        let result = appElement.wrappedElement.getValueResult(.windows, timeout: timeout)
        if result.timedOut {
            return (nil, true)
        }
        guard let array = result.value as? [AXUIElement] else { return (nil, false) }
        return (array.map { AccessibilityElement($0) }, false)
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
    
    /// Asks the app to bring this window to the front of its own windows.
    /// Setting AXMain alone does not do this in every app.
    func raise() {
        AXUIElementPerformAction(wrappedElement, kAXRaiseAction as CFString)
    }

    func bringToFront(force: Bool = false) {
        if isMainWindow != true {
            isMainWindow = true
        }
        if let pid = pid, let app = NSRunningApplication(processIdentifier: pid), !app.isActive || force {
            app.activate()
        }
    }
}

extension AccessibilityElement {
    static func getFrontApplicationElement() -> AccessibilityElement? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != -1 else {
            return nil
        }
        return AccessibilityElement(app.processIdentifier)
    }

    static func getFocusedWindowElement() -> AccessibilityElement? {
        getFrontApplicationElement()?.focusedWindowElement
    }
    
    static func resolveFrontWindowElement(
        focusedWindow: () -> WindowLookupResult,
        firstWindow: () -> WindowLookupResult,
        systemWideFocusedWindow: () -> WindowLookupResult,
        firstListedWindow: () -> WindowLookupResult
    ) -> WindowLookupResult {
        let focused = focusedWindow()
        if focused != .notFound { return focused }
        let first = firstWindow()
        if first != .notFound { return first }
        let systemWide = systemWideFocusedWindow()
        if systemWide != .notFound { return systemWide }
        return firstListedWindow()
    }

    static func getFrontWindowElement(timeout: Float? = nil) -> AccessibilityElement? {
        let ownPid = ProcessInfo.processInfo.processIdentifier
        let frontAppElement = getFrontApplicationElement()
        let result = resolveFrontWindowElement(
            focusedWindow: {
                guard let appElement = frontAppElement else { return .notFound }
                let res = appElement.wrappedElement.getValueResult(.focusedWindow, timeout: timeout)
                if res.timedOut {
                    Logger.log("AX focusedWindow lookup timed out")
                    return .timedOut
                }
                if let value = res.value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                    return .found(AccessibilityElement(value as! AXUIElement))
                }
                return .notFound
            },
            firstWindow: {
                guard let appElement = frontAppElement else { return .notFound }
                let lookup = appElement.getWindowElements(timeout: timeout)
                if lookup.timedOut {
                    Logger.log("AX front windows lookup timed out")
                    return .timedOut
                }
                return (lookup.elements?.first).map { .found($0) } ?? .notFound
            },
            systemWideFocusedWindow: {
                getSystemWideFocusedWindowElement(timeout: timeout)
            },
            firstListedWindow: {
                guard let firstWindowInfo = WindowUtil.getWindowList().first(where: {
                    NSRunningApplication(processIdentifier: $0.pid) != nil && (timeout == nil || $0.pid != ownPid)
                }) else {
                    return .notFound
                }
                let lookup = AccessibilityElement(firstWindowInfo.pid).getWindowElements(timeout: timeout)
                if lookup.timedOut {
                    return .timedOut
                }
                return (lookup.elements?.first { $0.windowId == firstWindowInfo.id }).map { .found($0) } ?? .notFound
            }
        )
        if result == .notFound {
            Logger.log("Failed to find frontmost window.")
        }
        return result.element
    }
    
    private static func getSystemWideFocusedWindowElement(timeout: Float? = nil) -> WindowLookupResult {
        let res = AXUIElement.systemWide.getValueResult(.focusedUIElement, timeout: timeout)
        if res.timedOut {
            return .timedOut
        }
        guard let focusedValue = res.value, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return .notFound
        }
        let focusedAX = focusedValue as! AXUIElement
        
        // Check if the focused element is already a window
        let roleRes = focusedAX.getValueResult(.role, timeout: timeout)
        if roleRes.timedOut {
            return .timedOut
        }
        if (roleRes.value as? String) == (kAXWindowRole as String) {
            return .found(AccessibilityElement(focusedAX))
        }
        
        // If it's a child element (e.g., button, text field), traverse up to its window
        let winRes = focusedAX.getValueResult(.window, timeout: timeout)
        if winRes.timedOut {
            return .timedOut
        }
        if let window = winRes.value, CFGetTypeID(window) == AXUIElementGetTypeID() {
            return .found(AccessibilityElement(window as! AXUIElement))
        }
        
        return .notFound
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

    static let axLookupTimeout: Float = 0.25

    static func resolveWindowElementUnderCursor(
        systemWideFirst: Bool,
        ownPid: pid_t,
        windowInfo: WindowInfo?,
        ownVisibleWindowAtPosition: Bool,
        frontmostPid: pid_t?,
        systemWideElement: () -> WindowLookupResult,
        windowElementFromInfo: (WindowInfo) -> WindowLookupResult,
        frontmostWindowElement: () -> WindowLookupResult
    ) -> WindowLookupResult {
        if windowInfo?.pid == ownPid || (windowInfo == nil && ownVisibleWindowAtPosition) {
            return .ownWindow
        }

        if systemWideFirst {
            let result = systemWideElement()
            if result != .notFound { return result }
        }

        if let info = windowInfo {
            let result = windowElementFromInfo(info)
            if result != .notFound { return result }
        }

        if !systemWideFirst {
            let result = systemWideElement()
            if result != .notFound { return result }
        }

        if frontmostPid != ownPid {
            return frontmostWindowElement()
        }

        return .notFound
    }

    static func getWindowElementUnderCursor(at mouseDown: CGPoint? = nil, eventWindowID: CGWindowID? = nil) -> AccessibilityElement? {
        getWindowElementUnderCursorResult(at: mouseDown, eventWindowID: eventWindowID).element
    }

    static func getWindowElementUnderCursorResult(at mouseDown: CGPoint? = nil, eventWindowID: CGWindowID? = nil) -> WindowLookupResult {
        let position = mouseDown ?? NSEvent.mouseLocation.screenFlipped
        let ownPid = ProcessInfo.processInfo.processIdentifier

        if let eventWindowID {
            let ownInteractiveWindowIDs = Set(NSApp.windows.compactMap { window in
                !window.ignoresMouseEvents ? CGWindowID(exactly: window.windowNumber) : nil
            })
            if ownInteractiveWindowIDs.contains(eventWindowID) {
                return .ownWindow
            }
        }
        
        var systemWideFirst = Defaults.systemWideMouseDown.userEnabled
        if Defaults.systemWideMouseDown.notSet, let frontAppId = ApplicationToggle.frontAppId {
            systemWideFirst = Defaults.systemWideMouseDownApps.typedValue?.contains(frontAppId) == true
        }

        let windowInfo = getWindowInfo(position, eventWindowID: eventWindowID)
        let ownVisibleWindowAtPosition = windowInfo == nil && NSApp.windows.contains {
            $0.isVisible && !$0.ignoresMouseEvents && $0.frame.screenFlipped.contains(position)
        }
        let frontmostPid = NSWorkspace.shared.frontmostApplication?.processIdentifier

        let result = resolveWindowElementUnderCursor(
            systemWideFirst: systemWideFirst,
            ownPid: ownPid,
            windowInfo: windowInfo,
            ownVisibleWindowAtPosition: ownVisibleWindowAtPosition,
            frontmostPid: frontmostPid,
            systemWideElement: {
                let hit = AXUIElement.systemWide.getElementAtPositionResult(position, timeout: Self.axLookupTimeout)
                if hit.timedOut {
                    Logger.log("AX lookup at cursor position timed out")
                    return .timedOut
                }
                guard let rawElement = hit.value else { return .notFound }
                let element = AccessibilityElement(rawElement)
                element.setMessagingTimeout(Self.axLookupTimeout)
                defer { element.setMessagingTimeout(0) }
                guard let windowElement = element.windowElement,
                      eventWindowID == nil || windowElement.windowId == eventWindowID else {
                    return .notFound
                }
                if !systemWideFirst, Logger.logging, let pid = windowElement.pid {
                    let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? ""
                    Logger.log("Window under cursor fallback matched: \(appName)")
                }
                return .found(windowElement)
            },
            windowElementFromInfo: { info in
                if !Defaults.dragFromStage.userDisabled {
                    if StageUtil.stageCapable && StageUtil.stageEnabled,
                       let group = StageUtil.getStageStripWindowGroup(info.id),
                       let windowId = group.first,
                       windowId != info.id,
                       let element = StageWindowAccessibilityElement(windowId) {
                        return .found(element)
                    }
                }
                let lookup = AccessibilityElement(info.pid).getWindowElements(timeout: Self.axLookupTimeout)
                if lookup.timedOut {
                    Logger.log("AX window lookup timed out for pid \(info.pid)")
                    return .timedOut
                }
                if let windowElements = lookup.elements {
                    if let windowElement = (windowElements.first { $0.windowId == info.id }) {
                        return .found(windowElement)
                    }
                    if eventWindowID == nil, let windowElement = (windowElements.first { $0.frame == info.frame }) {
                        return .found(windowElement)
                    }
                }
                return .notFound
            },
            frontmostWindowElement: {
                // Last resort for when the window server isn't vending window info (#640):
                // the frontmost app's own accessibility windows don't depend on it.
                if let frontAppElement = getFrontApplicationElement() {
                    let lookup = frontAppElement.getWindowElements(timeout: Self.axLookupTimeout)
                    if lookup.timedOut {
                        return .timedOut
                    }
                    if let windowElements = lookup.elements {
                        if let eventWindowID {
                            return (windowElements.first { $0.windowId == eventWindowID }).map { .found($0) } ?? .notFound
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
                            return .found(windowElement)
                        }
                    }
                }
                return .notFound
            }
        )

        if result == .notFound {
            Logger.log("Unable to obtain the accessibility element with the specified attribute at mouse location")
        }
        return result
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
