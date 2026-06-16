/// StandardWindowMover.swift

import Foundation

class StandardWindowMover: WindowMover {
    func moveWindow(toRect rect: CGRect, resultParameters: ResultParameters) {
        let windowElement = resultParameters.windowElement
        if windowElement.frame.isNull { return }
        windowElement.setFrame(rect.screenFlipped,
                               adjustSizeFirst: shouldAdjustSizeFirst(resultParameters.action))
    }
    
    private func shouldAdjustSizeFirst(_ action: WindowAction) -> Bool {
        switch (action, Defaults.cornerCycleExpansionAxis.value) {
        case (.topRight, .horizontal),
             (.bottomRight, .horizontal),
             (.bottomLeft, .vertical),
             (.bottomRight, .vertical):
            return false
        default:
            return true
        }
    }
}
