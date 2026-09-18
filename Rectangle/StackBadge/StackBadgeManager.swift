import Cocoa
import Carbon.HIToolbox
import MASShortcut

/// Shows a window-name list when the cursor dwells on a stack.
class StackBadgeManager {

    private static let tickInterval: TimeInterval = 0.1
    private static let dwellInterval: TimeInterval = 0.15
    private static let hoverZone: CGFloat = 48
    private static let moveTolerance: CGFloat = 2
    private static let axTimeout: Float = 0.25
    private static let titleBarClearance: CGFloat = 50
    private static var shortcutBindingsSessionActive = true
    private static var shortcutBindingsSuspended = false

    private var timer: Timer?
    private var lastMouseLocation = CGPoint.zero
    private var lastMoveTime: TimeInterval = 0
    private var dwellFired = false
    private var generation = 0

    private var listWindow: StackBadgeListPanel?
    private var visibleUIFrames = [CGRect]()

    /// Set while a window this list raised is being activated. Activation
    /// makes the raised app key, which would leave the list on screen and
    /// deaf, so the keyboard is taken back - but only for that. Any other app
    /// becoming key is the user going somewhere else, and fighting them for
    /// it would be a bug rather than a recovery.
    private var awaitingKeyAfterRaise = false

    enum NavigationKey {
        case up, down, commit, escape
    }

    /// Whether an open list should take this key away from the app underneath.
    /// Only bare navigation keys are taken. A held modifier means the
    /// keystroke belongs to the frontmost app - shift-return inserts a newline
    /// in a chat window, shift-arrow extends a selection - and taking those
    /// would break ordinary typing while the list happens to be open.
    ///
    /// Only the four keys a user actually holds count. macOS reports every
    /// arrow keystroke as carrying .function and .numericPad, so treating
    /// those as modifiers rejects the very keys this list is navigated by.
    static func navigationKey(forKeyCode keyCode: UInt16,
                              modifiers: NSEvent.ModifierFlags) -> NavigationKey? {
        guard modifiers.intersection([.command, .option, .control, .shift]).isEmpty
        else { return nil }
        switch Int(keyCode) {
        case kVK_UpArrow: return .up
        case kVK_DownArrow: return .down
        case kVK_Return, kVK_ANSI_KeypadEnter: return .commit
        case kVK_Escape: return .escape
        default: return nil
        }
    }

    /// The selection after moving `delta` rows, clamped to the ends of a list
    /// of `count` rows. Returns nil when there is nothing to select.
    static func selection(from current: Int, movedBy delta: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        return max(0, min(count - 1, current + delta))
    }

