/// WindowAnimator.swift

import Cocoa

struct WindowAnimationPlacement {
    let screenFrame: CGRect
    let sharedEdges: Edge?
    let constrainToScreen: Bool
    let gap: CGFloat
    var displayCommand = false

    func positionBeforeGrowing(from previous: CGRect, to requested: CGRect) -> CGPoint? {
        guard constrainToScreen else { return nil }
        var position = previous.origin
        // Make room on an expanding axis before asking AX to resize. Otherwise
        // macOS can clip the new size at the old origin even though the next
        // animation frame fits, producing a stop/start edge during the resize.
        if requested.width > previous.width + 1,
           previous.minX + requested.width > screenFrame.maxX + 1,
           requested.minX < previous.minX {
            position.x = requested.minX
        }
        if requested.height > previous.height + 1,
           previous.minY + requested.height > screenFrame.maxY + 1,
           requested.minY < previous.minY {
            position.y = requested.minY
        }
        return position == previous.origin ? nil : position
    }

    func frame(for requested: CGRect, actualSize: CGSize, origin: CGRect, progress: CGFloat) -> CGRect {
        var frame = CGRect(origin: requested.origin, size: actualSize)
        if let sharedEdges {
            frame = ClampedWindowAligner.aligned(window: frame, inZone: requested, sharedEdges: sharedEdges)
        }
        guard constrainToScreen else { return frame }

        // Bring an initially out-of-bounds window back gradually instead of clipping its first frame.
        let initialBounds = screenFrame.union(origin)
        let progress = min(1, max(0, progress))
        let bounds = CGRect(x: initialBounds.minX + (screenFrame.minX - initialBounds.minX) * progress,
                            y: initialBounds.minY + (screenFrame.minY - initialBounds.minY) * progress,
                            width: initialBounds.width + (screenFrame.width - initialBounds.width) * progress,
                            height: initialBounds.height + (screenFrame.height - initialBounds.height) * progress)
        return WindowFrameBounds.constrained(frame, to: bounds, gap: gap)
    }
}

/// Advances by elapsed time, skipping missed frames.
final class WindowFrameAnimation {
    let destination: CGRect
    private let origin: CGRect
    private let startTime: TimeInterval
    private let duration: TimeInterval
    private let offset: () -> CGPoint
    private let curve: (Double) -> CGFloat
    private let write: (CGRect, CGFloat) -> Bool
    private let finalize: ((CGRect) -> Void)?
    private let cleanup: () -> Void
    private let completion: (CGRect) -> Void
    private(set) var isFinished = false

    init(from: CGRect, to: CGRect, startTime: TimeInterval, duration: TimeInterval,
         offset: @escaping () -> CGPoint = { .zero },
         curve: @escaping (Double) -> CGFloat = WindowAnimationCurve.value,
         write: @escaping (CGRect, CGFloat) -> Bool,
         finalize: ((CGRect) -> Void)? = nil,
         cleanup: @escaping () -> Void,
         completion: @escaping (CGRect) -> Void) {
        origin = from
        destination = to
        self.startTime = startTime
        self.duration = duration
        self.offset = offset
        self.curve = curve
        self.write = write
        self.finalize = finalize
        self.cleanup = cleanup
        self.completion = completion
    }

    func tick(at time: TimeInterval) {
        guard !isFinished else { return }
        let progress = duration > 0 ? min(1, max(0, (time - startTime) / duration)) : 1
        if progress >= 1 {
            finish()
            return
        }
        let eased = curve(progress)
        let delta = offset()
        let frame = CGRect(x: origin.minX + (destination.minX - origin.minX) * eased + delta.x,
                           y: origin.minY + (destination.minY - origin.minY) * eased + delta.y,
                           width: origin.width + (destination.width - origin.width) * eased,
                           height: origin.height + (destination.height - origin.height) * eased)
        if !write(frame, eased) {
            // Let the normal mover settle the destination after a refused AX write.
            finish()
        }
    }

