/// WindowAnimator.swift

import Cocoa

struct WindowAnimationPlacement {
    let screenFrame: CGRect
    let sharedEdges: Edge?
    let constrainToScreen: Bool
    let gap: CGFloat

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

    /// A transient resize response must not send an intermediate position past
    /// its requested trajectory and then back when the size catches up.
    func intermediateFrame(_ resolved: CGRect, requested: CGRect, previous: CGRect) -> CGRect {
        var result = resolved
        result.origin.x = min(max(resolved.minX, min(previous.minX, requested.minX)),
                              max(previous.minX, requested.minX))
        result.origin.y = min(max(resolved.minY, min(previous.minY, requested.minY)),
                              max(previous.minY, requested.minY))
        return result
    }
}

/// Waits for AX and WindowServer to agree before accepting a constrained size.
/// Retries a stalled resize with a small position change before moving fully in bounds.
/// A new drag cancels this state in the driver.
struct WindowAnimationSettlement {
    enum Decision {
        case waiting, retrySize, retrySizeAt(CGPoint), align(CGRect), complete(CGRect), failed
    }

    let startedAt: TimeInterval
    private var previous: CGRect?
    private var stableSince: TimeInterval?
    private var retriedSize = false
    private var retriedNearDestination = false

    init(startedAt: TimeInterval) { self.startedAt = startedAt }

    mutating func observe(ax: CGRect, server: CGRect?, destination: CGRect,
                          placement: WindowAnimationPlacement, origin: CGRect,
                          at now: TimeInterval) -> Decision {
        guard now - startedAt < 0.3 else { return .failed }
        guard let server, WindowAnimationGeometry.valid(ax), WindowAnimationGeometry.valid(server),
              WindowAnimationGeometry.near(ax, server, tolerance: 1) else {
            resetObservation()
            return .waiting
        }
        guard let previous, WindowAnimationGeometry.near(previous, ax, tolerance: 1) else {
            self.previous = ax
            stableSince = now
            return .waiting
        }
        guard let stableSince, now - stableSince >= 1.0 / 30 else { return .waiting }
        if !retriedSize, abs(ax.width - destination.width) > 1 || abs(ax.height - destination.height) > 1 {
            if placement.constrainToScreen {
                // A shrink can stop while returning from off screen even when AX
                // reports success. Moving the entire oversized frame in bounds can
                // expose a backwards step after it has already reached its target.
                var retryFrame = placement.frame(for: destination, actualSize: ax.size, origin: origin, progress: 1)
                if let position = placement.positionBeforeGrowing(from: retryFrame, to: destination) {
                    retryFrame.origin = position
                }
                if !WindowAnimationGeometry.near(ax, retryFrame, tolerance: 1) {
                    if !retriedNearDestination,
                       abs(ax.minX - destination.minX) <= 1, abs(ax.minY - destination.minY) <= 1,
                       ax.width >= destination.width, ax.height >= destination.height {
                        // A one-point move can unblock the resize without exposing
                        // the full correction. Verify it before using the in-bounds
                        // retry; genuine minimum sizes still take the normal path.
                        retriedNearDestination = true
                        func step(_ current: CGFloat, toward target: CGFloat) -> CGFloat {
                            current + min(1, abs(target - current)) * (target < current ? -1 : 1)
                        }
                        resetObservation()
                        return .retrySizeAt(CGPoint(x: step(ax.minX, toward: retryFrame.minX),
                                                    y: step(ax.minY, toward: retryFrame.minY)))
                    }
                    retriedSize = true
                    resetObservation()
                    return .retrySizeAt(retryFrame.origin)
                }
            }
            retriedSize = true
            resetObservation()
            return .retrySize
        }
        let aligned = placement.frame(for: destination, actualSize: ax.size, origin: origin, progress: 1)
        if WindowAnimationGeometry.near(ax, aligned, tolerance: 1) { return .complete(ax) }
        resetObservation()
        return .align(aligned)
    }

