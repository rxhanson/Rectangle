/// StackCycleManager.swift

import Cocoa

/// Brings the windows stacked in the focused window's position forward one at
/// a time. Stacks are found with the hover list's cascade rule: windows at the
/// same corner or cascaded from it by the overlap offset and, when the user
/// limits stacks to one size, the same size as the focused window. The hover
/// list looks only near grid corners, so near other windows the two can
/// still see a stack differently.
enum StackCycleManager {

    private static let axTimeout: Float = 0.25
    private static let tolerance: CGFloat = 4

    /// One run of presses through a stack. It lasts while the focus stays on
    /// one of the stack's windows.
    struct Session: Equatable {
        /// The frame the stack is measured against, fixed for the session.
        /// Measuring against each newly raised window instead would let the
        /// stack drift when sizes differ within the tolerance, dropping
        /// windows at the far end.
        let anchor: CGRect
        /// The stack's windows in the order being cycled, front to back as
        /// first seen. Raising reshuffles the z-order, so the order being
        /// walked has to be remembered rather than re-read.
        let ring: [CGWindowID]
        /// The window the last press chose. The next press steps on from
        /// here rather than from whatever is in front: raises can still be
        /// in flight, land partway through a run of presses, or be refused
        /// by the app, and none of that should change where the walk goes.
        let cursor: CGWindowID
    }

    private static var session: Session?
    private static var sessionSameSizeOnly = false

    private static let raiseQueue = DispatchQueue(label: "StackCycleManager.raise", qos: .userInitiated)
    private static let raiseLock = NSLock()
    private static var latestRaise = 0
    private static var finishedRaise = 0

    /// `windowElement` picks the stack. It's taken to be the focused window
    /// unless `windowIsFocused` is false, as for the window under the pointer.
    static func cycle(forward: Bool, windowElement: AccessibilityElement? = nil, windowIsFocused: Bool = true) {
        guard let windowElement = windowElement ?? AccessibilityElement.getFrontWindowElement(),
              let focusedId = windowElement.getWindowId()
        else {
            fail()
            return
        }

        let ownPid = ProcessInfo.processInfo.processIdentifier
        let todoId = Defaults.todo.userEnabled ? TodoManager.getTodoWindowId() : nil
        let windows = WindowUtil.getWindowList(forceRefresh: true).filter { info in
            info.level == kCGNormalWindowLevel && info.alpha > 0 && info.pid != ownPid && info.id != todoId
        }

        let cascadeRange = StackBadgeGeometry.cascadeRange(offsetSize: CGFloat(Defaults.cyclingOverlapOffsetSize.value),
                                                           maxCascade: Defaults.cyclingOverlapMaxCascade.value,
                                                           tolerance: tolerance)
        let sameSizeOnly = Defaults.stackSameSizeOnly.userEnabled
        if sameSizeOnly != sessionSameSizeOnly {
            session = nil
            sessionSameSizeOnly = sameSizeOnly
        }
        let sizeTolerance = sameSizeOnly ? StackBadgeGeometry.sizeTolerance : nil
        let frames = windows.map { $0.frame }
        let stackFor = { (anchor: CGRect) -> [CGWindowID] in
            StackBadgeGeometry.stackMembers(anchor: anchor, among: frames, cascadeRange: cascadeRange,
                                            tolerance: tolerance, sizeTolerance: sizeTolerance)
                .map { windows[$0].id }
        }

        // Only a window this action could raise can anchor a stack.
        guard let focusedIndex = (windows.firstIndex { $0.id == focusedId }),
              let anchor = StackBadgeGeometry.stackAnchor(for: focusedIndex, among: frames, cascadeRange: cascadeRange,
                                                          tolerance: tolerance, sizeTolerance: sizeTolerance),
              let focus = sessionFocus(window: focusedId, isFocused: windowIsFocused, stack: stackFor(anchor)),
              let next = nextSession(focused: focus, freshAnchor: anchor,
                                     previous: session, forward: forward,
                                     raiseInFlight: isRaiseInFlight(), stackFor: stackFor),
              let targetWindow = (windows.first { $0.id == next.cursor })
        else {
            fail()
            return
        }

        session = next
        let ringPids = Set(windows.filter { next.ring.contains($0.id) }.map { $0.pid })
        raise(targetWindow, cycleApps: ringPids)
    }

    /// The window a press counts as focused. A window under the pointer stays
    /// under it while the walk raises the others, so if it counted, the walk
    /// would skip it as already in front; the front window of its stack
    /// counts instead.
    static func sessionFocus(window: CGWindowID, isFocused: Bool, stack: @autoclosure () -> [CGWindowID]) -> CGWindowID? {
        isFocused ? window : stack().first
    }

    private static func fail() {
        session = nil
        finishRaise(beginRaise())
        NSSound.beep()
    }