    func finish() {
        guard !isFinished else { return }
        let delta = offset()
        isFinished = true
        let finalFrame = destination.offsetBy(dx: delta.x, dy: delta.y)
        finalize?(finalFrame)
        cleanup()
        completion(finalFrame)
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        cleanup()
    }
}

enum WindowFrostInterruptionPolicy {
    static func isMissionControlElement(role: String?, identifier: String?) -> Bool {
        role == kAXGroupRole && identifier == "mc"
    }

    static var missionControlActive: Bool {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return false }
        let application = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.05)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return false }
        // Mission Control does not necessarily activate Dock or change the current Space.
        // Its AX identifier is independent of the localized title. This is a best-effort
        // system marker; ordinary Dock groups and unavailable AX reads must not match.
        return children.contains { child in
            var role: CFTypeRef?
            var identifier: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            guard role as? String == kAXGroupRole else { return false }
            AXUIElementCopyAttributeValue(child, kAXIdentifierAttribute as CFString, &identifier)
            return isMissionControlElement(role: role as? String, identifier: identifier as? String)
        }
    }

    static func shouldCancel(activatedPID: pid_t?, targetPID: pid_t) -> Bool {
        guard let activatedPID else { return false }
        return activatedPID != targetPID
    }
}

/// Keeps deferred callbacks and their logical geometry together. Removing the entry before
/// invoking its callback allows that callback to queue newer work without losing it on cleanup.
final class WindowFrostDeferredWork {
    private struct Entry {
        let generation: UUID
        let logicalFrame: CGRect?
        let action: () -> Void
    }
    private var entries: [CGWindowID: Entry] = [:]
    private var releasedFrames: [CGWindowID: CGRect] = [:]

    func replace(windowID: CGWindowID, logicalFrame: CGRect?, action: @escaping () -> Void) -> UUID {
        let generation = UUID()
        entries[windowID] = Entry(generation: generation, logicalFrame: logicalFrame, action: action)
        return generation
    }
    func isLatest(windowID: CGWindowID, generation: UUID) -> Bool { entries[windowID]?.generation == generation }
    func pendingFrame(windowID: CGWindowID) -> CGRect? { entries[windowID]?.logicalFrame }
    func releasedFrame(windowID: CGWindowID) -> CGRect? { releasedFrames[windowID] }
    func discard(windowID: CGWindowID) { entries[windowID] = nil }

    func run(windowID: CGWindowID, isReserved: Bool) {
        guard !isReserved, let entry = entries.removeValue(forKey: windowID) else { return }
        let previousFrame = releasedFrames[windowID]
        releasedFrames[windowID] = entry.logicalFrame
        defer { releasedFrames[windowID] = previousFrame }
        entry.action()
    }
}

struct WindowReleasedSnapStability {
    enum Decision { case waiting, ready, timedOut }
    let startedAt: TimeInterval
    private var previous: CGRect?
    private var stableSince: TimeInterval?

    init(startedAt: TimeInterval) { self.startedAt = startedAt }

    mutating func observe(ax: CGRect, server: CGRect?, at now: TimeInterval) -> Decision {
        if let server, WindowRecoveryGeometry.valid(ax), WindowRecoveryGeometry.valid(server),
           WindowRecoveryGeometry.near(ax, server, tolerance: 1) {
            if let previous, WindowRecoveryGeometry.near(previous, server, tolerance: 1) {
                if let stableSince, now - stableSince >= 1.0 / 30 { return .ready }
            } else { stableSince = now }
            previous = server
        } else {
            previous = nil
            stableSince = nil
        }
        return now - startedAt >= 0.15 ? .timedOut : .waiting
    }
}

struct WindowNativeRestoreDeferral {
    private var pending: (transition: UUID, action: () -> Void)?

    mutating func replace(after transition: UUID, action: @escaping () -> Void) {
        pending = (transition, action)
    }

    mutating func take(after transition: UUID) -> (() -> Void)? {
        guard let pending, pending.transition == transition else { return nil }
        self.pending = nil
        return pending.action
    }

    mutating func cancel() { pending = nil }
}

