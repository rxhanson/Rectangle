/// StandardWindowMover.swift

import Foundation

class StandardWindowMover: WindowMover {
    func moveWindow(toRect rect: CGRect, resultParameters: ResultParameters) {
        let windowElement = resultParameters.windowElement
        if windowElement.frame.isNull { return }
        windowElement.setFrame(rect.screenFlipped)
    }
}
