/// StandardWindowMover.swift

import Foundation

class StandardWindowMover: WindowMover {
    func moveWindow(toRect rect: CGRect, resultParameters: ResultParameters) {
        let windowElement = resultParameters.windowElement
        let before = windowElement.frame
        if before.isNull { return }
        let target = rect.screenFlipped
        let bounds = resultParameters.visibleFrameOfScreen.screenFlipped
        let sizeFirst = ImmediateFrameOrder.sizeFirst(from: before, to: target, bounds: bounds,
            acrossScreens: resultParameters.usableScreens.currentScreen != resultParameters.calcResult.screen,
            preferSizeFirst: shouldAdjustSizeFirst(resultParameters.action))
        let placement = WindowAnimationPlacement(screenFrame: bounds,
            sharedEdges: resultParameters.action.resizes ? Defaults.moveFixedSizeToEdge.value.alignmentEdges(
                for: resultParameters.calcResult.initialRect.screenFlipped, in: bounds) : nil,
            constrainToScreen: !(resultParameters.action.allowedToExtendOutsideCurrentScreenArea && !NSScreen.screensHaveSeparateSpaces),
            gap: CGFloat(Defaults.gapSize.value))
        windowElement.setImmediateFrame(target, from: before, sizeFirst: sizeFirst, placement: placement)
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

enum ImmediateFrameOrder {
    static func sizeFirst(from current: CGRect, to target: CGRect, bounds: CGRect,
                          acrossScreens: Bool, preferSizeFirst: Bool) -> Bool {
        // Moving an off-screen window first can make the system resize it against the Dock.
        if acrossScreens || !bounds.insetBy(dx: -1, dy: -1).contains(current) { return true }
        func overflow(_ frame: CGRect) -> CGFloat {
            max(0, bounds.minX - frame.minX) + max(0, frame.maxX - bounds.maxX)
                + max(0, bounds.minY - frame.minY) + max(0, frame.maxY - bounds.maxY)
        }
        let resized = overflow(CGRect(origin: current.origin, size: target.size))
        let moved = overflow(CGRect(origin: target.origin, size: current.size))
        if abs(resized - moved) > 1 { return resized < moved }
        return preferSizeFirst
    }
}
