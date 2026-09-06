/// WindowAnimator.swift

import Cocoa

/// A time-based transition. Missed timer ticks are skipped, never queued up.
/// Window I/O and the clock are supplied separately so cancellation and failures
/// can be tested without moving a user's windows.
final class WindowFrameAnimation {
    let destination: CGRect
    private let origin: CGRect
    private let startTime: TimeInterval
    private let duration: TimeInterval
    private let offset: () -> CGPoint
    private let write: (CGRect) -> Bool
    private let cleanup: () -> Void
    private let completion: (CGRect) -> Void
    private(set) var isFinished = false

    init(from: CGRect, to: CGRect, startTime: TimeInterval, duration: TimeInterval,
         offset: @escaping () -> CGPoint = { .zero },
         write: @escaping (CGRect) -> Bool,
         cleanup: @escaping () -> Void,
         completion: @escaping (CGRect) -> Void) {
        origin = from
        destination = to
        self.startTime = startTime
        self.duration = duration
        self.offset = offset
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
        // Smoothstep has zero velocity at both ends and does not overshoot.
        let eased = CGFloat(progress * progress * (3 - 2 * progress))
        let delta = offset()
        let frame = CGRect(x: origin.minX + (destination.minX - origin.minX) * eased + delta.x,
                           y: origin.minY + (destination.minY - origin.minY) * eased + delta.y,
                           width: origin.width + (destination.width - origin.width) * eased,
                           height: origin.height + (destination.height - origin.height) * eased)
        if !write(frame) {
            // A refused AX write ends interpolation; the ordinary mover settles
            // the destination using the application's existing size constraints.
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

/// Main-run-loop ownership serializes AX adjustments and history updates. Only
/// one window animates at a time, including when two windows belong to one app.
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
                 duration: TimeInterval = 0.25,
                 offset: @escaping () -> CGPoint = { .zero },
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
                                         duration: duration, offset: offset,
                                         write: { element.setAnimationFrame($0) },
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
        // Keyboard animations must also yield to a manual grab when drag-to-snap
        // is disabled and SnappingManager is not listening for mouse events.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.finish()
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
