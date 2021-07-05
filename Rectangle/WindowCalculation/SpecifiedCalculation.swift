import Foundation

final class SpecifiedCalculation: WindowCalculation {

    private let specifiedHeight: CGFloat
    private let specifiedWidth: CGFloat

    override init() {
        specifiedHeight = CGFloat(Defaults.specifiedHeight.value)
        specifiedWidth = CGFloat(Defaults.specifiedWidth.value)
    }

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {

        let visibleFrameOfScreen = params.visibleFrameOfScreen
        var calculatedWindowRect = visibleFrameOfScreen

        // Resize
        calculatedWindowRect.size.height = specifiedHeight <= 1
            ? visibleFrameOfScreen.height * specifiedHeight
            : round(specifiedHeight)
        calculatedWindowRect.size.width = specifiedWidth <= 1
            ? visibleFrameOfScreen.width * specifiedWidth
            : min(visibleFrameOfScreen.width, round(specifiedWidth))

        // Center
        calculatedWindowRect.origin.x = round((visibleFrameOfScreen.width - calculatedWindowRect.width) / 2.0) + visibleFrameOfScreen.minX
        calculatedWindowRect.origin.y = round((visibleFrameOfScreen.height - calculatedWindowRect.height) / 2.0) + visibleFrameOfScreen.minY

        return RectResult(calculatedWindowRect)
    }
}
