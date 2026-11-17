/// ScreenSelector.swift
///
/// Chooses the screens a window action is calculated against.
///
/// With cursor screen detection, a command moves the window to its target on the
/// display under the cursor. Repeating a command without pointing elsewhere still
/// repeats it, so repeats that cycle sizes or cross displays keep working.

import Cocoa

/// What cursor screen detection remembers about each window between presses.
final class CursorScreenHistory {

    static let shared = CursorScreenHistory()

    var screenFrames = [CGWindowID: CGRect]() // the frame of the display under the cursor when this app last acted on the window

    var actions = [CGWindowID: WindowAction]() // the command pressed when this app last acted on the window, which can differ from the action it resulted in

    /// A command is a fresh one on the cursor's display unless the cursor
    /// stayed on the display it was on last time.
    func changedDisplay(for windowId: CGWindowID?, cursorScreenFrame: CGRect) -> Bool {
        guard let windowId, let lastFrame = screenFrames[windowId] else { return true }
        return lastFrame != cursorScreenFrame
    }
}

/// The screens a move is calculated against, chosen by `ScreenSelector`.
struct ScreenSelection {
    /// The screens to calculate against.
    let usable: UsableScreens
    /// The screens the window starts on.
    let source: UsableScreens
    /// Whether the window's last action no longer counts as the one being repeated.
    var forgetsLastAction = false
}

struct ScreenSelector {

    let screenDetection: ScreenDetection
    var history: CursorScreenHistory = .shared

    /// The screens a move is calculated against, or nil when they can't be found.
    /// Records the press with cursor screen detection, so it must be called once per move.
    func screens(for windowElement: AccessibilityElement, windowId: CGWindowID?,
                 parameters: ExecutionParameters) -> ScreenSelection? {
        guard let sourceScreens = screenDetection.detectScreens(using: windowElement) else { return nil }

        // An explicit screen (display cycling) or the cursor screen controls the
        // calculation, but neither necessarily contains the window before it moves.
        if let screen = parameters.screen {
            let screens = parameters.source == .titleBar
            ? screenDetection.detectScreens(at: screen)
            : UsableScreens(currentScreen: screen, numScreens: 1)
            return screens.map { ScreenSelection(usable: $0, source: sourceScreens) }
        }

        return cursorSelection(for: parameters.action, windowId: windowId, sourceScreens: sourceScreens)
            ?? ScreenSelection(usable: sourceScreens, source: sourceScreens)
    }

    /// The cursor's screens, or nil to use the window's own.
    private func cursorSelection(for action: WindowAction, windowId: CGWindowID?,
                                 sourceScreens: UsableScreens) -> ScreenSelection? {
        // Display actions count from the window's display.
        guard Defaults.useCursorScreenDetection.enabled,
              action.classification != .display,
              let cursorScreens = screenDetection.detectScreensAtCursor()
        else { return nil }

        let cursorScreenFrame = cursorScreens.currentScreen.frame
        let cursorChangedDisplay = history.changedDisplay(for: windowId, cursorScreenFrame: cursorScreenFrame)
        let isSameCommandAgain = windowId.map { history.actions[$0] == action } ?? false

        if let windowId {
            history.screenFrames[windowId] = cursorScreenFrame
            history.actions[windowId] = action
        }

        if !cursorChangedDisplay && isSameCommandAgain {
            // Until the cursor points elsewhere, pressing the same command again continues
            // from wherever the last press left the window, so repeats that cross displays
            // keep working. This mustn't depend on the last action, which is forgotten
            // whenever the app adjusts the frame Rectangle set.
            return ScreenSelection(usable: sourceScreens, source: sourceScreens)
        }

        // Pointing at another display, or pressing another command, is a first press
        // on the cursor's display. The last action there doesn't count as a repeat if
        // the cursor moved or repeats walked the window off that display.
        let forgetsLastAction = cursorChangedDisplay || sourceScreens.currentScreen != cursorScreens.currentScreen
        return ScreenSelection(usable: cursorScreens, source: sourceScreens, forgetsLastAction: forgetsLastAction)
    }

    /// A window moved to the cursor's display was sent there by the cursor, so moving
    /// the cursor again would only pull it away from where the user put it.
    func shouldMoveCursorAcrossDisplays(onto screen: NSScreen) -> Bool {
        !(Defaults.useCursorScreenDetection.enabled
          && screenDetection.detectScreensAtCursor()?.currentScreen == screen)
    }

    /// Rectangle moving the cursor isn't the user pointing at another display,
    /// so the next press of the same command still counts as a repeat.
    func didMoveCursor(onto screen: NSScreen, windowId: CGWindowID?) {
        guard Defaults.useCursorScreenDetection.enabled, let windowId else { return }
        history.screenFrames[windowId] = screen.frame
    }

    /// Pointing at another display makes a press a first press there, so it
    /// mustn't cycle the window on from its display as a repeated command.
    func cursorChangedDisplay(for windowId: CGWindowID) -> Bool {
        guard Defaults.useCursorScreenDetection.enabled,
              let cursorScreen = screenDetection.detectScreensAtCursor()?.currentScreen
        else { return false }
        return history.changedDisplay(for: windowId, cursorScreenFrame: cursorScreen.frame)
    }
}
