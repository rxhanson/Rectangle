import Cocoa
import Carbon.HIToolbox
import MASShortcut

/// Shows a badge and window-name list when the cursor dwells on a stack.
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

    private var badgeWindow: StackBadgeWindow?
    private var listWindow: StackBadgeListPanel?
    private var visibleUIFrames = [CGRect]()

    private var keyMonitor: ActiveEventMonitor?
    private let keyClaim = KeyClaimState()
    private var lastListInteraction: TimeInterval = 0

    /// An open list holds the arrow keys, so it must not be able to stay open
    /// indefinitely: a cursor left resting on a stack would otherwise keep
    /// taking them from whatever the user is typing into. Any interaction with
    /// the list resets this.
    private static let listIdleTimeout: TimeInterval = 5

    /// Whether the list is claiming keys. Written on the main thread and read
    /// from the event tap's own thread, so the two are serialized.
    final class KeyClaimState {
        private let lock = NSLock()
        private var claiming = false

        var isClaiming: Bool {
            get { lock.lock(); defer { lock.unlock() }; return claiming }
            set { lock.lock(); claiming = newValue; lock.unlock() }
        }
    }

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
            // .common keeps the tick - and with it the idle expiry that
            // reclaims the arrow keys - running during menu and event
            // tracking, where default-mode timers pause but the tap does not.
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
                if isInsideVisibleUI(location) {
                    lastListInteraction = lastMoveTime
                } else {
                    dismiss()
                }
            }
            return
        }

        // The open list holds the arrow keys, so it can't be allowed to sit
        // there unattended: a cursor resting on a stack would keep taking them
        // from whatever the user is typing into. The same expiry covers a
        // badge shown without a list, which would otherwise have no exit at
        // all while the cursor rests. The UI also goes away if macOS hid it
        // out from under us, which a Space change does without any
        // notification the manager would otherwise see.
        if badgeWindow != nil {
            let idle = ProcessInfo.processInfo.systemUptime - lastListInteraction
            let uiHidden = badgeWindow?.isVisible != true
                || (listWindow != nil && listWindow?.isVisible != true)
            if idle > Self.listIdleTimeout || uiHidden {
                dismiss()
                return
            }
        }

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
        let screenFrameAX = screenFrame.screenFlipped
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

        // ...and the stack is the densest cascade cluster among them, so
        // the widened box doesn't count unrelated neighbors and an
        // unrelated leftmost window doesn't mask a real stack. A window
        // covering the screen joins a stack the tiled windows already form,
        // but never makes one on its own - see stackIndices.
        let coversScreen = candidates.map {
            OverlapOffsetGeometry.coversScreen($0.frame, screenFrame: screenFrameAX)
        }
        let stacked = StackBadgeGeometry
            .stackIndices(among: candidates.map { $0.frame.origin },
                          coversScreen: coversScreen,
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

        let anchor = CGPoint(x: corner.x, y: corner.y - Self.titleBarClearance)

        let badge = StackBadgeWindow(count: windows.count, corner: anchor)
        badge.orderFrontRegardless()
        badgeWindow = badge

        let listTop = CGPoint(x: anchor.x + 12, y: badge.frame.minY - 6)

        // Only build the rows that fit above the screen bottom. Building them
        // all and letting the panel clip would leave the arrow keys able to
        // select - and Return able to raise - a window with no visible row.
        // The badge still reports the true size of the stack.
        let listed = Array(windows.prefix(StackBadgeListPanel.rowsThatFit(below: listTop.y, above: screenFrame.minY)))
        lastListInteraction = ProcessInfo.processInfo.systemUptime
        guard !listed.isEmpty else {
            // No room for even one row - a stack at the bottom of the grid.
            // The badge alone still needs the exits the full UI gets (mouse
            // moving away, the idle expiry in tick()), or it would float
            // there with no path that ever dismisses it.
            let corridor = CGRect(x: badge.frame.minX, y: badge.frame.maxY,
                                  width: badge.frame.width,
                                  height: max(0, corner.y - badge.frame.maxY))
            visibleUIFrames = [badge.frame, corridor]
            return
        }

        let list = StackBadgeListPanel(
            windows: listed, listTop: listTop, screenFrame: screenFrame,
            onSelect: { [weak self] window in self?.focus(window) })

        list.orderFrontRegardless()
        listWindow = list
        startKeyMonitor()

        visibleUIFrames = list.visibleUIFrames(with: badge, triggerCorner: corner,
                                               cursor: NSEvent.mouseLocation)
    }

    private func dismiss() {
        // Invalidate any in-flight title fetch so a stale result can't
        // resurrect the UI after a dismissal.
        generation += 1
        stopKeyMonitor()
        badgeWindow?.orderOut(nil)
        badgeWindow = nil
        listWindow?.orderOut(nil)
        listWindow = nil
        visibleUIFrames = []
    }

    /// Arrow keys move the highlight, Return raises the selected window
    /// (leaving the list up so the stack can be walked), Escape closes. The
    /// keys are consumed so they don't reach the window underneath.
    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }

        // VoiceOver's Quick Nav uses the bare arrow keys, and taking those
        // would break navigating the very windows this list describes. Leave
        // the list mouse-driven instead.
        guard !NSWorkspace.shared.isVoiceOverEnabled else { return }

        let claim = keyClaim
        claim.isClaiming = true
        let monitor = ActiveEventMonitor(
            mask: .keyDown,
            filterer: { event in
                claim.isClaiming
                    && Self.navigationKey(forKeyCode: event.keyCode, modifiers: event.modifierFlags) != nil
            },
            handler: { [weak self] event in
                guard let self, self.listWindow != nil,
                      let key = Self.navigationKey(forKeyCode: event.keyCode, modifiers: event.modifierFlags)
                else { return }
                self.lastListInteraction = ProcessInfo.processInfo.systemUptime
                switch key {
                case .up: self.moveSelection(by: -1)
                case .down: self.moveSelection(by: 1)
                case .commit: self.commitSelection()
                case .escape: self.dismiss()
                }
            })
        monitor.start()
        keyMonitor = monitor
    }

    private func stopKeyMonitor() {
        // Stop claiming before tearing the tap down, so a keystroke already in
        // the filterer passes through rather than being swallowed on the way out.
        keyClaim.isClaiming = false
        keyMonitor?.stop()
        keyMonitor = nil
    }

    private func moveSelection(by delta: Int) {
        listWindow?.moveSelection(by: delta)
    }

    /// Return (or a click): bring the selected window forward. The list stays
    /// open so you can keep flipping through the stack.
    private func commitSelection() {
        guard let selectedWindow = listWindow?.selectedWindow else { return }
        focus(selectedWindow)
    }

    /// Resolves the window by pid directly (no shared window-list cache off
    /// the main thread), with AX timeouts so an unresponsive app can't hang
    /// the focus attempt.
    ///
    /// The list is deliberately NOT dismissed here, so you can click through
    /// several windows in the stack in a row without re-opening it. It
    /// dismisses when the cursor leaves the overlay (see tick()). Clicks keep
    /// working even though another app is now frontmost because the rows opt
    /// into first-mouse and the panel is non-activating.
    private func focus(_ window: StackBadgeStackedWindow) {
        // A click is list interaction just as much as a key press; without
        // this, clicking right before the idle expiry raises the window and
        // then watches the list vanish mid-walk.
        lastListInteraction = ProcessInfo.processInfo.systemUptime
        window.focus(axTimeout: Self.axTimeout)
    }

}