    static func rowsThatFit(below top: CGFloat, above bottom: CGFloat) -> Int {
        StackBadgeListPanel.rowsThatFit(below: top, above: bottom)
    }

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.dismiss()
        }
        NotificationCenter.default.addObserver(
            forName: .stackBadgeChanged,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.toggleListening()
        }
        NotificationCenter.default.addObserver(
            forName: .configImported,
            object: nil, queue: .main
        ) { [weak self] _ in
            // An import can change the toggle shortcut - or clear a conflict
            // that had left it unbound - so the binding is re-evaluated, not
            // just the listener.
            Self.reevaluateToggleShortcut()
            self?.toggleListening()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.dismiss()
        }
        Self.registerUnregisterToggleShortcut()
        toggleListening()
    }

    static let toggleDefaultsKey = "toggleStackBadge"
    static let defaultsKeys = [toggleDefaultsKey]

    private static func registerToggleShortcut() {
        guard isToggleShortcutBindable() else {
            unregisterToggleShortcut()
            return
        }

        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: toggleDefaultsKey, toAction: {
            Defaults.stackBadge.enabled = !Defaults.stackBadge.userEnabled
            Notification.Name.stackBadgeChanged.post()
        })
    }

    private static func unregisterToggleShortcut() {
        MASShortcutBinder.shared()?.breakBinding(withDefaultsKey: toggleDefaultsKey)
    }

    private static func registerUnregisterToggleShortcut() {
        if shortcutBindingsSessionActive && !shortcutBindingsSuspended {
            registerToggleShortcut()
        } else {
            unregisterToggleShortcut()
        }
    }

    /// Break the binding first so re-evaluation can't stack a second action
    /// on the same defaults key.
    private static func reevaluateToggleShortcut() {
        unregisterToggleShortcut()
        registerUnregisterToggleShortcut()
    }

    static func setShortcutBindingsSessionActive(_ isActive: Bool) {
        guard shortcutBindingsSessionActive != isActive else { return }

        shortcutBindingsSessionActive = isActive
        unregisterToggleShortcut()

        if isActive {
            registerUnregisterToggleShortcut()
        }
    }

    static func setShortcutBindingsSuspended(_ suspended: Bool) {
        guard shortcutBindingsSuspended != suspended else { return }
        shortcutBindingsSuspended = suspended
        registerUnregisterToggleShortcut()
    }

    private static func isToggleShortcutBindable() -> Bool {
        guard let shortcut = ShortcutCycle.shortcut(forDefaultsKey: toggleDefaultsKey) else { return true }
        return AppShortcutConflict.conflict(for: shortcut, ignoringDefaultsKey: toggleDefaultsKey) == nil
    }

    private func toggleListening() {
        if Defaults.stackBadge.userEnabled {
            guard timer == nil else { return }
            let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
                self?.tick()
            }
            timer.tolerance = 0.05
            // .common keeps mouse-leave and hidden-window detection running
            // during menu and event tracking, where default-mode timers pause.
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            timer?.invalidate()
            timer = nil
            dismiss()
        }
    }

    private func tick() {
        let location = NSEvent.mouseLocation
        let dx = location.x - lastMouseLocation.x
        let dy = location.y - lastMouseLocation.y

        if abs(dx) > Self.moveTolerance || abs(dy) > Self.moveTolerance {
            lastMouseLocation = location
            lastMoveTime = ProcessInfo.processInfo.systemUptime
            dwellFired = false
            generation += 1
            if !visibleUIFrames.isEmpty {
                if !isInsideVisibleUI(location) {
                    dismiss()
                    return
                }
                // Only once the list is staying: a list on its way out must
                // not take the keyboard on the way.
                takeListKeyIfCursorIsOnIt(at: location)
                reclaimListKeyIfNeeded()
            }
            return
        }

        // The UI goes away if macOS hid it out from under us, which a Space
        // change can do without a notification the manager would otherwise
        // see.
        if listWindow != nil, listWindow?.isVisible != true {
            dismiss()
            return
        }
        takeListKeyIfCursorIsOnIt(at: location)
        reclaimListKeyIfNeeded()

        guard !dwellFired,
              ProcessInfo.processInfo.systemUptime - lastMoveTime >= Self.dwellInterval
        else { return }
        dwellFired = true

        let zone = Self.hoverZone + CGFloat(Defaults.gapSize.value)

        guard visibleUIFrames.isEmpty,
              let screen = (NSScreen.screens.first { NSPointInRect(location, $0.frame) })
        else { return }
        let screenFrame = screen.adjustedVisibleFrame()
        let corners = StackBadgeGeometry.cornerPoints(in: screenFrame)
        guard let corner = StackBadgeGeometry.corner(near: location, in: corners, zone: zone) else { return }

        query(corner: corner, screenFrame: screenFrame)
    }

    private func isInsideVisibleUI(_ location: CGPoint) -> Bool {
        visibleUIFrames.contains { $0.insetBy(dx: -8, dy: -8).contains(location) }
    }

    private func query(corner: CGPoint, screenFrame: CGRect) {
        let cornerAX = corner.screenFlipped
        let tolerance: CGFloat = 4
        let offsetSize = CGFloat(Defaults.cyclingOverlapOffsetSize.value)
        let maxCascade = CGFloat(min(5, max(1, Defaults.cyclingOverlapMaxCascade.value)))
        let cascadeRange = max(offsetSize, 1) * maxCascade + tolerance

        let gap = CGFloat(Defaults.gapSize.value)
        let candidateRange = gap + cascadeRange

        let candidates = WindowUtil.getWindowList().filter { info in
            guard info.level == kCGNormalWindowLevel else { return false }
            let dx = info.frame.origin.x - cornerAX.x
            let dy = info.frame.origin.y - cornerAX.y
            return dx >= -tolerance && dx <= candidateRange
                && dy >= -candidateRange && dy <= candidateRange
        }

        // ...and the stack is the densest cascade cluster among them, so the
        // widened box doesn't count unrelated neighbors and an unrelated
        // leftmost window doesn't mask a real stack. Size plays no part: a
        // window sharing the corner is in the stack whether it is maximized
        // or a sixteenth, and a maximized window covering a smaller one is
        // exactly the case where the smaller one cannot be seen any other way.
        let stacked = StackBadgeGeometry
            .stackIndices(among: candidates.map { $0.frame.origin },
                          cascadeRange: cascadeRange,
                          tolerance: tolerance)
            .map { candidates[$0] }

        guard stacked.count >= 2,
              let leftMost = (stacked.min { $0.frame.origin.x < $1.frame.origin.x }),
              let topMost = (stacked.min { $0.frame.origin.y < $1.frame.origin.y })
        else { return }

        let anchorTopLeft = CGPoint(x: leftMost.frame.origin.x, y: topMost.frame.origin.y).screenFlipped

        let requestGeneration = generation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let windows = StackBadgeStackedWindow.titledWindows(for: stacked, axTimeout: Self.axTimeout)
            DispatchQueue.main.async {
                guard let self,
                      self.generation == requestGeneration,
                      self.timer != nil
                else { return }
                self.show(windows: windows, corner: anchorTopLeft, screenFrame: screenFrame)
            }
        }
    }

    private func show(windows: [StackBadgeStackedWindow], corner: CGPoint, screenFrame: CGRect) {
        dismiss()

        let listTop = CGPoint(x: corner.x + 12,
                              y: corner.y - Self.titleBarClearance)

        // Only build the rows that fit above the screen bottom. Building them
        // all and letting the panel clip would leave the arrow keys able to
        // select - and Return able to raise - a window with no visible row.
        let listed = Array(windows.prefix(StackBadgeListPanel.rowsThatFit(below: listTop.y, above: screenFrame.minY)))
        guard !listed.isEmpty else {
            dismiss()
            return
        }

        let list = StackBadgeListPanel(
            windows: listed, listTop: listTop, screenFrame: screenFrame,
            onSelect: { [weak self] window in self?.focus(window) },
            onDismiss: { [weak self] in self?.dismiss() },
            onLostKey: { [weak self] in
                DispatchQueue.main.async { self?.reclaimListKeyIfNeeded() }
            })

        list.orderFrontRegardless()
        listWindow = list

        // The corridor has to reach where the pointer actually is, not just
        // the geometric corner: a gap pushes the stack down and right of it,
        // so the dwell point can sit below the list's top edge and outside
        // its width. Without this the first move toward the list reads as
        // leaving.
        let cursor = NSEvent.mouseLocation
        let corridorMinX = min(list.frame.minX, corner.x, cursor.x)
        let corridorMaxX = max(list.frame.maxX, corner.x, cursor.x)
        let corridorTop = max(corner.y, cursor.y)
        let corridor = CGRect(x: corridorMinX, y: list.frame.maxY,
                              width: corridorMaxX - corridorMinX,
                              height: max(0, corridorTop - list.frame.maxY))
        visibleUIFrames = [list.frame, corridor]
    }

    private func dismiss() {
        // Invalidate any in-flight title fetch so a stale result can't
        // resurrect the UI after a dismissal.
        generation += 1
        let list = listWindow
        listWindow = nil
        awaitingKeyAfterRaise = false
        list?.orderOut(nil)
        visibleUIFrames = []
    }

    /// A visible list only owns the keyboard while the pointer is over it.
    /// This covers first entry and reclaim after another app becomes active.
    /// Hands the list the keyboard once the cursor is actually on it, which
    /// is what keeps a bare dwell from taking keys off whatever is being
    /// typed into.
    private func takeListKeyIfCursorIsOnIt(at location: CGPoint) {
        guard let list = listWindow,
              list.isVisible,
              list.frame.contains(location),
              !list.isKeyWindow
        else { return }
        list.makeKeyAndOrderFront(nil)
    }

    /// Takes the keyboard back after raising a window took it away. Does not
    /// test the cursor, since walking a stack lets the pointer drift off the
    /// rows between presses - but does test that we were the cause, so
    /// switching to another app by any other means is left alone.
    private func reclaimListKeyIfNeeded() {
        guard awaitingKeyAfterRaise else { return }
        guard let list = listWindow, list.isVisible, !list.isKeyWindow else { return }
        awaitingKeyAfterRaise = false
        list.makeKeyAndOrderFront(nil)
    }

    /// Resolves the window by pid directly (no shared window-list cache off
    /// the main thread), with AX timeouts so an unresponsive app can't hang
    /// the focus attempt.
    ///
    /// The list deliberately stays open: walking a stack means raising one
    /// window, looking, and moving on, so Return is "show me this one" rather
    /// than "I am done". Raising activates the window's app and makes it key,
    /// so the panel takes the keyboard back afterwards - otherwise the list
    /// would still be on screen while the arrow keys drove the window that
    /// just came forward.
    private func focus(_ window: StackBadgeStackedWindow) {
        awaitingKeyAfterRaise = true
        window.focus(axTimeout: Self.axTimeout) { [weak self] in
            DispatchQueue.main.async { self?.reclaimListKeyIfNeeded() }
        }
    }

}
