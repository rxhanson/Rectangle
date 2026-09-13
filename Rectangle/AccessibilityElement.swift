/// AccessibilityElement.swift

import Foundation

class AccessibilityElement {
    fileprivate let wrappedElement: AXUIElement
    
    init(_ element: AXUIElement) {
        wrappedElement = element
    }
    
    convenience init(_ pid: pid_t) {
        self.init(AXUIElementCreateApplication(pid))
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

    var isFullScreenButton: Bool? {
        guard let subrole = subrole else { return nil }
        return subrole == .fullScreenButton
    }
    
    private var position: CGPoint? {
        get {
            wrappedElement.getWrappedValue(.position)
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
            wrappedElement.getWrappedValue(.size)
        }
        set {
            guard let newValue = newValue else { return }
            if WindowAnimator.shared.deferUntilReleased(element: self, action: { [self] in self.size = newValue }) { return }
            wrappedElement.setValue(.size, newValue)
            Logger.log("AX sizing proposed: \(newValue.debugDescription), result: \(size?.debugDescription ?? "N/A")")
        }
    }

    var minimumSize: CGSize? {
        wrappedElement.getWrappedValue(.minSize)
            ?? wrappedElement.getWrappedValue(.minimumSize)
    }
    
    var frame: CGRect {
        guard let position = position, let size = size else { return .null }
        return .init(origin: position, size: size)
    }
    
    /// The Accessebility API only allows size & position adjustments individually.
    /// To handle moving to different displays, we have to adjust the size then the position, then the size again since macOS will enforce sizes that fit on the current display.
    /// When windows take a long time to adjust size & position, there is some visual stutter with doing each of these actions. The stutter can be slightly reduced by removing the initial size adjustment, which can make unsnap restore appear smoother.
    func setFrame(_ frame: CGRect, adjustSizeFirst: Bool = true, adjustPosition: Bool = true) {
        if WindowAnimator.shared.deferUntilReleased(element: self, action: { [self] in
            setFrame(frame, adjustSizeFirst: adjustSizeFirst, adjustPosition: adjustPosition)
        }) { return }
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
    }

    /// Holds the Enhanced UI policy for the transition; returns its cleanup closure.
    func beginAnimatedAdjustment() -> () -> Void {
        let appElement = applicationElement
        let restore = Defaults.enhancedUI.value.beginWindowAdjustment(
            bundleIdentifier: appElement?.bundleIdentifier,
            builtInAssistiveTechnologyEnabled: NSWorkspace.shared.isVoiceOverEnabled
                || NSWorkspace.shared.isSwitchControlEnabled,
            readEnhancedUI: { appElement?.enhancedUserInterface },
            writeEnhancedUI: { appElement?.enhancedUserInterface = $0 }
        )
        // Bound AX calls so an unresponsive app cannot stall the animation.
        setMessagingTimeout(0.05)
        return { [self] in
            setMessagingTimeout(0)
            restore()
        }
    }

    /// Writes one frame without readback; completion handles the final placement.
    /// The coordinator has already released recovery but still owns this drag.
    func setOwnedOrdinaryDragFrame(_ frame: CGRect, token: UUID) {
        guard WindowAnimator.shared.ownsOrdinaryDrag(element: self, token: token) else { return }
        // setFrame/size treat callers as external requests and cancel an active
        // transition. This token-checked path is the transition's own movement.
        // Its Enhanced UI adjustment remains held until the drag completes.
        wrappedElement.setValue(.size, frame.size)
        wrappedElement.setValue(.position, frame.origin)
        wrappedElement.setValue(.size, frame.size)
    }

    /// Writes one frame without readback; completion handles the final placement.
    func setAnimationFrame(_ frame: CGRect, resizeOnly: Bool = false) -> Bool {
        if WindowAnimator.shared.deferUntilReleased(element: self, action: { [self] in
            setFrame(frame, adjustSizeFirst: false, adjustPosition: !resizeOnly)
        }) { return false }
        var size = frame.size
        var position = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size),
              let positionValue = AXValueCreate(.cgPoint, &position) else { return false }
        guard AXUIElementSetAttributeValue(wrappedElement, kAXSizeAttribute as CFString, sizeValue) == .success else { return false }
        // Native dragging owns position during size restoration.
        if !resizeOnly {
            guard AXUIElementSetAttributeValue(wrappedElement, kAXPositionAttribute as CFString, positionValue) == .success else { return false }
        }
        return true
    }