/// Routes the selected animation style and serializes frosted requests behind their recovery lease.
final class WindowAnimator {
    static let shared = WindowAnimator()
    private let direct = DirectWindowAnimator()
    private var deferredNativeRestore = WindowNativeRestoreDeferral()
    var previewDragHandler: ((UUID, FrostedRestoreDragCandidate, CGRect, CGEvent) -> Void)?
    var previewDragEnded: ((UUID) -> Void)?

    private struct Request {
        let token: UUID
        let element: AccessibilityElement
        let startingFrame: CGRect?
        let destination: CGRect
        let duration: TimeInterval
        let placement: WindowAnimationPlacement?
        let curve: (Double) -> CGFloat
        let completion: (CGRect) -> Void
        var restoring = false
        var ownedDrag = false
        var releasedSnap = false
        var immediate = false
        var initialCursorOffset = CGPoint.zero
        var cancellationFrame: CGRect?
    }
    private struct Active {
        let request: Request
        let transition: WindowFrostTransition
        let targetPID: pid_t
        var suppressCompletion = false
        var ownedCompletion: ((CGRect?) -> Void)?
        var retargetedRequest: Request?
    }
    private var active: Active?
    private var queuedRequest: Request?
    private var settlingReleasedSnap: Request?
    private let deferredWork = WindowFrostDeferredWork()
    private var environmentTimer: Timer?
    private var latestIntent = UUID()