    /// The session after one press, whose `cursor` is the window to raise,
    /// or nil when the focused window has nothing stacked with it.
    /// `stackFor` returns the ids of the windows stacked at an anchor frame,
    /// front to back, and `freshAnchor` is the one a new session starts from.
    ///
    /// `raiseInFlight` says whether the last press's raise may not have
    /// landed yet. While it hasn't, the focused window is stale and says
    /// nothing about where the walk is.
    static func nextSession(focused: CGWindowID, freshAnchor: CGRect, previous: Session?, forward: Bool,
                            raiseInFlight: Bool = false,
                            stackFor: (CGRect) -> [CGWindowID]) -> Session? {
        if let previous, previous.ring.contains(focused) {
            let stack = stackFor(previous.anchor)
            if stack.contains(focused) {
                // If the window last chosen has gone, carry on from the
                // focused one instead.
                let from = stack.contains(previous.cursor) ? previous.cursor : focused
                if var result = target(stack: stack, from: from, previousRing: previous.ring, forward: forward) {
                    // The user brought a stacked window forward by hand, and
                    // the walk has reached it: raising it again would look
                    // like the press did nothing, so step past it.
                    if !raiseInFlight, result.target == focused,
                       let skipped = target(stack: stack, from: focused, previousRing: result.ring, forward: forward) {
                        result = skipped
                    }
                    return Session(anchor: previous.anchor, ring: result.ring, cursor: result.target)
                }
            }
        }

        let stack = stackFor(freshAnchor)
        guard let result = target(stack: stack, from: focused, previousRing: [], forward: forward) else { return nil }
        return Session(anchor: freshAnchor, ring: result.ring, cursor: result.target)
    }

    /// The window to raise after `from`, and the ring to remember for the
    /// press after. `stack` is front to back. The previous ring carries on
    /// while it holds exactly the same windows; otherwise the current order
    /// starts a new one.
    ///
    /// Forward raises the window behind `from` in ring order, going round
    /// from the back: from [A, B, C] it raises C, then B, then A. Backward
    /// goes the other way, raising B, then C, then A.
    static func target(stack: [CGWindowID], from: CGWindowID, previousRing: [CGWindowID], forward: Bool) -> (target: CGWindowID, ring: [CGWindowID])? {
        guard stack.count >= 2 else { return nil }

        let ring = Set(previousRing) == Set(stack) && previousRing.count == stack.count ? previousRing : stack
        guard let index = ring.firstIndex(of: from) else { return nil }

        let step = forward ? -1 : 1
        let targetIndex = (index + step + ring.count) % ring.count
        return (ring[targetIndex], ring)
    }

    // MARK: - Raising

    private static func beginRaise() -> Int {
        raiseLock.lock()
        defer { raiseLock.unlock() }
        latestRaise += 1
        return latestRaise
    }

    private static func isLatestRaise(_ generation: Int) -> Bool {
        raiseLock.lock()
        defer { raiseLock.unlock() }
        return generation == latestRaise
    }

    private static func finishRaise(_ generation: Int) {
        raiseLock.lock()
        defer { raiseLock.unlock() }
        finishedRaise = max(finishedRaise, generation)
    }

    private static func isRaiseInFlight() -> Bool {
        raiseLock.lock()
        defer { raiseLock.unlock() }
        return finishedRaise != latestRaise
    }

    /// Raises the window off the main thread with AX timeouts, so an
    /// unresponsive app can't hang the shortcut. Only the latest request
    /// runs: when presses outpace an app, the raises they queued would only
    /// be covered by the next one, and running them late would pull windows
    /// forward after the user has moved on. For the same reason, the app is
    /// only activated if the user is still among the cycle's apps.
    private static func raise(_ window: WindowInfo, cycleApps: Set<pid_t>) {
        let generation = beginRaise()
        let pid = window.pid
        let windowId = window.id
        raiseQueue.async {
            guard isLatestRaise(generation) else { return }
            let appElement = AccessibilityElement(pid)
            appElement.setMessagingTimeout(axTimeout)
            guard let windowElement = (appElement.windowElements?.first { $0.windowId == windowId }) else {
                Logger.log("Unable to raise stacked window \(windowId) - it has closed, or its app did not answer in time")
                finishRaise(generation)
                return
            }
            // Looking the window up can take a while; a newer press may have
            // taken over since.
            guard isLatestRaise(generation) else { return }
            windowElement.setMessagingTimeout(axTimeout)
            if windowElement.isMainWindow != true {
                windowElement.isMainWindow = true
            }
            windowElement.raise()
            DispatchQueue.main.async {
                defer { finishRaise(generation) }
                guard isLatestRaise(generation),
                      let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier,
                      cycleApps.contains(frontmost)
                else { return }
                NSRunningApplication(processIdentifier: pid)?.activate()
            }
        }
    }
}