    func setConstrainedAnimationFrame(_ frame: CGRect, placement: WindowAnimationPlacement,
                                      origin: CGRect, progress: CGFloat, previousFrame: CGRect? = nil) -> CGRect? {
        if WindowAnimator.shared.deferUntilReleased(element: self, action: { [self] in
            setFrame(frame)
        }) { return nil }
        var preparedPosition: CGPoint?
        if let previousFrame,
           let position = placement.positionBeforeGrowing(from: previousFrame, to: frame),
           writeAnimationPosition(position) == .success {
            preparedPosition = position
        }
        // Resize before moving on shrinking axes: a refused shrink must not carry the wider window
        // to the narrower frame's origin and leave it behind the Dock until completion.
        let resized = writeAnimationSize(frame.size) == .success
        let actualSize = size.flatMap { size -> CGSize? in
            guard size.width.isFinite, size.height.isFinite,
                  size.width > 0, size.height > 0 else { return nil }
            return size
        }
        // Finish positioning with the size the app reports. Shrinking axes must
        // not move to the requested origin and then move back after a delayed
        // Chromium readback. Continue moving even if resizing failed;
        // native display settlement must not stall every intermediate position.
        var resolved = placement.frame(for: frame, actualSize: actualSize ?? frame.size,
                                       origin: origin, progress: progress)
        if let preparedPosition, let previousFrame, let actualSize {
            // A delayed growth readback must not align the still-smaller size
            // back past the position just prepared for that same resize.
            if preparedPosition.x < previousFrame.minX, actualSize.width < frame.width {
                resolved.origin.x = min(resolved.minX, preparedPosition.x)
            }
            if preparedPosition.y < previousFrame.minY, actualSize.height < frame.height {
                resolved.origin.y = min(resolved.minY, preparedPosition.y)
            }
        }
        if preparedPosition != resolved.origin {
            guard writeAnimationPosition(resolved.origin) == .success else { return nil }
        }
        guard resized, actualSize != nil else { return nil }
        return resolved
    }

    func writeAnimationPosition(_ position: CGPoint) -> AXError {
        var position = position
        guard let value = AXValueCreate(.cgPoint, &position) else { return .failure }
        return AXUIElementSetAttributeValue(wrappedElement, kAXPositionAttribute as CFString, value)
    }

    func writeAnimationSize(_ size: CGSize) -> AXError {
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
        if isApplication == true { return self }
        guard let pid = pid else { return nil }
        return AccessibilityElement(pid)
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
            app.activate(options: .activateIgnoringOtherApps)
        }
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
        // Reused frost surfaces stay ordered at alpha zero. WindowServer still
        // lists them above the dragged app, even though they ignore mouse input.
        let ignoredWindows = Set(NSApp.windows.compactMap { window in
            window.ignoresMouseEvents ? CGWindowID(exactly: window.windowNumber) : nil
        })
        // A new click can follow a focus change or reveal within the list's
        // 100 ms cache lifetime. Select from the current stacking order.
        return windowInfoUnderCursor(at: location, windows: WindowUtil.getWindowList(ids: eventWindowID.map { [$0] }, forceRefresh: true),
                                     eventWindowID: eventWindowID, ignoring: ignoredWindows,
                                     frostSurfaces: WindowFrostRendererConnection.shared.inputTransparentSurfaces)
    }

    static func windowInfoUnderCursor(at location: CGPoint, windows: [WindowInfo],
                                     eventWindowID: CGWindowID? = nil,
                                     ignoring ignoredWindows: Set<CGWindowID> = [],
                                     frostSurfaces: [CGWindowID: pid_t] = [:]) -> WindowInfo? {
        windows.first(where: { windowInfo in
            windowInfo.level < 21 // 21 is the level of the Notification Center
            && windowInfo.alpha > 0
            && !ignoredWindows.contains(windowInfo.id)
            && !FrostedRestoreDragRules.isInputTransparentFrostSurface(windowID: windowInfo.id,
                ownerPID: windowInfo.pid, level: Int(windowInfo.level), registered: frostSurfaces)
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
