import Foundation

class CenterTwoScreensCalculation: WindowCalculation {
    
    override func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {

        let initialScreenFrame = params.usableScreens.currentScreen.visibleFrame
        let secondScreenFrame = params.usableScreens.adjacentScreens?.next.visibleFrame
        
        let screenFrame = initialScreenFrame.union(secondScreenFrame ?? .null)
                
        let rectResult = calculateRect(params.asRectParams(visibleFrame: screenFrame))
        
        return WindowCalculationResult(rect: rectResult.rect,
                                       screen: params.usableScreens.currentScreen,
                                       resultingAction: params.action,
                                       resultingScreenFrame: screenFrame)
    }
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {

        let bothScreens = params.visibleFrameOfScreen
        var calculatedWindowRect = params.window.rect

        // Make the window as tall as the screen
        calculatedWindowRect.origin.y = 0
        calculatedWindowRect.size.height = bothScreens.height
        
        // Set the x position to one screen width minus half the size of the window
        let oneScreenWidth = bothScreens.width / 2
        let halfWindowSize = calculatedWindowRect.width / 2
        calculatedWindowRect.origin.x = oneScreenWidth - halfWindowSize

        return RectResult(calculatedWindowRect)
    }
    
}
