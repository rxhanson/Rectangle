import Foundation

final class SpecifiedCalculation: WindowCalculation {

    let specifiedHeight: CGFloat
    let specifiedWidth: CGFloat

    override init() {
        self.specifiedHeight = CGFloat(Defaults.specifiedHeight.value)
        self.specifiedWidth = CGFloat(Defaults.specifiedWidth.value)
    }

    override func calculateRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {

        var calculatedWindowRect = visibleFrameOfScreen

        // Resize
        calculatedWindowRect.size.height = round(specifiedHeight)
        calculatedWindowRect.size.width = round(specifiedWidth)

        // Center
        calculatedWindowRect.origin.x = round((visibleFrameOfScreen.width - calculatedWindowRect.width) / 2.0) + visibleFrameOfScreen.minX
        calculatedWindowRect.origin.y = round((visibleFrameOfScreen.height - calculatedWindowRect.height) / 2.0) + visibleFrameOfScreen.minY

        return RectResult(calculatedWindowRect)
    }
}