    private init() {
        for name in [Notification.Name.windowAnimationPreferencesChanged, .configImported] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.finish()
                WindowFrostOverlay.clearPendingDismissal()
                if Self.frostedEnabled {
                    WindowRecoverySession.prewarm()
                    WindowFrostRendererConnection.shared.prewarm()
                } else { WindowRecoverySession.cancelPrewarm() }
            }
        }
        for name in [NSApplication.willTerminateNotification, NSApplication.didChangeScreenParametersNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.cancelActive(discardPending: true)
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.cancelActive(discardPending: true)
            }
        }
        workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self else { return }
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self.direct.cancelIfTargetDiffers(from: app?.processIdentifier)
            if let settling = self.settlingReleasedSnap, let targetPID = settling.element.pid,
               WindowFrostInterruptionPolicy.shouldCancel(activatedPID: app?.processIdentifier, targetPID: targetPID) {
                self.settlingReleasedSnap = nil
            }
            guard let active = self.active else { return }
            if WindowFrostInterruptionPolicy.shouldCancel(activatedPID: app?.processIdentifier, targetPID: active.targetPID) {
                self.cancelActive(discardPending: true)
            }
        }
    }

    static var enabled: Bool {
        Defaults.windowAnimationStyle.value.isEnabled(animations: Defaults.experimentalWindowAnimations.enabled,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            voiceOver: NSWorkspace.shared.isVoiceOverEnabled, switchControl: NSWorkspace.shared.isSwitchControlEnabled)
    }

    static var frostedEnabled: Bool { enabled && Defaults.windowAnimationStyle.value == .frosted }

    func destination(for element: AccessibilityElement) -> CGRect? { logicalFrame(for: element) }

    func logicalFrame(for element: AccessibilityElement) -> CGRect? {
        if let destination = direct.destination(for: element) { return destination }
        if let settlingReleasedSnap, settlingReleasedSnap.element == element { return settlingReleasedSnap.destination }
        if let queuedRequest, queuedRequest.element == element { return queuedRequest.destination }
        let id = element.windowId
        if let id, let deferred = deferredWork.pendingFrame(windowID: id) { return deferred }
        if let active, active.request.element == element { return active.transition.destination }
        return id.flatMap { deferredWork.releasedFrame(windowID: $0) }
    }

    func isRecovering(for element: AccessibilityElement) -> Bool {
        if let active, active.request.element == element { return active.transition.isRecovering }
        return element.windowId.map { WindowRecoverySession.isWindowReserved($0) } ?? false
    }

    func cancel(for element: AccessibilityElement) {
        direct.cancel(for: element)
        if settlingReleasedSnap?.element == element { settlingReleasedSnap = nil }
        if queuedRequest?.element == element { queuedRequest = nil }
        guard active?.request.element == element else { return }
        active?.suppressCompletion = true
        active?.transition.cancel()
    }

    func finish() {
        let settling = settlingReleasedSnap
        settlingReleasedSnap = nil
        direct.finish()
        active?.transition.finish()
        if let settling, latestIntent == settling.token { fallback(settling) }
    }

    func finishForNewDrag() {
        direct.mouseDown()
        finish()
    }

    /// Returns true only when the caller must defer its ordinary AX write. The most recent
    /// request for that window wins, and runs after verified recovery, including after a hang.
    @discardableResult
    func deferUntilReleased(element: AccessibilityElement, action: @escaping () -> Void) -> Bool {
        WindowFrostOverlay.clearPendingDismissal()
        guard let id = element.windowId else { return false }
        let owned = active?.request.element == element
        guard owned || WindowRecoverySession.isWindowReserved(id) else { return false }
        let generation = deferredWork.replace(windowID: id, logicalFrame: logicalFrame(for: element), action: action)
        latestIntent = generation
        if queuedRequest?.element == element { queuedRequest = nil }
        if owned {
            active?.suppressCompletion = true
            active?.transition.cancel()
        }
        WindowRecoverySession.whenReleased(windowID: id) { [weak self] in
            guard let self, self.deferredWork.isLatest(windowID: id, generation: generation) else { return }
            // Arming owns the coordinator before the helper's reservation exists.
            guard self.active?.request.element != element else { return }
            self.runDeferredWrite(id)
        }
        return true
    }

    func animate(_ element: AccessibilityElement, from startingFrame: CGRect? = nil, to destination: CGRect,
                 duration: TimeInterval = WindowAnimationCurve.duration,
                 resizeOnly: Bool = false, restoring: Bool = false, releasedSnap: Bool = false,
                 placement: WindowAnimationPlacement? = nil,
                 offset: @escaping () -> CGPoint = { .zero },
                 curve: @escaping (Double) -> CGFloat = WindowAnimationCurve.value,
                 completion: @escaping (CGRect) -> Void) {
        if Defaults.windowAnimationStyle.value == .direct {
            let animateDirect = { [weak self] in
                guard let self else { return }
                self.direct.animate(element, from: startingFrame, to: destination, duration: duration,
                                    resizeOnly: resizeOnly, releasedSnap: releasedSnap, placement: placement, offset: offset,
                                    curve: curve, completion: completion)
            }
            // A style change must never write through an outstanding frosted lease.
            if !deferUntilReleased(element: element, action: animateDirect) { animateDirect() }
            return
        }
        direct.finish()
        let delta = offset()
        var request = Request(token: UUID(), element: element, startingFrame: startingFrame,
                              destination: destination.offsetBy(dx: delta.x, dy: delta.y), duration: duration,
                              placement: placement, curve: curve, completion: completion)
        request.restoring = restoring
        request.releasedSnap = releasedSnap
        // A native held drag owns the real window. Only beginOwnedDrag may take its lease.
        request.immediate = resizeOnly || NSEvent.pressedMouseButtons & 1 != 0
        WindowFrostDiagnostics.event("animation-request", fields: ["windowID": element.windowId ?? 0,
            "immediate": request.immediate, "resizeOnly": resizeOnly, "buttons": NSEvent.pressedMouseButtons])
        enqueue(request)
    }

    @discardableResult
    func deferNativeRestoreIfBusy(with element: AccessibilityElement, action: @escaping () -> Void) -> Bool {
        guard let active, active.request.element != element else { return false }
        deferredNativeRestore.replace(after: active.request.token, action: action)
        return true
    }

    func cancelDeferredNativeRestore() { deferredNativeRestore.cancel() }

    func ownsOrdinaryDrag(element: AccessibilityElement, token: UUID) -> Bool {
        guard let active, active.request.token == token, active.request.element == element,
              active.transition.phase == .draggingOrdinarily,
              let id = element.windowId else { return false }
        return !WindowRecoverySession.isWindowReserved(id)
    }

    func beginOwnedDrag(_ element: AccessibilityElement, from source: CGRect, to destination: CGRect,
                        initialCursorOffset: CGPoint = .zero, cancellationFrame: CGRect? = nil,
                        completion: @escaping (CGRect?) -> Void) -> UUID? {
        guard active == nil, queuedRequest == nil, settlingReleasedSnap == nil, Self.frostedEnabled,
              let id = element.windowId, !WindowRecoverySession.isWindowReserved(id) else { return nil }
        var request = Request(token: UUID(), element: element, startingFrame: source, destination: destination,
                              duration: WindowAnimationCurve.unsnapDuration, placement: nil, curve: WindowAnimationCurve.unsnapValue,
                              completion: { completion($0.isNull ? nil : $0) })
        request.ownedDrag = true
        request.cancellationFrame = cancellationFrame
        request.initialCursorOffset = initialCursorOffset
        latestIntent = request.token
        guard start(request) else { return nil }
        return request.token
    }

    func adoptPreviewDrag(_ token: UUID, element: AccessibilityElement, destination: CGRect,
                          initialCursorOffset: CGPoint, completion: @escaping (CGRect?) -> Void) -> UUID? {
        guard let current = active, current.request.token == token, current.request.element == element,
              current.transition.previewPaused else { return nil }
        active?.ownedCompletion = completion
        guard current.transition.adoptPreviewDrag(destination: destination, initialCursorOffset: initialCursorOffset) else {
            active?.ownedCompletion = nil
            return nil
        }
        return token
    }

    func resumePreviewClick(_ token: UUID) {
        guard let active, active.request.token == token else { return }
        active.transition.resumeAfterPreviewClick()
    }

    func updateOwnedDrag(_ token: UUID, destination: CGRect) {
        guard let active, active.request.token == token, active.transition.ownsDrag else { return }
        active.transition.updateDrag(destination: destination)
    }

    func endOwnedDrag(_ token: UUID, destination: CGRect) {
        guard let active, active.request.token == token, active.transition.ownsDrag else { return }
        active.transition.endDrag(destination: destination)
    }

    func cancelOwnedDrag(_ token: UUID) {
        guard let active, active.request.token == token, active.transition.ownsDrag else { return }
        active.transition.cancel()
    }

    private func enqueue(_ request: Request) {
        WindowFrostOverlay.clearPendingDismissal()
        settlingReleasedSnap = nil
        latestIntent = request.token
        if let id = request.element.windowId {
            deferredWork.discard(windowID: id)
        }
        if let active {
            if active.request.element == request.element, !request.ownedDrag,
               !request.releasedSnap, !request.immediate,
               active.transition.canRetarget(to: request.destination) {
                queuedRequest = nil
                // Preserve the original token for the lease's callbacks, while
                // only the newest command receives the eventual completion.
                self.active?.retargetedRequest = request
                let displayCommand = request.placement?.displayCommand == true || Self.crossesDisplays(
                    from: active.transition.destination, to: request.destination)
                active.transition.retarget(to: request.destination, duration: request.duration,
                                           displayCommand: displayCommand,
                                           replanCoveredResize: Self.coveredResizePlanner(for: request,
                                               source: active.transition.source))
                return
            }
            if active.transition.isRecovering, active.request.element != request.element {
                // A hung app keeps its own reservation, but must not stop ordinary window
                // management in other apps while the recovery helper waits for it to respond.
                queuedRequest = nil
                if !deferUntilReleased(element: request.element, action: { [weak self] in self?.enqueue(request) }) {
                    fallback(request)
                }
                return
            }
            queuedRequest = request
            if active.request.element == request.element {
                self.active?.suppressCompletion = true
                // Disarming is already committed. Let that verified placement
                // finish, then start the latest command from its actual frame.
                if !active.transition.isFinishingPlacement { active.transition.cancel() }
            } else { active.transition.finish() }
            return
        }
        if deferUntilReleased(element: request.element, action: { [weak self] in self?.enqueue(request) }) { return }
        if request.releasedSnap && !request.immediate {
            settlingReleasedSnap = request
            settleReleasedSnap(request, stability: WindowReleasedSnapStability(startedAt: ProcessInfo.processInfo.systemUptime))
            return
        }
        if request.immediate || !start(request) { fallback(request) }
    }

    private func settleReleasedSnap(_ request: Request, stability: WindowReleasedSnapStability) {
        guard latestIntent == request.token, settlingReleasedSnap?.token == request.token else { return }
        var stability = stability
        let now = ProcessInfo.processInfo.systemUptime
        let server = request.element.windowId.flatMap { WindowUtil.getWindowFrame(id: $0) }
        let decision = stability.observe(ax: request.element.frame, server: server, at: now)
        switch decision {
        case .waiting:
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [weak self] in
                self?.settleReleasedSnap(request, stability: stability)
            }
        case .ready, .timedOut:
            settlingReleasedSnap = nil
            WindowFrostDiagnostics.event("released-snap-settled", fields: ["windowID": request.element.windowId ?? 0,
                "ready": decision == .ready, "milliseconds": (now - stability.startedAt) * 1000])
            if decision == .timedOut || !start(request) { fallback(request) }
        }
    }

    @discardableResult
    private func start(_ request: Request) -> Bool {
        let source = request.startingFrame ?? request.element.frame
        guard Self.frostedEnabled, request.element.isFullScreen != true,
              !WindowFrostInterruptionPolicy.missionControlActive,
              let id = request.element.windowId, let targetPID = request.element.pid,
              !WindowRecoverySession.isWindowReserved(id), Self.valid(source), Self.valid(request.destination),
              source != request.destination else { return false }
        let displays = Self.parkingDisplays
        let displayCommand = !request.ownedDrag && !request.releasedSnap
            && (request.placement?.displayCommand == true || Self.crossesDisplays(from: source, to: request.destination))
        // Automatic commands can later repark onto another display, so retain
        // their application minimum even when the initial destination is local.
        // Native restore and released snaps never use that repark closure.
        let compactLimit = request.ownedDrag || request.releasedSnap ? nil
            : Self.commandCompactLimit(minimum: request.element.minimumSize)
        let planned: WindowParkingPlan?
        if request.ownedDrag {
            planned = WindowParkingPlan.preferredForOwnedDrag(source: source, destination: request.destination, displays: displays)
        } else if request.releasedSnap {
            planned = WindowParkingPlan.preferredForReleasedSnap(source: source, destination: request.destination, displays: displays)
        } else if displayCommand {
            planned = WindowParkingPlan.preferredForDisplayCommand(source: source, destination: request.destination,
                                                                  displays: displays, compactLimit: compactLimit)
        } else {
            planned = WindowParkingPlan.preferred(source: source, destination: request.destination, displays: displays)
        }
        guard let plan = planned, !plan.operations.isEmpty else {
            WindowFrostDiagnostics.event("parking-admission-rejected", fields: [
                "ownedDrag": request.ownedDrag,
                "source": [source.minX, source.minY, source.width, source.height],
                "destination": [request.destination.minX, request.destination.minY, request.destination.width, request.destination.height]
            ])
            return false
        }
        // Automatic frost accepts keyboard replacements only. Do not inspect
        // or arm a mouse takeover of the moving cover.
        guard let overlay = WindowFrostOverlay(source: source, destination: request.destination,
                                               externallyOwnedDrag: request.ownedDrag, restoring: request.restoring,
                                               releasedSnap: request.releasedSnap,
                                               displayCommand: displayCommand,
                                               onCancel: { [weak self] in
            guard self?.active?.request.token == request.token else { return }
            self?.active?.transition.cancel()
        }) else { return false }
        var dependencies = WindowFrostTransition.Dependencies(acquire: { callback in
            WindowRecoverySession.start(element: request.element, source: source,
                                        destination: request.destination, releasedSnap: request.releasedSnap,
                                        recoverySource: request.cancellationFrame) { result in
                callback(result.map { $0 as WindowFrostRecovery })
            }
        }, plan: { parked, destination in
            let displays = Self.parkingDisplays
            if let plan = WindowParkingPlan.resizeParked(source: parked, destination: destination, displays: displays) {
                return plan.operations
            }
            return nil
        }, afterFrame: { callback in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0, execute: callback)
        }, afterRelease: { callback in
            WindowRecoverySession.whenReleased(windowID: id, action: callback)
        }, repark: request.ownedDrag || request.releasedSnap ? nil : { visible, destination in
            WindowParkingPlan.preferredForDisplayCommand(source: visible, destination: destination,
                displays: Self.parkingDisplays, compactLimit: compactLimit)
        })
        dependencies.displays = { Self.parkingDisplays }
        dependencies.replanCoveredResize = Self.coveredResizePlanner(for: request, source: source)
        dependencies.moveOrdinarily = { [weak self] frame in
            guard self?.ownsOrdinaryDrag(element: request.element, token: request.token) == true else { return }
            request.element.setOwnedOrdinaryDragFrame(frame, token: request.token)
        }
        // Hold the AX adjustment policy for every frost transition, including
        // titlebar and keyboard actions. Native AX animation can expose parking
        // frames before WindowServer reaches the position AX already reports.
        let finishAdjustment = request.element.beginAnimatedAdjustment()
        let transition = WindowFrostTransition(source: source, destination: request.destination, operations: plan.operations,
                                               overlay: overlay, dependencies: dependencies,
                                               duration: request.duration, curve: request.curve,
                                               externallyOwnedDrag: request.ownedDrag,
                                               initialCursorOffset: request.initialCursorOffset,
                                               coveredSizing: plan.sizing == .covered) { [weak self] outcome in
            finishAdjustment()
            self?.completed(request, outcome: outcome)
        }
        transition.onDestinationCovered = { frame in
            // A constrained window can cover a larger, aligned destination.
            // Release the outline belonging to the original requested snap zone.
            SnapPreviewHandoff(windowID: id, frame: request.releasedSnap ? request.destination : frame, covered: true).post()
        }
        active = Active(request: request, transition: transition, targetPID: targetPID)
        environmentTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard Self.frostedEnabled else { self?.cancelActive(discardPending: true); return }
            if WindowFrostInterruptionPolicy.missionControlActive {
                self?.cancelActive(discardPending: true)
            }
        }
        environmentTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        transition.start()
        return true
    }

    private static func coveredResizePlanner(for request: Request, source: CGRect) -> (CGRect, CGRect) -> WindowParkingPlan? {
        let placement = request.placement
        let ownedDrag = request.ownedDrag
        return { achieved, requested in
            if ownedDrag {
                // An offscreen native drag can clamp an in-place shrink to keep
                // its titlebar reachable. That is not the app's minimum width.
                return WindowParkingPlan.replanReleasedOwnedDrag(source: achieved, destination: requested,
                                                                  displays: Self.parkingDisplays)
            }
            let size = CGSize(width: max(achieved.width, requested.width),
                              height: max(achieved.height, requested.height))
            let target = placement?.frame(for: requested, actualSize: size, origin: source, progress: 1)
                ?? CGRect(origin: requested.origin, size: size)
            return WindowParkingPlan.preferredForReleasedSnap(source: achieved, destination: target,
                                                              displays: Self.parkingDisplays)
        }
    }

    private func completed(_ request: Request, outcome: WindowFrostTransition.Outcome) {
        guard let active, active.request.token == request.token else { return }
        let leaseToken = request.token
        let request = active.retargetedRequest ?? request
        if let id = request.element.windowId {
            SnapPreviewHandoff(windowID: id, frame: active.transition.destination, covered: false).post()
        }
        self.active = nil
        environmentTimer?.invalidate()
        environmentTimer = nil
        let queued = queuedRequest
        queuedRequest = nil
        if let completion = active.ownedCompletion {
            if active.suppressCompletion { completion(nil) }
            else {
                switch outcome {
                case .placed(let frame): completion(frame)
                case .placeOrdinarily(let frame):
                    request.element.setFrame(frame)
                    completion(request.element.frame)
                case .fallback, .cancelled: completion(nil)
                }
            }
        } else if !active.suppressCompletion {
            switch outcome {
            case .placed(let frame): request.completion(frame)
            case .placeOrdinarily(let frame):
                // A held drag can end in a snap whose new size has no safe route from the
                // parked corner. Recovery has released the lease before this ordinary move.
                request.element.setFrame(frame)
                request.completion(request.element.frame)
            case .fallback:
                if request.ownedDrag { request.completion(.null) }
                else { fallback(request) }
            case .cancelled:
                // Native movement precedes the preview. Once recovery finishes,
                // cancel back to the original snap, not its displaced drag frame.
                if let frame = request.cancellationFrame { request.element.setFrame(frame, adjustSizeFirst: false) }
                if request.ownedDrag { request.completion(.null) }
            }
        } else if request.ownedDrag { request.completion(.null) }
        previewDragEnded?(leaseToken)
        if let id = request.element.windowId { runDeferredWrite(id) }
        // Completion may itself have enqueued newer work; never let an older captured request win.
        if self.active == nil, queuedRequest == nil, let queued, latestIntent == queued.token { enqueue(queued) }
        if let resume = deferredNativeRestore.take(after: leaseToken) {
            DispatchQueue.main.async(execute: resume)
        }
    }

    private func runDeferredWrite(_ id: CGWindowID) {
        // Repeated shortcuts calculate from their last requested frame even though recovery
        // has physically returned the real window to its original frame. The next transition
        // still reads its actual source only after this lease has been released.
        deferredWork.run(windowID: id, isReserved: WindowRecoverySession.isWindowReserved(id))
    }

    private func fallback(_ request: Request) {
        WindowFrostDiagnostics.event("animation-fallback", fields: ["windowID": request.element.windowId ?? 0,
            "immediate": request.immediate])
        if let id = request.element.windowId {
            SnapPreviewHandoff(windowID: id, frame: request.destination, covered: false).post()
        }
        // Non-null completion is reserved for a helper-verified placement. The caller's
        // ordinary mover handles every ineligible or failed transition after lease release.
        request.completion(.null)
    }

    private func cancelActive(discardPending: Bool = false) {
        direct.cancel()
        if discardPending {
            latestIntent = UUID()
            settlingReleasedSnap = nil
            queuedRequest = nil
            if let id = active?.request.element.windowId {
                deferredWork.discard(windowID: id)
            }
        }
        active?.transition.cancel()
    }

    private static func commandCompactLimit(minimum: CGSize?) -> CGSize? {
        let usable = NSScreen.screens.map { $0.adjustedVisibleFrame(false) }
        guard let width = usable.map({ floor($0.width / 2) }).min(),
              let height = usable.map(\.height).min() else { return nil }
        // One preparation can cover repeated half-screen moves on every display.
        // Respect a reported application minimum instead of guessing below it.
        return CGSize(width: max(width, minimum?.width ?? 0), height: max(height, minimum?.height ?? 0))
    }

    static func crossesDisplays(from source: CGRect, to destination: CGRect) -> Bool {
        let frames = parkingDisplays.map(\.bounds)
        guard let a = WindowDisplayTransition.display(containing: source, displays: frames),
              let b = WindowDisplayTransition.display(containing: destination, displays: frames) else { return false }
        return a != b
    }

    private static var parkingDisplays: [WindowParkingDisplay] {
        NSScreen.screens.compactMap { screen -> WindowParkingDisplay? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return WindowParkingDisplay(id: number.uint32Value, bounds: screen.frame.screenFlipped,
                                        visibleFrame: screen.visibleFrame.screenFlipped)
        }
    }

    private static func valid(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isEmpty && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
    }
}
