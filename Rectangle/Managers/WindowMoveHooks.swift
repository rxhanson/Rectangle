/// WindowMoveHooks.swift
///
/// The extension points of `WindowManager.execute`. A feature brings its own conformer
/// and adds it to the manager's chain or factory, without editing `execute`.
/// Keep this file free of feature-specific code: that belongs in the conformers.

import Cocoa

// MARK: - Target adjusters

/// Refines a calculated target before anything about the move is derived from it,
/// such as whether the window resizes. Adjusters run in order and write no frames.
protocol WindowTargetAdjuster {
    func adjust(_ result: inout WindowCalculationResult, action: WindowAction, windowId: CGWindowID?)
}

// MARK: - Move delegates

/// What a window move is about to do, for a delegate to plan around.
struct WindowMoveRequest {
    let calcResult: WindowCalculationResult
    let windowId: CGWindowID?
    let isFixedSize: Bool
    let windowElement: AccessibilityElement
    let action: WindowAction
    let source: ExecutionSource
    /// The window's frame before the move, normalized.
    let currentFrame: CGRect
    /// The visible frame of the destination screen.
    let screenFrame: CGRect
    /// The screens the window starts on.
    let sourceScreens: UsableScreens
    let destinationScreenIsCurrentScreen: Bool
    let lastRectangleAction: RectangleAction?
}

/// Customizes a single move once its target is known: it can revise the target,
/// decide that the move is already achieved, place the window itself, and tidy up after.
/// Every hook but `calcResult` has a default that leaves the manager's own behavior in place.
///
/// A move has at most one delegate. When features that customize moves could both apply,
/// the order of the manager's `WindowManagerDelegateProvider`s decides which one does.
protocol WindowManagerDelegate {
    /// The target this move aims for, possibly revised from the one it was given.
    var calcResult: WindowCalculationResult { get }

    /// Whether the window is already where the move would put it, or nil to compare frames.
    /// Only called while no animation is pending, so it may record state.
    func isAlreadyAchieved() -> Bool?

    /// Places the window, or returns nil to have the manager apply the target.
    /// Not used for animated placements or cross-display retries.
    /// - Returns: The rect of the window after placing it
    func place(result: ResultParameters, moveWindow: (CGRect, ResultParameters) -> Void) -> CGRect?

    /// The window has settled on the screen it started on. Not called after a move across displays.
    func moveDidSettle(resultingRect: CGRect, screenFrame: CGRect)
}

extension WindowManagerDelegate {
    func isAlreadyAchieved() -> Bool? { nil }
    func place(result: ResultParameters, moveWindow: (CGRect, ResultParameters) -> Void) -> CGRect? { nil }
    func moveDidSettle(resultingRect: CGRect, screenFrame: CGRect) {}
}

/// Offers a feature's delegate for a move. The manager asks its providers in order,
/// and the first to return a delegate is used, so the order sets precedence.
protocol WindowManagerDelegateProvider {
    /// A delegate for this move, or nil when this feature doesn't apply to it.
    func delegate(for request: WindowMoveRequest) -> WindowManagerDelegate?
}
