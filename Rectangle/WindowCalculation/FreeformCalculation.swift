/// FreeformCalculation.swift

import AppKit

final class FreeformCalculation: WindowCalculation {
    override func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        let screen = params.usableScreens.currentScreen
        let workArea = screen.freeformWorkArea(ignoreTodo: params.ignoreTodo)
        guard let rect = params.action.freeformRegion?.typedValue?.rect(in: workArea) else { return nil }
        return WindowCalculationResult(rect: rect, screen: screen, resultingAction: params.action,
                                       resultingScreenFrame: workArea)
    }
}

extension WindowAction {
    var freeformRegion: JSONDefault<FreeformRegion>? {
        switch self {
        case .freeformOne: return Defaults.freeformOne
        case .freeformTwo: return Defaults.freeformTwo
        case .freeformThree: return Defaults.freeformThree
        case .freeformFour: return Defaults.freeformFour
        default: return nil
        }
    }
}

extension NSScreen {
    var freeformDisplayID: UUID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
              let uuidString = CFUUIDCreateString(nil, uuid) else { return nil }
        return UUID(uuidString: uuidString as String)
    }

    func freeformWorkArea(ignoreTodo: Bool = false) -> CGRect {
        adjustedVisibleFrame(ignoreTodo).intersection(frame)
    }
}

extension FreeformSelectionDisplay {
    /// The connected displays, with the same usable areas Freeform presets are calculated in.
    static func current() -> [FreeformSelectionDisplay] {
        NSScreen.screens.map {
            FreeformSelectionDisplay(frame: $0.frame, workArea: $0.freeformWorkArea(), id: $0.freeformDisplayID)
        }
    }
}