    private mutating func resetObservation() {
        previous = nil
        stableSince = nil
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

enum WindowAnimationInterruptionPolicy {
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

struct WindowReleasedSnapStability {
    enum Decision { case waiting, ready, timedOut }
    let startedAt: TimeInterval
    private var previous: CGRect?
    private var stableSince: TimeInterval?

    init(startedAt: TimeInterval) { self.startedAt = startedAt }

    mutating func observe(ax: CGRect, server: CGRect?, at now: TimeInterval) -> Decision {
        if let server, WindowAnimationGeometry.valid(ax), WindowAnimationGeometry.valid(server),
           WindowAnimationGeometry.near(ax, server, tolerance: 1) {
            if let previous, WindowAnimationGeometry.near(previous, server, tolerance: 1) {
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

enum WindowAnimationGeometry {
    static func valid(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy { $0.isFinite } && frame.width > 0 && frame.height > 0
    }
    static func near(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        valid(a) && valid(b) && abs(a.minX-b.minX) <= tolerance && abs(a.minY-b.minY) <= tolerance && abs(a.width-b.width) <= tolerance && abs(a.height-b.height) <= tolerance
    }
}

/// Opt-in local timing evidence. Normal app launches do no tracing or filesystem work.
enum WindowAnimationDiagnostics {
    private static let path = ProcessInfo.processInfo.environment["RECTANGLE_ANIMATION_TRACE_PATH"]
    static var enabled: Bool { !(path ?? "").isEmpty }
    private static let queue = DispatchQueue(label: "Rectangle.WindowAnimation.diagnostics", qos: .utility)
    static func event(_ name: String, fields: [String: Any] = [:]) {
        guard let path, !path.isEmpty else { return }
        var record = fields
        record["event"] = name
        record["uptime"] = ProcessInfo.processInfo.systemUptime
        record["timestamp"] = Date().timeIntervalSince1970
        record["pid"] = getpid()
        guard JSONSerialization.isValidJSONObject(record),
              var data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        queue.async {
            let descriptor = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { return }
            defer { close(descriptor) }
            data.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else { return }
                _ = Darwin.write(descriptor, base, buffer.count)
            }
        }
    }
}

/// Coordinates animation lifecycle and moves the actual application window.
final class WindowAnimator {
    static let shared = WindowAnimator()
    private let direct = DirectWindowAnimator()

    private init() {
        for name in [Notification.Name.windowAnimationPreferencesChanged, .configImported] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.finish()
            }
        }
        for name in [NSApplication.willTerminateNotification, NSApplication.didChangeScreenParametersNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.direct.cancel()
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.direct.cancel()
            }
        }
        workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.direct.cancelIfTargetDiffers(from: app?.processIdentifier)
        }
    }

    static var enabled: Bool {
        Defaults.experimentalWindowAnimations.enabled
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && !NSWorkspace.shared.isVoiceOverEnabled
            && !NSWorkspace.shared.isSwitchControlEnabled
    }

    func destination(for element: AccessibilityElement) -> CGRect? { direct.destination(for: element) }
    func logicalFrame(for element: AccessibilityElement) -> CGRect? { direct.destination(for: element) }
    func cancel(for element: AccessibilityElement) { direct.cancel(for: element) }
    func finish() { direct.finish() }
    func finishForNewDrag() {
        direct.mouseDown()
        finish()
    }

    func animate(_ element: AccessibilityElement, from startingFrame: CGRect? = nil, to destination: CGRect,
                 duration: TimeInterval = WindowAnimationCurve.duration,
                 resizeOnly: Bool = false, releasedSnap: Bool = false,
                 placement: WindowAnimationPlacement? = nil,
                 offset: @escaping () -> CGPoint = { .zero },
                 curve: @escaping (Double) -> CGFloat = WindowAnimationCurve.value,
                 completion: @escaping (CGRect) -> Void) {
        direct.animate(element, from: startingFrame, to: destination, duration: duration,
                       resizeOnly: resizeOnly, releasedSnap: releasedSnap, placement: placement,
                       offset: offset, curve: curve, completion: completion)
    }

    static func crossesDisplays(from source: CGRect, to destination: CGRect) -> Bool {
        let frames = NSScreen.screens.map { $0.frame.screenFlipped }
        guard let a = WindowDisplayTransition.display(containing: source, displays: frames),
              let b = WindowDisplayTransition.display(containing: destination, displays: frames) else { return false }
        return a != b
    }
}
