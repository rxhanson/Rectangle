import Cocoa
import QuartzCore

/// Coordinates animation lifecycle and moves the actual application window.
final class WindowAnimator {
    static let shared = WindowAnimator()
    private let direct = WindowAnimationExecutor()

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
    func prepare(_ element: AccessibilityElement) { direct.prepare(element) }
    func afterPendingWrites(cancellation: (() -> Void)? = nil, _ body: @escaping () -> Void) {
        direct.afterPendingWrites(cancellation: cancellation, body)
    }
    func performPlacementWork(_ body: @escaping () -> Void) { direct.performPlacementWork(body) }
    func finishForNewDrag() {
        direct.mouseDown()
        finish()
    }

    func animate(_ element: AccessibilityElement, from startingFrame: CGRect? = nil, to destination: CGRect,
                 duration: TimeInterval = WindowAnimationCurve.duration,
                 resizeOnly: Bool = false, releasedSnap: Bool = false,
                 placement: WindowAnimationPlacement? = nil,
                 profile: WindowAnimationProfile = .standard,
                 offset: @escaping () -> CGPoint = { .zero },
                 curve: @escaping (Double) -> CGFloat = WindowAnimationCurve.value,
                 cancellation: (() -> Void)? = nil,
                 completion: @escaping (CGRect) -> Void) {
        direct.animate(element, from: startingFrame, to: destination, duration: duration,
                       resizeOnly: resizeOnly, releasedSnap: releasedSnap, placement: placement, profile: profile,
                       offset: offset, curve: curve, cancellation: cancellation, completion: completion)
    }

    static func crossesDisplays(from source: CGRect, to destination: CGRect) -> Bool {
        let frames = NSScreen.screens.map { $0.frame.screenFlipped }
        guard let a = WindowDisplayTransition.display(containing: source, displays: frames),
              let b = WindowDisplayTransition.display(containing: destination, displays: frames) else { return false }
        return a != b
    }
}
