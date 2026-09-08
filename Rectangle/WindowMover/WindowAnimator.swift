/// WindowAnimator.swift

import Cocoa

enum WindowAnimationCurve {
    static let duration: TimeInterval = 0.34

    static func unsnapValue(at progress: Double) -> CGFloat {
        let t = min(1, max(0, progress))
        // Quintic smoothstep: zero velocity and acceleration at both endpoints.
        return CGFloat(t * t * t * (10 + t * (-15 + 6 * t)))
    }

    static func value(at progress: Double) -> CGFloat {
        let progress = min(1, max(0, progress))
        // Integral of t * (1 - t)^5, normalized to [0, 1].
        return CGFloat(1 - pow(1 - progress, 6) * (1 + 6 * progress))
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
    private let write: (CGRect) -> Bool
    private let cleanup: () -> Void
    private let completion: (CGRect) -> Void
    private(set) var isFinished = false

    init(from: CGRect, to: CGRect, startTime: TimeInterval, duration: TimeInterval,
         offset: @escaping () -> CGPoint = { .zero },
         curve: @escaping (Double) -> CGFloat = WindowAnimationCurve.value,
         write: @escaping (CGRect) -> Bool,
         cleanup: @escaping () -> Void,
         completion: @escaping (CGRect) -> Void) {
        origin = from
        destination = to
        self.startTime = startTime
        self.duration = duration
        self.offset = offset
        self.curve = curve
        self.write = write
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
        if !write(frame) {
            // Let the normal mover settle the destination after a refused AX write.
            finish()
        }
    }

    func finish() {
        guard !isFinished else { return }
        let delta = offset()
        isFinished = true
        cleanup()
        completion(destination.offsetBy(dx: delta.x, dy: delta.y))
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        cleanup()
    }
}

/// Coordinates one window animation at a time on the main run loop.
final class WindowAnimator {
    static let shared = WindowAnimator()
    private var window: AccessibilityElement?
    private var animation: WindowFrameAnimation?
    private var timer: Timer?
    private var mouseMonitor: Any?

    private init() {
        for name in [NSApplication.willTerminateNotification, NSApplication.didChangeScreenParametersNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.finish()
            }
        }
    }

    static var enabled: Bool {
        Defaults.experimentalWindowAnimations.enabled
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && !NSWorkspace.shared.isVoiceOverEnabled
            && !NSWorkspace.shared.isSwitchControlEnabled
    }

    func destination(for element: AccessibilityElement) -> CGRect? {
        window == element ? animation?.destination : nil
    }

    func cancel(for element: AccessibilityElement) {
        if window == element { animation?.cancel() }
    }

    func finish() {
        animation?.finish()
    }

    func animate(_ element: AccessibilityElement, to destination: CGRect,
                 duration: TimeInterval = WindowAnimationCurve.duration,
                 resizeOnly: Bool = false,
                 offset: @escaping () -> CGPoint = { .zero },
                 curve: @escaping (Double) -> CGFloat = WindowAnimationCurve.value,
                 completion: @escaping (CGRect) -> Void) {
        if window == element {
            animation?.cancel()
        } else {
            animation?.finish()
        }
        let origin = element.frame
        guard Self.enabled, !origin.isNull, !destination.isNull,
              !origin.isEmpty, !destination.isEmpty, origin != destination else {
            completion(destination)
            return
        }
        let restoreAccessibility = element.beginAnimatedAdjustment()
        window = element
        animation = WindowFrameAnimation(from: origin, to: destination,
                                         startTime: ProcessInfo.processInfo.systemUptime,
                                         duration: duration, offset: offset, curve: curve,
                                         write: { element.setAnimationFrame($0, resizeOnly: resizeOnly) },
                                         cleanup: { [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
            if let monitor = self?.mouseMonitor {
                NSEvent.removeMonitor(monitor)
                self?.mouseMonitor = nil
            }
            self?.animation = nil
            self?.window = nil
            restoreAccessibility()
        }, completion: completion)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !Self.enabled {
                self.finish()
            } else {
                self.animation?.tick(at: ProcessInfo.processInfo.systemUptime)
            }
        }
        self.timer = timer
        // Manual grabs must interrupt animation even when drag-to-snap is disabled.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.finish()
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
