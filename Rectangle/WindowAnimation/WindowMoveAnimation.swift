/// WindowMoveAnimation.swift

import Cocoa

/// How a window action animates while the experimental animation setting is on.
///
/// WindowManager doesn't decide anything about animation: it asks for an animation,
/// which is nil whenever the setting is off, and hands the result to `WindowAnimator.place`.
struct WindowMoveAnimation {
    /// The frame to animate to, in AX coordinates.
    let destination: CGRect
    let placement: WindowAnimationPlacement?
    let releasedSnap: Bool
    let profile: WindowAnimationProfile

    /// The animation for moving a window to a calculated target, or nil to place it immediately.
    static func forMove(of windowElement: AccessibilityElement, action: WindowAction,
                        calcResult: WindowCalculationResult, screenFrame: CGRect,
                        isFixedSize: Bool, isMovedAcrossDisplays: Bool, source: ExecutionSource) -> WindowMoveAnimation? {
        guard windowElement.canAnimate, !isFixedSize, !isMovedAcrossDisplays || source == .dragToSnap else { return nil }

        let flippedScreenFrame = screenFrame.screenFlipped
        let placement = WindowAnimationPlacement(
            screenFrame: flippedScreenFrame,
            sharedEdges: action.resizes ? Defaults.moveFixedSizeToEdge.value.alignmentEdges(
                for: calcResult.initialRect.screenFlipped, in: flippedScreenFrame) : nil,
            constrainToScreen: !(action.allowedToExtendOutsideCurrentScreenArea && !NSScreen.screensHaveSeparateSpaces),
            gap: CGFloat(Defaults.gapSize.value))
        return WindowMoveAnimation(destination: calcResult.rect.screenFlipped,
                                   placement: placement,
                                   releasedSnap: source == .dragToSnap,
                                   profile: profile(for: source))
    }

    /// The animation for restoring a window to a saved frame, or nil to restore it immediately.
    static func forRestore(to restoreRect: CGRect, of windowElement: AccessibilityElement,
                           source: ExecutionSource) -> WindowMoveAnimation? {
        guard windowElement.canAnimate, windowElement.isResizable() else { return nil }
        return WindowMoveAnimation(destination: restoreRect, placement: nil, releasedSnap: false,
                                   profile: profile(for: source))
    }

    private static func profile(for source: ExecutionSource) -> WindowAnimationProfile {
        source == .keyboardShortcut ? .keyboard : .standard
    }
}

extension WindowAnimator {
    /// Animates the window when there is an animation. Otherwise it stops any animation
    /// of the window and waits out its pending writes, so a write made after this can't be
    /// overwritten by an animation that is still finishing. Callers that don't animate only
    /// need this while the animator isn't idle.
    /// - Parameter completion: Receives the frame an animation achieved, or nil when the
    ///   caller still has to write the frame itself.
    func place(_ windowElement: AccessibilityElement, animation: WindowMoveAnimation?,
               cancellation: (() -> Void)?, completion: @escaping (CGRect?) -> Void) {
        guard let animation else {
            cancel(for: windowElement)
            afterPendingWrites(cancellation: cancellation) { completion(nil) }
            return
        }
        animate(windowElement, to: animation.destination, releasedSnap: animation.releasedSnap,
                placement: animation.placement, profile: animation.profile,
                cancellation: cancellation) { frame in
            completion(frame.isNull ? nil : frame)
        }
    }
}
